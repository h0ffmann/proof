#!/usr/bin/env bash
# The room's mesh against the triangle-grid size rules (tools/room-mesh/): its NOTE lines, and every
# lattice size and band ratio they print is the one triangle-grids/README.md quotes.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(tools/room-mesh/run.sh)
echo "$out"
readme=triangle-grids/README.md
missing=0
while read -r n; do
  grep -qF "$n" "$readme" || { echo "room-mesh: $readme does not quote $n" >&2; missing=1; }
done < <(grep -o 'lattice [0-9.]* km\|ratio [0-9.]*,' <<<"$out" | grep -o '[0-9][0-9.]*[0-9]')
[ "$missing" -eq 0 ]
echo "room-mesh: OK (the README quotes every lattice size and ratio)"
