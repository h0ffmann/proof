# Task runner for dogma. Install `just`: https://github.com/casey/just
# Needs: node >= 18, python3, and Chrome/Chromium for the Archify browser gate
# (set ARCHIFY_CHROME=/path/to/chromium if it is not on PATH).

archify := "node vendor/archify/bin/archify.mjs"
port := "8000"

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
      {{archify}} visual-check "$html" --summary --require-provenance --out-dir "$ev" > "$ev/summary.json"
      png=$(ls "$ev"/*light*1440*.png 2>/dev/null | head -1)
      [ -n "$png" ] || png=$(ls "$ev"/*.png | head -1)
      cp "$png" "docs/diagrams/img/$lang/$name.png"
      echo "docs/diagrams/img/$lang/$name.png"
    done

# Serve all diagrams at http://localhost:8000 (index links both languages)
serve port=port:
    @echo "Diagrams: http://localhost:{{port}}/"
    python3 -m http.server {{port}} --directory docs/diagrams

# Check the Lean proofs and run the Haskell examples
check:
    cd lean && lake build
    cd haskell && mkdir -p build && ghc -O2 -Wall -isrc -outputdir build -o build/examples app/Main.hs && ./build/examples
