#!/usr/bin/env bash
# The standing rules of AGENTS.md and the project, decided by clingo on Invariants.lp
# (`just invariants`). The self-test first: each rule must refuse a bad fact.
set -euo pipefail
python3 scripts/invariants.py --self-test
python3 scripts/invariants.py
