#!/usr/bin/env bash
# The preprints badge in README.md matches the folders of papers/ (tools/badges/).
set -euo pipefail
cd "$(dirname "$0")/.."
tools/badges/run.sh preprints --check
