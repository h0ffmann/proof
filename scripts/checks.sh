#!/usr/bin/env bash
# Run checks/<feature>.sh for every feature, or only for the features named. Nothing lists the
# checks, so two pull requests that each add one never edit the same file (AGENTS.md).
#
#   scripts/checks.sh                 # every check
#   scripts/checks.sh port-audit loc  # checks/port-audit.sh and checks/loc.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -gt 0 ]; then
  files=()
  for name in "$@"; do files+=("checks/$name.sh"); done
else
  shopt -s nullglob
  files=(checks/*.sh)
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "checks: no checks/*.sh yet"
  exit 0
fi

failed=()
for f in "${files[@]}"; do
  [ -f "$f" ] || { echo "checks: no file $f" >&2; exit 1; }
  echo "== $f"
  bash "$f" || failed+=("$f")
done

echo
if [ "${#failed[@]}" -gt 0 ]; then
  echo "checks: ${#failed[@]} of ${#files[@]} failed: ${failed[*]}" >&2
  exit 1
fi
echo "checks: all ${#files[@]} passed"
