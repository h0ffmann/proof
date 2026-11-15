#!/usr/bin/env bash
# The ocean-wave kernels as Triton kernels (`just ocean-triton`, ocean-triton/README.md):
#
# 1. tools/ocean-triton/Main.agda only writes files: no postulate, no pragma, no foreign code
#    (the kernels, their soundness theorems and the printer are --safe Agda in
#    agda/src/OceanTriton/, which checks/agda.sh type-checks);
# 2. ocean-triton/kernels.py, vectors.json, grid.py, grid_vectors.json, gather.py,
#    gather_vectors.json, sdb.py, sdb_vectors.json, lanes.py and lanes_vectors.json are what
#    the Agda prints now;
# 3. the printed kernels, run by Triton (its CPU interpreter, `nix develop .#triton`), agree
#    with the exact values within the float32 budget of ocean-triton/check.py, and so do the
#    printed launch programs of milestone M2 (ocean-triton/check_grid.py), and so do the
#    gather kernels and programs of M3 and M4, W3SBT1 and W3SNL1 among them
#    (ocean-triton/check_gather.py), and so does W3SDB1 in float64 (ocean-triton/check_sdb.py),
#    and so do the lane programs of ST4, W3SLN1, WAVNU1, INSIN4's tables and W3SRCE
#    (ocean-triton/check_lanes.py), whose glibc and libmvec functions equal the libraries' bits
#    (ocean-triton/libm.py --self-test);
# 4. self-test: a wrong exact value and a wrong operator in a kernel both fail step 3, for the
#    kernels, for the programs, for the gather module and for the lane programs (W3SDS4, and
#    W3SRCE's bound of DT), and so does a count above its R.
#
#   checks/ocean-triton.sh            # steps 1 to 4
#   checks/ocean-triton.sh --write    # print the ten files again into ocean-triton/
set -euo pipefail
cd "$(dirname "$0")/.."

main=tools/ocean-triton/Main.agda
if grep -nE 'postulate|\{-#[[:space:]]*(COMPILE|FOREIGN|TERMINATING|NON_TERMINATING|BUILTIN)' "$main"; then
  echo "ocean-triton: $main may only do output" >&2; exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
files="kernels.py vectors.json grid.py grid_vectors.json gather.py gather_vectors.json sdb.py sdb_vectors.json lanes.py lanes_vectors.json"
tools/ocean-triton/run.sh "$work/kernels.py" "$work/vectors.json" "$work/grid.py" "$work/grid_vectors.json" \
  "$work/gather.py" "$work/gather_vectors.json" "$work/sdb.py" "$work/sdb_vectors.json" \
  "$work/lanes.py" "$work/lanes_vectors.json"

if [ "${1:-}" = "--write" ]; then
  for f in $files; do cp "$work/$f" ocean-triton/; done
  echo "ocean-triton: wrote $files into ocean-triton/"
  exit 0
fi

for f in $files; do
  cmp -s "$work/$f" "ocean-triton/$f" || {
    echo "ocean-triton: ocean-triton/$f is stale; run checks/ocean-triton.sh --write" >&2
    diff "ocean-triton/$f" "$work/$f" | head -n 20 >&2; exit 1; }
done

py() {
  nix develop --extra-experimental-features 'nix-command flakes' --no-update-lock-file .#triton \
    --command python3 "$@"
}
triton() { py ocean-triton/check.py "$@"; }
grid() { py ocean-triton/check_grid.py "$@"; }
gather() { py ocean-triton/check_gather.py "$@"; }
sdb() { py ocean-triton/check_sdb.py "$@"; }
lanes() { py ocean-triton/check_lanes.py "$@"; }

triton ocean-triton/kernels.py ocean-triton/vectors.json
grid ocean-triton/grid.py ocean-triton/grid_vectors.json
gather ocean-triton/gather.py ocean-triton/gather_vectors.json
sdb ocean-triton/sdb.py ocean-triton/sdb_vectors.json
py ocean-triton/libm.py --self-test
lanes ocean-triton/lanes.py ocean-triton/lanes_vectors.json

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

# The same for the programs: a cell of the model's result off by 1/1000, then a + printed as -
# in the x sweep.
py - "$work/grid_vectors.json" "$work/wrong-grid-value.json" <<'PY'
import json, sys
from fractions import Fraction
c = json.load(open(sys.argv[1]))
e = c["model"]["expected"]
e[7] = str(Fraction(e[7]) + Fraction(1, 1000))
json.dump(c, open(sys.argv[2], "w"))
PY
if grid ocean-triton/grid.py "$work/wrong-grid-value.json" > /dev/null; then
  echo "ocean-triton: self-test: a wrong exact value of a program passed" >&2; exit 1
fi
sed '/^def sweep_x/,/tl.store/s|tl.store(out_ptr + i, ((tl.load(F_ptr + i, mask=m, other=0.0) + |tl.store(out_ptr + i, ((tl.load(F_ptr + i, mask=m, other=0.0) - |' \
  ocean-triton/grid.py > "$work/wrong-grid.py"
if cmp -s "$work/wrong-grid.py" ocean-triton/grid.py; then
  echo "ocean-triton: self-test: the grid kernel mutation did not apply" >&2; exit 1
fi
if grid "$work/wrong-grid.py" ocean-triton/grid_vectors.json > /dev/null; then
  echo "ocean-triton: self-test: a wrong grid kernel passed" >&2; exit 1
