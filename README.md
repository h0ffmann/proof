<div align="center">

<img alt="proof: a turnstile (⊢, 'proves') and a tombstone (∎, 'end of proof') whose hatch lines halve the gap that is left, so the box is full only in the limit; drawn from equations" src="docs/logo/proof.svg" width="216"/>

# proof

<sub>⊢ ∎ · <i>it proves, and it is done</i> · <a href="#in-one-minute">in one minute</a> · <a href="#index-of-experiments">experiments</a> · <a href="#papers">papers</a> · <a href="#recipes">recipes</a> · <a href="#structure">structure</a> · <a href="docs/logo/README.md">the logo</a> · <a href="#license">license</a></sub>

[![Lean 4 v4.24.0](https://img.shields.io/badge/Lean_4-v4.24.0-1b3a5c?style=flat-square)](lean/lean-toolchain)
[![no sorry](https://img.shields.io/badge/sorry-0-2a78d6?style=flat-square)](AGENTS.md)
[![Haskell](https://img.shields.io/badge/Haskell-base_%2B_containers-1b3a5c?style=flat-square&logo=haskell&logoColor=white)](haskell)
[![Rust](https://img.shields.io/badge/Rust-std_only-1b3a5c?style=flat-square&logo=rust&logoColor=white)](house-pricing/rust)
[![Python](https://img.shields.io/badge/Python-experiments-1b3a5c?style=flat-square&logo=python&logoColor=white)](#index-of-experiments)
[![papers: 4](https://img.shields.io/badge/papers-4-2a78d6?style=flat-square)](papers)
[![Nix](https://img.shields.io/badge/toolchain-Nix_flake-1b3a5c?style=flat-square&logo=nixos&logoColor=white)](flake.nix)
[![license: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-1b3a5c?style=flat-square)](#license)

</div>

## In one minute

- **proof** (formerly *dogma*) holds specifications written and proved in [Lean 4](https://lean-lang.org),
  and implementations that follow them name for name: Haskell for contextual bandits, Rust for
  house pricing. Lean is the source of truth; the implementations are checked against its `#eval`s.
- Next to the proofs sit data experiments in Python (fat tails, TV audiences, crypto networks), each
  with its results committed and, where it is worth it, a paper.
- Papers are Markdown built to PDF by the Paper Fabric pipeline (pandoc, pandoc-crossref, XeLaTeX),
  pinned by Nix. Every citation was fetched before it was cited, and `REFERENCES.md` logs how.
- The Lean code is core-only (no Mathlib) and has no `sorry`, `admit` or new `axiom`
  ([`AGENTS.md`](AGENTS.md), "Rules").
- Every change lands through a pull request. CI is off while the repository is private, so the
  checks run by hand ([Recipes](#recipes)).

## Index of experiments

| Folder | Problem | Language | Maturity |
|---|---|---|---|
| [`lean/`](lean), [`haskell/`](haskell) | Contextual bandits: a decision rule on top of a probabilistic reward model; validity and the UCB optimism lemma ([note](MULTI_ARMED_CONTEXTUAL_BANDIT.md), [paper](papers/contextual-bandits/metadata.md)) | Lean 4, Haskell | **Proved**: spec and proofs, Haskell port checked against Lean; regret bound open |
| [`house-pricing/`](house-pricing/README.md) | California house prices: seven models compared, gradient boosting replicated exactly in Lean and called from Rust | Rust, Lean 4 | **Proved**: output bounds and a monotone variant proved; Rust/Lean parity checked |
| [`ocean-waves/`](ocean-waves/README.md) | Physics and numerical kernels of a spectral wave model (WAVEWATCH III, WAM Cycle 4) | Lean 4 | **Proved**: kernels and their theorems; no runnable model port yet |
| [`cycle/`](cycle/README.md) | Eternal return: "time is a flat circle" as a theorem about a clock ([essay](papers/cycle/metadata.md)) | Lean 4, Markdown | **Draft**: theorem proved, essay is a skeleton |
| [`fat-tails/`](fat-tails/README.md) | Taleb's fat-tail diagnostics on the S&P 500, 1950 to 2026; power-law against Gaussian VaR ([paper](papers/fat-tails/metadata.md)) | Python | **Results**: real data, results committed, paper v0 |
| [`tv-audience/`](tv-audience/README.md) | Forecasting big-show TV audiences as a competition between channels: XGBoost, DNN, Mistral Timestral, joint competitive share model ([paper](papers/tv-audience/metadata.md)) | Python | **Simulated**: synthetic benchmark and paper v0; Timestral arm not run; real-channel test pending |
| [`crypto-strength/`](crypto-strength/README.md) | 17 crypto networks scored on nine factors, long-term top 10 | Python, CSV | **Results**: sourced scores, partly judgment |
| [`graphs/triad/`](graphs/triad/README.md) | Network of Musk, Thiel and Karp: companies, deals and ties | Python, JavaScript (graphify) | **Results**: sourced edges, rendered graph |

Maturity levels, strongest first: **Proved** (Lean proofs with no `sorry`, implementation
checked against them), **Results** (runs end to end on real data, outputs committed),
**Simulated** (runs end to end on synthetic data only), **Draft** (partial: a skeleton or an
unfinished write-up).

Every paper lives in [`papers/`](papers) and builds with `just paper <slug>` (see [Papers](#papers)).

## TV audience forecasting

[`tv-audience/`](tv-audience/README.md) forecasts prime-time audiences of big shows seven days
ahead and treats each hour as a market shared by competing channels. The Joint Competitive Share
model forecasts the pool of viewers in the hour and splits it between all channels with a
multinomial logit. On a simulated benchmark it has the lowest error on big shows, while XGBoost
with rival features is best over all slots. The paper names nine channels with public ratings
in the UK, US and Brazil for a real-data test. All data so far are synthetic.

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

## Fat tails in equity indexes

[`fat-tails/`](fat-tails/README.md) applies metrics from Taleb's *Statistical
Consequences of Fat Tails* (κ, Hill tail exponents, MS plots, kurtosis
instability) to the S&P 500 since 1950 and compares power-law VaR with Gaussian
VaR at today's volatility. Python only for now.

## Crypto strength map

[`crypto-strength/`](crypto-strength/README.md) scores 17 crypto networks from 1 to 5
on nine factors (decentralization, security, scalability, affordability, adoption,
maturity, fees, privacy, and resistance to 2026 attacks), renders the heatmap, and
derives a long-term top 10 of mature projects with their GitHub repositories.
Every score has evidence and a source id in a CSV. Educational only, not investment advice.

## Papers

Papers are written in Markdown and built to PDF with pandoc and XeLaTeX, using the
Paper Fabric pipeline from [h0ffmann/closed-source](https://github.com/h0ffmann/closed-source).
Start with [docs/paper-fabric.md](docs/paper-fabric.md); the starter paper is
[`papers/contextual-bandits`](papers/contextual-bandits/metadata.md).

```bash
nix develop          # pandoc, pandoc-crossref, XeLaTeX, Gleam (pinned by flake.lock)
just paper           # every paper -> pdf/<slug>.pdf
just paper-check     # + reference log and STE/pt-BR checks
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

## Recipes

```console
just check            # Lean builds (every package) and the Haskell spec check
just house-pricing    # fetch data, train, lake build, Rust/Lean parity
just paper [slug]     # build every paper, or one, to pdf/<slug>.pdf (inside `nix develop`)
just paper-check      # papers + reference log + STE/pt-BR checks
just md-quality       # markdownlint, Vale (prose rules) and lychee (links)
just diagrams         # render the archify diagrams; `just images` captures PNGs
just graph            # build the graphify network graph; `just render-graph` serves it
just crypto-strength  # rebuild the crypto heatmap and results
python3 fat-tails/python/fat_tails.py        # fat-tails results and figures
python3 tv-audience/python/experiment.py     # TV audience benchmark, results and figures
python3 docs/logo/logo.py                    # draw the logo again
```

## Structure

```
.
├── lean/, haskell/          contextual bandits: Lean spec and proofs, Haskell port
├── house-pricing/           Rust trains, Lean replicates and proves; Rust calls Lean through its C ABI
├── ocean-waves/             spectral wave model physics and kernels, Lean only
├── cycle/                   eternal return: a clock theorem in Lean, for the essay in papers/cycle
├── fat-tails/               Taleb's fat-tail diagnostics on the S&P 500 (Python)
├── tv-audience/             TV audience forecasting as a competition between channels (Python, simulated)
├── crypto-strength/         a scored map of 17 crypto networks (Python, CSV)
├── graphs/triad/            the Musk, Thiel and Karp network (graphify)
├── papers/<slug>/           one paper each: metadata.md, prose/, refs.bib, REFERENCES.md
├── format/, tools/, .vale/  Paper Fabric: LaTeX template, refs and STE checks (Gleam), prose rules
├── docs/                    paper-fabric.md, the archify diagrams, the logo
├── vendor/archify/          the pinned archify that draws the diagrams
├── flake.nix, flake.lock    the paper toolchain, from h0ffmann/picasso's paper lab
├── justfile                 every recipe above
└── AGENTS.md                the rules for agents (and humans) working here
```

## Credits

- The README layout follows [piabrota/nix-os](https://github.com/piabrota/nix-os), which took it
  from [picasso](https://github.com/h0ffmann/picasso) and
  [gvolpe/nix-config](https://github.com/gvolpe/nix-config).
- The paper pipeline is Paper Fabric, from [h0ffmann/closed-source](https://github.com/h0ffmann/closed-source).
- Diagrams by [archify](https://github.com/tt-a1i/archify) (Apache-2.0), network graphs by
  [graphify](https://graphify.com).
- The logo is drawn from equations by [`docs/logo/logo.py`](docs/logo/logo.py); see
  [`docs/logo/README.md`](docs/logo/README.md).

## License

| What | License |
|---|---|
| Everything in this repository, the logo included | [MPL-2.0](LICENSE) |
| `vendor/archify/` | Apache-2.0, from its upstream ([`VENDORED.md`](vendor/archify/VENDORED.md)) |
