#!/usr/bin/env bash
# Build tools/tv-z3/ with GHC and run the Z3 statements, from the repository root:
#
#   tools/tv-z3/run.sh
#
# Outside its shell it enters `nix develop .#tv-z3` (nix/tv-z3.nix: GHC with SBV and Z3, which
# SBV runs as a process), so every version comes from flake.lock. The binary is rebuilt when a
# source is newer.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here/../.."

if ! ghc-pkg latest sbv > /dev/null 2>&1 || ! command -v z3 > /dev/null; then
  if [ -n "${TV_Z3_IN_SHELL:-}" ]; then
    echo "tv-z3: the shell has no GHC with sbv and no z3" >&2; exit 1
  fi
  command -v nix > /dev/null || {
    echo "tv-z3: needs nix (or GHC with sbv and z3 on PATH)" >&2; exit 1; }
  exec env TV_Z3_IN_SHELL=1 nix develop --extra-experimental-features 'nix-command flakes' \
    --no-update-lock-file .#tv-z3 --command bash "$0" "$@"
fi
export LANG=C.UTF-8 LC_ALL=C.UTF-8

bin="$here/build/tv-z3"
if [ ! -x "$bin" ] || [ -n "$(find "$here" -maxdepth 1 -name '*.hs' -newer "$bin")" ]; then
  mkdir -p "$here/build"
  ghc -O1 -Wall -Werror -i"$here" -outputdir "$here/build" -o "$bin" "$here/Main.hs" > "$here/build/ghc.log" 2>&1 \
    || { cat "$here/build/ghc.log" >&2; exit 2; }
fi
exec "$bin" "$@"
