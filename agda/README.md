# agda/

The decision layer of the contextual bandit, and its theorems, in Agda 2.8.0 with the standard
library 2.3 only. Z3 (`z3-scala/src/main/scala/bandit/domain/`) stays the specification and
proves each statement for K = 1 to 5 arms. Agda proves the same statements for every K, by
induction on K, over exact rationals (`Data.Rational`). The design and the theorems come from
the Lean 4 package that held the bandit until 2026-11-09
([`docs/decisions/0001-z3-over-lean.md`](../docs/decisions/0001-z3-over-lean.md)).

## Run

```bash
just agda                                   # hygiene, self-test, then type-check (nix develop .#agda)
nix develop .#agda --command bash -c 'cd agda/src && agda ContextualBandit.agda'
```

A theorem is proved when its module type-checks. Every file starts with
`{-# OPTIONS --safe --without-K #-}`. `--safe` refuses `postulate`, the termination pragmas and
every other way to accept a statement without a proof. `checks/agda.sh` refuses a file without
it. Its self-test shows that a wrong example, a postulate and a file without `--safe` fail.

## Modules

| Module | What it holds |
|---|---|
| [`Interface.agda`](src/ContextualBandit/Interface.agda) | `Arm`, `Obs`, `Estimate`, `RewardModel` (with `posterior`), `Decision`, `DecisionRule`, `policy`, `invK` |
| [`Argmax.agda`](src/ContextualBandit/Argmax.agda) | `argmaxFrom`, `argmax` (the first maximum wins), `argmax-spec`, `argmax-cong` |
| [`Policies.agda`](src/ContextualBandit/Policies.agda) | `point`, `uniform`, `mix`, `ucbScore`, `greedy`, `ucb`, `epsGreedy`, `thompsonArm`, `mass`, `Valid` |
| [`Theorems.agda`](src/ContextualBandit/Theorems.agda) | the theorems below, and the sum lemmas they use |
| [`Examples.agda`](src/ContextualBandit/Examples.agda) | the tabular model of `Examples.scala`; each decision is checked by `refl` |

| Agda | Z3 (`Theorems.scala`) | Statement |
|---|---|---|
| `greedy-valid`, `ucb-valid`, `epsGreedy-valid` | `greedy_valid`, `ucb_valid`, `epsGreedy_valid` | the output is a probability distribution when `0 ≤ ε ≤ 1` |
| `epsGreedy-prob` | `epsGreedy_prob` | the greedy arm gets `1 - ε + ε/K`, each other arm `ε/K` |
| `epsGreedy-explores` | `epsGreedy_explores` | each arm has probability ≥ `ε/K` |
| `epsGreedy-one-is-ab-test` | `epsGreedy_one_is_ab_test` | ε = 1 gives the uniform decision |
| `greedy-is-argmax`, `ucb-is-argmax` | `greedy_is_argmax`, `ucb_is_argmax` | the selected arm maximises its score |
| `ucb-zero` | `ucb_zero` | UCB with β = 0 is greedy |
| `ucb-gap` | `ucb_gap` | calibrated model: UCB's arm is within `2 * (β * width)` of every arm |
| `greedy-gap` | `greedy_gap` | δ-accurate model: greedy loses at most `2 * δ` |
| `policy-factors` | `policy_factors` | two histories with the same belief give the same decision |

## Differences from Z3 and Lean

- A decision is a function `Arm K → ℚ`, and two decisions are compared arm by arm (`ucb-zero`,
  `policy-factors`, `epsGreedy-one-is-ab-test`): `--safe` has no function extensionality.
- `mass d` is the sum of `tabulate d`, the same list as Lean's map over `List.finRange K`, so
  the sums go by induction on K.
- `invK K` is `1 / ofℕ K` with `ofℕ` defined by recursion (`1 + ... + 1`), and `0` when K = 0.
- `2 * x` is written `2ℚ * x` with `2ℚ = 1 + 1`.
- The tabular model's width is `1 / (n + 1)`, as in Lean: `Data.Rational` has no square root.
- The video's rules (`Video.scala`: `etc`, `outer`, π) are not ported.

The skill [`.claude/skills/agda/SKILL.md`](../.claude/skills/agda/SKILL.md) says how to write
and check Agda here.
