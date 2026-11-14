#!/usr/bin/env bash
# Run WAVEWATCH III's regression test ww3_ts1 (switch ST4) at the pin and capture W3SNL1, W3SBT1
# and W3SDB1 from it (ww3-replay/README.md), from the repository root:
#
#   ww3-replay/run.sh OUTDIR     # writes OUTDIR/deep.txt, shallow.txt and surf.txt
#
# Outside its shell it enters `nix develop .#ww3-replay` (nix/ww3-replay.nix), which builds WW3.
# Three cases, each one run of ww3_grid, ww3_strt and ww3_shel on the test's own input, with one
# restart written at 06:00 of the first day (the test writes none), then ww3_capture on it:
#
#   deep     the test as it is: 2500 m
#   shallow  the depth scale -6 instead of -2500: 6 m, where W3SBT1 acts on part of the spectrum
#   surf     the depth scale -2 and the minimum depth 1 m instead of 5.75: W3SDB1 breaks
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here/.."

if [ -z "${WW3_HOME:-}" ]; then
  if [ -n "${WW3_IN_SHELL:-}" ]; then
    echo "ww3-replay: the shell has no WW3_HOME" >&2; exit 1
  fi
  exec env WW3_IN_SHELL=1 nix develop --extra-experimental-features 'nix-command flakes' \
    --no-update-lock-file .#ww3-replay --command bash "$0" "$@"
fi
export LANG=C.UTF-8 LC_ALL=C.UTF-8

out=$(realpath -m "${1:?usage: ww3-replay/run.sh OUTDIR}")
mkdir -p "$out"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# shellcheck disable=SC2086  # WW3_LIBS is a list of linker flags
gfortran -cpp -I"$WW3_HOME/mod" "$here/ww3_capture.F90" "$WW3_HOME/lib/libww3.a" $WW3_LIBS \
  -o "$work/ww3_capture"

input="$WW3_SRC/regtests/ww3_ts1/input"
restart_day=19680606
restart_hour=060000

run() { # name, the grid line's depth limits and scale
  local name=$1 limits=$2 d="$work/$1"
  mkdir -p "$d"
  cp "$input/HOMOGENEOUS.depth" "$input/points.list" "$input/ww3_strt.inp" "$d/"
  sed "s|^  -5. 5.75  10  -2500. |  $limits |" "$input/ww3_grid.inp" > "$d/ww3_grid.inp"
  grep -q "^  $limits " "$d/ww3_grid.inp" || { echo "ww3-replay: the grid line moved at the pin" >&2; exit 1; }
  # The second of the two lines "19680607 000000 0 19680608 000000" is the restart output.
  awk -v r="$restart_day $restart_hour" '/^   19680607 000000      0  19680608 000000/ { n++; if (n == 2) { print "   " r "   3600  " r; next } } { print }' \
    "$input/ww3_shel.inp" > "$d/ww3_shel.inp"
  (cd "$d" && chmod u+w ./* && "$WW3_HOME/bin/ww3_grid" > grid.out && "$WW3_HOME/bin/ww3_strt" > strt.out \
     && "$WW3_HOME/bin/ww3_shel" > shel.out && mv restart001.ww3 restart.ww3 \
     && "$work/ww3_capture" "$restart_day" "$restart_hour" 1)
  cp "$d/capture.txt" "$out/$name.txt"
}

run deep    "-5. 5.75  10  -2500."
run shallow "-5. 5.75  10  -6."
run surf    "-0.1 1.0  10  -2."
echo "ww3-replay: wrote deep.txt, shallow.txt and surf.txt into $out"
