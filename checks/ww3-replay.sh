#!/usr/bin/env bash
# Milestone M5 of ocean-triton/PLAN.md, the W mark (ww3-replay/README.md):
#
# 1. WAVEWATCH III at the pin, built by nix/ww3-replay.nix, runs ww3_ts1 in three cases, and
#    ww3_capture writes captures whose sha256 are those of ww3-replay/captures.sha256 (the run
#    reproduces, byte for byte);
# 2. the printed Triton kernels of ocean-triton/gather.py, sdb.py and lanes.py, run by Triton's
#    CPU interpreter on each fresh capture, give W3SNL1's, W3SBT1's, W3SDB1's, W3SDS4's,
#    W3SIN4's and W3SLN1's S and D, W3SIN4's LLWS and wave stresses, W3SPR4's means and stress,
#    WAVNU1's K and CG bit for bit (ww3-replay/replay.py --bits), and, on the deep case, INSIN4's
#    tables (TAUT, TABU_TAUHF's TAUHFT, TABU_TAUHF2's TAUHFT and a plane of TAUHFT2, SATINDICES,
#    SATWEIGHTS, CUMULW) and a whole W3SRCE call run pass by pass on the kernels (--only W3SRCE);
# 3. self-test: a + printed as - in the S kernel of W3SNL1, a sign dropped in W3SDB1's D, libmvec's
#    powf replaced by scalar powf in W3SDS4's DDIAG, COSWIND**(SSINTHP+1) in W3SIN4's DSTAB, and
#    one captured output of WW3 off by a part in 1000 (and 1e-9), in W3SNL1's S, in W3SDB1's D,
#    in W3SDS4's D and in W3SIN4's D, each fail step 2, and so do TABU_STRESS's XM+1 and INSIN4's
#    0.5*C2 printed wrong.
#
#   checks/ww3-replay.sh            # steps 1 to 3
#   checks/ww3-replay.sh --write    # run WW3 again and write the captures' hashes into ww3-replay/captures.sha256
set -euo pipefail
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cases="deep shallow surf"
ww3-replay/run.sh "$work/captures"

hashes=$(realpath ww3-replay/captures.sha256)
if [ "${1:-}" = "--write" ]; then
  (cd "$work/captures" && sha256sum deep.txt shallow.txt surf.txt) > "$hashes"
  echo "ww3-replay: wrote the hashes of $cases into ww3-replay/captures.sha256"
  exit 0
fi

(cd "$work/captures" && sha256sum --check --quiet "$hashes") || {
  echo "ww3-replay: WW3's run no longer writes the captures of ww3-replay/captures.sha256" >&2; exit 1; }

replay() {
  nix develop --extra-experimental-features 'nix-command flakes' --no-update-lock-file .#triton \
    --command python3 ww3-replay/replay.py "$@" --bits
}
for c in $cases; do replay ocean-triton/gather.py "$work/captures/$c.txt"; done
# INSIN4's tables depend on the grid only, the same in every case.
replay ocean-triton/gather.py "$work/captures/deep.txt" --only TABU_STRESS,TABU_TAUHF,TABU_TAUHF2,INSIN4
replay ocean-triton/gather.py "$work/captures/deep.txt" --only W3SRCE

sed '/^def w3snl1_s(/,/tl.store/s|(tl.load(SA1_ptr + tl.load(self_ptr + i, mask=m, other=0), mask=m, other=0.0) + |(tl.load(SA1_ptr + tl.load(self_ptr + i, mask=m, other=0), mask=m, other=0.0) - |' \
  ocean-triton/gather.py > "$work/wrong-gather.py"
if cmp -s "$work/wrong-gather.py" ocean-triton/gather.py; then
  echo "ww3-replay: self-test: the kernel mutation did not apply" >&2; exit 1
fi
if replay "$work/wrong-gather.py" "$work/captures/deep.txt" --only W3SNL1 > /dev/null; then
  echo "ww3-replay: self-test: a wrong kernel passed" >&2; exit 1
fi
awk 'f && !done { printf "%.9e\n", $1 * 1.001 + 1e-9; done = 1; next } /^SNL / { f = 1 } { print }' \
  "$work/captures/deep.txt" > "$work/wrong-capture.txt"
if replay ocean-triton/gather.py "$work/wrong-capture.txt" --only W3SNL1 > /dev/null; then
  echo "ww3-replay: self-test: a wrong output of WW3 passed" >&2; exit 1
fi
sed 's|    d = (-cbj).to(tl.float32)|    d = (cbj).to(tl.float32)|' ocean-triton/sdb.py > "$work/wrong-sdb.py"
if cmp -s "$work/wrong-sdb.py" ocean-triton/sdb.py; then
  echo "ww3-replay: self-test: the W3SDB1 mutation did not apply" >&2; exit 1
fi
if replay ocean-triton/gather.py "$work/captures/surf.txt" --sdb "$work/wrong-sdb.py" --only W3SDB1 > /dev/null; then
  echo "ww3-replay: self-test: a wrong W3SDB1 kernel passed" >&2; exit 1
