#!/usr/bin/env bash
# The port audit of chaceon (`just port-audit`, tools/port-audit/): the 28 statements of Chaceon.hs, checked
# by Z3 through SBV, and the coverage table of port-audit/README.md, which must be current
# (`coverage` fetches chaceon and WW3 at their pins, so it needs the network once).
set -euo pipefail
cd "$(dirname "$0")/.."
tools/port-audit/run.sh chaceon
tools/port-audit/run.sh coverage --check > /dev/null
echo "port-audit: coverage table current"
