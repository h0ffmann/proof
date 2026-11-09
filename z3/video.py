"""The invariants of the video script, checked with Z3.

This is the third form of lean/ContextualBandit/Video.lean, after the Haskell twin
(haskell/src/Video.hs). Lean proves each invariant for all values. Z3 does the same by
refutation: for each theorem, this script asserts its negation and asks Z3 for a model.
"unsat" means that no counterexample exists, so the theorem holds in the theory of real
arithmetic (QF_NRA, exact rationals). The #eval values of the Lean file are checked as
"sat" queries on the same definitions.

    python3 z3/video.py          # prints one line per invariant; exit code 1 on a failure

The decision rules (epsGreedy, uniform, greedy) are those of Policies.lean, for K = 3 arms,
with symbolic estimates. Z3 cannot speak about the factorial of a symbolic k, so the
Ramanujan terms are checked for k = 0 .. 9 and the Leibniz pairs for every real k >= 0.
"""

from __future__ import annotations

import sys
from fractions import Fraction
from math import factorial

from z3 import (And, Bool, If, Implies, Not, Or, RatVal, Real, RealVal, Reals, Solver,
                simplify, sat, unsat)

K = 3  # arms of the inner bandit and of the examples; M arms of the outer bandit below

failures = 0


def report(name: str, holds: bool, note: str = "") -> None:
    global failures
    mark = "OK " if holds else "FAIL"
    print(f"{mark}  {name:<28} {note}")
    if not holds:
        failures += 1


def proves(name: str, premises, conclusion, note: str = "") -> None:
    """Theorem: premises imply the conclusion. Z3 must find the negation unsat."""
    s = Solver()
    s.add(*premises)
    s.add(Not(conclusion))
    result = s.check()
    report(name, result == unsat, note or f"negation is {result}")


def evaluates(name: str, expression, expected: Fraction) -> None:
    """#eval: the closed expression equals the expected rational."""
    value = simplify(expression)
    holds = simplify(value == RatVal(expected.numerator, expected.denominator))
    report(name, bool(holds), f"= {value}  (Lean: {expected})")


# ---------------------------------------------------------------------------------------
# Policies.lean, for K arms: uniform, greedy (first arm with the largest mean), epsGreedy.


def uniform(k: int):
    return [RealVal(1) / k] * k


def argmax_first(scores):
    """Lean's argmaxFrom: the first index with the largest score, as a list of booleans."""
    chosen = []
    for i, score in enumerate(scores):
        earlier_not_larger = And(*[scores[j] < score for j in range(i)]) if i else True
        later_not_larger = And(*[scores[j] <= score for j in range(i + 1, len(scores))])
        chosen.append(And(earlier_not_larger, later_not_larger))
    return chosen


def point(chosen):
    return [If(c, RealVal(1), RealVal(0)) for c in chosen]


def greedy(means):
    return point(argmax_first(means))


def mix(w, d1, d2):
    return [w * p + (1 - w) * q for p, q in zip(d1, d2)]


def eps_greedy(eps, means):
    return mix(eps, uniform(len(means)), greedy(means))


def valid(decision):
    """Decision.Valid: every probability is >= 0 and the mass is 1."""
    return And(*[p >= 0 for p in decision], sum(decision) == 1)


# ---------------------------------------------------------------------------------------
# R1. The reward is the input of the user, in [0, 1]: clip and byDistance.

x, target = Reals("x target")


def clip(v):
    return If(v < 0, RealVal(0), If(1 < v, RealVal(1), v))


def dist(a, b):
    return If(a <= b, b - a, a - b)


def by_distance(t, v):
    return clip(1 - dist(v, t))


proves("clip_nonneg", [], clip(x) >= 0)
proves("clip_le_one", [], clip(x) <= 1)
proves("User.bounded (byDistance)", [], And(by_distance(target, x) >= 0, by_distance(target, x) <= 1))

# ---------------------------------------------------------------------------------------
# R2. One arm: exploit shows pi(N) again, explore computes pi(N+1).
# The approximation and the user are symbolic: approx_next is pi(N+1), reward_next is
# what the user says about it, in [0, 1].

n = Real("n")
shown, last_reward, approx_next, reward_next = Reals("shown last_reward approx_next reward_next")
user_bounded = And(reward_next >= 0, reward_next <= 1)


def explore_step():
    keep = last_reward <= reward_next
    return (n + 1, If(keep, approx_next, shown), If(keep, reward_next, last_reward))


def step(explore: bool):
    return explore_step() if explore else (n, shown, last_reward)


n_exploit, shown_exploit, reward_exploit = step(explore=False)
n_explore, shown_explore, reward_explore = step(explore=True)

proves("step_exploit", [], And(n_exploit == n, shown_exploit == shown, reward_exploit == last_reward))
proves("step_explore_n", [], n_explore == n + 1)
proves("step_explore_reward", [], last_reward <= reward_explore)
proves("step_reward_bounded", [user_bounded, last_reward >= 0, last_reward <= 1],
       And(reward_explore >= 0, reward_explore <= 1, reward_exploit >= 0, reward_exploit <= 1))

