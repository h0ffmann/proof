// What is proved about a triangle grid built with the size rules of Abdolali, Hesser, Roland et al.
// (2026, Section 5.2), and about how WAVEWATCH III steps the explicit N-scheme on it.
//
// 1. The size rule: the spacing is the smallest of the local minimums (depth, coast, slope), never
//    below the 5 km floor, and a depth gradient over 0.1 gives the floor.
// 2. The depth rule makes a cell as wide as a wave at the lowest frequency travels in one step of
//    600 s. Every cell is then at least as fine as that, so its Courant number for a 600 s step is
//    at least 1, and above 1 wherever another rule is finer: the reason the paper steps
//    implicitly.
// 3. A growth rate of 30% between neighbours needs at least 7 steps from 5 km to 30 km.
// 4. WAVEWATCH III's explicit N-scheme splits a step into ITER sub-steps
//    (model/src/w3profsmd.F90:648-656 at metocean/WW3 92e2cf66). ITER covers the CFL number up
//    to THR8 = TINY(1d0) (:561), and is 0, so the scheme does not move the spectrum at all, when
//    the CFL number is at most THR8.
// 5. The room's mesh (piabrota/room, scripts/grid.mjs at 66e38a7) measured against the rules:
//    NOTE lines, numbers and not proofs.
//
//     z3-scala/z3.sh grids
package z3scala.grids

import z3scala.Z.{*, given}
import z3scala.{*, given}

object Grids:
  private val hMin = 5 // km, "a minimum grid spacing of 5 km"
  private val step = 600 // s, "an implicit time step of 600 s"
  private val growth = Rational(13, 10) // "a mesh size growth rate of 30%"

  private def min(a: Real, b: Real): Real = ite(a <= b, a, b)
  private def max(a: Real, b: Real): Real = ite(a >= b, a, b)

  def counterexample(name: String, premises: Seq[Bool], conclusion: Bool, why: String): Unit =
    val s = ctx.mkSolver()
    premises.foreach(s.add(_))
    s.add(not(conclusion))
    val found = s.check() == com.microsoft.z3.Status.SATISFIABLE
    report(
      name,
      found,
      if found then s"counterexample ${Py.model(s.getModel)} ($why)"
      else "no counterexample, but one was expected"
    )

  def run(args: Seq[String]): Int =
    // 1. The size rule.
    val List(hDepth, hCoast, slope, cg) = reals("hDepth hCoast slope cg"): @unchecked
    val size = ite(slope > Rational(1, 10), hMin, max(hMin, min(hDepth, hCoast)))
    val positive = List(hDepth > 0, hCoast > 0, slope >= 0)
    proves("size_floor", positive, size >= hMin)
    proves("size_steep_is_floor", positive :+ (slope > Rational(1, 10)), size === num(hMin))
    proves(
      "size_smallest_minimum",
      positive :+ (slope <= Rational(1, 10)) :+ (hDepth >= hMin) :+ (hCoast >= hMin),
      and(size <= hDepth, size <= hCoast, or(size === hDepth, size === hCoast))
    )

    // 2. The depth rule and the Courant number of a 600 s step.
    val depthRule = List(cg > 0, hDepth === num(step) * cg, hDepth >= hMin) ++ positive
    val courant = cg * num(step) / size
    proves("courant_at_least_1", depthRule, courant >= 1)
    proves("courant_above_1_where_finer", depthRule :+ (size < hDepth), courant > 1)
    counterexample(
      "explicit_600s_stable",
      depthRule,
      courant <= 1,
      "a cell finer than the depth rule breaks the explicit CFL condition at 600 s"
    )

    // 3. Gradation: six steps of 30% from 5 km stay below 30 km; seven reach it.
    val h = List.tabulate(8)(i => real(s"h$i"))
    val chain = (h.head === num(hMin)) :: h.zip(h.tail).map((a, b) => b <= num(growth) * a)
    proves("growth_6_steps_below_30km", chain.take(7), h(6) < 30)
    counterexample("growth_7_steps_reach_30km", chain, h(7) < 30, "1.3^7 * 5 km = 31.37 km")

    // 4. WW3's ITER (w3profsmd.F90:648-656), for a positive CFL number.
    val List(cfl, thr8) = reals("cfl thr8"): @unchecked
    val fl = toReal(int("floor"))
    val rest = cfl - fl // MOD(CFLXY, 1) of a positive CFLXY
    val n = ite(rest < Rational(1, 2), fl, fl + 1) // NINT: half away from zero
    val iter = ite(rest < thr8, n, ite(and(rest > thr8, rest < Rational(1, 2)), n + 1, n))
    val ww3 = List(cfl > 0, thr8 > 0, thr8 < Rational(1, 2), fl <= cfl, cfl < fl + 1)
    proves("iter_covers_cfl_to_thr8 (w3profsmd.F90:649)", ww3, iter >= cfl - thr8)
    proves("iter_covers_cfl_unless_rest_in_(0,thr8]", ww3 :+ or(rest === num(0), rest > thr8), iter >= cfl)
    counterexample("iter_covers_cfl", ww3, iter >= cfl, "a fractional part in (0, THR8] rounds down")
    counterexample(
      "iter_at_least_1 (w3profsmd.F90:663)",
      ww3,
      iter >= 1,
      "a CFL number up to THR8 gives ITER = 0: no sub-step runs"
    )
    proves("iter_at_least_1_above_thr8", ww3 :+ (cfl > thr8), iter >= 1)

    roomMesh()
    finish("grids (Z3)")

  // ------------------------------------------------------------------------------------------
  // 5. piabrota/room, scripts/grid.mjs at 66e38a7: spacing [9, 70] km, reach 550 km,
  //    spacingAt(d) = S0 + (S1 - S0) * min(1, d / REACH)^1.4, one lattice per distance band.

  private def roomMesh(): Unit =
    val (s0, s1, reach) = (9.0, 70.0, 550.0)
    def spacingAt(d: Double) = s0 + (s1 - s0) * math.pow(math.min(1, math.max(0, d) / reach), 1.4)
    val bands = List((0.5 * s0, 40.0), (40.0, 130.0), (130.0, 300.0), (300.0, reach))
    val sizes = bands.map((a, b) => spacingAt((a + b) / 2))
    println()
    println(
      f"NOTE  room coast spacing $s0%.0f km: above the 5 km floor, so no coast is finer than the paper's"
    )
    for ((a, b), hh) <- bands.zip(sizes) do println(f"NOTE  room band $a%.1f-$b%.0f km: lattice $hh%.2f km")
    for (x, y) <- sizes.zip(sizes.tail) do
      val ratio = y / x
      println(f"NOTE  room band step ${x}%.2f -> ${y}%.2f km: ratio $ratio%.2f, ${
          if ratio <= 1.3 then "within" else "above"
        } the 30%% growth rate")
