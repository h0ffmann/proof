#!/usr/bin/env bash
# The text checks in Haskell (tools/text-checks/): the language rule of AGENTS.md, the PTC rules of
# the video script and its PTC-9 noise catalogue, each with its self-test. Z3 decides each rule
# through SBV; agda/src/TextChecks/ proves the decision layer.
set -euo pipefail
cd "$(dirname "$0")/.."
run=tools/text-checks/run.sh
$run language
$run ptc --self-test
$run ptc
$run ruido-ia --self-test
$run ruido-ia
