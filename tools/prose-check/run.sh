#!/usr/bin/env bash
# Build tools/prose-check/ with `agda --compile` (Agda's GHC backend) and run it, from the
# repository root:
#
#   tools/prose-check/run.sh ste [--review] [--dictionary WORDS] FILE...
#   tools/prose-check/run.sh ptc FILE...
#   tools/prose-check/run.sh compare ORIGINAL EDITION
#   tools/prose-check/run.sh self-test
#
# Outside its shell it enters `nix develop .#agda` (nix/agda.nix): the Agda wrapper there calls
# the GHC of the same locked nixpkgs, so every version comes from flake.lock. The binary is built
# again when a source is newer than it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here/../.."

if ! command -v agda > /dev/null; then
  if [ -n "${AGDA_IN_SHELL:-}" ]; then
    echo "prose-check: the shell has no agda" >&2; exit 1
  fi
  command -v nix > /dev/null || {
    echo "prose-check: needs nix (or agda with its standard library and GHC on PATH)" >&2; exit 1; }
  exec env AGDA_IN_SHELL=1 nix develop --extra-experimental-features 'nix-command flakes' \
    --no-update-lock-file .#agda --command bash "$0" "$@"
fi
export LANG=C.UTF-8 LC_ALL=C.UTF-8

bin="$here/build/Main"
if [ ! -x "$bin" ] || [ -n "$(find "$here/Main.agda" agda/src/Prose.agda agda/src/Prose agda/src/TextChecks/Verdict.agda \
    -name '*.agda' -newer "$bin")" ]; then
  mkdir -p "$here/build"
  (cd "$here" && agda --compile --compile-dir=build Main.agda) > "$here/build/agda.log" 2>&1 \
    || { cat "$here/build/agda.log" >&2; exit 2; }
fi
exec "$bin" "$@"
