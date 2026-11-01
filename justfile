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

# ---- contextual-bandit/diagrams (archify) ----

# Regenerate the Archify candidate JSON (en + pt-BR) from contextual-bandit/diagrams/src/build_candidates.py
candidates:
    python3 contextual-bandit/diagrams/src/build_candidates.py

# Render every diagram to contextual-bandit/diagrams/<lang>/<name>.html (validate + deliver + browser check)
diagrams: candidates
    #!/usr/bin/env bash
    set -euo pipefail
    for json in contextual-bandit/diagrams/src/*/*.json; do
      lang=$(basename "$(dirname "$json")")
      file=$(basename "$json" .json)          # e.g. bandit-round.sequence
      name=${file%.*}; type=${file##*.}
      out="contextual-bandit/diagrams/$lang/$name.html"
      mkdir -p "contextual-bandit/diagrams/$lang" ".archify/evidence/$lang"
      echo "== $lang/$name ($type)"
      {{archify}} finalize "$type" "$json" "$out" --quality showcase \
        --out-dir ".archify/evidence/$lang/$name" --json > ".archify/evidence/$lang/$name.finalize.json" \
        || { cat ".archify/evidence/$lang/$name.finalize.json"; exit 1; }
    done

# Capture PNG figures of every rendered diagram into contextual-bandit/diagrams/img/<lang>/ (used by the Markdown notes)
images:
    #!/usr/bin/env bash
    set -euo pipefail
    for html in contextual-bandit/diagrams/en/*.html contextual-bandit/diagrams/pt-BR/*.html; do
      lang=$(basename "$(dirname "$html")"); name=$(basename "$html" .html)
      ev=".archify/capture/$lang/$name"; rm -rf "$ev"; mkdir -p "$ev" "contextual-bandit/diagrams/img/$lang"
      {{archify}} visual-check "$html" --summary --require-provenance --out-dir "$ev" > "$ev/summary.json" \
        || { echo "visual-check failed for $lang/$name:" >&2; cat "$ev/summary.json" >&2; exit 1; }
      # visual-check writes <name>.visual-check.<W>x<H>.<theme>.png; take the smallest light capture.
      png=$(find "$ev" -name '*.light.png' | sort -V | head -1 || true)
      [ -n "$png" ] || png=$(find "$ev" -name '*.png' | sort -V | head -1 || true)
      [ -n "$png" ] || { echo "no PNG capture for $lang/$name in $ev:" >&2; ls -la "$ev" >&2; exit 1; }
      cp "$png" "contextual-bandit/diagrams/img/$lang/$name.png"
      echo "contextual-bandit/diagrams/img/$lang/$name.png"
    done

# Serve the bandit diagrams at http://localhost:8000 (index links both languages)
serve port=port:
    @echo "Diagrams: http://localhost:{{port}}/"
    python3 -m http.server {{port}} --directory contextual-bandit/diagrams

# ---- triad-graph (graphify) ----

# Needs graphify and Playwright with Chromium (set VIS_NETWORK if unpkg.com is blocked; see triad-graph/README.md).
# Build a triad graph (or all of them): CSV -> graph.json -> graphify graph.html -> PDF and PNG in triad-graph/<triad>/out/
graph triad="":
    #!/usr/bin/env bash
    set -euo pipefail
    triads="{{triad}}"
    [ -n "$triads" ] || triads=$(for m in triad-graph/*/meta.json; do basename "$(dirname "$m")"; done)
    for t in $triads; do
      [ -f "triad-graph/$t/meta.json" ] || { echo "graph: no triad triad-graph/$t" >&2; exit 1; }
      python3 triad-graph/build.py "triad-graph/$t"
      {{graphify}} export html --graph "triad-graph/$t/out/graph.json"
      node triad-graph/render.mjs "triad-graph/$t"
    done

# Build one triad's graphify graph.html and serve it at http://localhost:8000/graph.html
render-graph triad="musk-thiel-karp" port=port:
    python3 triad-graph/build.py triad-graph/{{triad}}
    {{graphify}} export html --graph triad-graph/{{triad}}/out/graph.json
    @echo "Graph: http://localhost:{{port}}/graph.html"
    python3 -m http.server {{port}} --directory triad-graph/{{triad}}/out

# ---- Lean and Haskell checks ----

# Check every Lean package and run the Haskell examples (the projects below, except house-pricing)
check: bandit ocean-waves cycle

# Contextual bandit: check the Lean proofs, then run the Haskell examples (spec check first)
bandit:
    cd contextual-bandit/lean && lake build
    cd contextual-bandit/haskell && mkdir -p build && ghc -O2 -Wall -isrc -outputdir build -o build/examples app/Main.hs && ./build/examples

# Ocean waves: check the Lean proofs and print the #eval examples
ocean-waves:
    cd ocean-waves/lean && lake build

# Eternal return: check the Lean clock theorem
cycle:
    cd cycle/lean && lake build

# House pricing: fetch the data, train in Rust, check the Lean proofs, then Lean vs Rust through the C ABI
house-pricing:
    house-pricing/data/fetch.sh
    cd house-pricing/rust && cargo run --release -- train
    cd house-pricing/lean && lake build && lake build HousePricing:static
    cd house-pricing/rust && cargo run --release --features lean -- parity

# ---- papers (Paper Fabric, shared) ----

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
paper-check: paper
    tools/fabric refs-check papers/*/refs.bib
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
