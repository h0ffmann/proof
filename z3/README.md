# Z3

The invariants of the video script (`lean/ContextualBandit/Video.lean`) in a third form, after
the Haskell twin (`haskell/src/Video.hs`): an SMT check with Z3, in Python (`z3-solver`).

Lean proves each theorem for all values. `video.py` does the same by refutation: it asserts the
negation of each theorem and asks Z3 for a model. `unsat` means that no counterexample exists in
exact real arithmetic. The `#eval` values of the Lean file are checked as closed terms.

| In Lean | In Z3 | How |
|---|---|---|
| `clip_nonneg`, `clip_le_one`, `User.bounded` | the same names | negation unsat, for every real `x` and `target` |
| `step_exploit`, `step_explore_n`, `step_explore_reward`, `step_reward_bounded` | the same names | the approximation and the user's answer are symbolic reals |
| `epsGreedy_zero`, `epsGreedy_one_is_ab_test`, `etc_before`, `etc_after`, `etc_valid` | the same names | K = 3 arms, symbolic means and rounds |
| `rsi_valid`, `outer_explores` | the same names | M = 4 candidate ε, K = 3 inner arms, every ε symbolic |
| `leibnizPair_pos` | the same name | for every real `k ≥ 0` (Lean: every natural `k`) |
| `ramTerm_pos`, `ramSum_lt_succ` | the same names | for `k = 0 .. 9` only: Z3 has no factorial of a symbolic `k` |
| `ramApprox_anti` | the same name | symbolic `c`, `s_n`, `s_next` |
| the `#eval` lines | `leibniz 1, 2, 5`, `leibnizEven 2`, `ramSum 1`, `etc 10 3`, `etc 10 10`, `step` | closed terms, compared with the Lean output |

Run it:

```sh
just z3          # python3 z3/video.py
```

It needs `z3-solver` (`pip install z3-solver`, or `python3-z3` from the distribution; `nix
develop` has it). The exit code is 1 when an invariant fails.
