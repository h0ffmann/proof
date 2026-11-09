#!/usr/bin/env bash
# The roteiro-preview skill (.claude/skills/roteiro-preview/): parse the example script, check the
# timeline and the subtitles, and render a 5-second preview when ffmpeg and Pillow are present.
set -euo pipefail
cd "$(dirname "$0")/.."
skill=.claude/skills/roteiro-preview
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

python3 "$skill/preview.py" "$skill/example.md" --dry-run --out "$out" > /dev/null
grep -q '| 0:00–0:08 | 0:00–0:08 | 1.1 | Abertura |' "$out/shots.md"
grep -q '| 1.2 | Sem horário |' "$out/shots.md"
grep -q '^Esta é uma cena de teste\.$' "$out/preview.srt"
if grep -q '@exemplo2026' "$out/preview.srt"; then echo "roteiro-preview: citation read aloud" >&2; exit 1; fi

if command -v ffmpeg > /dev/null && python3 -c 'import PIL' 2> /dev/null; then
  python3 "$skill/preview.py" "$skill/example.md" --length 0:05 --size 640x360 --tts none --out "$out" > /dev/null
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out/preview.mp4")
  python3 -c "import sys; d=float('$dur'); sys.exit(0 if abs(d - 5) < 0.2 else 1)" \
    || { echo "roteiro-preview: preview lasts $dur s, not 5 s" >&2; exit 1; }
else
  echo "roteiro-preview: no ffmpeg or Pillow, render step skipped"
fi
echo "roteiro-preview: OK"