fi
awk 'f && !done { printf "%.9e\n", $1 * 1.001 + 1e-9; done = 1; next } /^DDB / { f = 1 } { print }' \
  "$work/captures/surf.txt" > "$work/wrong-sdb-capture.txt"
if replay ocean-triton/gather.py "$work/wrong-sdb-capture.txt" --only W3SDB1 > /dev/null; then
  echo "ww3-replay: self-test: a wrong output of W3SDB1 passed" >&2; exit 1
fi
# W3SDS4: glibc's scalar powf where WW3's -O3 code calls libmvec's (ocean-triton/libm.py); then
# a captured D off by a part in 1000.
sed 's|libm\.vpowf(|libm.scalarf(|g' ocean-triton/lanes.py > "$work/wrong-lanes.py"
if cmp -s "$work/wrong-lanes.py" ocean-triton/lanes.py; then
  echo "ww3-replay: self-test: the W3SDS4 mutation did not apply" >&2; exit 1
fi
if replay ocean-triton/gather.py "$work/captures/surf.txt" --lanes "$work/wrong-lanes.py" --only W3SDS4 > /dev/null; then
  echo "ww3-replay: self-test: scalar powf in W3SDS4's DDIAG passed" >&2; exit 1
fi
awk 'f && !done { printf "%.9e\n", $1 * 1.001 + 1e-9; done = 1; next } /^DDS / { f = 1 } { print }' \
  "$work/captures/surf.txt" > "$work/wrong-sds4-capture.txt"
if replay ocean-triton/gather.py "$work/wrong-sds4-capture.txt" --only W3SDS4 > /dev/null; then
  echo "ww3-replay: self-test: a wrong output of W3SDS4 passed" >&2; exit 1
fi
sed '/^def w3sin4_d(/,/tl.store/s|sinthp, lm_ptr, z)|(sinthp + 1.0), lm_ptr, z)|' ocean-triton/lanes.py > "$work/wrong-sin4.py"
if cmp -s "$work/wrong-sin4.py" ocean-triton/lanes.py; then
  echo "ww3-replay: self-test: the W3SIN4 mutation did not apply" >&2; exit 1
fi
if replay ocean-triton/gather.py "$work/captures/deep.txt" --lanes "$work/wrong-sin4.py" --only W3SIN4 > /dev/null; then
  echo "ww3-replay: self-test: COSWIND**(SSINTHP+1) in W3SIN4's DSTAB passed" >&2; exit 1
fi
awk 'f && !done { printf "%.9e\n", $1 * 1.001 + 1e-9; done = 1; next } /^DIN / { f = 1 } { print }' \
  "$work/captures/deep.txt" > "$work/wrong-sin4-capture.txt"
if replay ocean-triton/gather.py "$work/wrong-sin4-capture.txt" --only W3SIN4 > /dev/null; then
  echo "ww3-replay: self-test: a wrong output of W3SIN4 passed" >&2; exit 1
fi
# TABU_STRESS: XM+1 printed as 1.25. (W3SRCE's call is not mutated here: each replay of it takes about
# an hour on the interpreter; its kernels are mutated in checks/ocean-triton.sh, and the comparison
# is the one every routine above uses.)
sed '/^def tabu_stress(/,/tl.store/s|(3.0 / 2.0)|(5.0 / 4.0)|g' ocean-triton/lanes.py > "$work/wrong-taut.py"
if cmp -s "$work/wrong-taut.py" ocean-triton/lanes.py; then
  echo "ww3-replay: self-test: the TABU_STRESS mutation did not apply" >&2; exit 1
fi
if replay ocean-triton/gather.py "$work/captures/deep.txt" --lanes "$work/wrong-taut.py" --only TABU_STRESS > /dev/null; then
  echo "ww3-replay: self-test: XM+1 = 1.25 in TABU_STRESS passed" >&2; exit 1
fi
# INSIN4's CUMULW: 0.5*C2 printed as 0.25*C2.
sed '/^def insin4_cumulw(/,/tl.store/s|(1.0 / 2.0)|(1.0 / 4.0)|g' ocean-triton/lanes.py > "$work/wrong-insin4.py"
if cmp -s "$work/wrong-insin4.py" ocean-triton/lanes.py; then
  echo "ww3-replay: self-test: the INSIN4 mutation did not apply" >&2; exit 1
fi
if replay ocean-triton/gather.py "$work/captures/deep.txt" --lanes "$work/wrong-insin4.py" --only INSIN4 > /dev/null; then
  echo "ww3-replay: self-test: 0.25*C2 in INSIN4's CUMULW passed" >&2; exit 1
fi
echo "ww3-replay: self-test OK (a wrong kernel and a wrong output of WW3 fail, for W3SNL1, W3SDB1, W3SDS4, W3SIN4, TABU_STRESS and INSIN4)"
