#!/usr/bin/env bash
# Every papers/*/aixiv.json is a valid aiXiv manifest, and the check refuses bad ones (scripts/aixiv.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/aixiv.sh check --self-test
scripts/aixiv.sh check
