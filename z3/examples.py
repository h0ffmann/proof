"""A concrete model you can run: the tabular model, and the examples the Haskell spec check
reproduces.

`tabular` keeps, for each (context, arm), a reward sum and a pull count:
mean = sum / count (0 when never pulled), width = 1 / (count + 1), a rational stand-in for
1 / sqrt(n). The policy is `rule(estimates(posterior(history), context))`: the rule sees the
history only through the belief.

The values below are the ground truth of `specCheck` in haskell/app/Main.hs. They are exact
rationals (Fraction) fed to the same Z3 rules as the theorems, so a change in a rule shows up
here first.

    python3 z3/examples.py
"""

from __future__ import annotations

import sys
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from bandit import eps_greedy, greedy  # noqa: E402
from refute import evaluates, finish, rational  # noqa: E402

# --------------------------------------------------------------------------------------
# The tabular model, over exact rationals

Belief = dict  # (context, arm) -> (reward sum, count)


def update(belief: Belief, context, arm: int, reward: Fraction) -> Belief:
    total, count = belief.get((context, arm), (Fraction(0), 0))
    return {**belief, (context, arm): (total + reward, count + 1)}


def estimate(belief: Belief, context, arm: int) -> tuple[Fraction, Fraction]:
    total, count = belief.get((context, arm), (Fraction(0), 0))
    mean = Fraction(0) if count == 0 else total / count
    return mean, Fraction(1, count + 1)


def posterior(history) -> Belief:
    belief: Belief = {}
    for context, arm, reward in history:
        belief = update(belief, context, arm, Fraction(reward))
    return belief


def policy(rule, history, context, arms: int):
    """The decision of a rule after a history, in a context, as Z3 terms."""
    belief = posterior(history)
    est = [tuple(rational(x) for x in estimate(belief, context, a)) for a in range(arms)]
    return rule(est)


# --------------------------------------------------------------------------------------
# Three arms; in the morning arm 1 pays off, in the evening arm 2.

history = [
    ("morning", 0, 0), ("morning", 1, 1), ("morning", 1, 1), ("morning", 2, 0),
    ("evening", 0, 0), ("evening", 1, 0), ("evening", 2, 1),
]

expected = {
    "greedy morning": (greedy, "morning", [0, 1, 0]),
    "greedy evening": (greedy, "evening", [0, 0, 1]),
    "epsGreedy 1/10 morning": (lambda est: eps_greedy(rational(Fraction(1, 10)), est), "morning",
                                [Fraction(1, 30), Fraction(14, 15), Fraction(1, 30)]),
}

for name, (rule, context, values) in expected.items():
    decision = policy(rule, history, context, arms=3)
    for arm, (p, v) in enumerate(zip(decision, values)):
        evaluates(f"{name} [{arm}]", p, Fraction(v))

finish("examples of the tabular model")
