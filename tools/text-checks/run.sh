#!/usr/bin/env bash
# Build tools/text-checks/ with GHC and run one check, from the repository root:
#
#   tools/text-checks/run.sh language | ptc [--self-test|--review] | ruido-ia [--self-test|--review|--level L]
#
# Outside its shell it enters `nix develop .#text-checks` (nix/text-checks.nix: GHC with
# regex-pcre-builtin and SBV, and Z3), so every version comes from flake.lock. The binary is
# rebuilt when a source is newer than it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here/../.."

if ! ghc-pkg latest sbv > /dev/null 2>&1 || ! ghc-pkg latest regex-pcre-builtin > /dev/null 2>&1 \
  || ! command -v z3 > /dev/null; then
  if [ -n "${TEXT_CHECKS_IN_SHELL:-}" ]; then
    echo "text-checks: the shell has no GHC with sbv and regex-pcre-builtin, or no z3" >&2; exit 1
  fi
  command -v nix > /dev/null || {
    echo "text-checks: needs nix (or GHC with sbv and regex-pcre-builtin, and z3, on PATH)" >&2; exit 1; }
  exec env TEXT_CHECKS_IN_SHELL=1 nix develop --extra-experimental-features 'nix-command flakes' \
    --no-update-lock-file .#text-checks --command bash "$0" "$@"
fi
export LANG=C.UTF-8 LC_ALL=C.UTF-8

bin="$here/build/text-checks"
if [ ! -x "$bin" ] || [ -n "$(find "$here" -maxdepth 1 -name '*.hs' -newer "$bin")" ]; then
  mkdir -p "$here/build"
  ghc -O1 -Wall -Werror -i"$here" -outputdir "$here/build" -o "$bin" "$here/Main.hs" > "$here/build/ghc.log" 2>&1 \
    || { cat "$here/build/ghc.log" >&2; exit 2; }
fi
exec "$bin" "$@"
