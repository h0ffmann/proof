#!/usr/bin/env bash
# The prose checks in Agda (`just prose`, tools/prose-check/): the cases of Prose.Examples through
# the compiled program, the ASD-STE100 rules on every Markdown file that names ASD-STE100 as its
# writing standard, and the PTC rules on the video script. The rules and verdicts are --safe
# Agda in agda/src/Prose/; tools/prose-check/Main.agda only reads files and prints, so it may hold
# no postulate, no pragma and no foreign code.
set -euo pipefail
cd "$(dirname "$0")/.."

main=tools/prose-check/Main.agda
if grep -nE 'postulate|\{-#[[:space:]]*(COMPILE|FOREIGN|TERMINATING|NON_TERMINATING|BUILTIN)' "$main"; then
  echo "prose-check: $main may only do input and output" >&2; exit 1
fi

run=tools/prose-check/run.sh
$run self-test
mapfile -t ste < <(git grep -l -F 'Writing standard: ASD-STE100' -- '*.md')
[ "${#ste[@]}" -gt 0 ] || { echo "prose-check: no file names ASD-STE100 as its writing standard" >&2; exit 1; }
$run ste "${ste[@]}"
$run ptc contextual-bandits/script/prose-pt-BR/*.md
