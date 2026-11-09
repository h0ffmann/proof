#!/usr/bin/env bash
# The Z3 specification of the contextual bandit and the checks of its video script (`just z3`).
set -euo pipefail
python3 z3/theorems.py
python3 z3/examples.py
python3 z3/video.py
python3 z3/language.py
python3 z3/ptc.py --self-test
python3 z3/ptc.py
python3 z3/ruido_ia.py --self-test
python3 z3/ruido_ia.py
