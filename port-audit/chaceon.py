"""Z3 checks of chaceon, the Rust port of WAVEWATCH III (github.com/h0ffmann/chaceon).

chaceon checks its Rust against the Fortran by `cmp` on whole runs and by captured calls. Those
show that the two agree on the inputs that ran. They cannot show a fact for every input, and they
cannot see a defect that both sides share. This file states such facts about chaceon's code and asks
Z3 for a counterexample. `unsat` means none exists. The audited commit is `CHACEON_COMMIT`; every
`file:line` below is at that commit.

Three groups:

* D. The division rewrite of `rust/tools/spirv_exact/src/main.rs:3-7`. An `f32` division becomes an
  `f64` division rounded to `f32`, because Vulkan allows 2.5 ULP in `OpFDiv`. chaceon proves this in
  Lean (`lean/Chaceon/Division.lean`) with Mathlib. Here Z3 checks the same statements: the integer
  facts over bit-vectors, the rounding facts over the reals.
* U. Fortran's intrinsics in `rust/crates/ww3-kernels/src/util.rs`: `nint`, `floor`, `sign`. Z3 checks
  them over IEEE `f32` (its floating-point theory), so the check is about the bits Rust computes.
* S. The time step of `W3SRCE` in `rust/crates/ww3-kernels/src/srce.rs`: the dynamic step, its split
  into equal parts, the limited and implicit increments, and the spectrum that stays non-negative.

Some checks expect a counterexample (`counterexample(...)`): they show that a hypothesis is needed,
or that the code allows more than its comment says. Each one says why.

    python3 port-audit/chaceon.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "z3"))

from z3 import (  # noqa: E402
    RNA, RNE, RTN, RTZ, And, BitVecSort, BitVecs, Extract, Float32, FP, FPVal, If,
    Int, Not, Or, Real, Reals, Solver, ToReal, UGE, ULT, fpAbs, fpEQ, fpGEQ, fpGT, fpIsNaN,
    fpIsNegative, fpIsZero, fpLEQ, fpLT, fpMax, fpMin, fpMul, fpAdd, fpNeg, fpRoundToIntegral,
    fpSignedToFP, fpSub, fpToIEEEBV, fpToSBV, sat,
)

from refute import finish, proves, report  # noqa: E402

CHACEON_COMMIT = "fe531e1e64950c0f3ce7987ae4ed0325a56adfbe"


def counterexample(name: str, premises, conclusion, why: str) -> None:
    """The statement must fail: Z3 must find a model of the premises and the negated conclusion."""
    s = Solver()
    s.add(*premises)
    s.add(Not(conclusion))
    found = s.check() == sat
    report(name, found, f"counterexample {s.model()} ({why})" if found else "no counterexample, but one was expected")


# ======================================================================================
# D. spirv_exact: f32 division through f64 (rust/tools/spirv_exact/src/main.rs:3-7, 57-64)
#
# a = A * 2^ea, b = B * 2^eb with 24-bit significands A, B in [2^23, 2^24). The power of two is exact
# in the normal range, so the quotient is q = A / B, in (1/2, 2), against the f32 grid there. Its
# midpoints are m = M / 2^t with M odd in [2^24, 2^25): t = 25 on [1/2, 1), t = 24 on [1, 2). So two
# values of t cover every normal quotient. Lean needs every integer t; here the scaling argument
# leaves two, and Z3 checks both.

W = 100  # bits: A * 2^25 and M * B fit in 50, and the margin product in 99
A, B, M = BitVecs("A B M", W)
significands = [UGE(A, 2**23), ULT(A, 2**24), UGE(B, 2**23), ULT(B, 2**24)]
odd_midpoint = [UGE(M, 2**24), ULT(M, 2**25), Extract(0, 0, M) == 1]

for t in (24, 25):
    lhs, rhs = A * 2**t, M * B
    # q = A/B equals m = M/2^t exactly when A * 2^t = M * B.
    proves(f"no_tie (t = {t})", significands + odd_midpoint, lhs != rhs)
    # margin: |q - m| >= m / 2^49  <=>  2^49 * |A 2^t - M B| >= M B   (divide by B 2^t > 0)
    gap = If(UGE(lhs, rhs), lhs - rhs, rhs - lhs)
    proves(f"margin (t = {t})", significands + odd_midpoint, UGE(gap * 2**49, rhs))

# The margin cannot be doubled: 2^48 in place of 2^49 fails, as in chaceon's Lean log.
counterexample("margin_2^48_fails (t = 25)", significands + odd_midpoint,
               UGE(If(UGE(A * 2**25, M * B), A * 2**25 - M * B, M * B - A * 2**25) * 2**48, M * B),
               "the margin 2^-49 cannot be doubled")

# Subnormal: a midpoint with fewer than 25 bits can be hit exactly (Lean's small_midpoint_ties).
a1, b1, m1 = BitVecs("a1 b1 m1", W)
counterexample("no_tie_needs_normal", [UGE(a1, 1), ULT(a1, 2**24), UGE(b1, 1), ULT(b1, 2**24),
                                       ULT(m1, 2**24), Extract(0, 0, m1) == 1],
               a1 * 2 != m1 * b1, "subnormal results are not covered")

# same_side: r within 5/2 * 2^-52 of q (Vulkan's 2.5 ULP on f64), and q keeps the margin from m.
q, m, r = Reals("q m r")
ulp_error = Real("ulp_error")
side = [q > 0, m > 0, Or(q - m >= m / 2**49, m - q >= m / 2**49),
        r - q <= q * 5 / 2 / 2**52, q - r <= q * 5 / 2 / 2**52]
proves("same_side", side, (r < m) == (q < m))
proves("same_side_not_tie", side, And(r != m, q != m))
# An error of 8 * 2^-52 reaches the margin 2^-49 and can cross the midpoint: the margin is the limit.
counterexample("same_side_8ulp_fails", [q > 0, m > 0, Or(q - m >= m / 2**49, m - q >= m / 2**49),
                                       r - q <= q * 8 / 2**52, q - r <= q * 8 / 2**52],
               (r < m) == (q < m), "an error of 8 * 2^-52 can reach the midpoint")

# closer_lo: round to nearest between adjacent grid points lo < hi is the comparison with the midpoint.
lo, hi, x = Reals("lo hi x")
dist = lambda u, v: If(u >= v, u - v, v - u)  # noqa: E731
proves("closer_lo", [lo < hi], (dist(x, lo) < dist(x, hi)) == (x < (lo + hi) / 2))

# ======================================================================================
# U. Fortran intrinsics (rust/crates/ww3-kernels/src/util.rs), over IEEE f32.
#
# Rust's `x as i32` truncates and saturates; inside (-2^31, 2^31) it is fpToSBV with RTZ, and NaN
# is outside the premises. `t as Real` is fpSignedToFP with RNE.

F32 = Float32()
xf = FP("x", F32)
I32 = BitVecSort(32)
big = FPVal(2.0**31, F32)
in_i32 = [fpLT(xf, big), fpGT(xf, fpNeg(big)), Not(fpIsNaN(xf))]
half = FPVal(0.5, F32)

# util.rs:21-31  nint: t = x as i32; frac = x - t; t+1 if frac >= 0.5, t-1 if frac <= -0.5.
t_ = fpToSBV(RTZ(), xf, I32)
frac = fpSub(RNE(), xf, fpSignedToFP(RNE(), t_, F32))
nint = If(fpGEQ(frac, half), t_ + 1, If(fpLEQ(frac, fpNeg(half)), t_ - 1, t_))
proves("nint = round half away (util.rs:21)", in_i32, nint == fpToSBV(RTZ(), fpRoundToIntegral(RNA(), xf), I32))
proves("nint_frac_exact (util.rs:24)", in_i32,
       fpEQ(fpAdd(RNE(), fpSignedToFP(RNE(), t_, F32), frac), xf))

# util.rs:34-37  floor: t = x as i32; t-1 if t > x.
floor = If(fpGT(fpSignedToFP(RNE(), t_, F32), xf), t_ - 1, t_)
proves("floor = round down (util.rs:34)", in_i32, floor == fpToSBV(RTZ(), fpRoundToIntegral(RTN(), xf), I32))

# util.rs:41-43  sign: the magnitude bits of a with the sign bit of b, as Fortran SIGN(A, B).
af, bf = FP("a", F32), FP("b", F32)
bits_a, bits_b = fpToIEEEBV(af), fpToIEEEBV(bf)
sign_bits = (bits_a & 0x7FFFFFFF) | (bits_b & 0x80000000)
fortran_sign = If(fpIsNegative(bf), fpNeg(fpAbs(af)), fpAbs(af))
proves("sign = SIGN(A, B) (util.rs:41)", [Not(fpIsNaN(af)), Not(fpIsNaN(bf))],
       sign_bits == fpToIEEEBV(fortran_sign))
# gfortran keeps the sign of a negative zero B: SIGN(1., -0.) = -1. The bit copy does the same.
proves("sign_negative_zero", [fpIsZero(bf), fpIsNegative(bf), Not(fpIsNaN(af)), fpGT(af, FPVal(0.0, F32))],
       fpToIEEEBV(fpNeg(af)) == sign_bits)

# ======================================================================================
# S. W3SRCE's time step (rust/crates/ww3-kernels/src/srce.rs), first over f32, then over the reals.

sp, einc, dam = FP("sp", F32), FP("einc", F32), FP("dam", F32)
zero = FPVal(0.0, F32)

# srce.rs:619, 624, 629, 742: sp = (sp + einc).max(0.). Rust's f32::max returns the other operand
# for a NaN, as IEEE maxNum, so the spectrum stays >= 0 even after an overflow to NaN.
updated = fpMax(fpAdd(RNE(), sp, einc), zero)
proves("spectrum_nonneg (srce.rs:619)", [], And(Not(fpIsNaN(updated)), fpGEQ(updated, zero)))

# srce.rs:617-618, the limited increment: einc2 = sign(min(dam, |einc1|), einc1).
# Rust's f32::min also drops a NaN operand. For dam >= 0 the step is at most dam, with einc1's sign.
einc2_mag = fpMin(dam, fpAbs(einc))
einc2 = If(fpIsNegative(einc), fpNeg(fpAbs(einc2_mag)), fpAbs(einc2_mag))
dam_ok = [fpGEQ(dam, zero), Not(fpIsNaN(dam))]
proves("limited_step_le_dam (srce.rs:618)", dam_ok, fpLEQ(fpAbs(einc2), dam))
proves("limited_step_sign (srce.rs:618)", dam_ok + [Not(fpIsNaN(einc)), Not(fpIsZero(einc))],
       Or(fpIsZero(einc2), fpIsNegative(einc2) == fpIsNegative(einc)))

# srce.rs:673: the tail sp(ik) = sp(ik-1) * fachfa + 0. The `+ 0.` turns a -0 into +0.
fachfa = FP("fachfa", F32)
tail = fpAdd(RNE(), fpMul(RNE(), sp, fachfa), zero)
proves("tail_no_negative_zero (srce.rs:673)", [fpGEQ(sp, zero), fpGEQ(fachfa, zero)],
       Not(And(fpIsZero(tail), fpIsNegative(tail))))

# --- Over the reals: the semi-implicit increment and the dynamic step.
vs, vd, dt, damax, afac = Reals("vs vd dt damax afac")

# srce.rs:617, 623: einc1 = vs * dt / max(1, 1 - dt * vd). With dt >= 0 the denominator is >= 1, so the
# implicit step never exceeds the explicit one, whatever the sign of vd.
denominator = If(1 - dt * vd >= 1, 1 - dt * vd, 1)
einc1 = vs * dt / denominator
proves("implicit_le_explicit (srce.rs:617)", [dt >= 0], dist(einc1, 0) <= dist(vs * dt, 0))

# srce.rs:598-600: the limiter. afac = 1 / max(|vs / damax|, 1e-10);
# dt <= afac / max(1 + afac * min(vd, 0), 1e-10). Without the two clamps of 1e-10, and with
# vd <= 0 (the damping sign), the increment of this component is at most damax.
limiter = [damax > 0, vs != 0, vd <= 0, afac == damax / dist(vs, 0), 1 + afac * vd > 0,
           dt >= 0, dt * (1 + afac * vd) <= afac]
proves("limiter_bounds_increment (srce.rs:600)", limiter, dist(vs * dt / (1 - dt * vd), 0) <= damax)

# srce.rs:602: dt = dt.max(0.5). The floor of half a second can exceed the limiter's step.
counterexample("limiter_vs_floor_0.5 (srce.rs:602)",
               limiter[:-1] + [dt == If(afac / (1 + afac * vd) >= 0.5, afac / (1 + afac * vd), 0.5)],
               dist(vs * dt / (1 - dt * vd), 0) <= damax,
               "the 0.5 s floor wins over the limiter when the limit is smaller")

# srce.rs:604-605: idt = 1 + trunc(0.99 * rem / dt); dt' = rem / idt, with rem = dtg - dttot > 0.
rem, dtl, dtn = Reals("rem dtl dtn")
idt = Int("idt")
split = [rem > 0, dtl >= 0.5, idt - 1 <= 0.99 * rem / dtl, 0.99 * rem / dtl < idt, dtn * ToReal(idt) == rem]
proves("split_idt_ge_1 (srce.rs:604)", split, idt >= 1)
proves("split_le_rem (srce.rs:605)", split, dtn <= rem)
proves("split_le_dt/0.99 (srce.rs:605)", split, dtn <= dtl / 0.99)
counterexample("split_le_dt (srce.rs:605)", split, dtn <= dtl,
               "the 0.99 lets each equal part exceed the limited step by up to 1/0.99")

# srce.rs:607-612: dt'' = max(dt', min(dtmin, rem)), dttot += dt''. Each pass moves dttot forward by at
# least min(dtmin, rem) and never past dtg.
dtmin, dtf = Reals("dtmin dtf")
step = split + [dtmin > 0, dtf == If(dtn >= If(dtmin <= rem, dtmin, rem), dtn, If(dtmin <= rem, dtmin, rem))]
proves("step_never_past_dtg (srce.rs:607)", step, dtf <= rem)
proves("step_progress (srce.rs:607)", step, dtf >= If(dtmin <= rem, dtmin, rem))

finish("chaceon (Z3)")
