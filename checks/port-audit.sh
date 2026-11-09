#!/usr/bin/env bash
# Z3 checks of chaceon, the Rust port of WAVEWATCH III (`just port-audit`), and its coverage table
# (`z3-scala/z3.sh coverage` fetches chaceon and WW3 at their pins, so this needs the network once).
set -euo pipefail
z3-scala/z3.sh chaceon
z3-scala/z3.sh coverage --check
