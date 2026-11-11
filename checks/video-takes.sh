#!/usr/bin/env bash
# The Manim takes of the video script (contextual-bandits/script/animation/): every take of the
# script has one scene, every label a scene names exists, and every number the takes draw is still in
# results.md. Needs Python 3.11 or later and no Manim; the render itself is `just takes`.
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHONDONTWRITEBYTECODE=1 python3 contextual-bandits/script/animation/coverage.py
