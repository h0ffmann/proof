#!/usr/bin/env bash
# The Z3 specification of the contextual bandit and the checks of its video script (`just z3`).
# z3-scala/z3.sh needs a JDK and sbt; it fetches Z3's Java binding on its first run.
set -euo pipefail
z3=z3-scala/z3.sh
$z3 theorems
$z3 examples
$z3 video
$z3 language
$z3 ptc --self-test
$z3 ptc
$z3 ruido-ia --self-test
$z3 ruido-ia
