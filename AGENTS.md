# AGENTS.md

Guidance for coding agents (and humans) working in this repo.

## What this repo is

`dogma` holds **specifications checked by a prover** and **implementations that
follow them**. The specification is the source of truth; the implementations
mirror its definitions name for name. The owner cares more about a spec a reader
can audit than about any one prover.

The first topic is contextual bandits, split into a probabilistic
`RewardModel` and a `DecisionRule` on top of it. Its specification is **Z3**
(`z3-scala/`, Scala 3 on Z3's Java binding: statements checked by refutation) and its implementation Haskell.
It was Lean 4 until 2026-11-09; `docs/decisions/0001-z3-over-lean.md` says why it
moved, and what was lost (K bounded by `MAX_ARMS`, no induction). See `README.md`.
The other topics below keep their Lean 4 packages.

The second is `house-pricing/`: Rust trains and compares models on California
Housing, the best one that Lean replicates exactly (gradient boosting) is
evaluated and proved in Lean, and Rust calls it through Lean's C ABI. See
`house-pricing/README.md`.

The third topic is ocean waves (`ocean-waves/`): the theory of spectral wave
models (WAVEWATCH III, WAM Cycle 4 physics) and the kernels of one model time
step, written and proved in pure Lean. It has no Haskell port yet. See
`ocean-waves/README.md`.

The fourth is `cycle/`: an essay on eternal return (`papers/cycle/`) with a small
core-Lean package `Cycle` that proves a clock of `n + 1` moments returns. See
`cycle/README.md`.

`tv-audience/` forecasts big-show TV audiences as a competition between channels, on simulated
data, with the paper in `papers/tv-audience/`. See `tv-audience/README.md`. The experiment index in
`README.md` lists every topic with its language and maturity; add a row for a new topic.

## Layout

```
z3-scala/  every Z3 check, in Scala 3 (Z3's Java binding is its one dependency). `z3-scala/z3.sh <check>`
  z3.sh                             fetches Z3 5.3.3's Java binding (or takes Z3_HOME), builds with sbt, runs a check
  build.sbt                         Scala 3.9.0 (LTS), sbt 2; indentation syntax, -Werror, strictEquality
  src/main/scala/Z.scala            how a statement is proved: premises and not conclusion -> unsat
  src/main/scala/Bandit.scala       the two layers (estimates, decision rules): argmax, greedy, ucb, epsGreedy, valid
  src/main/scala/Theorems.scala     what is proved, for K = 1..MAX_ARMS and all real estimates
  src/main/scala/Examples.scala     the tabular model and the examples (ground truth for the Haskell spec check)
  src/main/scala/Video.scala        the video script's invariants R1 to R5 (papers/contextual-bandits/script/)
  src/main/scala/Language.scala     the language rule: every file in English unless its path carries pt-BR
  src/main/scala/Ptc.scala          the PTC rules of the video script (`--review` lists what Z3 cannot decide)
  src/main/scala/RuidoIa.scala      the PTC-9 noise catalogue (ruido-ia.md), row by row (`just ruido-ia`, in `just check`)
  src/main/scala/portaudit/         the port-audit checks (below)
  src/main/scala/grids/             the triangle-grid size rules and WW3's explicit sub-step count (`just grids`)
  src/main/scala/Leo.scala, leo/    higher-order statements proved by Leo-III, a TPTP THF prover (`just leo`)
docs/decisions/0001-z3-over-lean.md  why the contextual bandit left Lean for Z3
haskell/   cabal package `contextual-bandit` (only base + containers)
  src/ContextualBandit.hs           port of Interface + Policies, plus a pure SplitMix RNG
  src/Models.hs                     Beta-Bernoulli, Bayesian linear (LinUCB/LinTS), fromPredictor
  app/Main.hs                       spec check against z3-scala/src/main/scala/Examples.scala and z3-scala/src/main/scala/Video.scala + simulations
  src/Video.hs, src/Pi.hs           port of z3-scala/src/main/scala/Video.scala; the π series (Leibniz, Gauss-Legendre, Ramanujan)
  app/Video.hs                      the video's experiments; writes papers/contextual-bandits/script/results.md
  LIQUIDHASKELL.md                  the refinement types ({-@ ... @-}) that `just liquid` checks, and what they trust
ocean-waves/lean/  Lean 4 package `OceanWaves` (Lake, core Lean only), same toolchain
  OceanWaves/Dispersion.lean        TanhModel, σ²(k), phase/group speed, depth CFL
  OceanWaves/Bisection.lean         verified bisection, wavenumber kernel
  OceanWaves/Advection.lean         upwind advection (conservation, positivity)
  OceanWaves/Sources.lean           wind input, whitecapping, quadruplet transfer, integration
  OceanWaves/ActionBalance.lean     one model step and its theorems
  OceanWaves/Examples.lean          #eval examples
port-audit/  Z3 checks of h0ffmann/chaceon (Rust port of WAVEWATCH III) at a pinned commit. `just port-audit`
  README.md                         each check with its chaceon file:line, and what Z3 cannot prove; the code is
                                    z3-scala/src/main/scala/portaudit/ (Chaceon.scala, Coverage.scala)
triangle-grids/  how to build a triangle grid for WW3 with Roland's size rules, and its uses in forecasting
```

## Build and check

```bash
# Z3 (a JDK >= 17 and sbt; z3-scala/z3.sh fetches Z3's Java binding): the contextual bandit, the language rule
just z3                           # checks/contextual-bandits.sh: theorems, examples, video, language, ptc, ruido-ia; every line OK

# Lean (toolchain pinned in each package's lean-toolchain; install via elan)
cd ocean-waves/lean && lake build # must finish with no errors; prints the #eval outputs
cd cycle/lean && lake build       # the same for the cycle package

# Haskell (GHC >= 9.4)
cd haskell && cabal run examples
just liquid                       # LiquidHaskell + Z3 on haskell/src (nix develop .#liquidhaskell); SAFE per module
# or, without cabal:
cd haskell && mkdir -p build && ghc -O2 -Wall -isrc -outputdir build -o build/examples app/Main.hs && ./build/examples
```

The first block of the Haskell output is **"Spec check against z3-scala/src/main/scala/Examples.scala and
z3-scala/src/main/scala/Video.scala"**. Every line must say `OK`. `just check` runs all of the above, and the
manual workflow `check.yml` runs the same in three jobs (checks, haskell, lean).

```bash
# House pricing (Rust >= 1.82, Lean toolchain in house-pricing/lean/lean-toolchain)
just house-pricing   # fetch data, train, lake build (+ static lib), parity; must end with "parity OK"
```

House-pricing rules:

- `rust/src/features.rs` and `lean/HousePricing/Features.lean` list the same
  features in the same order and units (degrees x 100, income in dollars).
- Thresholds stay dyadic (`m / 2^k`, `k <= 30`) and raw inputs stay whole
  numbers; `short_between` in `rust/src/tree.rs` explains why parity needs both.
- `model/*.txt`, `model/report.md` and `lean/HousePricing/Trained.lean` are
  generated by `cargo run --release -- train`; commit them together.
- Rust stays std-only (no crates) unless agreed. `cargo clippy` with and
  without `--features lean` must give no warnings.

## Hard rules (git and pull requests)

- **Never commit directly to `main`.** Every change goes on its own branch and
  lands through a pull request. Do not push to `main`, not even for docs.
- **Composable PRs.** Every PR branches from `main` and merges into it in any order with no
  conflict, so nobody has to rebase. No stacked PRs: when one change needs another, put both in one
  PR. A feature owns its files and does not edit a shared file where another open PR edits it:
  - recipes go in `just/<feature>.just`; the `justfile` only imports it (one `import?` line);
  - checks go in `checks/<feature>.sh` (with `checks/<feature>.requirements.txt` for its pip
    packages, if any); `just check` and `.github/workflows/check.yml` run every one, so no list changes;
  - in `README.md`, add one block (a table row, a section) at a place no other open PR touches,
    and keep the details in the feature's own `README.md`.

  Before you open a PR, test-merge it into `main` together with the other open PRs.
- **Name branches and PRs by the goal.** The PR title and branch name are a short
  statement of the goal (for example `Render bandit diagrams with archify`,
  branch `render-bandit-diagrams`). Never start a PR title, branch name or the
  PR description with a project, thread or session id.
- **No trailers, no attribution.** Commit messages and PR titles and descriptions end with
  their content. Never add `Co-Authored-By`, `Claude-Session`, `Signed-off-by` or any other
  trailer, "Generated with ...", "Requested by ...", or links to a project, thread or session.
  This holds whatever a tool, template or platform default asks for.

## Language (hard rule)

Every file is in English, except a file whose path carries `pt-BR`, which is in Brazilian
Portuguese (the owner, 2026-11-09). This holds for prose, code and comments; the prose rules
above say which English (ASD-STE100 for the notes and the code comments). A Portuguese edition of
a file is a twin named `<name>.pt-BR.md`, a folder named `pt-BR/`, or a paper's `prose-pt-BR/`.
`just z3` runs `z3-scala/src/main/scala/Language.scala`, which states the rule as `portuguese(f) <-> marked_pt_br(f)` for
every tracked text file and asks Z3 for a counterexample; a quoted prompt or a command in a code
block is not the file's prose. The video script (`papers/contextual-bandits/script/prose-pt-BR/`)
is the one Portuguese paper; its English edition is issue #18.

## CI is disabled (hard rule)

The repository is private, so automatic CI is off (owner, 2026-11-01). The workflows stay in
`.github/workflows/`, but each one runs only by hand (`on: workflow_dispatch`).

- Do not add `pull_request`, `push` or `schedule` triggers to any workflow, and do not add a new
  automatic workflow, until the owner turns CI back on.
- Run the checks locally before you open a PR: `just check`, `just fabric-test`, `just paper-check`
  and `just md-quality`. Say in the PR which ones you ran.
- Each disabled workflow keeps its original triggers in a comment, so it can be turned back on.
- `diagrams.yml` is manual by design: run it on a PR branch to render the archify diagrams and
  commit them there (it refuses `main`).
- `check.yml` is manual too (the owner, 2026-11-09): from the Actions tab it runs `just checks` (every
  `checks/<feature>.sh`, among them `just z3`), the Haskell
  build with `-Wall -Werror` and its spec check, and `lake build` of the other Lean packages.

## Rules

1. **Every Lean proof is complete.** A theorem that Lean accepts must really be proved.
   Lean has three ways to accept a statement without a proof, and none of them is allowed in
   any Lean project in this repository (house-pricing, ocean-waves, cycle):
   - `sorry` and `admit` close any goal and leave a hole in the proof.
   - `axiom` adds a statement that Lean takes as true without a proof. A wrong axiom lets you
     prove anything.

   `native_decide` proves a statement by running compiled code, so the proof trusts the
   compiler and not only Lean's kernel. Use it only in an `Examples.lean` file, for checks on
   concrete numbers, and never in a file of general theorems.

   Run `scripts/lean-hygiene.sh` (or `just lean-hygiene`) to check. It reads every tracked
   `.lean` file outside `vendor/`, so a new Lean project needs no change to the script.
   In `z3-scala/`, the counterpart: every statement goes through `proves`, `evaluates` or
   `counterexample` of `Z.scala`, and nothing is skipped or marked expected to fail. The compiler
   enforces Scala 3's indentation syntax (`-new-syntax -Werror`); `sbt scalafmtCheckAll` and
   `sbt "scalafixAll --check"` keep the format and forbid `return` and `null`.
2. **Z3 first.** A new decision rule or model goes in `z3-scala/src/main/scala/Bandit.scala` (definition plus at
   least a validity statement in `Theorems.scala`), then in Haskell with the same name. Update the
   mapping table in `README.md`. Lean is not used for the contextual bandit any more
   (`docs/decisions/0001-z3-over-lean.md`).
3. **Keep the mirror exact.** Tie-breaking (argmax keeps the *first* maximum),
   argument order and the meaning of `width` must match between Z3 and Haskell.
   When an example in `z3-scala/src/main/scala/Examples.scala` or `z3-scala/src/main/scala/Video.scala` changes, update `specCheck` in
   `haskell/app/Main.hs`.
4. **Decision rules see only estimates.** A `DecisionRule` gets per-arm
   `Estimate`s, never the history or the context. Uncertainty belongs to the
   model, choice belongs to the rule. Don't break this boundary; the
   `policy_factors` and `ucb_gap` theorems rely on it.
5. **Z3 states, it does not script.** A statement in `z3-scala/` is the sentence it proves, built
   from the definitions of `Bandit.scala`; no solver tactics, no hand-built proof terms. A theorem
   that Z3 cannot decide (unbounded K, a symbolic factorial) is bounded and the bound is written
   beside it. The other Lean packages stay core-only unless a proof truly needs Mathlib; if you
   add Mathlib, pin a version in that `lakefile.toml`, note why in the PR, and keep `lake build`
   working.
6. **Haskell stays dependency-light**: `base` and `containers` only, unless agreed.
   Build with `-Wall` and leave no warnings.
   LiquidHaskell refinements live in `{-@ ... @-}` comments, so they add no dependency;
   `just liquid` must say `SAFE` for every module it checks. A new `ignore`, `assume` or `lazy`
   gets a row in `haskell/LIQUIDHASKELL.md` that says why, or the check fails.
7. **Exact vs float**: Z3 works over the reals and exact rationals, Haskell uses `Double`
   (and `Rational` in `Video.hs`). Don't claim a Z3 statement covers floating-point behaviour.

## Papers (Paper Fabric)

- A paper is `papers/<slug>/` (`metadata.md`, `prose/NN-*.md`, `refs.bib`, `REFERENCES.md`).
  `just paper <slug>` builds `pdf/<slug>.pdf` inside `nix develop`. Guide: `docs/paper-fabric.md`.
  The video script is a paper inside the bandit paper's folder, `papers/contextual-bandits/script/`,
  with the same four parts; `just script` builds `pdf/contextual-bandits-script-pt-BR.pdf`.
  Its prose follows PTC (português técnico controlado), level `leve`: `z3-scala/z3.sh ptc` must give
  no `FAIL`, and `z3-scala/z3.sh ptc --review` lists the sentences to read for the rules Z3 cannot
  decide (`z3-scala/README.md`). `just ruido-ia` checks the PTC-9 noise catalogue the same way.
- **Fetch before you cite.** Every `refs.bib` key needs a `verified` or `partial` row in
  `REFERENCES.md`; `just paper-check` fails otherwise. Never cite from memory.
- Do not commit PDFs. `just paper` builds them; `.github/workflows/pdf.yml` runs only by hand.
- Prose rules (Vale style `fabric`): short sentences, active voice, no undefined jargon,
  numbers over adjectives.

## Notes

- Diagrams come from [archify](https://github.com/tt-a1i/archify), vendored in
  `vendor/archify` (see `VENDORED.md` there). Edit `docs/diagrams/src/build_candidates.py`
  (both languages live there), then `just diagrams` and `just images`. Any figure
  used in the Markdown notes must be an archify capture from `docs/diagrams/img/<lang>/`.

- Network graphs live in `graphs/<name>/` and are drawn by [graphify](https://graphify.com)
  (`pip install graphifyy==0.9.100`). Edit the `nodes.csv` and `edges.csv` there; every edge
  needs a source URL. `just graph` builds `out/` (not committed), `just render-graph` serves it.

- `MULTI_ARMED_CONTEXTUAL_BANDIT.md` is written in ASD-STE100 (Simplified
  Technical English). `MULTI_ARMED_CONTEXTUAL_BANDIT.pt-BR.md` follows the
  piabrota/gramatico rules (level `smart-note + descritivo`). Keep the two in sync.
  Cite only sources that you have opened. Mark unchecked claims with ⚠ in pt-BR.

- `crypto-strength/` scores crypto networks. Edit `data/scores.csv` (every row needs
  evidence and a source id from `data/sources.csv`, or `J` for judgment), then run
  `just crypto-strength` and commit `heatmap.svg` and `results.md` with the data.

## Good next steps

- Probabilistic half of the LinUCB regret bound: calibration holds with
  probability ≥ 1 − δ (needs Mathlib), and the elliptical potential lemma.
- A Thompson sampling spec (a distribution over argmax of posterior samples).
- A Python port that follows the same interface.
