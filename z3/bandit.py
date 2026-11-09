"""The contextual bandit, as a specification in Z3.

The design splits a contextual bandit into two layers:

* a reward model (the probabilistic part): a belief that is updated with observations
  (context, arm, reward) and that reports, for each context and arm, a predicted mean reward
  and an uncertainty width;
* a decision rule (the bandit part): a function that sees only those per-arm estimates and
  returns a probability for each arm.

The decision rules never see the raw history. They see it only through the model. That boundary
is what lets a model be swapped (Beta-Bernoulli, Bayesian linear regression, a neural net with
calibrated uncertainty) without touching the decision layer, and the other way round.

This file defines the decision layer as Z3 terms over the reals. A decision rule here is a
Python function from a list of K estimates to a list of K probabilities. Each estimate is a
pair (mean, width) of Z3 reals; the rules are built from If, +, * and comparisons, so that
`theorems.py` can ask Z3 whether a statement holds for every real value of the estimates.

K, the number of arms, is a Python integer: Z3 has no induction over lists. The theorems are
proved for each K from 1 to MAX_ARMS, for all real estimates. `docs/decisions/0001-z3-over-lean.md` says
why that trade was made.

haskell/src/ContextualBandit.hs is the port that runs, name for name.
"""

from __future__ import annotations

from z3 import And, BoolRef, If, Real, RealVal

MAX_ARMS = 5

Estimate = tuple  # (mean, width), two Z3 reals
Decision = list   # one Z3 real per arm


def estimates(k: int, prefix: str = "e") -> list[Estimate]:
    """K symbolic estimates: (mean_i, width_i)."""
    return [(Real(f"{prefix}{i}_mean"), Real(f"{prefix}{i}_width")) for i in range(k)]


def mean(e: Estimate):
    return e[0]


def width(e: Estimate):
    return e[1]


# --------------------------------------------------------------------------------------
# Argmax. Every deterministic rule (greedy, UCB) is "argmax of some score". Ties go to the
# first arm, the same convention as the Haskell port.


def argmax_first(scores) -> list[BoolRef]:
    """One Boolean per arm: this arm is the first with the largest score.

    Arm i is chosen when every earlier score is strictly smaller and no later score is larger.
    Exactly one of the Booleans is true for any real scores.
    """
    chosen = []
    for i, score in enumerate(scores):
        earlier_smaller = And(*[scores[j] < score for j in range(i)]) if i else True
        later_not_larger = And(*[scores[j] <= score for j in range(i + 1, len(scores))])
        chosen.append(And(earlier_smaller, later_not_larger))
    return chosen


# --------------------------------------------------------------------------------------
# Decisions and the rules


def point(chosen: list[BoolRef]) -> Decision:
    """Point mass on the chosen arm."""
    return [If(c, RealVal(1), RealVal(0)) for c in chosen]


def uniform(k: int) -> Decision:
    return [RealVal(1) / k] * k


def mix(w, d1: Decision, d2: Decision) -> Decision:
    """w * d1 + (1 - w) * d2."""
    return [w * p + (1 - w) * q for p, q in zip(d1, d2)]


def ucb_score(beta, e: Estimate):
    return mean(e) + beta * width(e)


def greedy_arm(est: list[Estimate]) -> list[BoolRef]:
    return argmax_first([mean(e) for e in est])


def ucb_arm(beta, est: list[Estimate]) -> list[BoolRef]:
    return argmax_first([ucb_score(beta, e) for e in est])


def greedy(est: list[Estimate]) -> Decision:
    """Pure exploitation: the arm with the largest mean."""
    return point(greedy_arm(est))


def ucb(beta, est: list[Estimate]) -> Decision:
    """Optimism in the face of uncertainty: the arm with the largest mean + beta * width.
    With a Bayesian linear model this is LinUCB."""
    return point(ucb_arm(beta, est))


def eps_greedy(eps, est: list[Estimate]) -> Decision:
    """With probability eps pick an arm uniformly, otherwise be greedy."""
    return mix(eps, uniform(len(est)), greedy(est))


# --------------------------------------------------------------------------------------
# What a decision must be


def mass(d: Decision):
    return sum(d)


def valid(d: Decision):
    """A probability distribution: every arm non-negative, the mass is 1."""
    return And(*[p >= 0 for p in d], mass(d) == 1)


def same(d1: Decision, d2: Decision):
    return And(*[a == b for a, b in zip(d1, d2)])
