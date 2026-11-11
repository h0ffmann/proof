#!/usr/bin/env bash
# The preprints badge in README.md matches the folders of papers/ (scripts/preprints.py).
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/preprints.py --check
