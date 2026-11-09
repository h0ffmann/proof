# Task runner for dogma. Install `just`: https://github.com/casey/just
# Needs: node >= 18, python3, and Chrome/Chromium for the Archify browser gate
# (set ARCHIFY_CHROME=/path/to/chromium if it is not on PATH).

archify := "node vendor/archify/bin/archify.mjs"

# Paper Fabric (from h0ffmann/closed-source): Markdown prose -> pandoc (pandoc-crossref, citeproc,
# BibTeX) -> LaTeX -> XeLaTeX twice. docs/paper-fabric.md has the guide. Tools: `nix develop`.
pandoc_opts := "--from markdown+fancy_lists+raw_tex -F pandoc-crossref --citeproc --metadata link-citations=true --number-sections --top-level-division=section --fail-if-warnings -s --template format/tex/template.tex -t latex --metadata-file format/crossref.yaml"
port := "8000"
# graphify (https://graphify.com), pinned: `pip install graphifyy==0.9.100`. Override with GRAPHIFY=...
graphify := env_var_or_default("GRAPHIFY", "graphify")

# List recipes
default:
    @just --list

# Regenerate the Archify candidate JSON (en + pt-BR) from docs/diagrams/src/build_candidates.py
candidates:
    python3 docs/diagrams/src/build_candidates.py

