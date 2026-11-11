#!/usr/bin/env bash
# The validation pipeline of tv-audience/ (tools/tv-validate/): tv-audience/python/experiment.py
# runs as it is, and Haskell computes its numbers again. Every score of every model from the
# forecasts, the JCS and neurosymbolic JCS forecasts from the fitted weights, the gradient of the
# logit loss by automatic differentiation, and the theorems of agda/src/TvAudience/ on the run's
# own numbers and as Hedgehog properties. Then the self-test changes the run in ways that one line
# each must catch. The Agda proofs themselves are checks/agda.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
tools/tv-validate/run.sh
tools/tv-validate/run.sh --self-test
