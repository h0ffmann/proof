// The contextual bandit, as a specification in Z3.
//
// The design splits a contextual bandit into two layers:
//
// * a reward model (the probabilistic part): a belief that is updated with observations
//   (context, arm, reward) and that reports, for each context and arm, a predicted mean reward
//   and an uncertainty width;
// * a decision rule (the bandit part): a function that sees only those per-arm estimates and
//   returns a probability for each arm.
//
// The decision rules never see the raw history. They see it only through the model. That boundary
// is what lets a model be swapped (Beta-Bernoulli, Bayesian linear regression, a neural net with
// calibrated uncertainty) without touching the decision layer, and the other way round.
//
// This file defines the decision layer as Z3 terms over the reals. A decision rule here is a
// function from a list of K estimates to a list of K probabilities. Each estimate is a pair
// (mean, width) of Z3 reals; the rules are built from ite, +, * and comparisons, so that
// Theorems.scala can ask Z3 whether a statement holds for every real value of the estimates.
//
// K, the number of arms, is a Scala integer: Z3 has no induction over lists. The theorems are
// proved for each K from 1 to MAX_ARMS, for all real estimates. docs/decisions/0001-z3-over-lean.md
// says why that trade was made.
//
// haskell/src/ContextualBandit.hs is the port that runs, name for name.
package z3scala.bandit.domain

import z3scala.kernel.smt.*
import z3scala.kernel.smt.Z.{*, given}

object Bandit:
  val MAX_ARMS = 5

  type Estimate = (Real, Real) // (mean, width)
  type Decision = List[Real] // one probability per arm

  /** K symbolic estimates: (mean_i, width_i). */
  def estimates(k: Int, prefix: String = "e"): List[Estimate] =
    List.tabulate(k)(i => (real(s"$prefix${i}_mean"), real(s"$prefix${i}_width")))

  def mean(e: Estimate): Real = e._1
  def width(e: Estimate): Real = e._2

  // ------------------------------------------------------------------------------------------
  // Argmax. Every deterministic rule (greedy, UCB) is "argmax of some score". Ties go to the
  // first arm, the same convention as the Haskell port.

  /**
   * One Boolean per arm: this arm is the first with the largest score.
   *
   * Arm i is chosen when every earlier score is strictly smaller and no later score is larger. Exactly one of
   * the Booleans is true for any real scores.
   */
  def argmaxFirst(scores: List[Real]): List[Bool] =
    scores.zipWithIndex.map { (score, i) =>
      val earlierSmaller = if i > 0 then and((0 until i).map(j => scores(j) < score)*) else True
      val laterNotLarger = and((i + 1 until scores.size).map(j => scores(j) <= score)*)
      and(earlierSmaller, laterNotLarger)
    }

  // ------------------------------------------------------------------------------------------
  // Decisions and the rules

  /** Point mass on the chosen arm. */
  def point(chosen: List[Bool]): Decision = chosen.map(c => ite(c, 1, 0))

  def uniform(k: Int): Decision = List.fill(k)(num(1) / num(k))

  /** w * d1 + (1 - w) * d2. */
  def mix(w: Real, d1: Decision, d2: Decision): Decision =
    d1.zip(d2).map((p, q) => w * p + (num(1) - w) * q)

  def ucbScore(beta: Real, e: Estimate): Real = mean(e) + beta * width(e)

  def greedyArm(est: List[Estimate]): List[Bool] = argmaxFirst(est.map(mean))

  def ucbArm(beta: Real, est: List[Estimate]): List[Bool] = argmaxFirst(est.map(ucbScore(beta, _)))

  /** Pure exploitation: the arm with the largest mean. */
  def greedy(est: List[Estimate]): Decision = point(greedyArm(est))

  /**
   * Optimism in the face of uncertainty: the arm with the largest mean + beta * width. With a Bayesian linear
   * model this is LinUCB.
   */
  def ucb(beta: Real, est: List[Estimate]): Decision = point(ucbArm(beta, est))

  /** With probability eps pick an arm uniformly, otherwise be greedy. */
  def epsGreedy(eps: Real, est: List[Estimate]): Decision = mix(eps, uniform(est.size), greedy(est))

  // ------------------------------------------------------------------------------------------
  // What a decision must be

  def mass(d: Decision): Real = sum(d)

  /** A probability distribution: every arm non-negative, the mass is 1. */
  def valid(d: Decision): Bool = and((d.map(_ >= 0) :+ (mass(d) === num(1)))*)

  def same(d1: Decision, d2: Decision): Bool = and(d1.zip(d2).map(_ === _)*)
