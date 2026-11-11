#!/usr/bin/env bash
# Build tools/fat-tails/ with GHC and run it, from the repository root:
#
#   tools/fat-tails/run.sh [--self-test]
#
# Outside its shell it enters `nix develop .#haskell` (nix/haskell.nix: GHC from flake.lock's
# nixpkgs). The tool uses base only, and shares Json.hs with tools/port-audit/. The binary is
# rebuilt when a source is newer than it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tools="$here/.."
cd "$here/../.."

if ! command -v ghc > /dev/null; then
  if [ -n "${FAT_TAILS_IN_SHELL:-}" ]; then echo "fat-tails: the shell has no GHC" >&2; exit 1; fi
  command -v nix > /dev/null || { echo "fat-tails: needs nix (or GHC on PATH)" >&2; exit 1; }
  exec env FAT_TAILS_IN_SHELL=1 nix develop --extra-experimental-features 'nix-command flakes' \
    --no-update-lock-file .#haskell --command bash "$0" "$@"
fi
export LANG=C.UTF-8 LC_ALL=C.UTF-8

bin="$here/build/fat-tails"
srcs=("$here/Main.hs" "$here/FatTails.hs" "$tools/port-audit/Json.hs")
stale=0
[ -x "$bin" ] || stale=1
for s in "${srcs[@]}"; do [ "$s" -nt "$bin" ] && stale=1; done
if [ "$stale" -eq 1 ]; then
  mkdir -p "$here/build"
  ghc -O1 -Wall -Werror -i"$here" -i"$tools/port-audit" -outputdir "$here/build" \
    -o "$bin" "$here/Main.hs" > "$here/build/ghc.log" 2>&1 || { cat "$here/build/ghc.log" >&2; exit 2; }
fi
exec "$bin" "$@"
