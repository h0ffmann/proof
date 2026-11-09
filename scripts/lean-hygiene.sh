#!/usr/bin/env bash
# lean-hygiene: the Lean proofs must be complete. AGENTS.md rule 1 says why.
#   - no `sorry` or `admit`: both close any goal without a proof
#   - no `axiom`: an axiom is a statement Lean accepts without a proof
#   - `native_decide` only in an `Examples.lean`: it trusts the compiler, not the kernel
# It checks every tracked .lean file outside vendor/, so a new Lean project is covered
# without editing this script.
#
#   scripts/lean-hygiene.sh              # exit 1 and print each offending line
#   scripts/lean-hygiene.sh --self-test  # the checks must catch a bad file
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

check() {
  local status=0 files examples others
  files=$(cat)
  [ -n "$files" ] || { echo "lean-hygiene: no .lean files found" >&2; return 1; }
  others=$(grep -v '/Examples\.lean$' <<<"$files" || true)

  if xargs grep -nHwE 'sorry|admit' <<<"$files"; then
    echo "lean-hygiene: found sorry or admit (an unfinished proof)" >&2; status=1
  fi
  # An axiom can be indented or carry modifiers, so `^axiom` is not enough.
  if xargs grep -nHE '^[[:space:]]*((private|protected|noncomputable|unsafe|@\[[^]]*\])[[:space:]]+)*axiom([[:space:]]|$)' <<<"$files"; then
    echo "lean-hygiene: found an axiom (a statement accepted without proof)" >&2; status=1
  fi
  if [ -n "$others" ] && xargs grep -nHw 'native_decide' <<<"$others"; then
    echo "lean-hygiene: native_decide is allowed only in Examples.lean" >&2; status=1
  fi
  return $status
}

self_test() {
  local d; d="$(mktemp -d)"; trap 'rm -rf "$d"' RETURN
  fail() { echo "lean-hygiene: self-test: $1" >&2; exit 1; }
  printf 'theorem t : 1 = 1 := by\n  sorry\n' > "$d/Sorry.lean"
  printf 'namespace X\n  private axiom bad : False\nend X\n' > "$d/Axiom.lean"
  printf 'theorem t : 2 = 2 := by native_decide\n' > "$d/Theorems.lean"
  printf 'theorem t : 2 = 2 := by native_decide\n' > "$d/Examples.lean"
  printf 'theorem sorryless : 1 = 1 := rfl\n' > "$d/Clean.lean"
  for f in Sorry Axiom Theorems; do
    ! echo "$d/$f.lean" | check >/dev/null 2>&1 || fail "passed $f.lean"
  done
  printf '%s\n' "$d/Examples.lean" "$d/Clean.lean" | check >/dev/null || fail "refused a clean file"
  echo "lean-hygiene: self-test passed"
}

case "${1:-}" in
  --self-test) self_test ;;
  "") git ls-files '*.lean' | grep -v '^vendor/' | check && echo "lean-hygiene: ok" ;;
  *) echo "usage: $0 [--self-test]" >&2; exit 2 ;;
esac
