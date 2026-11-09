# Z3: the specification of the contextual bandit

The contextual bandit is specified here, in Python over Z3 (`z3-solver`), and ported to Haskell in
`haskell/`. Every statement is proved by refutation (`refute.py`): the premises and the negation of
the conclusion are asserted, and Z3 is asked for a model. `unsat` means that no counterexample
exists in exact real arithmetic. A model, when there is one, is printed: it is the counterexample.
It was a Lean 4 package until 2026-11-09; `docs/decisions/0001-z3-over-lean.md` says why it moved
and what the move cost.

| File | What it holds | Statements |
|---|---|---|
| `refute.py` | `proves(name, premises, conclusion)`, `evaluates(name, term, rational)`, `finish()` | the method |
| `bandit.py` | the two layers: K estimates `(mean, width)` as Z3 reals; the rules `greedy`, `ucb(beta)`, `eps_greedy(eps)` built from `argmax_first` (ties to the first arm), `point`, `uniform`, `mix`; `valid`, `same` | the definitions |
| `theorems.py` | validity of the three rules, `epsGreedy_prob`, `epsGreedy_explores`, `epsGreedy_one_is_ab_test`, `greedy_is_argmax`, `ucb_is_argmax`, `ucb_zero`, the optimism lemma `ucb_gap` under calibration, `greedy_gap`, `policy_factors` (an uninterpreted estimate function) | 60, for K = 1..5 |
| `examples.py` | the tabular model over exact rationals (`update`, `estimate`, `posterior`, `policy`) and the values the Haskell spec check reproduces | 9 |
| `video.py` | the video script's invariants R1 to R5 (`papers/contextual-bandits/script/`): the user as reward, the one-armed agent, explore-then-commit as one rule, RSI as the same rule, the series of pi; and the examples of the spec check | 31 |
| `language.py` | the language rule of `AGENTS.md`: every tracked text file is in English unless its path carries `pt-BR`, as `portuguese(f) <-> marked_pt_br(f)` | one per file |

What Z3 cannot do, and how it is bounded:

- **No induction over K.** Each theorem is checked for every K from 1 to `MAX_ARMS` (5) in
  `bandit.py`, for all real estimates. The rules are the same code for every K.
- **No factorial of a symbolic k.** The positivity of Ramanujan's terms is checked for k = 0 to 9
  in exact rationals; Leibniz's pairs hold for every real k >= 0.
- **No probability.** The probabilistic half of a regret bound (calibration with high
  probability, the sum of the widths) is not here, as it was not in Lean.

Run it:

```sh
just z3          # theorems.py, examples.py, video.py, language.py; every line OK, exit 1 otherwise
```

It needs `z3-solver` (`pip install z3-solver`, or `python3-z3` from the distribution). The Haskell
spec check (`cabal run examples`, block 0) compares its values with `examples.py` and `video.py`.
