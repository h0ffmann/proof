# agda/

The decision layer of the contextual bandit, and its theorems, in Agda 2.8.0 with the standard
library 2.3 only. It is the specification since 2026-11-11, when `z3-scala/` was removed; Z3
checked each statement there for K = 1 to 5 arms. Agda proves the same statements for every K, by
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
| [`Video.agda`](src/ContextualBandit/Video.agda) | the invariants R1 to R5 of the video script (`Video.scala`), and its examples by `refl` |

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
- The video's rules (`Video.scala`, R1 to R5) are in [`Video.agda`](src/ContextualBandit/Video.agda):
  `clip`, `byDistance`, `explore`, `exploit`, `etc`, the RSI statements and the two series of
  π, with Z3's examples by `refl`. Z3 checks R3 and R4 for K = 3 and M = 4, and the Ramanujan
  terms for k = 0 to 9. Agda proves them for every K and M and every term, and that the paired
  Leibniz sums and the Ramanujan sums increase at every n.

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
| [`Grids.Courant`](src/Grids/Courant.agda) | `Grids.scala`, part 2 | `courant-at-least-1`, `courant-above-1-where-finer`; Z3's counterexample `explicit_600s_stable` as a witness |
| [`Grids.Iter`](src/Grids/Iter.agda) | `Grids.scala`, part 4 | WAVEWATCH III's ITER: `iter-covers-cfl-to-thr8`, `iter-covers-cfl-unless-rest-in-0-thr8`, `iter-at-least-1-above-thr8`; the counterexamples `iter_covers_cfl` and `iter_at_least_1` as one witness (`small-cfl`) |
| [`Leo`](src/Leo/Problems.agda) | `z3-scala/leo/*.p` (Leo-III) | `through-belief`, `cantor` and `cantor-Set`, `surj-right-inverse`, `compose`; `surj-injective-refuted` refutes the problem that Leo-III must not prove |
| [`PortAudit.Division`](src/PortAudit/Division.agda) | `Chaceon.scala`, group D (integers) | `no-tie` and `margin` for every t, A, B and M, read at Z3's ranges (`no-tie-24`, `no-tie-25`, `margin-24`, `margin-25`); `margin-2^48-fails` and `no-tie-needs-normal` as witnesses |
| [`PortAudit.Rounding`](src/PortAudit/Rounding.agda) | `Chaceon.scala`, group D (reals) | `same-side` and `same-side-not-tie` for every error bound that meets two inequalities, read at 2^-49 and 5/2 · 2^-52; `same-side-8ulp-fails` as a witness; `closer-lo` |
| [`PortAudit.TimeStep`](src/PortAudit/TimeStep.agda) | `Chaceon.scala`, group S (reals) | `implicit-le-explicit` (for every dt), `limiter-bounds-increment`, `split-idt-ge-1`, `split-le-rem`, `split-le-dt/0·99`, `step-never-past-dtg`, `step-progress`; `limiter-vs-floor-0·5` and `split-le-dt-refuted` as witnesses |
| [`TextChecks`](src/TextChecks/Verdict.agda) | `Ptc.scala`, `NoiseCatalogue.scala`, `LanguageRule.scala` | the decision layer of the text checks: the verdict and the list of broken units are right for every text (`holds-sound`, `holds-complete`, `broken-sound`, `broken-complete`), the exit code is 0 exactly when every required check holds (`exit-zero`, `zero-exit`), `CHECKS` with its limits, the level table of the noise catalogue (`sempre-sai-required`, `stricter-never-relaxes`, `leve-fails-only-sempre-sai`), and the stop-word judgement of the language rule (`short-not-judged`, `judged-rule`) |

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
- `Grids.Iter` and `PortAudit.TimeStep` take Z3's integer floor and count as natural numbers:
  Z3's premises make each one larger than a positive number, so no case is lost.
- Leo-III's logic is classical with choice. In Agda "for every y there is an x" is a dependent
  pair, so `surj-right-inverse` needs no axiom. Cantor's theorem is proved for Boolean sets and
  for sets as predicates into `Set`.
- `margin` uses `gap`, Z3's `ite(lhs >= rhs, lhs - rhs, rhs - lhs)` on the built-in ℕ
  operations: the standard library's `∣_-_∣` recurses in unary, and a witness on 50-bit numbers
  does not finish.
- The text checks measure the script and the files with regular expressions. Agda proves
  while it type-checks, and under `--safe` it cannot read a file, so the measures are in Haskell
  ([`tools/text-checks/`](../tools/text-checks/README.md)) and the Agda modules take them as functions. The rules that `ptc --review` lists need the
  meaning of a sentence, which no formula gives.
- Not ported to Agda, and in Haskell instead:
  - part 5 of `Grids.scala`, NOTE lines that print numbers of a measured mesh (it uses `Double`
    and `x^1.4`): [`tools/room-mesh/`](../tools/room-mesh/Main.hs);
  - groups U and S of `Chaceon.scala` over IEEE f32 (`nint`, `floor`, `sign`, the f32 spectrum
    update): they are about the bits that Rust computes, and ℚ has no rounding;
    [`tools/port-audit/`](../tools/port-audit/README.md) asks Z3 through SBV;
  - `Coverage.scala`, a count over the fetched WAVEWATCH III sources, which is a measurement and
    not a statement: `tools/port-audit/`, too.

The skill [`.claude/skills/agda/SKILL.md`](../.claude/skills/agda/SKILL.md) says how to write
and check Agda here.
