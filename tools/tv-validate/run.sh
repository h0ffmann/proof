#!/usr/bin/env bash
# Run the validation pipeline of tv-audience/, from anywhere in the repository:
#
#   tools/tv-validate/run.sh               # the experiment, then every property and every line
#   tools/tv-validate/run.sh --self-test   # changes to the run that one line each must catch
#   tools/tv-validate/run.sh -- -p metrics # one group (a Tasty pattern)
#
# Step 1 runs tv-audience/python/experiment.py as it is (export.py) and keeps its forecasts and
# fitted weights in build/run; it runs again when a Python source is newer. Step 2 builds the
# cabal package offline. Step 3 runs it. GHC, the Hackage libraries, cabal-install and Python come
# from `nix develop .#tv-validate` (nix/tv-validate.nix); the script enters that shell by itself.
#
# TV_VALIDATE_RUN=DIR checks a folder that export.py wrote somewhere else, for example with the
# XGBoost release of tv-audience/results.json (README.md, "The committed numbers").
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here/../.."

if [ -z "${TV_VALIDATE_IN_SHELL:-}" ]; then
  command -v nix > /dev/null || { echo "tv-validate: needs nix" >&2; exit 1; }
  exec env TV_VALIDATE_IN_SHELL=1 nix develop --extra-experimental-features 'nix-command flakes' \
    --no-update-lock-file .#tv-validate --command bash "$0" "$@"
fi
export LANG=C.UTF-8 LC_ALL=C.UTF-8
# cabal keeps its own files in build/, not in the home folder.
export CABAL_DIR="$here/build/cabal"
mkdir -p "$here/build"

run="${TV_VALIDATE_RUN:-$here/build/run}"
if [ -z "${TV_VALIDATE_RUN:-}" ]; then
  fresh=1
  [ -f "$run/bootstrap.csv" ] || fresh=0
  for s in tv-audience/python/*.py "$here/export.py"; do [ "$s" -nt "$run/bootstrap.csv" ] && fresh=0; done
  if [ "$fresh" -eq 0 ]; then
    rm -rf "$run.tmp"
    python3 -I "$here/export.py" "$run.tmp" > "$here/build/export.log" 2>&1 \
      || { cat "$here/build/export.log" >&2; exit 2; }
    rm -rf "$run"
    mv "$run.tmp" "$run"
  fi
fi

cabal=(cabal --offline --builddir="$here/build/dist" --project-dir="$here")
"${cabal[@]}" build -v0 --ghc-options=-Werror exe:tv-validate > "$here/build/cabal.log" 2>&1 \
  || { cat "$here/build/cabal.log" >&2; exit 2; }
exec "$("${cabal[@]}" list-bin -v0 exe:tv-validate)" --run "$run" --committed tv-audience/results.json "$@"
