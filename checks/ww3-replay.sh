#!/usr/bin/env bash
# Milestone M5 of ocean-triton/PLAN.md, the W mark (ww3-replay/README.md):
#
# 1. WAVEWATCH III at the pin, built by nix/ww3-replay.nix, runs ww3_ts1 in three cases and
#    ww3_capture writes the same captures as ww3-replay/captures/ (the run reproduces);
# 2. the printed Triton kernels of ocean-triton/gather.py, run by Triton's CPU interpreter on each
#    capture, give W3SNL1's and W3SBT1's S and D bit for bit (ww3-replay/replay.py --bits);
# 3. self-test: a + printed as - in the S kernel of W3SNL1, and one captured output of WW3 off by
#    a part in 1000 (and 1e-9), both fail step 2.
#
#   checks/ww3-replay.sh            # steps 1 to 3
#   checks/ww3-replay.sh --write    # run WW3 again and write the captures into ww3-replay/captures/
set -euo pipefail
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cases="deep shallow surf"
ww3-replay/run.sh "$work/captures"

if [ "${1:-}" = "--write" ]; then
  mkdir -p ww3-replay/captures
  for c in $cases; do cp "$work/captures/$c.txt" ww3-replay/captures/; done
  echo "ww3-replay: wrote $cases into ww3-replay/captures/"
  exit 0
fi

for c in $cases; do
  cmp -s "$work/captures/$c.txt" "ww3-replay/captures/$c.txt" || {
    echo "ww3-replay: WW3's run no longer writes ww3-replay/captures/$c.txt" >&2
    diff "ww3-replay/captures/$c.txt" "$work/captures/$c.txt" | head -n 10 >&2; exit 1; }
done

replay() {
  nix develop --extra-experimental-features 'nix-command flakes' --no-update-lock-file .#triton \
    --command python3 ww3-replay/replay.py "$@" --bits
}
for c in $cases; do replay ocean-triton/gather.py "ww3-replay/captures/$c.txt"; done

sed '/^def w3snl1_s(/,/tl.store/s|(tl.load(SA1_ptr + tl.load(self_ptr + i, mask=m, other=0), mask=m, other=0.0) + |(tl.load(SA1_ptr + tl.load(self_ptr + i, mask=m, other=0), mask=m, other=0.0) - |' \
  ocean-triton/gather.py > "$work/wrong-gather.py"
if cmp -s "$work/wrong-gather.py" ocean-triton/gather.py; then
  echo "ww3-replay: self-test: the kernel mutation did not apply" >&2; exit 1
fi
if replay "$work/wrong-gather.py" ww3-replay/captures/deep.txt > /dev/null; then
  echo "ww3-replay: self-test: a wrong kernel passed" >&2; exit 1
fi
awk 'f && !done { printf "%.9e\n", $1 * 1.001 + 1e-9; done = 1; next } /^SNL / { f = 1 } { print }' \
  ww3-replay/captures/deep.txt > "$work/wrong-capture.txt"
if replay ocean-triton/gather.py "$work/wrong-capture.txt" > /dev/null; then
  echo "ww3-replay: self-test: a wrong output of WW3 passed" >&2; exit 1
fi
echo "ww3-replay: self-test OK (a wrong kernel and a wrong output of WW3 both fail)"
