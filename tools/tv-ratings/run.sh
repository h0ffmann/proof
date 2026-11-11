#!/usr/bin/env bash
# Build tools/tv-ratings/ with GHC and run it, from anywhere in the repository:
#
#   tools/tv-ratings/run.sh               # fetch every source, then write tv-audience/real/*.csv
#   tools/tv-ratings/run.sh parse         # only read the pages fetched before (no network)
#   tools/tv-ratings/run.sh nielsen-us    # one source
#   tools/tv-ratings/run.sh --self-test   # the parsers on pages written for the test
#
# GHC and curl come from `nix develop .#tv-ratings` (nix/tv-ratings.nix); the script enters that
# shell by itself. The tool uses GHC's bundled libraries only (AGENTS.md, rule 6).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here/../.."

if [ -z "${TV_RATINGS_IN_SHELL:-}" ]; then
  command -v nix > /dev/null || { echo "tv-ratings: needs nix" >&2; exit 1; }
  exec env TV_RATINGS_IN_SHELL=1 nix develop --extra-experimental-features 'nix-command flakes' \
    --no-update-lock-file .#tv-ratings --command bash "$0" "$@"
fi
export LANG=C.UTF-8 LC_ALL=C.UTF-8

bin="$here/build/tv-ratings"
stale=0
[ -x "$bin" ] || stale=1
for s in "$here"/*.hs; do [ "$s" -nt "$bin" ] && stale=1; done
if [ "$stale" -eq 1 ]; then
  mkdir -p "$here/build"
  ghc -O1 -Wall -Werror -i"$here" -outputdir "$here/build/o" -o "$bin" "$here/Main.hs" \
    > "$here/build/ghc.log" 2>&1 || { cat "$here/build/ghc.log" >&2; exit 2; }
fi
exec "$bin" "$@"
