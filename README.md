# dogma

axioms and proofs

Specifications written and proved in Lean 4, and implementations that follow
them. Each project is a self-contained folder with its own README, sources and
build steps. No project imports code from another.

## Projects

| Project | What it is | Languages | Build |
| --- | --- | --- | --- |
| [`contextual-bandit/`](contextual-bandit/README.md) | A bandit as a decision rule on top of a probabilistic model. Lean proves the rules (UCB optimism lemma, ε-greedy exploration); Haskell runs them. | Lean, Haskell | `just bandit` |
| [`house-pricing/`](house-pricing/README.md) | Rust trains seven models on California Housing. The best one that Lean replicates exactly (gradient boosting, test R² 0.833) runs in Lean over `Rat`, is called from Rust through Lean's C ABI, and has proved output bounds. | Rust, Lean | `just house-pricing` |
| [`ocean-waves/`](ocean-waves/README.md) | Spectral wave model physics (WAVEWATCH III, WAM Cycle 4 source terms) and the kernels of one model time step, in pure Lean. | Lean | `just ocean-waves` |
| [`triad-graph/`](triad-graph/README.md) | A sourced graph of Elon Musk, Peter Thiel and Alex Karp: their companies, large deals and ties to other tech figures, drawn by graphify. | CSV, Python, JS | `just graph`, `just render-graph` |
| [`cycle/`](cycle/README.md) | An essay on eternal return, with a small Lean theorem that a clock of `n + 1` moments returns. | Lean, Markdown | `just cycle` |
| [`fat-tails/`](fat-tails/README.md) | Taleb's fat-tail metrics (κ, Hill exponents, MS plots) on the S&P 500 since 1950. | Python | see its README |

`just check` runs every Lean package and the Haskell examples. `just` with no
argument lists every recipe.

## Shared tooling

These folders serve more than one project. They hold no project content.

| Folder | What it holds |
| --- | --- |
| [`papers/`](docs/paper-fabric.md) | Paper Fabric: one folder per paper (`papers/<slug>/`), built to PDF with pandoc and XeLaTeX. Papers today: [`contextual-bandits`](papers/contextual-bandits/metadata.md), [`cycle`](papers/cycle/metadata.md), [`fat-tails`](papers/fat-tails/metadata.md). |
| `format/`, `tools/`, `flake.nix` | The paper template, the Gleam reference and STE checks, and the Nix toolchain. |
| [`vendor/archify`](vendor/archify/VENDORED.md) | The diagram tool used by `contextual-bandit/diagrams`. |
| `scripts/`, `.vale/`, `.markdownlint-cli2.jsonc` | Markdown quality checks (`just md-quality`). |

```bash
nix develop          # pandoc, pandoc-crossref, XeLaTeX, Gleam (pinned by flake.lock)
just paper           # every paper -> pdf/<slug>.pdf
just paper-check     # + reference log and STE/pt-BR checks
```

Rules for agents and contributors are in [AGENTS.md](AGENTS.md).
