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
z3-scala/  every Z3 check, in Scala 3 on Z3's Java binding and Kyo. `z3-scala/z3.sh <check>`
  z3.sh                             takes Z3 5.3.3's Java binding from Z3_HOME (or fetches it), builds with sbt, runs a check
  build.sbt                         Scala 3.9.0 (LTS), sbt 2, Kyo 1.0.0-RC7; indentation syntax, -Werror, strictEquality
  src/main/scala/                   domain-driven: a shared kernel and one bounded context per family of checks
    kernel/smt/                     Z3 vocabulary (Z.scala: operators, reals, ints) and exact rationals
    kernel/proof/                   statements as values (Item, Script) and the Prover that runs them by refutation in Kyo
    kernel/text/, kernel/infrastructure/  Python-compatible text handling; files, processes and console as Kyo effects
    bandit/domain/                  Bandit.scala (the two layers, the rules), Theorems.scala (for K = 1..MAX_ARMS),
                                    Examples.scala (the tabular model, ground truth for the Haskell spec check),
                                    Video.scala (the video script's invariants R1 to R5)
    language/domain/                LanguageRule.scala: every file in English unless its path carries pt-BR
    ptc/domain/                     Ptc.scala (the PTC rules of the video script; `--review` lists what Z3 cannot decide),
                                    NoiseCatalogue.scala (the PTC-9 noise catalogue, ruido-ia.md, row by row)
    portaudit/                      the port-audit checks (below); infrastructure/Pins.scala fetches the two pins
    grids/domain/                   the triangle-grid size rules and WW3's explicit sub-step count (`just grids`)
    leo/                            higher-order statements proved by Leo-III, a TPTP THF prover (`just leo`); problems in z3-scala/leo/
    */application/                  each context's use cases: read the inputs, call the domain, print the report
    app/                            Cli.scala (which word runs which check, exit codes) and Main.scala (the Z3 version check)
contextual-bandits/  README.md (+ README.pt-BR.md): the one page for the bandit, with an index of its files
docs/decisions/0001-z3-over-lean.md  why the contextual bandit left Lean for Z3
haskell/   cabal package `contextual-bandit` (only base + containers)
  src/ContextualBandit.hs           port of Interface + Policies, plus a pure SplitMix RNG
  src/Models.hs                     Beta-Bernoulli, Bayesian linear (LinUCB/LinTS), fromPredictor
  app/Main.hs                       spec check against z3-scala/src/main/scala/bandit/domain/Examples.scala and z3-scala/src/main/scala/bandit/domain/Video.scala + simulations
  src/Video.hs, src/Pi.hs           port of z3-scala/src/main/scala/bandit/domain/Video.scala; the π series (Leibniz, Gauss-Legendre, Ramanujan)
  app/Video.hs                      the video's experiments; writes contextual-bandits/script/results.md
  LIQUIDHASKELL.md                  the refinement types ({-@ ... @-}) that `just liquid` checks, and what they trust
agda/      Agda library `contextual-bandit` (standard library only), one root per topic in agda/src/*.agda:
           the bandit's decision layer and its theorems for every K, by induction; the cycle clock;
           every kernel and theorem of ocean-waves/; the triangle-grid checks; the video's rules, the Leo-III
           problems, the port audit and the decision layer of the text checks of z3-scala/. `just agda` (nix develop .#agda).
           Skill: .claude/skills/agda/SKILL.md
ocean-waves/lean/  Lean 4 package `OceanWaves` (Lake, core Lean only), same toolchain
  OceanWaves/Dispersion.lean        TanhModel, σ²(k), phase/group speed, depth CFL
  OceanWaves/Bisection.lean         verified bisection, wavenumber kernel
  OceanWaves/Advection.lean         upwind advection (conservation, positivity)
  OceanWaves/Sources.lean           wind input, whitecapping, quadruplet transfer, integration
  OceanWaves/ActionBalance.lean     one model step and its theorems
  OceanWaves/Examples.lean          #eval examples
port-audit/  Z3 checks of h0ffmann/chaceon (Rust port of WAVEWATCH III) at a pinned commit. `just port-audit`
  README.md                         each check with its chaceon file:line, and what Z3 cannot prove; the code is
                                    z3-scala/src/main/scala/portaudit/domain/ (Chaceon.scala, Coverage.scala)
triangle-grids/  how to build a triangle grid for WW3 with Roland's size rules, and its uses in forecasting
```

## Build and check

```bash
# Z3, inside `nix develop .#scala` (the JDK, sbt and Z3 pinned): the contextual bandit, the language rule
just z3                           # checks/contextual-bandits.sh: theorems, examples, video, language, ptc, ruido-ia; every line OK

# Lean, inside `nix develop .#lean` (the release each package's lean-toolchain names)
cd ocean-waves/lean && lake build # must finish with no errors; prints the #eval outputs
cd cycle/lean && lake build       # the same for the cycle package

# Haskell, inside `nix develop .#haskell` (GHC and cabal-install)
cd haskell && cabal run examples
just liquid                       # LiquidHaskell + Z3 on haskell/src (nix develop .#liquidhaskell); SAFE per module
# or, without cabal:
cd haskell && mkdir -p build && ghc -O2 -Wall -isrc -outputdir build -o build/examples app/Main.hs && ./build/examples
```

The first block of the Haskell output is **"Spec check against z3-scala/src/main/scala/bandit/domain/Examples.scala and
z3-scala/src/main/scala/bandit/domain/Video.scala"**. Every line must say `OK`. `just check` runs all of the above, and the
manual workflow `check.yml` runs the same in three jobs (checks, haskell, lean).

```bash
# House pricing, inside `nix develop .#house-pricing` (Rust, Lean, curl)
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
- **No repository named in an issue, a PR or a commit message** (the owner, 2026-11-09). Do not
  write another repository's `owner/name`, its URL, or a link to its issues or pull requests in an
  issue, a PR title or description, a review comment or a commit message: GitHub turns those into
  backlinks on the other repository. Name the library or tool and its version instead ("Kyo
  1.0.0-RC7", "Z3 5.3.3"). Files of the repository may still cite a source by URL where the
  evidence needs it.

## Invariants.lp

`Invariants.lp` states the rules above that a script can decide, as an answer set program for
clingo 5.8: composable PRs (every `just/*.just` imported, every `checks/*.sh` strict), no other
repository and no attribution in the commits of a branch, a branch not named by a session, Nix at
the root with a locked input, complete Lean proofs, Haskell on `base` and `containers`, workflows
by hand only, no PDF committed. `scripts/invariants.py` reads the tree into facts and solves them;
`checks/invariants.sh` (`just invariants`, in `just check`) fails on a violation that is not
waived, and on a waiver that excuses nothing. A `gap` is a rule the tree does not keep yet (a
toolchain that Nix does not pin, in `flake.nix` or in a `nix/<name>.nix` shell that the flake
discovers); it prints but does not fail. clingo's own shell is `nix/invariants.nix`. A new rule goes in
`Invariants.lp`, with a bad case in the self-test of `scripts/invariants.py`.

## Language (hard rule)

Every file is in English, except a file whose path carries `pt-BR`, which is in Brazilian
Portuguese (the owner, 2026-11-09). This holds for prose, code and comments; the prose rules
above say which English (ASD-STE100 for the notes and the code comments). A Portuguese edition of
a file is a twin named `<name>.pt-BR.md`, a folder named `pt-BR/`, or a paper's `prose-pt-BR/`.
`just z3` runs `z3-scala/src/main/scala/language/domain/LanguageRule.scala`, which states the rule as `portuguese(f) <-> marked_pt_br(f)` for
every tracked text file and asks Z3 for a counterexample; a quoted prompt or a command in a code
block is not the file's prose. The video script (`contextual-bandits/script/prose-pt-BR/`)
is the one Portuguese paper; its English edition is issue #18.

## CI is disabled (hard rule)

The repository is private, so automatic CI is off (owner, 2026-11-01). The workflows stay in
`.github/workflows/`, but each one runs only by hand (`on: workflow_dispatch`).

- Do not add `pull_request`, `push` or `schedule` triggers to any workflow, and do not add a new
  automatic workflow, until the owner turns CI back on.
- Run the checks locally before you open a PR: `just check`, `just paper-check`
  and `just md-quality`. Say in the PR which ones you ran.
- Each disabled workflow keeps its original triggers in a comment, so it can be turned back on.
- `diagrams.yml` is manual by design: run it on a PR branch to render the archify diagrams and
  commit them there (it refuses `main`).
- `check.yml` is manual too (the owner, 2026-11-09): from the Actions tab it runs `just checks` (every
  `checks/<feature>.sh`, among them `just z3`), the Haskell
  build with `-Wall -Werror` and its spec check, and `lake build` of the other Lean packages.

## Reproducible builds (hard rule)

The repository must build and check the same on any machine, from the Nix flake at its root (the
owner, 2026-11-09). `flake.lock` pins nixpkgs, and every tool version is written in one place in
the repository:

- **z3-scala**: run it inside `nix develop .#scala`. `nix/scala.nix` pins the JDK (`jdk25_headless`) and
  Z3 with its Java binding, built from the release tag with a fixed hash, and sets `Z3_HOME`.
  `z3-scala/build.sbt` holds Scala's version (`scalaVersion`) and Z3's (`z3Version`, which
  `nix/scala.nix` and `z3.sh` read), and `z3-scala/project/build.properties` holds sbt's. The build stops
  without the jar, and every check stops when the Z3 it loads is another version.
- **z3-scala's dependencies** are Z3's Java binding and Kyo (`kyoVersion` in `build.sbt`, the
  effect system, the owner, 2026-11-09). A new dependency needs the owner's yes in the PR.
- A new tool or a version bump goes into the flake (or the one file that pins it) in the same PR.
  Nothing is installed globally, and no step needs a tool the flake does not give, except the
  Maven artifacts that sbt fetches at the versions pinned above.
- Leo-III is built from source at the commit that `LEO3_COMMIT` in `z3-scala/z3.sh` names.
- **Lean**: each package's `lean-toolchain` names the Lean release, and `nix/lean.nix` gives that
  release from GitHub with a fixed hash per platform (no elan, no download at run time). The three
  files must name the same release, or the evaluation stops; a new release needs the four hashes.
- **One shell per feature**, each a `nix/<name>.nix` that `flake.nix` finds by itself: `scala`,
  `liquidhaskell`, `invariants`, `lean`, `haskell`, `house-pricing` (Rust, Lean, curl), `data`
  (Python with NumPy, pandas, SciPy, Matplotlib, XGBoost for `fat-tails/` and `tv-audience/`),
  `diagrams` (Node and Chromium for archify), `graph` (graphify 0.9.100, Node, Playwright,
  Chromium), `roteiro-preview` (Pillow, ffmpeg, espeak-ng, DejaVu fonts), `pomodoro` (Zig 0.14),
  `agda` (Agda 2.8.0 and its standard library 2.3, versions asserted in `nix/agda.nix`),
  `manim` (Manim Community 0.21, ffmpeg and LaTeX for the 3Blue1Brown-style takes of the video
  script), and `check`, which joins the shells `just check` needs: `nix develop .#check --command just
  check`. The default shell (the paper toolchain) and `md` are in `flake.nix`.
- Outside Nix: the voice of the video script (`contextual-bandits/script/voice/`, XTTS and
  OpenVoice on PyTorch) has its own `requirements.txt`; nixpkgs does not package OpenVoice.

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
   `counterexample` of `kernel/proof/Proof.scala`, and nothing is skipped or marked expected to fail. The compiler
   enforces Scala 3's indentation syntax (`-new-syntax -Werror`); `sbt scalafmtCheckAll` and
   `sbt "scalafixAll --check"` keep the format and forbid `return` and `null`.
2. **Z3 first.** A new decision rule or model goes in `z3-scala/src/main/scala/bandit/domain/Bandit.scala` (definition plus at
   least a validity statement in `Theorems.scala`), then in Haskell with the same name. Update the
   interface and theorem tables in `contextual-bandits/README.md` (and its pt-BR twin). Lean is not used for the contextual bandit any more
   (`docs/decisions/0001-z3-over-lean.md`).
3. **Keep the mirror exact.** Tie-breaking (argmax keeps the *first* maximum),
   argument order and the meaning of `width` must match between Z3, Haskell and Agda (`agda/`).
   When an example in `z3-scala/src/main/scala/bandit/domain/Examples.scala` or `z3-scala/src/main/scala/bandit/domain/Video.scala` changes, update `specCheck` in
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
6. **Haskell stays dependency-light**: `base` and `containers` only, unless agreed. Agreed for
   the tools under `tools/` (the owner, 2026-11-11): GHC's bundled libraries, SBV and zlib, from
   the tool's own `nix/<tool>.nix` shell; the bandit package `haskell/` keeps the rule.
   Build with `-Wall` and leave no warnings.
   LiquidHaskell refinements live in `{-@ ... @-}` comments, so they add no dependency;
   `just liquid` must say `SAFE` for every module it checks. A new `ignore`, `assume` or `lazy`
   gets a row in `haskell/LIQUIDHASKELL.md` that says why, or the check fails.
7. **Exact vs float**: Z3 works over the reals and exact rationals, Haskell uses `Double`
   (and `Rational` in `Video.hs`). Don't claim a Z3 statement covers floating-point behaviour.

## Papers (Paper Fabric)

- A paper is `papers/<slug>/` (`metadata.md`, `prose/NN-*.md`, `refs.bib`, `REFERENCES.md`).
  `just paper <slug>` builds `pdf/<slug>.pdf` inside `nix develop`. Guide: `docs/paper-fabric.md`.
  The video script is a paper in the bandit's folder, `contextual-bandits/script/`,
  with the same four parts; `just script` builds `pdf/contextual-bandits-script-pt-BR.pdf`.
  Its prose follows PTC (português técnico controlado), level `leve`: `z3-scala/z3.sh ptc` must give
  no `FAIL`, and `z3-scala/z3.sh ptc --review` lists the sentences to read for the rules Z3 cannot
  decide (`z3-scala/README.md`). `just ruido-ia` checks the PTC-9 noise catalogue the same way.
- **Fetch before you cite.** Every `refs.bib` key needs a `verified` or `partial` row in
  `REFERENCES.md`. Never cite from memory.
- Do not commit PDFs. `just paper` builds them; `.github/workflows/pdf.yml` runs only by hand.
- Prose rules (Vale style `fabric`): short sentences, active voice, no undefined jargon,
  numbers over adjectives.

## Notes

- Diagrams come from [archify](https://github.com/tt-a1i/archify), vendored in
  `vendor/archify` (see `VENDORED.md` there). Edit `docs/diagrams/src/build_candidates.py`
  (both languages live there), then `just diagrams` and `just images`. Any figure
  used in the Markdown notes must be an archify capture from `docs/diagrams/img/<lang>/`.
- **The diagrams are dark, always** (the owner, 2026-11-09). `just images` keeps the dark
  capture, never a light one. Every link to a diagram page carries `?theme=dark`, which archify
  reads before the reader's setting. `site/build.py` adds it to the links of the pages it builds.
  `docs/diagrams/index.html` is dark too. `checks/diagrams.sh` fails on a light PNG or a link
  without `?theme=dark`.

- Network graphs live in `graphs/<name>/` and are drawn by [graphify](https://graphify.com)
  (`pip install graphifyy==0.9.100`). Edit the `nodes.csv` and `edges.csv` there; every edge
  needs a source URL. `just graph` builds `out/` (not committed), `just render-graph` serves it.

- `contextual-bandits/README.md` is the one page for the contextual bandit: the idea, an index
  of every bandit file, the commands, the interface, the theorems, the Haskell port and the note
  for the video. A new bandit file gets a row in its "Files" table; the bandit's details go there,
  not in the root `README.md`. The code stays where it is (`z3-scala/`, `haskell/`). The page is
  written in ASD-STE100 (Simplified Technical English). `contextual-bandits/README.pt-BR.md`
  follows the gramatico rules (level `smart-note + descritivo`). Keep the two in sync.
  Cite only sources that you have opened. Mark unchecked claims with ⚠ in pt-BR.

- `crypto-strength/` scores crypto networks. Edit `data/scores.csv` (every row needs
  evidence and a source id from `data/sources.csv`, or `J` for judgment), then run
  `just crypto-strength` and commit `heatmap.svg` and `results.md` with the data.

## Good next steps

- Probabilistic half of the LinUCB regret bound: calibration holds with
  probability ≥ 1 − δ (needs Mathlib), and the elliptical potential lemma.
- A Thompson sampling spec (a distribution over argmax of posterior samples).
- A Python port that follows the same interface.
