#!/usr/bin/env bash
# Z3 checks of the JCS model of tv-audience and of its logit fit (tools/tv-z3/): the theorems of
# agda/src/TvAudience/ over the exact reals, one statement a line, proved by refutation, as the
# port audit runs its statements. The Agda proofs themselves are checks/agda.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
tools/tv-z3/run.sh
