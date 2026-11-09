// A concrete model you can run: the tabular model, and the examples the Haskell spec check
// reproduces.
//
// `tabular` keeps, for each (context, arm), a reward sum and a pull count:
// mean = sum / count (0 when never pulled), width = 1 / (count + 1), a rational stand-in for
// 1 / sqrt(n). The policy is `rule(estimates(posterior(history), context))`: the rule sees the
// history only through the belief.
//
// The values below are the ground truth of `specCheck` in haskell/app/Main.hs. They are exact
// rationals fed to the same Z3 rules as the theorems, so a change in a rule shows up here first.
//
//     z3-scala/z3.sh examples
package z3scala

import Z.*
import Bandit.*

object Examples:
  // ------------------------------------------------------------------------------------------
  // The tabular model, over exact rationals

  type Belief = Map[(String, Int), (Rational, Int)] // (context, arm) -> (reward sum, count)

  def update(belief: Belief, context: String, arm: Int, reward: Rational): Belief =
    val (total, count) = belief.getOrElse((context, arm), (Rational.zero, 0))
    belief.updated((context, arm), (total + reward, count + 1))

  def estimate(belief: Belief, context: String, arm: Int): (Rational, Rational) =
    val (total, count) = belief.getOrElse((context, arm), (Rational.zero, 0))
    val mean = if count == 0 then Rational.zero else total / Rational(count)
    (mean, Rational(1, count + 1))

  def posterior(history: List[(String, Int, Int)]): Belief =
    history.foldLeft(Map.empty: Belief) { case (b, (context, arm, reward)) =>
      update(b, context, arm, Rational(reward))
    }

  /** The decision of a rule after a history, in a context, as Z3 terms. */
  def policy(
      rule: List[Estimate] => Decision,
      history: List[(String, Int, Int)],
      context: String,
      arms: Int
  ): Decision =
    val belief = posterior(history)
    rule(List.tabulate(arms) { a =>
      val (m, w) = estimate(belief, context, a); (num(m), num(w))
    })

  // ------------------------------------------------------------------------------------------
  // Three arms; in the morning arm 1 pays off, in the evening arm 2.

  val history = List(
    ("morning", 0, 0),
    ("morning", 1, 1),
    ("morning", 1, 1),
    ("morning", 2, 0),
    ("evening", 0, 0),
    ("evening", 1, 0),
    ("evening", 2, 1)
  )

  def run(args: Seq[String]): Int =
    val expected: List[(String, List[Estimate] => Decision, String, List[Rational])] = List(
      ("greedy morning", greedy, "morning", List(0, 1, 0)),
      ("greedy evening", greedy, "evening", List(0, 0, 1)),
      (
        "epsGreedy 1/10 morning",
        est => epsGreedy(num(Rational(1, 10)), est),
        "morning",
        List(Rational(1, 30), Rational(14, 15), Rational(1, 30))
      )
    )
    for (name, rule, context, values) <- expected do
      val decision = policy(rule, history, context, arms = 3)
      for ((p, v), arm) <- decision.zip(values).zipWithIndex do evaluates(s"$name [$arm]", p, v)
    finish("examples of the tabular model")
