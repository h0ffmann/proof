// The invariants of the video script (papers/contextual-bandits/script/), checked with Z3.
//
// The requirements of the owner for the 30-minute video, as statements. Each R is one sentence
// of the owner, 2026-11-09:
//
// * R1. The reward is the input of the user. A user gives a reward in [0, 1] for each thing
//   shown; the agent sees nothing else.
// * R2. One arm: exploitation shows pi(N), exploration computes pi(N+1). One arm, two actions.
// * R3. The A/B test is a special case of the CMAB. The whole A/B procedure, "explore then
//   commit", is one decision rule: epsGreedy(1) before the switch, epsGreedy(0) after it.
// * R4. RSI is the same rule, applied to itself. The arms of the outer agent are values of eps
//   for the inner agent; the outer rule is epsGreedy again.
// * R5. The two series of pi have positive terms. Thus their partial sums increase.
//
// For each statement, Z3 looks for a counterexample in exact real arithmetic and finds none.
// The approximation of pi and the user's answer are symbolic reals, so R1 and R2 hold for every
// user and every series. Z3 has no factorial of a symbolic k, so the Ramanujan terms are checked
// for k = 0 to 9 and the Leibniz pairs for every real k >= 0. The examples at the end are the
// ground truth of the spec check in haskell/app/Main.hs; haskell/src/Video.hs is the port that
// runs, name for name.
//
//     z3-scala/z3.sh video
package z3scala

import com.microsoft.z3.Status

import Z.{*, given}
import Bandit.*

