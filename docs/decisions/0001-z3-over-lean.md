# 1. The contextual bandit is specified in Z3, not in Lean

Date: 2026-11-09. Status: accepted (the owner).

## Context

Until this decision the contextual bandit had two twins: a Lean 4 specification in
`lean/ContextualBandit/` (an interface, the decision rules, eleven theorems, examples with `#eval`,
and the video's invariants), and a Haskell port in `haskell/` whose spec check reproduced the
`#eval` outputs. On 2026-11-09 the video's invariants were written a second time in Z3
(`z3/video.py`), then the rule that every file is in English (`z3/language.py`). Reading the two
side by side, the owner asked that every invariant of the contextual bandit be in Z3 and that the
Lean package go: "quesito de interpretabilidade, código Z3 é muito mais human readable".

## Decision

The specification of the contextual bandit is `z3/`: `bandit.py` defines the two layers and the
rules, `theorems.py` what is proved about them, `examples.py` the tabular model and the values the
Haskell spec check reproduces, `video.py` the invariants of the video script. `lean/` is deleted.
The other experiments (ocean-waves, cycle, house-pricing) keep their Lean packages; this decision
is about the contextual bandit only.

Why Z3:

- **A statement reads as it is said.** `proves("ucb_valid", [], valid(ucb(beta, est)))` is the
  sentence "ucb returns a probability distribution", with no tactic script between the statement
  and the fact that it holds. A reader who knows Python and the problem can audit every line; a
  Lean proof needs a reader who knows Lean, Mathlib and the tactics.
- **The proof is a search, not a text.** Z3 looks for a counterexample in exact real arithmetic and
  reports `unsat`. There is nothing to maintain when a definition changes: the statement is run
  again. A Lean proof is a text that breaks when a definition moves and is repaired by hand.
- **The examples are the same code as the theorems.** `examples.py` feeds exact rationals to the
  same `greedy` and `eps_greedy` that `theorems.py` quantifies over, and the Haskell spec check
  compares with those values. In Lean the examples were `#eval`s beside the theorems.
- **One toolchain.** `python3` and `z3-solver` run anywhere in a second; the Lean package pulled
  Mathlib. The same Z3 already checks the language rule and the video.

## Consequences

What is lost, and how it is paid for:

- **K is bounded.** Z3 has no induction over the number of arms. Each theorem is checked for
  K = 1 to `MAX_ARMS` (5), for all real values of the estimates; the Lean theorems held for every
  K. The rules are the same code for every K, so the bound is on the search, not on the
  specification; raise `MAX_ARMS` to search further.
- **Factorials are concrete.** Z3 has no factorial of a symbolic k, so the positivity of
  Ramanujan's terms is checked for k = 0 to 9, in exact rationals; Leibniz's pairs still hold
  for every real k >= 0.
- **No proof artifact.** A Lean build leaves a term that another checker can verify. A Z3 run
  leaves a transcript of `unsat` answers; trust moves from Lean's kernel to Z3. The checks run on
  every `just check`, and the manual `check` workflow.
- **Nothing is lost on the theorems themselves.** All of Theorems.lean (validity of the three
  rules, the exploration bounds of eps-greedy, argmax, `ucb_zero`, the optimism lemma `ucb_gap`
  under calibration, `greedy_gap`, and `policy_factors` through an uninterpreted estimate
  function) and all of Video.lean (R1 to R5 and the examples) are in `z3/`, 100 statements.

The Haskell port is unchanged in code; its comments and spec check now point to `z3/`.
