#!/usr/bin/env bash
# The fat-tail metrics of agda/src/FatTails/ against their two references (tools/fat-tails/):
# on Rational, every example of agda/src/FatTails/Examples.agda, exactly; on Double, the numbers
# that fat-tails/python/fat_tails.py wrote to fat-tails/results.json. The self-test first shows
# that a wrong example fails. The Agda proofs themselves are checks/agda.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
tools/fat-tails/run.sh --self-test
tools/fat-tails/run.sh
