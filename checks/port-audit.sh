#!/usr/bin/env bash
# Z3 checks of chaceon, the Rust port of WAVEWATCH III (`just port-audit`), and its coverage table
# (port-audit/coverage.py fetches chaceon and WW3 at their pins, so this needs the network once).
set -euo pipefail
python3 port-audit/chaceon.py
python3 port-audit/coverage.py --check
