// Z3 checks of chaceon, the Rust port of WAVEWATCH III (github.com/h0ffmann/chaceon).
//
// chaceon checks its Rust against the Fortran by `cmp` on whole runs and by captured calls. Those
// show that the two agree on the inputs that ran. They cannot show a fact for every input, and they
// cannot see a defect that both sides share. This file states such facts about chaceon's code and
// asks Z3 for a counterexample. `unsat` means none exists. The audited commit is CHACEON_COMMIT;
// every `file:line` below is at that commit.
//
// Three groups:
//
// * D. The division rewrite of `rust/tools/spirv_exact/src/main.rs:3-7`. An `f32` division becomes
//   an `f64` division rounded to `f32`, because Vulkan allows 2.5 ULP in `OpFDiv`. chaceon proves
//   this in Lean (`lean/Chaceon/Division.lean`) with Mathlib. Here Z3 checks the same statements:
//   the integer facts over bit-vectors, the rounding facts over the reals.
// * U. Fortran's intrinsics in `rust/crates/ww3-kernels/src/util.rs`: `nint`, `floor`, `sign`. Z3
//   checks them over IEEE `f32` (its floating-point theory), so the check is about the bits Rust
//   computes.
// * S. The time step of `W3SRCE` in `rust/crates/ww3-kernels/src/srce.rs`: the dynamic step, its
//   split into equal parts, the limited and implicit increments, and the spectrum that stays
//   non-negative.
//
// Some checks expect a counterexample (`counterexample(...)`): they show that a hypothesis is
// needed, or that the code allows more than its comment says. Each one says why.
//
//     z3-scala/z3.sh chaceon
package z3scala.portaudit.domain

import com.microsoft.z3.*
import z3scala.kernel.proof.Script.*
import z3scala.kernel.proof.{Item, Script}
import z3scala.kernel.smt.*
import z3scala.kernel.smt.Z.{*, given}

