<div align="center">

<img alt="A neural network flowing into the universal quantifier, drawn from Desmos equations, by @h0ffmann" src="docs/logo/logo.svg" width="820"/>

# proof

<sub>∀ · <i>for all</i> · <a href="#in-one-minute">in one minute</a> · <a href="#index-of-experiments">experiments</a> · <a href="#lines-of-code">lines of code</a> · <a href="#papers">papers</a> · <a href="#recipes">recipes</a> · <a href="#structure">structure</a> · <a href="docs/logo/README.md">the logo</a> · <a href="docs/logo/logo.desmos.json">its Desmos equations</a> · <a href="#license">license</a></sub>

[![Z3 5.3.3](https://img.shields.io/badge/Z3-5.3.3-1b3a5c?style=flat-square)](z3-scala/build.sbt)
[![Scala 3.9.0](https://img.shields.io/badge/Scala-3.9.0_on_Kyo-1b3a5c?style=flat-square&logo=scala&logoColor=white)](z3-scala)
[![Lean 4 v4.24.0](https://img.shields.io/badge/Lean_4-v4.24.0-1b3a5c?style=flat-square)](ocean-waves/lean/lean-toolchain)
[![no sorry](https://img.shields.io/badge/sorry-0-2a78d6?style=flat-square)](AGENTS.md)
[![Haskell](https://img.shields.io/badge/Haskell-base_%2B_containers-1b3a5c?style=flat-square&logo=haskell&logoColor=white)](haskell)
[![Rust](https://img.shields.io/badge/Rust-std_only-1b3a5c?style=flat-square&logo=rust&logoColor=white)](house-pricing/rust)
[![Python](https://img.shields.io/badge/Python-experiments-1b3a5c?style=flat-square&logo=python&logoColor=white)](#index-of-experiments)
[![preprints: 4](https://img.shields.io/badge/preprints-4-2a78d6?style=flat-square)](papers)
[![Nix](https://img.shields.io/badge/toolchain-Nix_flake-1b3a5c?style=flat-square&logo=nixos&logoColor=white)](flake.nix)
[![license: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-1b3a5c?style=flat-square)](#license)

</div>

## In one minute

- **proof** (formerly *dogma*) holds specifications checked by a prover, and implementations that
  follow them name for name. The contextual bandit is specified in [Z3](https://github.com/Z3Prover/z3)
  (`z3-scala/`, since 2026-11-09: [why](docs/decisions/0001-z3-over-lean.md)) and implemented in Haskell;
  house pricing, ocean waves and the cycle are proved in [Lean 4](https://lean-lang.org), with Rust
  for house pricing. The specification is the source of truth; the implementations are checked
  against its examples.
- Next to the proofs sit data experiments in Python (fat tails, TV audiences, crypto networks), each
  with its results committed and, where it is worth it, a paper.
- Papers are Markdown built to PDF by the Paper Fabric pipeline (pandoc, pandoc-crossref, XeLaTeX),
  pinned by Nix. Every citation was fetched before it was cited, and `REFERENCES.md` logs how.
- Every Z3 statement is checked by refutation (`unsat`), none is skipped; the Lean code is
  core-only (no Mathlib) and has no `sorry`, `admit` or new `axiom` ([`AGENTS.md`](AGENTS.md), "Rules").
- Every change lands through a pull request. CI is off while the repository is private, so the
  checks run by hand ([Recipes](#recipes)).

## Index of experiments

| Folder | Problem | Language | Maturity |
|---|---|---|---|
| [`contextual-bandits/`](contextual-bandits/README.md), [`z3-scala/`](z3-scala/README.md), [`haskell/`](haskell) | Contextual bandits: a decision rule on top of a probabilistic reward model; validity and the UCB optimism lemma ([page](contextual-bandits/README.md), [preprint](papers/contextual-bandits/metadata.md)) | Z3 (Scala), Haskell, Agda | **Proved**: spec checked by Z3 for K ≤ 5 arms and by Agda for every K ([`agda/`](agda/README.md)), Haskell port checked against its examples; regret bound open |
| [`house-pricing/`](house-pricing/README.md) | California house prices: seven models compared, gradient boosting replicated exactly in Lean and called from Rust | Rust, Lean 4 | **Proved**: output bounds and a monotone variant proved; Rust/Lean parity checked |
| [`ocean-waves/`](ocean-waves/README.md) | Physics and numerical kernels of a spectral wave model (WAVEWATCH III, WAM Cycle 4) | Lean 4 | **Proved**: kernels and their theorems; no runnable model port yet |
| [`cycle/`](cycle/README.md) | Eternal return: "time is a flat circle" as a theorem about a clock ([essay](papers/cycle/metadata.md)) | Lean 4, Markdown | **Draft**: theorem proved, essay is a skeleton |
| [`fat-tails/`](fat-tails/README.md) | Taleb's fat-tail diagnostics on the S&P 500, 1950 to 2026; power-law against Gaussian VaR ([preprint](papers/fat-tails/metadata.md)) | Python | **Results**: real data, results committed, preprint v0 |
| [`tv-audience/`](tv-audience/README.md) | Forecasting big-show TV audiences as a competition between channels: XGBoost, DNN, Mistral Timestral, joint competitive share model ([preprint](papers/tv-audience/metadata.md)) | Python | **Simulated**: synthetic benchmark and preprint v0; Timestral arm not run; real-channel test pending |
| [`crypto-strength/`](crypto-strength/README.md) | 17 crypto networks scored on nine factors, long-term top 10 | Python, CSV | **Results**: sourced scores, partly judgment |
| [`port-audit/`](port-audit/README.md) | Audit of [chaceon](https://github.com/h0ffmann/chaceon), the Rust port of WAVEWATCH III: the `f32` division rewrite, Fortran intrinsics, `W3SRCE`'s time step; how much of WW3 is translated and integrated | Z3 (Scala) | **Proved**: 28 statements, 5 with an expected counterexample; two show the time step can exceed its limiter. Coverage: 37% of WW3 translated, 47% of the target build integrated |
| [`triangle-grids/`](triangle-grids/README.md) | Triangle grids for WAVEWATCH III with Aron Roland's size rules (depth, coast, slope, 5 km floor, 30% growth), and their uses in global, hurricane and nearshore forecasting | Z3 (Scala), Markdown | **Proved**: 13 statements on the size rules and WW3's explicit sub-step count; no WW3 run |
| [`graphs/triad/`](graphs/triad/README.md) | Network of Musk, Thiel and Karp: companies, deals and ties | Python, JavaScript (graphify) | **Results**: sourced edges, rendered graph |
| [`pomodoro/`](pomodoro/README.md) | Interval timer for macOS: native dialogs set the period and the beep sound, remembered in `~/.pomodoro` (`just build-mac`) | Zig | **Tool**: builds for Apple Silicon |

Maturity levels, strongest first: **Proved** (Lean proofs with no `sorry`, or Z3 statements all `unsat`; implementation
checked against them), **Results** (runs end to end on real data, outputs committed),
**Simulated** (runs end to end on synthetic data only), **Draft** (partial: a skeleton or an
unfinished write-up).

Every paper lives in [`papers/`](papers) and builds with `just paper <slug>` (see [Papers](#papers)).

## Lines of code

A line of code is a line that is not blank and not only a comment, in a file tracked by git, with
`vendor/` left out. The badge is generated by `just loc` ([`scripts/loc.py`](scripts/loc.py)); do
not edit it by hand.

<!-- loc:start -->
![lines of code: 10,114 in 118 files](https://img.shields.io/badge/lines_of_code-10%2C114_in_118_files-1b3a5c?style=flat-square)
<!-- loc:end -->

## TV audience forecasting

[`tv-audience/`](tv-audience/README.md) forecasts prime-time audiences of big shows seven days
ahead and treats each hour as a market shared by competing channels. The Joint Competitive Share
model forecasts the pool of viewers in the hour and splits it between all channels with a
multinomial logit. On a simulated benchmark it has the lowest error on big shows, while XGBoost
with rival features is best over all slots. The paper names nine channels with public ratings
in the UK, US and Brazil for a real-data test. All data so far are synthetic.

## Contextual bandits

[`contextual-bandits/`](contextual-bandits/README.md) is the one page for the contextual bandit
([pt-BR](contextual-bandits/README.pt-BR.md)): the idea, an index of every file, the commands, the
Z3/Haskell interface, the table of what Z3 proves, the Haskell port and the note for the video.
The bandit is a decision rule on top of a probabilistic model; Z3 (`z3-scala/`) proves the rules
for K ≤ 5 arms, and the Haskell port (`haskell/`) is checked against Z3's examples.

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
The diagrams are dark whatever the reader's setting: the PNGs are dark captures, and each link
opens the page with `?theme=dark`.

| Diagram | English | Português (BR) |
|---|---|---|
| Model and decision layers (architecture) | [html](docs/diagrams/en/bandit-architecture.html?theme=dark) | [html](docs/diagrams/pt-BR/bandit-architecture.html?theme=dark) |
| One round (sequence) | [html](docs/diagrams/en/bandit-round.html?theme=dark) | [html](docs/diagrams/pt-BR/bandit-round.html?theme=dark) |
| A/B test as a special case (workflow) | [html](docs/diagrams/en/ab-test-vs-bandit.html?theme=dark) | [html](docs/diagrams/pt-BR/ab-test-vs-bandit.html?theme=dark) |
| Timeline, 1952 to 2026, video scene 1.2 (timeline) | [html](docs/diagrams/en/bandit-timeline.html?theme=dark) | [html](docs/diagrams/pt-BR/bandit-timeline.html?theme=dark) |
| π and you, video scenes 1.3 and 1.4 (workflow) | [html](docs/diagrams/en/pi-arms.html?theme=dark) | [html](docs/diagrams/pt-BR/pi-arms.html?theme=dark) |
| RSI loop, video scenes 3.1 to 3.3 (workflow) | [html](docs/diagrams/en/rsi-loop.html?theme=dark) | [html](docs/diagrams/pt-BR/rsi-loop.html?theme=dark) |

Render and host them (needs [`just`](https://github.com/casey/just), Node ≥ 18, Python 3 and Chrome/Chromium;
set `ARCHIFY_CHROME` if Chromium is not on `PATH`):

```bash
just diagrams   # validate + render every diagram to docs/diagrams/<lang>/*.html
just images     # capture PNG figures to docs/diagrams/img/<lang>/ for the notes
just serve      # host everything at http://localhost:8000 (just serve 9000 for another port)
```

To publish them, enable GitHub Pages for the `docs/` folder: the index is
`docs/diagrams/index.html`.

## Site

[`site/`](site/README.md) builds one browsable folder from the repository: an index of the
preprints (as PDF), the contextual-bandit page, the Z3 reports, the video script with its preview
and the diagrams. `just site` builds it with Nix into `result-site/`; any web server can serve it at
any path.

## Recipes

```console
just check            # every checks/<feature>.sh (`just z3` among them), the other Lean packages, the Haskell spec check
just z3               # the Z3 specification of the contextual bandit, and the language rule
just liquid           # LiquidHaskell: the refinement types of the Haskell port (nix develop .#liquidhaskell)
just house-pricing    # fetch data, train, lake build, Rust/Lean parity
just paper [slug]     # build every paper, or one, to pdf/<slug>.pdf (inside `nix develop`)
just paper-check      # papers + reference log + STE/pt-BR checks
just md-quality       # markdownlint, Vale (prose rules) and lychee (links)
just diagrams         # render the archify diagrams; `just images` captures PNGs
just graph            # build the graphify network graph; `just render-graph` serves it
just crypto-strength  # rebuild the crypto heatmap and results
just invariants       # the rules of AGENTS.md, decided by clingo on Invariants.lp (also in `just check`)
just loc              # refresh the lines-of-code table in this README (`just loc-check` only checks)
just preprints        # recount the preprints badge from papers/ (`just preprints-check` only checks; in `just check`)
python3 fat-tails/python/fat_tails.py        # fat-tails results and figures
python3 tv-audience/python/experiment.py     # TV audience benchmark, results and figures
python3 docs/logo/logo.py                    # draw the logo again (--check to verify)
```

## Structure

```
.
├── contextual-bandits/      the one page for the contextual bandit: idea, file index, proofs, video note
├── z3-scala/, haskell/      contextual bandits: Z3 spec and proofs (and the language rule), Haskell port
├── house-pricing/           Rust trains, Lean replicates and proves; Rust calls Lean through its C ABI
├── ocean-waves/             spectral wave model physics and kernels, Lean only
├── cycle/                   eternal return: a clock theorem in Lean, for the essay in papers/cycle
├── fat-tails/               Taleb's fat-tail diagnostics on the S&P 500 (Python)
├── tv-audience/             TV audience forecasting as a competition between channels (Python, simulated)
├── crypto-strength/         a scored map of 17 crypto networks (Python, CSV)
├── graphs/triad/            the Musk, Thiel and Karp network (graphify)
├── port-audit/              Z3 checks of chaceon, the Rust port of WAVEWATCH III
├── triangle-grids/          triangle grids for WW3: Roland's size rules, checked by Z3
├── papers/<slug>/           one paper each: metadata.md, prose/, refs.bib, REFERENCES.md
├── format/, tools/, .vale/  Paper Fabric: LaTeX template, refs and STE checks (Gleam), prose rules
├── docs/                    paper-fabric.md, the archify diagrams, the logo
├── vendor/archify/          the pinned archify that draws the diagrams
├── flake.nix, flake.lock    the paper toolchain, from h0ffmann/picasso's paper lab
├── Invariants.lp            the standing rules as an answer set program; `just invariants` solves it with clingo
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
- The logo is the drawing from [h0ffmann/awesome-neurosymbolic-ai](https://github.com/h0ffmann/awesome-neurosymbolic-ai),
  drawn from equations by [`docs/logo/logo.py`](docs/logo/logo.py); see
  [`docs/logo/README.md`](docs/logo/README.md).

## License

| What | License |
|---|---|
| Everything in this repository, the logo included | [MPL-2.0](LICENSE) |
| `vendor/archify/` | Apache-2.0, from its upstream ([`VENDORED.md`](vendor/archify/VENDORED.md)) |
