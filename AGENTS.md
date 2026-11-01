# AGENTS.md

Guidance for coding agents (and humans) working in this repo.

## What this repo is

`dogma` holds **specifications proved in Lean 4** and **implementations that
follow them** in Haskell (Python may come later). Lean is the source of truth.
The implementations mirror the Lean definitions name for name. The owner cares
more about using Lean as a verified spec than about Lean itself.

The current topic is contextual bandits, split into a probabilistic
`RewardModel` and a `DecisionRule` on top of it. See `README.md`.

## Layout

```
lean/      Lean 4 package `ContextualBandit` (Lake, core Lean only, no Mathlib)
  ContextualBandit/Interface.lean   types: Obs, Estimate, RewardModel, DecisionRule, policy
  ContextualBandit/Argmax.lean      verified argmax
  ContextualBandit/Policies.lean    greedy, ucb, epsGreedy
  ContextualBandit/Theorems.lean    all proofs
  ContextualBandit/Examples.lean    #eval examples (ground truth for the Haskell spec check)
haskell/   cabal package `contextual-bandit` (only base + containers)
  src/ContextualBandit.hs           port of Interface + Policies, plus a pure SplitMix RNG
  src/Models.hs                     Beta-Bernoulli, Bayesian linear (LinUCB/LinTS), fromPredictor
  app/Main.hs                       spec check against Lean + simulations
```

## Build and check

```bash
# Lean (toolchain pinned in lean/lean-toolchain; install via elan)
cd lean && lake build            # must finish with no errors; prints the #eval outputs

# Haskell (GHC >= 9.4)
cd haskell && cabal run examples
# or, without cabal:
cd haskell && mkdir -p build && ghc -O2 -Wall -isrc -outputdir build -o build/examples app/Main.hs && ./build/examples
```

The first block of the Haskell output is **"Spec check against Lean #eval"**.
Every line must say `OK`.

## Rules

1. **No `sorry`, `admit` or new `axiom`** in `lean/`. Check with
   `grep -rnE "sorry|admit|^axiom" lean/ContextualBandit`. `native_decide` is
   allowed only in `Examples.lean`.
2. **Lean first.** A new decision rule or model goes in Lean (definition plus at
   least a validity theorem), then in Haskell with the same name. Update the
   mapping table in `README.md`.
3. **Keep the mirror exact.** Tie-breaking (argmax keeps the *first* maximum),
   argument order and the meaning of `width` must match between Lean and Haskell.
   When a Lean `#eval` in `Examples.lean` changes, update `specCheck` in
   `haskell/app/Main.hs`.
4. **Decision rules see only estimates.** A `DecisionRule` gets per-arm
   `Estimate`s, never the history or the context. Uncertainty belongs to the
   model, choice belongs to the rule. Don't break this boundary; the
   `policy_factors` and `ucb_gap` theorems rely on it.
5. **Lean stays core-only** unless a proof truly needs Mathlib (for example
   concentration inequalities or martingales). If you add Mathlib, pin a
   version in `lakefile.toml`, note why in the PR, and keep `lake build` working.
6. **Haskell stays dependency-light**: `base` and `containers` only, unless agreed.
   Build with `-Wall` and leave no warnings.
7. **Exact vs float**: Lean uses `Rat`, Haskell uses `Double`. Don't claim a
   Lean theorem covers floating-point behaviour.

## Good next steps

- Probabilistic half of the LinUCB regret bound: calibration holds with
  probability ≥ 1 − δ (needs Mathlib), and the elliptical potential lemma.
- A Thompson sampling spec (a distribution over argmax of posterior samples).
- A Python port that follows the same interface.
