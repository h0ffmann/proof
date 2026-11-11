#!/usr/bin/env bash
# Agda on the contextual bandit (`just agda`): every module of agda/ type-checks, so every
# theorem in it is proved. Outside the shell it enters `nix develop .#agda` (nix/agda.nix:
# Agda and its standard library).
#
# A proof is complete when Agda accepts it under --safe: --safe refuses postulate, the
# TERMINATING and NON_TERMINATING pragmas, and every other way to accept a statement without a
# proof. So every tracked .agda file must start with an OPTIONS line that names --safe.
#
#   checks/agda.sh              # the hygiene rule, then type-check agda/
#   checks/agda.sh --self-test  # also: a wrong example and a postulate must fail
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v agda >/dev/null; then
  if [ -n "${AGDA_IN_SHELL:-}" ]; then
    echo "agda: the shell has no agda" >&2; exit 1
  fi
  command -v nix >/dev/null || {
    echo "agda: needs nix (or agda with its standard library on PATH)" >&2; exit 1; }
  exec env AGDA_IN_SHELL=1 nix develop --extra-experimental-features 'nix-command flakes' \
    --no-update-lock-file .#agda --command bash "$0" "$@"
fi
export LANG=C.UTF-8 LC_ALL=C.UTF-8

# Type-check the library at $1 (a copy of agda/ or agda/ itself).
typecheck() {
  (cd "$1/src" && agda ContextualBandit.agda)
}

# Every .agda file under $1 starts with {-# OPTIONS --safe ... #-}.
hygiene() {
  local bad=0 f
  while IFS= read -r f; do
    head -n 1 "$f" | grep -q '^{-# OPTIONS .*--safe' || {
      echo "agda: $f does not start with {-# OPTIONS --safe ... #-}" >&2; bad=1; }
  done < <(find "$1" -name '*.agda' -not -path '*/_build/*' | sort)
  return $bad
}

if [ "${1:-}" = "--self-test" ]; then
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  # A wrong number in an example: refl must fail.
  cp -r agda "$work/wrong"; rm -rf "$work/wrong/_build"
  sed -i.bak 's|+ 14 / 15|+ 13 / 15|' "$work/wrong/src/ContextualBandit/Examples.agda"
  if cmp -s "$work/wrong/src/ContextualBandit/Examples.agda" agda/src/ContextualBandit/Examples.agda; then
    echo "agda: self-test: the mutation did not apply" >&2; exit 1
  fi
  if typecheck "$work/wrong" >/dev/null 2>&1; then
    echo "agda: self-test: a wrong example passed" >&2; exit 1
  fi
  # A postulate that proves the false example: --safe must refuse it.
  cp -r agda "$work/postulate"; rm -rf "$work/postulate/_build"
  cat >> "$work/postulate/src/ContextualBandit/Examples.agda" <<'AGDA'

postulate
  cheat : show3 (policy (tabular 3) greedy history morning) ≡ 1ℚ ∷ 1ℚ ∷ 1ℚ ∷ []
AGDA
  if typecheck "$work/postulate" >/dev/null 2>&1; then
    echo "agda: self-test: a postulate passed" >&2; exit 1
  fi
  # A file without --safe: the hygiene rule must catch it.
  printf 'module NoSafe where\n' > "$work/postulate/src/NoSafe.agda"
  if hygiene "$work/postulate" 2>/dev/null; then
    echo "agda: self-test: a file without --safe passed" >&2; exit 1
  fi
  echo "agda: self-test OK (a wrong example, a postulate and a file without --safe fail)"
fi

hygiene agda
typecheck agda
echo "agda: OK ($(agda --version | head -n 1), $(find agda/src -name '*.agda' | wc -l) modules)"
