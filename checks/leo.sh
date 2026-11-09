#!/usr/bin/env bash
# Higher-order statements proved by Leo-III (`just leo`). The first run builds Leo-III with sbt.
set -euo pipefail
z3-scala/z3.sh leo