object Video:
  val K = 3 // arms of the inner bandit and of the examples
  val M = 4 // arms of the outer bandit: the candidate values of eps

  // ------------------------------------------------------------------------------------------
  // R1. The reward is the input of the user, in [0, 1].

  /** v brought into [0, 1]. */
  def clip(v: Real): Real = ite(v < 0, 0, ite(num(1) < v, 1, v))

  def dist(a: Real, b: Real): Real = ite(a <= b, b - a, a - b)

  /** The simulated user of the video: the grade of v is 1 - |v - t|, clipped. */
  def byDistance(t: Real, v: Real): Real = clip(num(1) - dist(v, t))

  // ------------------------------------------------------------------------------------------
  // R3. Explore-then-commit is one decision rule: epsGreedy(1) before T, epsGreedy(0) after.

  def etc(horizon: Real, now: Real, est: List[Estimate]): Decision =
    val before = now < horizon
    epsGreedy(1, est).zip(epsGreedy(0, est)).map((p1, p0) => ite(before, p1, p0))

  // ------------------------------------------------------------------------------------------
  // R5 and the examples, over exact rationals

  def factorial(n: Int): BigInt = (1 to n).foldLeft(BigInt(1))(_ * _)

  /** (4j)! (1103 + 26390 j) / ((j!)^4 396^(4j)), the j-th term of Ramanujan's sum. */
  def ramanujanTerm(j: Int): Rational =
    Rational(factorial(4 * j) * (1103 + 26390 * j), factorial(j).pow(4) * BigInt(396).pow(4 * j))

  /** 4 * sum_{j < terms} (-1)^j / (2j + 1). */
  def leibniz(terms: Int): Rational =
    (0 until terms).foldLeft(Rational.zero)((s, j) => s + Rational(if j % 2 == 0 then 4 else -4, 2 * j + 1))

  def leibnizEven(pairs: Int): Rational =
    (0 until pairs).foldLeft(Rational.zero)((s, j) => s + Rational(4, 4 * j + 1) - Rational(4, 4 * j + 3))

  def run(args: Seq[String]): Int =
    val List(x, target) = reals("x target"): @unchecked
    proves("clip_nonneg", Nil, clip(x) >= 0)
    proves("clip_le_one", Nil, clip(x) <= 1)
    proves("User.bounded (byDistance)", Nil, and(byDistance(target, x) >= 0, byDistance(target, x) <= 1))

    // R2. One arm. The state is (n, shown, lastReward): the terms paid for, the approximation the
    // user saw, the grade the user gave. approxNext is pi(n+1) and rewardNext the user's grade of
    // it, both symbolic.
    val List(n, shown, lastReward, approxNext, rewardNext) =
      reals("n shown last_reward approx_next reward_next"): @unchecked
    val userBounded = and(rewardNext >= 0, rewardNext <= 1)

    // To exploit changes nothing. To explore pays one term, shows pi(n+1), and keeps the new grade
    // when it is not lower.
    def step(explore: Boolean): (Real, Real, Real) =
      if !explore then (n, shown, lastReward)
      else
        val keep = lastReward <= rewardNext
        (n + 1, ite(keep, approxNext, shown), ite(keep, rewardNext, lastReward))

    val (nExploit, shownExploit, rewardExploit) = step(explore = false)
    val (nExplore, shownExplore, rewardExplore) = step(explore = true)

    proves("step_exploit", Nil, and(nExploit === n, shownExploit === shown, rewardExploit === lastReward))
    proves("step_explore_n", Nil, nExplore === n + 1)
    proves("step_explore_reward", Nil, lastReward <= rewardExplore)
    proves(
      "step_reward_bounded",
      List(userBounded, lastReward >= 0, lastReward <= 1),
      and(rewardExplore >= 0, rewardExplore <= 1, rewardExploit >= 0, rewardExploit <= 1)
    )

    val est = estimates(K)
    val List(horizonT, t) = reals("T t"): @unchecked
    proves("epsGreedy_zero", Nil, same(epsGreedy(0, est), greedy(est)))
    proves("etc_before", List(t < horizonT), same(etc(horizonT, t, est), uniform(K)))
    proves("etc_after", List(not(t < horizonT)), same(etc(horizonT, t, est), greedy(est)))
    proves("etc_valid", Nil, valid(etc(horizonT, t, est)))

    // R4. RSI: the outer agent (M arms, one per candidate eps) uses epsGreedy too.
    val eps0 = real("eps0")
    val outerEst = estimates(M, "o")
    val innerEps = List.tabulate(M)(i => real(s"eps$i"))
    val innerEst = estimates(K, "i")
    val outer = epsGreedy(eps0, outerEst)

    proves("rsi_valid (outer)", List(eps0 >= 0, eps0 <= 1), valid(outer))
    proves(
      "rsi_valid (inner, each i)",
      innerEps.map(e => and(e >= 0, e <= 1)),
      and(innerEps.map(e => valid(epsGreedy(e, innerEst)))*)
    )
    proves("outer_explores", List(eps0 <= 1), and(outer.map(p => eps0 / M <= p)*))

    // R5. The series of pi have positive terms.
    val k = real("k")
    val leibnizPair = num(4) / (num(4) * k + 1) - num(4) / (num(4) * k + 3) // two consecutive terms, times 4
    proves("leibnizPair_pos (real k >= 0)", List(k >= 0), leibnizPair > 0)

    val ramTerms = (0 until 10).map(ramanujanTerm)
    report("ramTerm_pos (k = 0..9)", ramTerms.forall(_ > Rational.zero), "each term is a positive rational")
    val ramSums = (0 to 10).map(j => ramTerms.take(j).foldLeft(Rational.zero)(_ + _))
    report("ramSum_lt_succ (n = 0..9)", ramSums.zip(ramSums.tail).forall(_ < _), "partial sums increase")

    val List(c, sN, sNext) = reals("c s_n s_next"): @unchecked
    proves("ramApprox_anti", List(c > 0, sN > 0, sN < sNext), num(1) / (c * sNext) < num(1) / (c * sN))

    // Examples: the ground truth of the Haskell spec check.
    evaluates("leibniz 1", num(leibniz(1)), Rational(4))
    evaluates("leibniz 2", num(leibniz(2)), Rational(8, 3))
    evaluates("leibniz 5", num(leibniz(5)), Rational(1052, 315))
    evaluates("leibnizEven 2", num(leibnizEven(2)), Rational(304, 105))
    evaluates("ramSum 1", num(ramSums(1)), Rational(1103))

    val est3 =
      List((num(Rational(1, 2)), num(0)), (num(Rational(9, 10)), num(0)), (num(Rational(1, 10)), num(0)))
    for ((p3, p10), i) <- etc(10, 3, est3).zip(etc(10, 10, est3)).zipWithIndex do
      evaluates(s"etc 10 3 est3 [$i]", p3, Rational(1, 3))
      evaluates(s"etc 10 10 est3 [$i]", p10, Rational(if i == 1 then 1 else 0))

    // step with leibniz and byDistance(355/113), from (1, leibniz 1, 0): explore gives n = 2, exploit n = 1.
    val s = ctx.mkSolver()
    s.add(
      n === 1,
      shown === num(leibniz(1)),
      lastReward === 0,
      approxNext === num(leibniz(2)),
      rewardNext === byDistance(num(Rational(355, 113)), approxNext)
    )
    assert(s.check() == Status.SATISFIABLE)
    val model = s.getModel
    val explored = model.eval(nExplore, false)
    val exploited = model.eval(nExploit, false)
    report("step explore n", (explored === 2).simplify().isTrue, s"= ${Py.expr(explored)}  (expected 2)")
    report("step exploit n", (exploited === 1).simplify().isTrue, s"= ${Py.expr(exploited)}  (expected 1)")

    finish("invariants of the video")
