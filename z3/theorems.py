"""What is proved about the decision rules, by Z3.

Each statement below is checked for every number of arms K from 1 to MAX_ARMS and for every
real value of the estimates, the epsilon, the beta and the true means: Z3 looks for a
counterexample in exact real arithmetic and finds none.

1. greedy, ucb and eps_greedy (for 0 <= eps <= 1) return probability distributions.
2. eps-greedy explores: every arm gets at least eps / K, the greedy arm exactly
   1 - eps + eps / K.
3. greedy and ucb pick a maximiser of their score; ucb with beta = 0 is greedy.
4. The UCB optimism lemma, the deterministic core of every UCB or LinUCB regret proof: if the
   model is calibrated (each true mean within beta * width of its estimate), the arm UCB picks
   loses at most 2 beta * width against the best arm. The regret bound then needs only a
   probability bound for the calibration event and a bound on the sum of the widths: those are
   the probabilistic parts, and they are not here.
5. The same for greedy with a delta-accurate model: it loses at most 2 delta.
6. The agent depends on the history only through the model's belief.

    python3 z3/theorems.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from z3 import And, Function, If, Implies, Not, Real, RealSort, Reals  # noqa: E402

from bandit import (MAX_ARMS, eps_greedy, estimates, greedy, greedy_arm, mean, same, ucb,  # noqa: E402
                    ucb_arm, ucb_score, uniform, valid, width)
from refute import finish, proves  # noqa: E402

eps, beta, delta = Reals("eps beta delta")


def If_(condition, value):
    """value when the arm is the chosen one, else 0: the sum over arms picks one value."""
    return If(condition, value, 0)


for k in range(1, MAX_ARMS + 1):
    est = estimates(k)
    true_means = [Real(f"mu{i}") for i in range(k)]
    K = f"K={k}"

    # 1. Every rule returns a probability distribution.
    proves(f"greedy_valid {K}", [], valid(greedy(est)))
    proves(f"ucb_valid {K}", [], valid(ucb(beta, est)))
    proves(f"epsGreedy_valid {K}", [eps >= 0, eps <= 1], valid(eps_greedy(eps, est)))

    # 2. eps-greedy explores every arm.
    chosen = greedy_arm(est)
    probability = eps_greedy(eps, est)
    proves(f"epsGreedy_prob {K}", [],
           And(*[Implies(c, p == 1 - eps + eps / k) for c, p in zip(chosen, probability)],
               *[Implies(Not(c), p == eps / k) for c, p in zip(chosen, probability)]))
    proves(f"epsGreedy_explores {K}", [eps <= 1], And(*[eps / k <= p for p in probability]))
    proves(f"epsGreedy_one_is_ab_test {K}", [], same(eps_greedy(1, est), uniform(k)))

    # 3. greedy and ucb pick maximisers.
    best_mean = sum(If_(c, mean(e)) for c, e in zip(chosen, est))
    proves(f"greedy_is_argmax {K}", [], And(*[mean(e) <= best_mean for e in est]))
    ucb_chosen = ucb_arm(beta, est)
    best_score = sum(If_(c, ucb_score(beta, e)) for c, e in zip(ucb_chosen, est))
    proves(f"ucb_is_argmax {K}", [], And(*[ucb_score(beta, e) <= best_score for e in est]))
    proves(f"ucb_zero {K}", [], same(ucb(0, est), greedy(est)))

    # 4. The UCB optimism lemma.
    calibrated = [And(mean(e) - beta * width(e) <= mu, mu <= mean(e) + beta * width(e))
                  for e, mu in zip(est, true_means)]
    mu_of_ucb = sum(If_(c, mu) for c, mu in zip(ucb_chosen, true_means))
    width_of_ucb = sum(If_(c, width(e)) for c, e in zip(ucb_chosen, est))
    proves(f"ucb_gap {K}", calibrated,
           And(*[mu <= mu_of_ucb + 2 * (beta * width_of_ucb) for mu in true_means]))

    # 5. Greedy with a delta-accurate model.
    accurate = [And(mean(e) - delta <= mu, mu <= mean(e) + delta) for e, mu in zip(est, true_means)]
    mu_of_greedy = sum(If_(c, mu) for c, mu in zip(chosen, true_means))
    proves(f"greedy_gap {K}", accurate, And(*[mu <= mu_of_greedy + 2 * delta for mu in true_means]))

# 6. The model is the only channel from history to decision. The estimate of an arm is an
# uninterpreted function of the belief; two histories with the same belief give the same
# estimates, so the same decision, whatever the rule does with them.
belief1, belief2 = Reals("belief1 belief2")
estimate_mean = Function("estimate_mean", RealSort(), RealSort(), RealSort())
estimate_width = Function("estimate_width", RealSort(), RealSort(), RealSort())
for k in range(1, MAX_ARMS + 1):
    est1 = [(estimate_mean(belief1, i), estimate_width(belief1, i)) for i in range(k)]
    est2 = [(estimate_mean(belief2, i), estimate_width(belief2, i)) for i in range(k)]
    proves(f"policy_factors K={k}", [belief1 == belief2],
           And(same(greedy(est1), greedy(est2)), same(ucb(beta, est1), ucb(beta, est2)),
               same(eps_greedy(eps, est1), eps_greedy(eps, est2))))

finish("theorems of the decision rules")
