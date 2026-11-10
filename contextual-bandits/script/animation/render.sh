#!/usr/bin/env bash
# Render the takes of the video, one Manim scene per take, into build/takes/take-N.M.mp4.
#
#   render.sh [-q l|m|h|k] [N.M ...]    every take, or only the ones named; -q h (1080p) by default
#
# Run it inside `nix develop .#manim` (`just takes` does). It calls `python3 -m manim`, not the
# `manim` program: nixpkgs wraps that program with a PATH that puts its own small TeX Live first,
# and that TeX Live has no babel-portuges, so the Portuguese words on screen fail to compile.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel)
quality=h
while getopts "q:" opt; do
  case $opt in
    q) quality=$OPTARG ;;
    *) echo "usage: render.sh [-q l|m|h|k] [N.M ...]" >&2; exit 64 ;;
  esac
done
shift $((OPTIND - 1))

case $quality in
  l) res=480p15 ;; m) res=720p30 ;; h) res=1080p60 ;; k) res=2160p60 ;;
  *) echo "render.sh: -q must be l, m, h or k" >&2; exit 64 ;;
esac
media="$root/build/manim"
out="$root/build/takes"
mkdir -p "$out"
cd "$here"
found=0
for f in *.py; do
  cls=$(sed -n 's/^class \(Take[0-9]*\)(Take):.*/\1/p' "$f")
  [ -n "$cls" ] || continue
  take=$(sed -n 's/^    TAKE = "\(.*\)"$/\1/p' "$f")
  if [ $# -gt 0 ] && ! printf '%s\n' "$@" | grep -qxF "$take"; then continue; fi
  found=$((found + 1))
  echo "== take $take ($f, $cls)"
  python3 -m manim -q"$quality" --progress_bar none --media_dir "$media" -o "take-$take" "$f" "$cls"
  cp "$media/videos/${f%.py}/$res/take-$take.mp4" "$out/take-$take.mp4"
done
[ "$found" -gt 0 ] || { echo "render.sh: no take matches: $*" >&2; exit 1; }
echo "render.sh: $found take(s) in $out"
