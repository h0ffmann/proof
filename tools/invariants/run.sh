#!/usr/bin/env bash
# Build tools/invariants/ with GHC and run it, from the repository root:
#
#   tools/invariants/run.sh [--facts | --self-test]
#
# Outside its shell it enters `nix develop .#invariants` (nix/invariants.nix: clingo, and GHC with
# regex-pcre-builtin), so every version comes from flake.lock. It shares Py.hs with
# tools/text-checks/ and Json.hs with tools/port-audit/. The binary is rebuilt when a source is
# newer than it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tools="$here/.."
cd "$here/../.."

if ! ghc-pkg latest regex-pcre-builtin > /dev/null 2>&1 || ! command -v clingo > /dev/null; then
  if [ -n "${INVARIANTS_IN_SHELL:-}" ]; then
    echo "invariants: the shell has no GHC with regex-pcre-builtin, or no clingo" >&2; exit 1
  fi
  command -v nix > /dev/null || {
    echo "invariants: needs nix (or GHC with regex-pcre-builtin, and clingo, on PATH)" >&2; exit 1; }
  exec env INVARIANTS_IN_SHELL=1 nix develop --extra-experimental-features 'nix-command flakes' \
    --no-update-lock-file .#invariants --command bash "$0" "$@"
fi
export LANG=C.UTF-8 LC_ALL=C.UTF-8

bin="$here/build/invariants"
srcs=("$here/Main.hs" "$tools/text-checks/Py.hs" "$tools/port-audit/Json.hs")
stale=0
[ -x "$bin" ] || stale=1
for s in "${srcs[@]}"; do [ "$s" -nt "$bin" ] && stale=1; done
if [ "$stale" -eq 1 ]; then
  mkdir -p "$here/build"
  ghc -O1 -Wall -Werror -i"$here" -i"$tools/text-checks" -i"$tools/port-audit" -outputdir "$here/build" \
    -o "$bin" "$here/Main.hs" > "$here/build/ghc.log" 2>&1 || { cat "$here/build/ghc.log" >&2; exit 2; }
fi
exec "$bin" "$@"
