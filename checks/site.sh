#!/usr/bin/env bash
# The browsable index (site/build.py, `just site`): every page and file it lists exists, every paper
# has its metadata, and the index is written. It needs no pandoc, XeLaTeX or ffmpeg; `just site` runs
# the full build in Nix.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 site/build.py --check
