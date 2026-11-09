#!/usr/bin/env bash
# LiquidHaskell on the Haskell port (`just liquid`): the refinement types in haskell/src hold.
# haskell/LIQUIDHASKELL.md lists what is proved and what is trusted. Outside the shell it enters
# `nix develop .#liquidhaskell` (nix/liquidhaskell.nix: GHC, the plugin, Z3).
#
#   checks/liquidhaskell.sh              # check the modules
#   checks/liquidhaskell.sh --self-test  # also: a broken refinement must fail
set -euo pipefail
cd "$(dirname "$0")/.."

# Rational has no SMT sort in LiquidHaskell, so Video.hs and Pi.hs stay out (LIQUIDHASKELL.md).
modules=(ContextualBandit Models)
doc=haskell/LIQUIDHASKELL.md

if ! ghc-pkg latest liquidhaskell >/dev/null 2>&1 || ! command -v z3 >/dev/null; then
  if [ -n "${LIQUID_IN_SHELL:-}" ]; then
    echo "liquidhaskell: the shell has no LiquidHaskell or no Z3" >&2; exit 1
  fi
  command -v nix >/dev/null || {
    echo "liquidhaskell: needs nix (or ghc with the liquidhaskell package, and z3, on PATH)" >&2; exit 1; }
  exec env LIQUID_IN_SHELL=1 nix develop --extra-experimental-features 'nix-command flakes' \
    --no-update-lock-file .#liquidhaskell --command bash "$0" "$@"
fi
export LANG=C.UTF-8 LC_ALL=C.UTF-8

# Run the plugin on a copy of the modules (it writes .liquid/ beside each source).
# $1: the directory of the sources. Prints the plugin's output with repository paths.
liquid() {
  local src=$1 work
  work=$(mktemp -d)
  for m in "${modules[@]}"; do cp "$src/$m.hs" "$work/"; done
  (cd "$work" && ghc -fplugin=LiquidHaskell -fforce-recomp -no-link -outputdir out \
      "${modules[@]/%/.hs}" 2>&1) | sed "s|$work/|haskell/src/|g"
  rm -rf "$work"
}

# Every module SAFE, and no "Found false": a context that is false proves any refinement in it.
verdict() {
  local out=$1 safe
  safe=$(grep -c 'LIQUID: SAFE' <<<"$out" || true)
  if grep -q 'LIQUID: UNSAFE\|LIQUID: ERROR' <<<"$out" || [ "$safe" -ne "${#modules[@]}" ]; then
    return 1
  fi
  if grep -q 'Found false' <<<"$out"; then
    grep 'Found false' <<<"$out" >&2; return 1
  fi
}

# Each trusted name (ignore, assume, lazy) appears in LIQUIDHASKELL.md, so none goes unread.
trusted() {
  local missing=0 name files=()
  for m in "${modules[@]}"; do files+=("haskell/src/$m.hs"); done
  while read -r name; do
    grep -qF "\`$name\`" "$doc" || { echo "liquidhaskell: $name is trusted but not in $doc" >&2; missing=1; }
  done < <(sed -n 's/.*{-@ *\(ignore\|assume\|lazy\) \+\([^ ]*\).*/\2/p' "${files[@]}" | sort -u)
  return $missing
}

if [ "${1:-}" = "--self-test" ]; then
  # argmax returns an index past the end: the refinement {v:Nat | v < len xs} must catch it.
  broken=$(mktemp -d)
  for m in "${modules[@]}"; do cp "haskell/src/$m.hs" "$broken/"; done
  sed -i.bak 's/^    go best _ _ \[\] = best$/    go _ _ i [] = i/' "$broken/ContextualBandit.hs"
  if cmp -s "$broken/ContextualBandit.hs" "haskell/src/ContextualBandit.hs"; then
    echo "liquidhaskell: self-test: the mutation did not apply" >&2; exit 1
  fi
  if verdict "$(liquid "$broken")"; then
    echo "liquidhaskell: self-test: a wrong argmax passed" >&2; rm -rf "$broken"; exit 1
  fi
  rm -rf "$broken"
  echo "liquidhaskell: self-test OK (a wrong argmax fails)"
fi

out=$(liquid haskell/src)
if ! verdict "$out"; then
  echo "$out" >&2
  echo "liquidhaskell: FAIL" >&2
  exit 1
fi
trusted
grep 'LIQUID: SAFE' <<<"$out" | sed 's/\x1b\[[0-9;]*m//g; s/\*//g; s/ *$//'
echo "liquidhaskell: OK (${modules[*]})"
