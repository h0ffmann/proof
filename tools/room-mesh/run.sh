#!/usr/bin/env bash
# Print the room mesh's NOTE lines (tools/room-mesh/Main.hs), with GHC from `nix develop .#haskell`
# when GHC is not on PATH. base only, like the bandit package.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
if ! command -v runghc > /dev/null; then
  if [ -n "${ROOM_MESH_IN_SHELL:-}" ]; then echo "room-mesh: the shell has no GHC" >&2; exit 1; fi
  command -v nix > /dev/null || { echo "room-mesh: needs nix (or GHC on PATH)" >&2; exit 1; }
  exec env ROOM_MESH_IN_SHELL=1 nix develop --extra-experimental-features 'nix-command flakes' \
    --no-update-lock-file "$here/../..#haskell" --command bash "$0" "$@"
fi
exec runghc -Wall -Werror "$here/Main.hs"