fi
# The same for the gather module: a point of W3SNL1's S off by a part in 1000, a + printed as - in its
# S kernel, and a count of UE's rep above its R.
py - "$work/gather_vectors.json" "$work/wrong-gather-value.json" <<'PY'
import json, sys
from fractions import Fraction
c = json.load(open(sys.argv[1]))
e = c["programs"]["w3snl1"]["expected"]["S"]
e[3] = str(Fraction(e[3]) * Fraction(1001, 1000))
json.dump(c, open(sys.argv[2], "w"))
PY
if gather ocean-triton/gather.py "$work/wrong-gather-value.json" > /dev/null; then
  echo "ocean-triton: self-test: a wrong exact value of W3SNL1 passed" >&2; exit 1
fi
sed '/^def w3snl1_s(/,/tl.store/s|(tl.load(SA1_ptr + tl.load(self_ptr + i, mask=m, other=0), mask=m, other=0.0) + |(tl.load(SA1_ptr + tl.load(self_ptr + i, mask=m, other=0), mask=m, other=0.0) - |' \
  ocean-triton/gather.py > "$work/wrong-gather.py"
if cmp -s "$work/wrong-gather.py" ocean-triton/gather.py; then
  echo "ocean-triton: self-test: the gather kernel mutation did not apply" >&2; exit 1
fi
if gather "$work/wrong-gather.py" ocean-triton/gather_vectors.json > /dev/null; then
  echo "ocean-triton: self-test: a wrong gather kernel passed" >&2; exit 1
fi
py - "$work/gather_vectors.json" "$work/wrong-gather-count.json" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
c["programs"]["w3snl1"]["indices"]["cnt"][-1] = 3
json.dump(c, open(sys.argv[2], "w"))
PY
if gather ocean-triton/gather.py "$work/wrong-gather-count.json" > /dev/null 2>&1; then
  echo "ocean-triton: self-test: a count above R passed" >&2; exit 1
fi
# The same for W3SDB1: the D of the case at the fixed point off by a part in 1000, then
# HRMS * HRMS printed as HRMS + HRMS in the FDONLY kernel.
py - "$work/sdb_vectors.json" "$work/wrong-sdb-value.json" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
c[2]["D"] = repr(float(c[2]["D"]) * 1.001)
json.dump(c, open(sys.argv[2], "w"))
PY
if sdb ocean-triton/sdb.py "$work/wrong-sdb-value.json" > /dev/null; then
  echo "ocean-triton: self-test: a wrong exact value of W3SDB1 passed" >&2; exit 1
fi
sed '/^def w3sdb1_fdonly(/,/tl.store/s|((v7 \* v7) / (v6 \* v6))|((v7 + v7) / (v6 * v6))|' ocean-triton/sdb.py > "$work/wrong-sdb.py"
if cmp -s "$work/wrong-sdb.py" ocean-triton/sdb.py; then
  echo "ocean-triton: self-test: the W3SDB1 kernel mutation did not apply" >&2; exit 1
fi
if sdb "$work/wrong-sdb.py" ocean-triton/sdb_vectors.json > /dev/null; then
  echo "ocean-triton: self-test: a wrong W3SDB1 kernel passed" >&2; exit 1
fi
# The same for the lane programs: a point of W3SDS4's D off by a part in 1000, and the * of
# SRHS = DDIAG A printed as +.
py - "$work/lanes_vectors.json" "$work/wrong-lanes-value.json" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
e = c["w3sds4"][0]["expected"]["D"]
e[9] = repr(float(e[9]) * 1.001)
json.dump(c, open(sys.argv[2], "w"))
PY
if lanes ocean-triton/lanes.py "$work/wrong-lanes-value.json" > /dev/null; then
  echo "ocean-triton: self-test: a wrong exact value of W3SDS4 passed" >&2; exit 1
fi
sed '/^def w3sds4_s1(/,/tl.store/s|(tl.load(D1_ptr + (i) + z, mask=m, other=0.0) \* |(tl.load(D1_ptr + (i) + z, mask=m, other=0.0) + |' \
  ocean-triton/lanes.py > "$work/wrong-lanes.py"
if cmp -s "$work/wrong-lanes.py" ocean-triton/lanes.py; then
  echo "ocean-triton: self-test: the W3SDS4 kernel mutation did not apply" >&2; exit 1
fi
if lanes "$work/wrong-lanes.py" ocean-triton/lanes_vectors.json > /dev/null; then
  echo "ocean-triton: self-test: a wrong W3SDS4 kernel passed" >&2; exit 1
fi
# W3SRCE's step: the lower bound of DT, 0.5 s, printed as 0.25 s.
sed '/^def w3srce_dt(/,/tl.store/s|(1.0 / 2.0)|(1.0 / 4.0)|g' ocean-triton/lanes.py > "$work/wrong-srce.py"
if cmp -s "$work/wrong-srce.py" ocean-triton/lanes.py; then
  echo "ocean-triton: self-test: the W3SRCE kernel mutation did not apply" >&2; exit 1
fi
if lanes "$work/wrong-srce.py" ocean-triton/lanes_vectors.json --only w3srce_step > /dev/null; then
  echo "ocean-triton: self-test: a DT bound of 0.25 s in W3SRCE passed" >&2; exit 1
fi
echo "ocean-triton: self-test OK (a wrong value and a wrong kernel fail, for kernels, programs, gathers, W3SDB1, W3SDS4 and W3SRCE; a count above R fails)"
