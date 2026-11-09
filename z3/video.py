"""The invariants of the video script (papers/contextual-bandits/script/), checked with Z3.

The requirements of the owner for the 30-minute video, as statements. Each R is one sentence
of the owner, 2026-11-09:

* R1. The reward is the input of the user. A user gives a reward in [0, 1] for each thing
  shown; the agent sees nothing else.
* R2. One arm: exploitation shows pi(N), exploration computes pi(N+1). One arm, two actions.
* R3. The A/B test is a special case of the CMAB. The whole A/B procedure, "explore then
  commit", is one decision rule: eps_greedy(1) before the switch, eps_greedy(0) after it.
* R4. RSI is the same rule, applied to itself. The arms of the outer agent are values of eps
  for the inner agent; the outer rule is eps_greedy again.
* R5. The two series of pi have positive terms. Thus their partial sums increase.

For each statement, Z3 looks for a counterexample in exact real arithmetic and finds none.
The approximation of pi and the user's answer are symbolic reals, so R1 and R2 hold for every
user and every series. Z3 has no factorial of a symbolic k, so the Ramanujan terms are checked
for k = 0 to 9 and the Leibniz pairs for every real k >= 0. The examples at the end are the
ground truth of the spec check in haskell/app/Main.hs; haskell/src/Video.hs is the port that
runs, name for name.

    python3 z3/video.py
"""

from __future__ import annotations

import sys
from fractions import Fraction
from math import factorial
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from z3 import And, If, Not, Real, RealVal, Reals, Solver, sat  # noqa: E402

from bandit import eps_greedy, estimates, greedy, same, uniform, valid  # noqa: E402
from refute import evaluates, finish, proves, rational, report  # noqa: E402

K = 3  # arms of the inner bandit and of the examples
M = 4  # arms of the outer bandit: the candidate values of eps

# --------------------------------------------------------------------------------------
# R1. The reward is the input of the user, in [0, 1].

x, target = Reals("x target")


def clip(v):
    """v brought into [0, 1]."""
    return If(v < 0, RealVal(0), If(1 < v, RealVal(1), v))


def dist(a, b):
    return If(a <= b, b - a, a - b)


def by_distance(t, v):
    """The simulated user of the video: the grade of v is 1 - |v - t|, clipped."""
    return clip(1 - dist(v, t))


proves("clip_nonneg", [], clip(x) >= 0)
proves("clip_le_one", [], clip(x) <= 1)
proves("User.bounded (byDistance)", [], And(by_distance(target, x) >= 0, by_distance(target, x) <= 1))

# --------------------------------------------------------------------------------------
# R2. One arm. The state is (n, shown, last_reward): the terms paid for, the approximation the
# user saw, the grade the user gave. approx_next is pi(n+1) and reward_next the user's grade of
# it, both symbolic.

n, shown, last_reward, approx_next, reward_next = Reals("n shown last_reward approx_next reward_next")
user_bounded = And(reward_next >= 0, reward_next <= 1)


def step(explore: bool):
    """To exploit changes nothing. To explore pays one term, shows pi(n+1), and keeps the
    new grade when it is not lower."""
    if not explore:
        return n, shown, last_reward
    keep = last_reward <= reward_next
    return n + 1, If(keep, approx_next, shown), If(keep, reward_next, last_reward)


n_exploit, shown_exploit, reward_exploit = step(explore=False)
n_explore, shown_explore, reward_explore = step(explore=True)

proves("step_exploit", [], And(n_exploit == n, shown_exploit == shown, reward_exploit == last_reward))
proves("step_explore_n", [], n_explore == n + 1)
proves("step_explore_reward", [], last_reward <= reward_explore)
proves("step_reward_bounded", [user_bounded, last_reward >= 0, last_reward <= 1],
       And(reward_explore >= 0, reward_explore <= 1, reward_exploit >= 0, reward_exploit <= 1))

# --------------------------------------------------------------------------------------
# R3. Explore-then-commit is one decision rule: eps_greedy(1) before T, eps_greedy(0) after.

est = estimates(K)
T, t = Reals("T t")


def etc(horizon, now, estimates_):
    before = now < horizon
    return [If(before, p1, p0)
            for p1, p0 in zip(eps_greedy(RealVal(1), estimates_), eps_greedy(RealVal(0), estimates_))]


