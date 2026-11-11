#!/usr/bin/env bash
# The standing rules of AGENTS.md and the project, decided by clingo on Invariants.lp
# (`just invariants`, tools/invariants/). The self-test first: each rule must refuse a bad fact.
set -euo pipefail
cd "$(dirname "$0")/.."
tools/invariants/run.sh --self-test
tools/invariants/run.sh
