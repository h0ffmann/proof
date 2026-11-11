#!/usr/bin/env bash
# Build tools/port-audit/ with GHC and run one check, from the repository root:
#
#   tools/port-audit/run.sh chaceon
#   tools/port-audit/run.sh coverage [--write | --check] [--chaceon DIR --ww3 DIR]
#
# Outside its shell it enters `nix develop .#port-audit` (nix/port-audit.nix: GHC with SBV, Z3 and
# git), so every version comes from flake.lock. The binary is rebuilt when a source is newer.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here/../.."

if ! ghc-pkg latest sbv > /dev/null 2>&1 || ! command -v z3 > /dev/null || ! command -v git > /dev/null; then
  if [ -n "${PORT_AUDIT_IN_SHELL:-}" ]; then
    echo "port-audit: the shell has no GHC with sbv, no z3 or no git" >&2; exit 1
  fi
  command -v nix > /dev/null || {
    echo "port-audit: needs nix (or GHC with sbv, z3 and git on PATH)" >&2; exit 1; }
  exec env PORT_AUDIT_IN_SHELL=1 nix develop --extra-experimental-features 'nix-command flakes' \
    --no-update-lock-file .#port-audit --command bash "$0" "$@"
fi
export LANG=C.UTF-8 LC_ALL=C.UTF-8

bin="$here/build/port-audit"
if [ ! -x "$bin" ] || [ -n "$(find "$here" -maxdepth 1 -name '*.hs' -newer "$bin")" ]; then
  mkdir -p "$here/build"
  ghc -O1 -Wall -Werror -i"$here" -outputdir "$here/build" -o "$bin" "$here/Main.hs" > "$here/build/ghc.log" 2>&1 \
    || { cat "$here/build/ghc.log" >&2; exit 2; }
fi
exec "$bin" "$@"