proves("epsGreedy_zero", [], same(eps_greedy(RealVal(0), est), greedy(est)))
proves("etc_before", [t < T], same(etc(T, t, est), uniform(K)))
proves("etc_after", [Not(t < T)], same(etc(T, t, est), greedy(est)))
proves("etc_valid", [], valid(etc(T, t, est)))

# --------------------------------------------------------------------------------------
# R4. RSI: the outer agent (M arms, one per candidate eps) uses eps_greedy too.

eps0 = Real("eps0")
outer_est = estimates(M, "o")
inner_eps = [Real(f"eps{i}") for i in range(M)]
inner_est = estimates(K, "i")
outer = eps_greedy(eps0, outer_est)

proves("rsi_valid (outer)", [eps0 >= 0, eps0 <= 1], valid(outer))
proves("rsi_valid (inner, each i)", [And(e >= 0, e <= 1) for e in inner_eps],
       And(*[valid(eps_greedy(e, inner_est)) for e in inner_eps]))
proves("outer_explores", [eps0 <= 1], And(*[eps0 / M <= p for p in outer]))

# --------------------------------------------------------------------------------------
# R5. The series of pi have positive terms.

k = Real("k")
leibniz_pair = 4 / (4 * k + 1) - 4 / (4 * k + 3)   # two consecutive terms of Leibniz, times 4
proves("leibnizPair_pos (real k >= 0)", [k >= 0], leibniz_pair > 0)


def ramanujan_term(j: int) -> Fraction:
    """(4j)! (1103 + 26390 j) / ((j!)^4 396^(4j)), the j-th term of Ramanujan's sum."""
    return Fraction(factorial(4 * j) * (1103 + 26390 * j), factorial(j) ** 4 * 396 ** (4 * j))


ram_terms = [ramanujan_term(j) for j in range(10)]
report("ramTerm_pos (k = 0..9)", all(term > 0 for term in ram_terms), "each term is a positive rational")
ram_sums = [sum(ram_terms[:j], Fraction(0)) for j in range(11)]
report("ramSum_lt_succ (n = 0..9)", all(a < b for a, b in zip(ram_sums, ram_sums[1:])), "partial sums increase")

c, s_n, s_next = Reals("c s_n s_next")
proves("ramApprox_anti", [c > 0, s_n > 0, s_n < s_next], 1 / (c * s_next) < 1 / (c * s_n))

# --------------------------------------------------------------------------------------
# Examples: the ground truth of the Haskell spec check.


def leibniz(terms: int) -> Fraction:
    """4 * sum_{j < terms} (-1)^j / (2j + 1)."""
    return sum((Fraction(4 * (-1) ** j, 2 * j + 1) for j in range(terms)), Fraction(0))


def leibniz_even(pairs: int) -> Fraction:
    return sum((Fraction(4, 4 * j + 1) - Fraction(4, 4 * j + 3) for j in range(pairs)), Fraction(0))


evaluates("leibniz 1", rational(leibniz(1)), Fraction(4))
evaluates("leibniz 2", rational(leibniz(2)), Fraction(8, 3))
evaluates("leibniz 5", rational(leibniz(5)), Fraction(1052, 315))
evaluates("leibnizEven 2", rational(leibniz_even(2)), Fraction(304, 105))
evaluates("ramSum 1", rational(ram_sums[1]), Fraction(1103))

est3 = [(rational(Fraction(1, 2)), RealVal(0)), (rational(Fraction(9, 10)), RealVal(0)), (rational(Fraction(1, 10)), RealVal(0))]
for i, (p3, p10) in enumerate(zip(etc(RealVal(10), RealVal(3), est3), etc(RealVal(10), RealVal(10), est3))):
    evaluates(f"etc 10 3 est3 [{i}]", p3, Fraction(1, 3))
    evaluates(f"etc 10 10 est3 [{i}]", p10, Fraction(1 if i == 1 else 0))

# step with leibniz and byDistance(355/113), from (1, leibniz 1, 0): explore gives n = 2, exploit n = 1.
s = Solver()
s.add(n == 1, shown == rational(leibniz(1)), last_reward == 0,
      approx_next == rational(leibniz(2)), reward_next == by_distance(rational(Fraction(355, 113)), approx_next))
assert s.check() == sat
model = s.model()
report("step explore n", model.eval(n_explore) == 2, f"= {model.eval(n_explore)}  (expected 2)")
report("step exploit n", model.eval(n_exploit) == 1, f"= {model.eval(n_exploit)}  (expected 1)")

finish("invariants of the video")
