#!/usr/bin/env bash
# The generated badges of README.md (tools/badges/Main.hs): `loc` or `preprints`, then --check or
# --print. GHC from `nix develop .#haskell` when GHC is not on PATH; GHC's bundled libraries only.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
if ! command -v runghc > /dev/null; then
  if [ -n "${BADGES_IN_SHELL:-}" ]; then echo "badges: the shell has no GHC" >&2; exit 1; fi
  command -v nix > /dev/null || { echo "badges: needs nix (or GHC on PATH)" >&2; exit 1; }
  exec env BADGES_IN_SHELL=1 nix develop --extra-experimental-features 'nix-command flakes' \
    --no-update-lock-file "$here/../..#haskell" --command bash "$0" "$@"
fi
cd "$here/../.."
exec runghc -Wall -Werror "$here/Main.hs" "$@"
