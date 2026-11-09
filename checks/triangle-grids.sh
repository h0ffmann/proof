#!/usr/bin/env bash
# Z3 checks of the triangle-grid size rules and of WW3's explicit sub-step count (`just grids`).
set -euo pipefail
z3-scala/z3.sh grids