# Render every diagram to docs/diagrams/<lang>/<name>.html (validate + deliver + browser check)
diagrams: candidates
    #!/usr/bin/env bash
    set -euo pipefail
    for json in docs/diagrams/src/*/*.json; do
      lang=$(basename "$(dirname "$json")")
      file=$(basename "$json" .json)          # e.g. bandit-round.sequence
      name=${file%.*}; type=${file##*.}
      out="docs/diagrams/$lang/$name.html"
      mkdir -p "docs/diagrams/$lang" ".archify/evidence/$lang"
      echo "== $lang/$name ($type)"
      {{archify}} finalize "$type" "$json" "$out" --quality showcase \
        --out-dir ".archify/evidence/$lang/$name" --json > ".archify/evidence/$lang/$name.finalize.json" \
        || { cat ".archify/evidence/$lang/$name.finalize.json"; exit 1; }
    done

# Capture PNG figures of every rendered diagram into docs/diagrams/img/<lang>/ (used by the Markdown notes)
images:
    #!/usr/bin/env bash
    set -euo pipefail
    for html in docs/diagrams/en/*.html docs/diagrams/pt-BR/*.html; do
      lang=$(basename "$(dirname "$html")"); name=$(basename "$html" .html)
      ev=".archify/capture/$lang/$name"; rm -rf "$ev"; mkdir -p "$ev" "docs/diagrams/img/$lang"
      {{archify}} visual-check "$html" --summary --require-provenance --out-dir "$ev" > "$ev/summary.json" \
        || { echo "visual-check failed for $lang/$name:" >&2; cat "$ev/summary.json" >&2; exit 1; }
      # visual-check writes <name>.visual-check.<W>x<H>.<theme>.png; take the smallest light capture.
      png=$(find "$ev" -name '*.light.png' | sort -V | head -1 || true)
      [ -n "$png" ] || png=$(find "$ev" -name '*.png' | sort -V | head -1 || true)
      [ -n "$png" ] || { echo "no PNG capture for $lang/$name in $ev:" >&2; ls -la "$ev" >&2; exit 1; }
      cp "$png" "docs/diagrams/img/$lang/$name.png"
      echo "docs/diagrams/img/$lang/$name.png"
    done

# Serve all diagrams at http://localhost:8000 (index links both languages)
serve port=port:
    @echo "Diagrams: http://localhost:{{port}}/"
    python3 -m http.server {{port}} --directory docs/diagrams

# Needs graphify and Playwright with Chromium (set VIS_NETWORK if unpkg.com is blocked; see graphs/triad/README.md).
# Musk, Thiel and Karp graph: CSV -> graph.json -> graphify graph.html -> PDF and PNG in graphs/triad/out/
graph:
    python3 graphs/triad/build.py
    {{graphify}} export html --graph graphs/triad/out/graph.json
    node graphs/triad/render.mjs

# Build the graphify graph.html and serve it at http://localhost:8000/graph.html
render-graph port=port:
    python3 graphs/triad/build.py
    {{graphify}} export html --graph graphs/triad/out/graph.json
    @echo "Graph: http://localhost:{{port}}/graph.html"
    python3 -m http.server {{port}} --directory graphs/triad/out

# Crypto strength map: check data/, write heatmap.svg and results.md in crypto-strength/
crypto-strength:
    python3 crypto-strength/build.py

# Check the Lean proofs (every package) and run the Haskell examples
check:
    cd lean && lake build
    cd ocean-waves/lean && lake build
    cd cycle/lean && lake build
    cd haskell && mkdir -p build && ghc -O2 -Wall -isrc -outputdir build -o build/examples app/Main.hs && ./build/examples

# The video script's invariants checked by Z3 (z3/video.py; needs python3 with z3-solver)
z3:
    python3 z3/video.py

# House pricing: fetch the data, train in Rust, check the Lean proofs, then Lean vs Rust through the C ABI
house-pricing:
    house-pricing/data/fetch.sh
    cd house-pricing/rust && cargo run --release -- train
    cd house-pricing/lean && lake build && lake build HousePricing:static
    cd house-pricing/rust && cargo run --release --features lean -- parity

# Pomodoro timer: compile pomodoro/pomodoro.zig for Apple Silicon (needs Zig >= 0.13; works from Linux too)
build-mac:
    cd pomodoro && zig build-exe pomodoro.zig -target aarch64-macos -O ReleaseSmall
    @echo "pomodoro: pomodoro/pomodoro"

# Build every paper, or the papers named: pdf/<slug>.pdf (and pdf/<slug>-ste.pdf, pdf/<slug>-pt-BR.pdf
# when the paper has prose-ste/ or prose-pt-BR/). Run inside `nix develop`.
paper *slugs:
    #!/usr/bin/env bash
    set -euo pipefail
    slugs="{{slugs}}"
    [ -n "$slugs" ] || slugs="$(ls papers)"
    mkdir -p build/tex pdf
    # The revision stamped on every page: short hash + commit count.
    printf '%s+%s' "$(git rev-parse --short HEAD)" "$(git rev-list --count HEAD)" > build/.current-revision
    for p in $slugs; do
      [ -d "papers/$p" ] || { echo "paper: no paper papers/$p" >&2; exit 1; }
      just _pdf "$p" prose "$p"
      if [ -d "papers/$p/prose-ste" ]; then just _pdf "$p" prose-ste "$p-ste"; fi
      if [ -d "papers/$p/prose-pt-BR" ]; then just _pdf "$p" prose-pt-BR "$p-pt-BR"; fi
    done

# The video script (papers/contextual-bandits/roteiro/), a paper inside the paper's folder:
# pdf/contextual-bandits-roteiro.pdf. Run inside `nix develop`.
roteiro:
    mkdir -p build/tex pdf
    printf '%s+%s' "$(git rev-parse --short HEAD)" "$(git rev-list --count HEAD)" > build/.current-revision
    just _pdf contextual-bandits/roteiro prose contextual-bandits-roteiro

# One PDF: papers/<slug>/<dir>/*.md -> build/tex/<out>.tex -> pdf/<out>.pdf (XeLaTeX twice).
_pdf slug dir out:
    pandoc {{pandoc_opts}} --bibliography papers/{{slug}}/refs.bib -o build/tex/{{out}}.tex \
      papers/{{slug}}/metadata.md papers/{{slug}}/{{dir}}/*.md
    cd build && for _ in 1 2; do \
      xelatex -interaction=nonstopmode -halt-on-error tex/{{out}}.tex > /dev/null \
        || { tail -n 30 {{out}}.log >&2; exit 1; }; \
    done
    cp build/{{out}}.pdf pdf/{{out}}.pdf
    @echo "paper: pdf/{{out}}.pdf"

# Build the papers, then check that every cited reference was fetched and logged (REFERENCES.md)
# and that each STE text and pt-BR translation keeps its citations, quotations and numbers.
paper-check: paper roteiro
    tools/fabric refs-check papers/*/refs.bib papers/*/*/refs.bib
    for p in papers/*/prose-ste; do [ -d "$p" ] || continue; p="${p#papers/}"; tools/fabric ste-check "${p%/prose-ste}"; done
    for p in papers/*/prose-pt-BR; do [ -d "$p" ] || continue; p="${p#papers/}"; tools/fabric ste-check --translation "${p%/prose-pt-BR}"; done

# The tests of tools/ (gleeunit): refs-check and ste-check.
fabric-test:
    cd tools && gleam test

# Three analysers over the Markdown files, in the flake's `md` shell: markdownlint-cli2 (structure),
# Vale (prose rules) and lychee (links). `--online` also fetches web links; `--self-test` gives each
# analyser a bad file.
md-quality *args:
    nix develop --extra-experimental-features 'nix-command flakes' --no-update-lock-file .#md --command scripts/md-quality.sh {{args}}

# Enter the paper toolchain: pandoc, pandoc-crossref, XeLaTeX, pdfLaTeX, Gleam and Erlang, just (Nix).
shell:
    nix develop --extra-experimental-features 'nix-command flakes'

# Remove the paper build outputs.
clean:
    rm -rf build pdf tools/build
