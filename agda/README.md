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

## Other topics

The library has one root per topic, a file `src/<Topic>.agda`. `checks/agda.sh` type-checks
every root.

| Root | Ported from | What it proves |
|---|---|---|
| [`Cycle`](src/Cycle/Clock.agda) | `cycle/lean/Cycle/Clock.lean` | `tick-iterate` (k ticks are `(t + k) mod (n + 1)`), `eternal-return`, `history-periodic`, `returns-forever` |
| [`OceanWaves.Order`](src/OceanWaves/Order.agda), [`OceanWaves.Sums`](src/OceanWaves/Sums.agda) | `ocean-waves/lean/OceanWaves/RatLemmas.lean` | Lean's total division `_/₀_` (`inv₀ 0 = 0`) and its lemmas, the order lemmas, finite sums (`sumTo-comm`, `sumTo-pick`, the telescope) and `tabulate` with `tabulate-eq` |
| [`OceanWaves.Dispersion`](src/OceanWaves/Dispersion.agda) | `ocean-waves/lean/OceanWaves/Dispersion.lean` | for every `TanhModel`: `sigma2-strictMono`, the deep and shallow bounds, `nFactor-ge-half`, `nFactor-le-one`, `groupSpeed-bounds` (c/2 ≤ c_g ≤ c), `phaseSpeed-sq-le` (c² ≤ g h), `courant-le-one` (the depth-based CFL); the clamped Padé model `padeModel` with `pade-mono` and `pade-sech-bound` |
| [`OceanWaves.Bisection`](src/OceanWaves/Bisection.agda) | `ocean-waves/lean/OceanWaves/Bisection.lean` | the bracket invariants, `bisect-width` (the width halves at each step), `bisect-root`; the wavenumber kernel `waveNumber` with `waveNumber-upper` and `waveNumber-error` |
| [`OceanWaves.Advection`](src/OceanWaves/Advection.agda) | `ocean-waves/lean/OceanWaves/Advection.lean` | first-order upwind advection: `advect-eq` (a convex combination), `advect-sum` (only the boundary fluxes change the total), `advectPeriodic-sum` and `advectPeriodicN-sum` (exact conservation on a periodic grid), `advect-nonneg` and `advectPeriodicN-nonneg` (positivity under CFL), `advect-le-max` (no new maximum) |
| [`OceanWaves.Sources`](src/OceanWaves/Sources.agda) | `ocean-waves/lean/OceanWaves/Sources.lean` | `windRate-nonneg`, `windRate-zero`, `dsRate-nonneg`, `quad-moment`, `snl-conserves-action`, `snl-conserves-energy`, `linStep-nonneg` (for every Δt), `eulerStep-nonneg` (only under a restriction), the limiter, `sourceStep-nonneg`, `sourceStep-sum` |
| [`OceanWaves.ActionBalance`](src/OceanWaves/ActionBalance.agda) | `ocean-waves/lean/OceanWaves/ActionBalance.lean` | `advect-is-euler`; for one model step: `courant-bins`, `propagate-bin-sum`, `propagate-total`, `propagate-nonneg`, `step-nonneg`, `step-total`, and `stepFast-eq` (the tabulated kernel computes `step`) |
| [`OceanWaves.Examples`](src/OceanWaves/Examples.agda) | `ocean-waves/lean/OceanWaves/Examples.lean` (the idea) | one, two and five periodic steps of a pulse on three cells, by `refl` |
| [`OceanWaves.ModelExamples`](src/OceanWaves/ModelExamples.agda) | `ocean-waves/lean/OceanWaves/Examples.lean` | Lean's examples as checks Agda computes: c² ≤ g h in 10 m, a bump kept over four steps, a negative value above CFL, semi-implicit against Euler, no wind input for a 10 s wave and input for a 5 s wave, S_nl keeps action and energy, `cfg-valid`, `cfg-local`, and the 6 × 4 step that grows the total action |
| [`Grids`](src/Grids/SizeRule.agda) | `z3-scala/src/main/scala/grids/domain/Grids.scala`, parts 1 and 3 | `size-floor`, `size-steep-is-floor`, `size-smallest-minimum`; `chain-le-reach` (a chain of 30% steps from 5 km stays under 5 · 1.3^i, for every i), `growth-6-steps-below-30km`, and Z3's counterexample `growth-7-steps-reach-30km` as a witness |

Differences from the sources:

- Lean's `Fin (n + 1)` and `Fin.ext` are `Fin (suc n)` and `toℕ-injective`.
- Lean writes the upstream value of face i as `if i = 0 then b else N (i - 1)`. Agda matches on
  i (`upstream`), so each case reduces by computation.
- The periodic theorems take a grid of `suc n` cells, where Lean takes `n` with `0 < n`.
- `size-floor` holds for every input. Z3 states it for positive inputs.
- Z3 checks gradation for a chain of 7 and 8 sizes. Agda proves the bound for a chain of any
  length (`Chain h` is a function `ℕ → ℚ`) and reads it at 6 and 7 steps.
- Lean's `Rat` divides by zero and gives zero. `_/₀_` does the same, so the kernels read as in
  Lean. Equalities of fractions such as (σ/k)² = σ²/k² are not used: a proof multiplies by the
  inverse and cancels it with `inv₀-inverse`.
- Lean's `if c then … else …` on a decidable proposition is a function of the answer
  (`clamp` for the Padé model, `bisect-step`, `gate` for an interior centre), and each proof
  matches on the answer. A `with` on `x ≤? 3ℚ` does not abstract, because the goal unfolds it.
- Lean's `funext` is not available under `--safe`: `StepConfig.Local` and `snl-moment` state
  their equalities bin by bin.
- `ModelExamples.agda` checks numbers that Lean only prints with `#eval`, and has no `Float`
  reference (Lean compares with `Float.tanh` and a Newton solve). It uses 12 bisection steps
  where Lean prints 30.
- Not ported: parts 2, 4 and 5 of `Grids.scala` (the Courant number of a 600 s step,
  WAVEWATCH III's ITER, the measured mesh).

The skill [`.claude/skills/agda/SKILL.md`](../.claude/skills/agda/SKILL.md) says how to write
and check Agda here.