object Chaceon:
  val CHACEON_COMMIT = "fe531e1e64950c0f3ce7987ae4ed0325a56adfbe"

  private def c = Z.ctx

  // ------------------------------------------------------------------------------------------
  // Bit-vectors and IEEE f32, in the words of the statements

  private val W = 100 // bits: A * 2^25 and M * B fit in 50, and the margin product in 99
  private def bv(v: BigInt, width: Int = W): BV = c.mkBV(v.toString, width)
  private def uge(a: BV, b: BV): Bool = c.mkBVUGE(a, b)
  private def ult(a: BV, b: BV): Bool = c.mkBVULT(a, b)
  private def iteBV(cond: Bool, a: BV, b: BV): BV = c.mkITE(cond, a, b).asInstanceOf[BV]
  private def iteFP(cond: Bool, a: FP, b: FP): FP = c.mkITE(cond, a, b).asInstanceOf[FP]
  private def pow2(k: Int): BigInt = BigInt(2).pow(k)
  private def pow2r(k: Int): Real = num(pow2(k).toString)

  val title = "chaceon (Z3)"

  def statements: Vector[Item] = Script:
    // ======================================================================================
    // D. spirv_exact: f32 division through f64 (rust/tools/spirv_exact/src/main.rs:3-7, 57-64)
    //
    // a = A * 2^ea, b = B * 2^eb with 24-bit significands A, B in [2^23, 2^24). The power of two is
    // exact in the normal range, so the quotient is q = A / B, in (1/2, 2), against the f32 grid
    // there. Its midpoints are m = M / 2^t with M odd in [2^24, 2^25): t = 25 on [1/2, 1), t = 24 on
    // [1, 2). So two values of t cover every normal quotient. Lean needs every integer t; here the
    // scaling argument leaves two, and Z3 checks both.
    val List(a, b, m) = List("A", "B", "M").map(c.mkBVConst(_, W)): @unchecked
    val significands =
      List(uge(a, bv(pow2(23))), ult(a, bv(pow2(24))), uge(b, bv(pow2(23))), ult(b, bv(pow2(24))))
    val oddMidpoint = List(uge(m, bv(pow2(24))), ult(m, bv(pow2(25))), c.mkExtract(0, 0, m) === bv(1, 1))

    for t <- List(24, 25) do
      val (lhs, rhs) = (a * bv(pow2(t)), m * b)
      // q = A/B equals m = M/2^t exactly when A * 2^t = M * B.
      proves(s"no_tie (t = $t)", significands ++ oddMidpoint, lhs =/= rhs)
      // margin: |q - m| >= m / 2^49  <=>  2^49 * |A 2^t - M B| >= M B   (divide by B 2^t > 0)
      val gap = iteBV(uge(lhs, rhs), lhs - rhs, rhs - lhs)
      proves(s"margin (t = $t)", significands ++ oddMidpoint, uge(gap * bv(pow2(49)), rhs))

    // The margin cannot be doubled: 2^48 in place of 2^49 fails, as in chaceon's Lean log.
    counterexample(
      "margin_2^48_fails (t = 25)",
      significands ++ oddMidpoint,
      uge(
        iteBV(uge(a * bv(pow2(25)), m * b), a * bv(pow2(25)) - m * b, m * b - a * bv(pow2(25))) * bv(
          pow2(48)
        ),
        m * b
      ),
      "the margin 2^-49 cannot be doubled"
    )

    // Subnormal: a midpoint with fewer than 25 bits can be hit exactly (Lean's small_midpoint_ties).
    val List(a1, b1, m1) = List("a1", "b1", "m1").map(c.mkBVConst(_, W)): @unchecked
    counterexample(
      "no_tie_needs_normal",
      List(
        uge(a1, bv(1)),
        ult(a1, bv(pow2(24))),
        uge(b1, bv(1)),
        ult(b1, bv(pow2(24))),
        ult(m1, bv(pow2(24))),
        c.mkExtract(0, 0, m1) === bv(1, 1)
      ),
      a1 * bv(2) =/= m1 * b1,
      "subnormal results are not covered"
    )

    // same_side: r within 5/2 * 2^-52 of q (Vulkan's 2.5 ULP on f64), and q keeps the margin from m.
    val List(q, mid, r) = reals("q m r"): @unchecked
    val side = List(
      q > 0,
      mid > 0,
      or(q - mid >= mid / pow2r(49), mid - q >= mid / pow2r(49)),
      r - q <= q * 5 / 2 / pow2r(52),
      q - r <= q * 5 / 2 / pow2r(52)
    )
    proves("same_side", side, (r < mid) === (q < mid))
    proves("same_side_not_tie", side, and(r =/= mid, q =/= mid))
    // An error of 8 * 2^-52 reaches the margin 2^-49 and can cross the midpoint: the margin is the limit.
    counterexample(
      "same_side_8ulp_fails",
      List(
        q > 0,
        mid > 0,
        or(q - mid >= mid / pow2r(49), mid - q >= mid / pow2r(49)),
        r - q <= q * 8 / pow2r(52),
        q - r <= q * 8 / pow2r(52)
      ),
      (r < mid) === (q < mid),
      "an error of 8 * 2^-52 can reach the midpoint"
    )

    // closer_lo: round to nearest between adjacent grid points lo < hi is the comparison with the midpoint.
    val List(lo, hi, x) = reals("lo hi x"): @unchecked
    def dist(u: Real, v: Real): Real = ite(u >= v, u - v, v - u)
    proves("closer_lo", List(lo < hi), (dist(x, lo) < dist(x, hi)) === (x < (lo + hi) / 2))

    // ======================================================================================
    // U. Fortran intrinsics (rust/crates/ww3-kernels/src/util.rs), over IEEE f32.
    //
    // Rust's `x as i32` truncates and saturates; inside (-2^31, 2^31) it is fpToSBV with RTZ, and
    // NaN is outside the premises. `t as Real` is fpSignedToFP with RNE.
    val f32 = c.mkFPSort32()
    def fp(name: String): FP = c.mkConst(name, f32).asInstanceOf[FP]
    def fpVal(v: Double): FP = c.mkFP(v, f32)
    val (rne, rna, rtn, rtz) = (
      c.mkFPRoundNearestTiesToEven(),
      c.mkFPRoundNearestTiesToAway(),
      c.mkFPRoundTowardNegative(),
      c.mkFPRoundTowardZero()
    )
    def toSBV(rm: FPRMExpr, v: FP): BV = c.mkFPToBV(rm, v, 32, true)
    def fromSBV(v: BV): FP = c.mkFPToFP(rne, v, f32, true)
    def neg(v: FP): FP = c.mkFPNeg(v)
    def abs(v: FP): FP = c.mkFPAbs(v)
    def isNaN(v: FP): Bool = c.mkFPIsNaN(v)
    def isNeg(v: FP): Bool = c.mkFPIsNegative(v)
    def isZero(v: FP): Bool = c.mkFPIsZero(v)

    val xf = fp("x")
    val big = fpVal(math.pow(2, 31))
    val inI32 = List(c.mkFPLt(xf, big), c.mkFPGt(xf, neg(big)), not(isNaN(xf)))
    val half = fpVal(0.5)

    // util.rs:21-31  nint: t = x as i32; frac = x - t; t+1 if frac >= 0.5, t-1 if frac <= -0.5.
    val t0 = toSBV(rtz, xf)
    val frac = c.mkFPSub(rne, xf, fromSBV(t0))
    val nint =
      iteBV(c.mkFPGEq(frac, half), t0 + bv(1, 32), iteBV(c.mkFPLEq(frac, neg(half)), t0 - bv(1, 32), t0))
    proves("nint = round half away (util.rs:21)", inI32, nint === toSBV(rtz, c.mkFPRoundToIntegral(rna, xf)))
    proves("nint_frac_exact (util.rs:24)", inI32, c.mkFPEq(c.mkFPAdd(rne, fromSBV(t0), frac), xf))

    // util.rs:34-37  floor: t = x as i32; t-1 if t > x.
    val floor = iteBV(c.mkFPGt(fromSBV(t0), xf), t0 - bv(1, 32), t0)
    proves("floor = round down (util.rs:34)", inI32, floor === toSBV(rtz, c.mkFPRoundToIntegral(rtn, xf)))

    // util.rs:41-43  sign: the magnitude bits of a with the sign bit of b, as Fortran SIGN(A, B).
    val (af, bf) = (fp("a"), fp("b"))
    val (bitsA, bitsB) = (c.mkFPToIEEEBV(af), c.mkFPToIEEEBV(bf))
    val signBits = (bitsA & bv(0x7fffffffL, 32)) | (bitsB & bv(0x80000000L, 32))
    val fortranSign = iteFP(isNeg(bf), neg(abs(af)), abs(af))
    proves(
      "sign = SIGN(A, B) (util.rs:41)",
      List(not(isNaN(af)), not(isNaN(bf))),
      signBits === c.mkFPToIEEEBV(fortranSign)
    )
    // gfortran keeps the sign of a negative zero B: SIGN(1., -0.) = -1. The bit copy does the same.
    proves(
      "sign_negative_zero",
      List(isZero(bf), isNeg(bf), not(isNaN(af)), c.mkFPGt(af, fpVal(0.0))),
      c.mkFPToIEEEBV(neg(af)) === signBits
    )

    // ======================================================================================
    // S. W3SRCE's time step (rust/crates/ww3-kernels/src/srce.rs), first over f32, then over the reals.
    val (sp, einc, dam) = (fp("sp"), fp("einc"), fp("dam"))
    val zero = fpVal(0.0)

    // srce.rs:619, 624, 629, 742: sp = (sp + einc).max(0.). Rust's f32::max returns the other
    // operand for a NaN, as IEEE maxNum, so the spectrum stays >= 0 even after an overflow to NaN.
    val updated = c.mkFPMax(c.mkFPAdd(rne, sp, einc), zero)
    proves("spectrum_nonneg (srce.rs:619)", Nil, and(not(isNaN(updated)), c.mkFPGEq(updated, zero)))

    // srce.rs:617-618, the limited increment: einc2 = sign(min(dam, |einc1|), einc1). Rust's
    // f32::min also drops a NaN operand. For dam >= 0 the step is at most dam, with einc1's sign.
    val einc2Mag = c.mkFPMin(dam, abs(einc))
    val einc2 = iteFP(isNeg(einc), neg(abs(einc2Mag)), abs(einc2Mag))
    val damOk = List(c.mkFPGEq(dam, zero), not(isNaN(dam)))
    proves("limited_step_le_dam (srce.rs:618)", damOk, c.mkFPLEq(abs(einc2), dam))
    proves(
      "limited_step_sign (srce.rs:618)",
      damOk ++ List(not(isNaN(einc)), not(isZero(einc))),
      or(isZero(einc2), isNeg(einc2) === isNeg(einc))
    )

    // srce.rs:673: the tail sp(ik) = sp(ik-1) * fachfa + 0. The `+ 0.` turns a -0 into +0.
    val fachfa = fp("fachfa")
    val tail = c.mkFPAdd(rne, c.mkFPMul(rne, sp, fachfa), zero)
    proves(
      "tail_no_negative_zero (srce.rs:673)",
      List(c.mkFPGEq(sp, zero), c.mkFPGEq(fachfa, zero)),
      not(and(isZero(tail), isNeg(tail)))
    )

    // --- Over the reals: the semi-implicit increment and the dynamic step.
    val List(vs, vd, dt, damax, afac) = reals("vs vd dt damax afac"): @unchecked

    // srce.rs:617, 623: einc1 = vs * dt / max(1, 1 - dt * vd). With dt >= 0 the denominator is >= 1,
    // so the implicit step never exceeds the explicit one, whatever the sign of vd.
    val denominator = ite(num(1) - dt * vd >= 1, num(1) - dt * vd, 1)
    val einc1 = vs * dt / denominator
    proves("implicit_le_explicit (srce.rs:617)", List(dt >= 0), dist(einc1, 0) <= dist(vs * dt, 0))

    // srce.rs:598-600: the limiter. afac = 1 / max(|vs / damax|, 1e-10);
    // dt <= afac / max(1 + afac * min(vd, 0), 1e-10). Without the two clamps of 1e-10, and with
    // vd <= 0 (the damping sign), the increment of this component is at most damax.
    val limiter = List(
      damax > 0,
      vs =/= 0,
      vd <= 0,
      afac === damax / dist(vs, 0),
      num(1) + afac * vd > 0,
      dt >= 0,
      dt * (num(1) + afac * vd) <= afac
    )
    proves("limiter_bounds_increment (srce.rs:600)", limiter, dist(vs * dt / (num(1) - dt * vd), 0) <= damax)

    // srce.rs:602: dt = dt.max(0.5). The floor of half a second can exceed the limiter's step.
    counterexample(
      "limiter_vs_floor_0.5 (srce.rs:602)",
      limiter.init :+ (dt === ite(
        afac / (num(1) + afac * vd) >= num("0.5"),
        afac / (num(1) + afac * vd),
        num("0.5")
      )),
      dist(vs * dt / (num(1) - dt * vd), 0) <= damax,
      "the 0.5 s floor wins over the limiter when the limit is smaller"
    )

    // srce.rs:604-605: idt = 1 + trunc(0.99 * rem / dt); dt' = rem / idt, with rem = dtg - dttot > 0.
    val List(rem, dtl, dtn) = reals("rem dtl dtn"): @unchecked
    val idt = int("idt")
    val ratio = num("0.99") * rem / dtl
    val split = List(
      rem > 0,
      dtl >= num("0.5"),
      toReal(idt) - 1 <= ratio,
      ratio < toReal(idt),
      dtn * toReal(idt) === rem
    )
    proves("split_idt_ge_1 (srce.rs:604)", split, idt >= intVal(1))
    proves("split_le_rem (srce.rs:605)", split, dtn <= rem)
    proves("split_le_dt/0.99 (srce.rs:605)", split, dtn <= dtl / num("0.99"))
    counterexample(
      "split_le_dt (srce.rs:605)",
      split,
      dtn <= dtl,
      "the 0.99 lets each equal part exceed the limited step by up to 1/0.99"
    )

    // srce.rs:607-612: dt'' = max(dt', min(dtmin, rem)), dttot += dt''. Each pass moves dttot forward
    // by at least min(dtmin, rem) and never past dtg.
    val List(dtmin, dtf) = reals("dtmin dtf"): @unchecked
    val least = ite(dtmin <= rem, dtmin, rem)
    val step = split ++ List(dtmin > 0, dtf === ite(dtn >= least, dtn, least))
    proves("step_never_past_dtg (srce.rs:607)", step, dtf <= rem)
    proves("step_progress (srce.rs:607)", step, dtf >= least)
