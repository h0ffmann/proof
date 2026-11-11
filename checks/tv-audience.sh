#!/usr/bin/env bash
# The TV audience definitions of agda/src/TvAudience/ against their references (tools/tv-audience/):
# on Rational, every example of agda/src/TvAudience/Examples.agda, exactly; on Double, the seasonal
# naive numbers that tv-audience/python/experiment.py wrote to tv-audience/results.json, what the
# Agda theorems say of every model's numbers there, and the rounding of tv-audience/results.md.
# The self-test first shows that a wrong example fails. The Agda proofs themselves are
# checks/agda.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
tools/tv-audience/run.sh --self-test
tools/tv-audience/run.sh
