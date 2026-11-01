# dogma
axioms and proofs

Specs written and proved in Lean 4, then implemented in Haskell (and later Python).
The first one is contextual bandits. Background note: [MULTI_ARMED_CONTEXTUAL_BANDIT.md](MULTI_ARMED_CONTEXTUAL_BANDIT.md) ([pt-BR](MULTI_ARMED_CONTEXTUAL_BANDIT.pt-BR.md)).

## Contextual bandits: Lean 4 spec, Haskell implementation

The Lean side is the *specification with proofs*. The Haskell side is a
line-by-line port that runs. Both share one idea:

> **The bandit is a decision rule on top of a probabilistic model.**
> The model turns history into beliefs. The decision rule turns beliefs into an action.

```
           context c
               │
               ▼
 history ─► RewardModel ──estimate(b, c, a) = (mean, width)──► DecisionRule ──► action a
   ▲        (belief b)    sample(b, c, a)  ~ posterior          greedy / ε-greedy /      │
   │                                                            UCB / Thompson           ▼
   └────────────── update(b, (c, a, r)) ◄────────────── reward r ◄──────────────── environment
```

## Diagrams

All figures are made with [archify](https://github.com/tt-a1i/archify) by tt-a1i
(Apache-2.0), vendored in [`vendor/archify`](vendor/archify/VENDORED.md).
Sources for both languages are in [`docs/diagrams/src`](docs/diagrams/src).

| Diagram | English | Português (BR) |
|---|---|---|
| Model and decision layers (architecture) | [html](docs/diagrams/en/bandit-architecture.html) | [html](docs/diagrams/pt-BR/bandit-architecture.html) |
| One round (sequence) | [html](docs/diagrams/en/bandit-round.html) | [html](docs/diagrams/pt-BR/bandit-round.html) |
| A/B test as a special case (workflow) | [html](docs/diagrams/en/ab-test-vs-bandit.html) | [html](docs/diagrams/pt-BR/ab-test-vs-bandit.html) |

Render and host them (needs [`just`](https://github.com/casey/just), Node ≥ 18, Python 3 and Chrome/Chromium;
set `ARCHIFY_CHROME` if Chromium is not on `PATH`):

```bash
just diagrams   # validate + render every diagram to docs/diagrams/<lang>/*.html
just images     # capture PNG figures to docs/diagrams/img/<lang>/ for the notes
just serve      # host everything at http://localhost:8000 (just serve 9000 for another port)
```

To publish them, enable GitHub Pages for the `docs/` folder: the index is
`docs/diagrams/index.html`.

### Layout

```
lean/                          Lean 4 (core only, no Mathlib), toolchain v4.24.0
  ContextualBandit/Interface.lean   RewardModel, Estimate, DecisionRule, policy
  ContextualBandit/Argmax.lean      argmax + proof that it maximises
  ContextualBandit/Policies.lean    greedy, ucb β, epsGreedy ε
  ContextualBandit/Theorems.lean    the proofs (below)
  ContextualBandit/Examples.lean    a tabular model you can #eval
haskell/                       GHC, only base + containers
  src/ContextualBandit.hs           the same interface and rules, plus a pure RNG
  src/Models.hs                     Beta-Bernoulli, Bayesian linear (LinUCB/LinTS), fromPredictor
  app/Main.hs                       4 runnable examples
```

Run:

```bash
cd lean && lake build                        # checks every proof and prints the #evals
cd haskell && runghc -isrc app/Main.hs       # or: cabal run examples
```

### The interface

| Concept | Lean | Haskell |
|---|---|---|
| Arm | `Fin K` | `Int` in `0..k-1` |
| Observation | `Obs C K` | `Obs c` |
| Model output | `Estimate {mean, width}` | `Estimate {mean, width}` |
| Probabilistic model | `RewardModel C K B {prior, update, estimate}` | `RewardModel c b {numArms, prior, update, estimate, sample}` |
| Decision | `Arm K → Rat` | `[Double]` |
| Decision rule | `(Arm K → Estimate) → Decision K` | `[Estimate] -> [Double]` |
| Agent's policy | `policy m rule history ctx` | `policy m rule history ctx` |

The decision rule never sees the raw history or the context, only the model's
per-arm estimates. So any model that can report a mean and an uncertainty
plugs into any rule.

### What is proved (all in `Theorems.lean`, no `sorry`)

| Theorem | Statement |
|---|---|
| `greedy_valid`, `ucb_valid`, `epsGreedy_valid` | the output is a probability distribution (non-negative, sums to 1) when `0 ≤ ε ≤ 1` |
| `epsGreedy_prob` | greedy arm gets `1 - ε + ε/K`, every other arm gets `ε/K` |
| `epsGreedy_explores` | every arm has probability ≥ `ε/K` |
| `epsGreedy_one_is_ab_test` | ε-greedy with ε = 1 is the uniform allocation of an A/B/n test |
| `greedy_is_argmax`, `ucb_is_argmax` | the chosen arm maximises its score |
| `ucb_zero` | UCB with β = 0 is greedy |
| `ucb_gap` (optimism lemma) | if the model is **calibrated** (`|mean − μ| ≤ β·width` for every arm), UCB's arm is within `2β·width` of the best arm |
| `greedy_gap` | if every mean is within δ of the truth, greedy loses at most 2δ |
| `policy_factors` | two histories with the same belief give the same decision |

`ucb_gap` is the important one. It says exactly **what the probabilistic model
owes the decision layer**: calibrated uncertainty. A LinUCB regret bound is

1. `ucb_gap` each round (done here), plus
2. *the model is calibrated with probability ≥ 1 − δ for all rounds*. This is a
   self-normalised martingale bound, a probability statement that needs Mathlib.
3. *Σ widths = O(√(d T log T))*. This is the elliptical potential lemma, plain
   linear algebra.

Items 2 and 3 are the natural next steps.

### Connecting your own probabilistic model

Implement four functions, or wrap an existing model with `fromPredictor`:

```haskell
fromPredictor
  :: Int                                   -- number of arms
  -> s                                     -- model state (weights, handle, ...)
  -> (s -> Obs c -> s)                     -- online update; `const` if frozen
  -> (s -> c -> Arm -> (Double, Double))   -- predictive (mean, std)
  -> RewardModel c s
```

* **Conjugate / closed form** (Beta-Bernoulli, Gaussian, Bayesian linear
  regression): `update` is the posterior update and `estimate` the
  posterior mean and std. See `Models.hs`.
* **Trained offline** (logistic regression, gradient boosting, a neural net
  with an ensemble or MC dropout, a PyMC/Stan fit): freeze it with `const`,
  use its predictive mean and std, and retrain in batches outside the loop.
* **Any rule**: `act m greedy`, `act m (epsGreedy 0.1)`, `act m (ucb 2)`,
  `thompsonArm m`.

The `width` must be an honest uncertainty. An over-confident model breaks the
`Calibrated` hypothesis, and UCB/Thompson degrade to greedy.

### Example output (Haskell)

```
== 0. Spec check against Lean #eval ==        all three OK
== 1. Beta-Bernoulli, 2 contexts x 3 arms, T=5000 (avg 20 runs)
greedy 41.1   eps-greedy 0.1 43.3   UCB beta=2 25.3   Thompson 32.8
== 2. Bayesian linear, d=3, 4 arms, T=2000 (avg 10 runs)
greedy 322.9  eps-greedy 0.1 62.0   LinUCB 25.3       LinTS 31.5
```

These numbers are expected cumulative regret. They come from one small
simulation each and are not benchmarks.

### Caveats

* Lean proofs are over exact `Rat`. The Haskell port uses `Double`, so
  floating-point rounding isn't covered by the proofs. The spec check in
  `Main.hs` confirms both agree on the shared example.
* Thompson sampling is specified as "greedy on a posterior sample". Its
  randomness and its regret aren't formalised here.
* The Lean `tabular` example uses width `1/(n+1)` because core Lean has no `√`
  on `Rat`.
