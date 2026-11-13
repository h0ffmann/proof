#!/usr/bin/env bash
# The ocean-wave kernels as Triton kernels (`just ocean-triton`, ocean-triton/README.md):
#
# 1. tools/ocean-triton/Main.agda only writes files: no postulate, no pragma, no foreign code
#    (the kernels, their soundness theorems and the printer are --safe Agda in
#    agda/src/OceanTriton/, which checks/agda.sh type-checks);
# 2. ocean-triton/kernels.py and ocean-triton/vectors.json are what the Agda prints now;
# 3. the printed kernels, run by Triton (its CPU interpreter, `nix develop .#triton`), agree
#    with the exact values within the float32 budget of ocean-triton/check.py;
# 4. self-test: a wrong exact value and a wrong operator in a kernel both fail step 3.
#
#   checks/ocean-triton.sh            # steps 1 to 4
#   checks/ocean-triton.sh --write    # print the two files again into ocean-triton/
set -euo pipefail
cd "$(dirname "$0")/.."

main=tools/ocean-triton/Main.agda
if grep -nE 'postulate|\{-#[[:space:]]*(COMPILE|FOREIGN|TERMINATING|NON_TERMINATING|BUILTIN)' "$main"; then
  echo "ocean-triton: $main may only do output" >&2; exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tools/ocean-triton/run.sh "$work/kernels.py" "$work/vectors.json"

if [ "${1:-}" = "--write" ]; then
  cp "$work/kernels.py" "$work/vectors.json" ocean-triton/
  echo "ocean-triton: wrote ocean-triton/kernels.py and ocean-triton/vectors.json"
  exit 0
fi

for f in kernels.py vectors.json; do
  cmp -s "$work/$f" "ocean-triton/$f" || {
    echo "ocean-triton: ocean-triton/$f is stale; run checks/ocean-triton.sh --write" >&2
    diff "ocean-triton/$f" "$work/$f" | head -n 20 >&2; exit 1; }
done

py() {
  nix develop --extra-experimental-features 'nix-command flakes' --no-update-lock-file .#triton \
    --command python3 "$@"
}
triton() { py ocean-triton/check.py "$@"; }

triton ocean-triton/kernels.py ocean-triton/vectors.json

# Self-test: an exact value off by 1/1000, then a + printed as - in the upwind kernel.
py - "$work/vectors.json" "$work/wrong-value.json" <<'PY'
import json, sys
from fractions import Fraction
c = json.load(open(sys.argv[1]))
e = c["advect"]["expected"]
e[5] = str(Fraction(e[5]) + Fraction(1, 1000))
json.dump(c, open(sys.argv[2], "w"))
PY
if triton ocean-triton/kernels.py "$work/wrong-value.json" > /dev/null; then
  echo "ocean-triton: self-test: a wrong exact value passed" >&2; exit 1
fi
sed 's|tl.store(out_ptr + i, ((tl.load(N_ptr + i, mask=m, other=0.0) + |tl.store(out_ptr + i, ((tl.load(N_ptr + i, mask=m, other=0.0) - |' \
  ocean-triton/kernels.py > "$work/wrong-kernel.py"
if cmp -s "$work/wrong-kernel.py" ocean-triton/kernels.py; then
  echo "ocean-triton: self-test: the kernel mutation did not apply" >&2; exit 1
fi
if triton "$work/wrong-kernel.py" ocean-triton/vectors.json > /dev/null; then
  echo "ocean-triton: self-test: a wrong kernel passed" >&2; exit 1
fi
echo "ocean-triton: self-test OK (a wrong value and a wrong kernel fail)"
