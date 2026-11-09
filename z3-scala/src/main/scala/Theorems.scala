// What is proved about the decision rules, by Z3.
//
// Each statement below is checked for every number of arms K from 1 to MAX_ARMS and for every
// real value of the estimates, the epsilon, the beta and the true means: Z3 looks for a
// counterexample in exact real arithmetic and finds none.
//
// 1. greedy, ucb and epsGreedy (for 0 <= eps <= 1) return probability distributions.
// 2. eps-greedy explores: every arm gets at least eps / K, the greedy arm exactly
//    1 - eps + eps / K.
// 3. greedy and ucb pick a maximiser of their score; ucb with beta = 0 is greedy.
// 4. The UCB optimism lemma, the deterministic core of every UCB or LinUCB regret proof: if the
//    model is calibrated (each true mean within beta * width of its estimate), the arm UCB picks
//    loses at most 2 beta * width against the best arm. The regret bound then needs only a
//    probability bound for the calibration event and a bound on the sum of the widths: those are
//    the probabilistic parts, and they are not here.
// 5. The same for greedy with a delta-accurate model: it loses at most 2 delta.
// 6. The agent depends on the history only through the model's belief.
//
//     z3-scala/z3.sh theorems
package z3scala

import com.microsoft.z3.{Expr, Sort}

import Z.{*, given}
import Bandit.*

object Theorems:
  /** value when the arm is the chosen one, else 0: the sum over arms picks one value. */
  private def ifChosen(condition: Bool, value: Real): Real = ite(condition, value, 0)

  def run(args: Seq[String]): Int =
    val List(eps, beta, delta) = reals("eps beta delta"): @unchecked

    for k <- 1 to MAX_ARMS do
      val est = estimates(k)
      val trueMeans = List.tabulate(k)(i => real(s"mu$i"))
      val K = s"K=$k"

      // 1. Every rule returns a probability distribution.
      proves(s"greedy_valid $K", Nil, valid(greedy(est)))
      proves(s"ucb_valid $K", Nil, valid(ucb(beta, est)))
      proves(s"epsGreedy_valid $K", List(eps >= 0, eps <= 1), valid(epsGreedy(eps, est)))

      // 2. eps-greedy explores every arm.
      val chosen = greedyArm(est)
      val probability = epsGreedy(eps, est)
      proves(
        s"epsGreedy_prob $K",
        Nil,
        and(
          (chosen.zip(probability).map((c, p) => implies(c, p === num(1) - eps + eps / k)) ++
            chosen.zip(probability).map((c, p) => implies(not(c), p === eps / k)))*
        )
      )
      proves(s"epsGreedy_explores $K", List(eps <= 1), and(probability.map(p => eps / k <= p)*))
      proves(s"epsGreedy_one_is_ab_test $K", Nil, same(epsGreedy(1, est), uniform(k)))

      // 3. greedy and ucb pick maximisers.
      val bestMean = sum(chosen.zip(est).map((c, e) => ifChosen(c, mean(e))))
      proves(s"greedy_is_argmax $K", Nil, and(est.map(e => mean(e) <= bestMean)*))
      val ucbChosen = ucbArm(beta, est)
      val bestScore = sum(ucbChosen.zip(est).map((c, e) => ifChosen(c, ucbScore(beta, e))))
      proves(s"ucb_is_argmax $K", Nil, and(est.map(e => ucbScore(beta, e) <= bestScore)*))
      proves(s"ucb_zero $K", Nil, same(ucb(0, est), greedy(est)))

      // 4. The UCB optimism lemma.
      val calibrated = est
        .zip(trueMeans)
        .map((e, mu) => and(mean(e) - beta * width(e) <= mu, mu <= mean(e) + beta * width(e)))
      val muOfUcb = sum(ucbChosen.zip(trueMeans).map((c, mu) => ifChosen(c, mu)))
      val widthOfUcb = sum(ucbChosen.zip(est).map((c, e) => ifChosen(c, width(e))))
      proves(
        s"ucb_gap $K",
        calibrated,
        and(trueMeans.map(mu => mu <= muOfUcb + num(2) * (beta * widthOfUcb))*)
      )

      // 5. Greedy with a delta-accurate model.
      val accurate = est.zip(trueMeans).map((e, mu) => and(mean(e) - delta <= mu, mu <= mean(e) + delta))
      val muOfGreedy = sum(chosen.zip(trueMeans).map((c, mu) => ifChosen(c, mu)))
      proves(s"greedy_gap $K", accurate, and(trueMeans.map(mu => mu <= muOfGreedy + num(2) * delta)*))

    // 6. The model is the only channel from history to decision. The estimate of an arm is an
    // uninterpreted function of the belief; two histories with the same belief give the same
    // estimates, so the same decision, whatever the rule does with them.
    val List(belief1, belief2) = reals("belief1 belief2"): @unchecked
    val rs = ctx.getRealSort
    val estimateMean = ctx.mkFuncDecl("estimate_mean", Array[Sort](rs, rs), rs)
    val estimateWidth = ctx.mkFuncDecl("estimate_width", Array[Sort](rs, rs), rs)
    def app(f: com.microsoft.z3.FuncDecl[?], b: Real, i: Int): Real =
      f.apply(Array[Expr[?]](b, num(i))*).asInstanceOf[Real]
    for k <- 1 to MAX_ARMS do
      val est1 = List.tabulate(k)(i => (app(estimateMean, belief1, i), app(estimateWidth, belief1, i)))
      val est2 = List.tabulate(k)(i => (app(estimateMean, belief2, i), app(estimateWidth, belief2, i)))
      proves(
        s"policy_factors K=$k",
        List(belief1 === belief2),
        and(
          same(greedy(est1), greedy(est2)),
          same(ucb(beta, est1), ucb(beta, est2)),
          same(epsGreedy(eps, est1), epsGreedy(eps, est2))
        )
      )

    finish("theorems of the decision rules")