# ---------------------------------------------------------------------------------------
# R3. Explore-then-commit is one decision rule: epsGreedy 1 before T, epsGreedy 0 after.

means = Reals("m0 m1 m2")
T, t = Reals("T t")


def etc(horizon, now, est_means):
    before = now < horizon
    return [If(before, p1, p0) for p1, p0 in zip(eps_greedy(RealVal(1), est_means), eps_greedy(RealVal(0), est_means))]


proves("epsGreedy_zero", [], And(*[a == b for a, b in zip(eps_greedy(RealVal(0), means), greedy(means))]))
proves("epsGreedy_one_is_ab_test", [], And(*[a == b for a, b in zip(eps_greedy(RealVal(1), means), uniform(K))]))
proves("etc_before", [t < T], And(*[a == b for a, b in zip(etc(T, t, means), uniform(K))]))
proves("etc_after", [Not(t < T)], And(*[a == b for a, b in zip(etc(T, t, means), greedy(means))]))
proves("etc_valid", [], valid(etc(T, t, means)))

# ---------------------------------------------------------------------------------------
# R4. RSI: the outer agent (M arms, one per candidate eps) uses epsGreedy too.

M = 4
eps0 = Real("eps0")
outer_means = Reals("o0 o1 o2 o3")
inner_eps = Reals("e0 e1 e2 e3")
inner_means = Reals("i0 i1 i2")
eps_probabilities = [And(e >= 0, e <= 1) for e in inner_eps]

outer = eps_greedy(eps0, outer_means)
proves("rsi_valid (outer)", [eps0 >= 0, eps0 <= 1], valid(outer))
proves("rsi_valid (inner, each i)", eps_probabilities,
       And(*[valid(eps_greedy(e, inner_means)) for e in inner_eps]))
proves("outer_explores", [eps0 <= 1], And(*[eps0 / M <= p for p in outer]))

# ---------------------------------------------------------------------------------------
# R5. The series of pi have positive terms.

k = Real("k")
leibniz_pair = 4 / (4 * k + 1) - 4 / (4 * k + 3)
proves("leibnizPair_pos (real k >= 0)", [k >= 0], leibniz_pair > 0)


def ramanujan_term(j: int) -> Fraction:
    return Fraction(factorial(4 * j) * (1103 + 26390 * j), factorial(j) ** 4 * 396 ** (4 * j))


ram_terms = [ramanujan_term(j) for j in range(10)]
report("ramTerm_pos (k = 0..9)", all(term > 0 for term in ram_terms), "each term is a positive rational")
ram_sums = [sum(ram_terms[:j], Fraction(0)) for j in range(11)]
report("ramSum_lt_succ (n = 0..9)", all(a < b for a, b in zip(ram_sums, ram_sums[1:])), "partial sums increase")

c, s_n, s_next = Reals("c s_n s_next")
proves("ramApprox_anti", [c > 0, s_n > 0, s_n < s_next], 1 / (c * s_next) < 1 / (c * s_n))

# ---------------------------------------------------------------------------------------
# The #eval values of Video.lean.


def leibniz(terms: int) -> Fraction:
    return sum((Fraction(4 * (-1) ** j, 2 * j + 1) for j in range(terms)), Fraction(0))


evaluates("leibniz 1", RealVal(str(leibniz(1))), Fraction(4))
evaluates("leibniz 2", RealVal(str(leibniz(2))), Fraction(8, 3))
evaluates("leibniz 5", RealVal(str(leibniz(5))), Fraction(1052, 315))
evaluates("leibnizEven 2", RealVal(str(sum((Fraction(4, 4 * j + 1) - Fraction(4, 4 * j + 3) for j in range(2)), Fraction(0)))), Fraction(304, 105))
evaluates("ramSum 1", RealVal(str(ram_sums[1])), Fraction(1103))

est3 = [RatVal(1, 2), RatVal(9, 10), RatVal(1, 10)]
for i, (p3, p10) in enumerate(zip(etc(RealVal(10), RealVal(3), est3), etc(RealVal(10), RealVal(10), est3))):
    evaluates(f"etc 10 3 est3 [{i}]", p3, Fraction(1, 3))
    evaluates(f"etc 10 10 est3 [{i}]", p10, Fraction(1 if i == 1 else 0))

# step with leibniz and byDistance (355/113), from <1, leibniz 1, 0>: explore gives n = 2, exploit n = 1.
s = Solver()
s.add(n == 1, shown == RealVal(str(leibniz(1))), last_reward == 0,
      approx_next == RealVal(str(leibniz(2))), reward_next == by_distance(RatVal(355, 113), approx_next))
assert s.check() == sat
model = s.model()
report("step explore n", model.eval(n_explore) == 2, f"= {model.eval(n_explore)}  (Lean: 2)")
report("step exploit n", model.eval(n_exploit) == 1, f"= {model.eval(n_exploit)}  (Lean: 1)")

print()
if failures:
    print(f"{failures} invariant(s) failed")
    sys.exit(1)
print("every invariant holds (Z3)")
