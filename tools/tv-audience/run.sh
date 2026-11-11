#!/usr/bin/env bash
# Build tools/tv-audience/ with GHC and run it, from the repository root:
#
#   tools/tv-audience/run.sh [--self-test]
#
# The data check reads the test rows of the experiment, which export.py writes to
# build/test.csv from tv-audience/python as it is (`nix develop .#data`: NumPy and pandas); the
# file is written again when a Python source is newer than it. GHC comes from
# `nix develop .#haskell`. The tool uses base only, and shares Json.hs with tools/port-audit/.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tools="$here/.."
cd "$here/../.."
nixdev=(nix develop --extra-experimental-features 'nix-command flakes' --no-update-lock-file)

csv="$here/build/test.csv"
if [ "${1:-}" != "--self-test" ]; then
  fresh=1
  [ -f "$csv" ] || fresh=0
  for s in tv-audience/python/*.py "$here/export.py"; do [ "$s" -nt "$csv" ] && fresh=0; done
  if [ "$fresh" -eq 0 ]; then
    mkdir -p "$here/build"
    if python3 -c 'import numpy, pandas' 2> /dev/null; then
      python3 -I "$here/export.py" "$csv.tmp"
    else
      command -v nix > /dev/null || { echo "tv-audience: needs nix (or NumPy and pandas)" >&2; exit 1; }
      "${nixdev[@]}" .#data --command python3 -I "$here/export.py" "$csv.tmp"
    fi 2> "$here/build/export.log" || { cat "$here/build/export.log" >&2; exit 2; }
    mv "$csv.tmp" "$csv"
  fi
fi

if ! command -v ghc > /dev/null; then
  if [ -n "${TV_AUDIENCE_IN_SHELL:-}" ]; then echo "tv-audience: the shell has no GHC" >&2; exit 1; fi
  command -v nix > /dev/null || { echo "tv-audience: needs nix (or GHC on PATH)" >&2; exit 1; }
  exec env TV_AUDIENCE_IN_SHELL=1 "${nixdev[@]}" .#haskell --command bash "$0" "$@"
fi
export LANG=C.UTF-8 LC_ALL=C.UTF-8

bin="$here/build/tv-audience"
srcs=("$here/Main.hs" "$here/TvAudience.hs" "$tools/port-audit/Json.hs")
stale=0
[ -x "$bin" ] || stale=1
for s in "${srcs[@]}"; do [ "$s" -nt "$bin" ] && stale=1; done
if [ "$stale" -eq 1 ]; then
  mkdir -p "$here/build"
  ghc -O1 -Wall -Werror -i"$here" -i"$tools/port-audit" -outputdir "$here/build" \
    -o "$bin" "$here/Main.hs" > "$here/build/ghc.log" 2>&1 || { cat "$here/build/ghc.log" >&2; exit 2; }
fi
exec "$bin" "$@"
