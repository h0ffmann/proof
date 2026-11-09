#!/usr/bin/env bash
# Z3 checks of chaceon, the Rust port of WAVEWATCH III (`just port-audit`).
set -euo pipefail
python3 port-audit/chaceon.py
