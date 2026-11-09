# Animations

Python only draws. The code of the video is Haskell (`haskell/src/Video.hs`, `haskell/src/Pi.hs`,
`haskell/app/Video.hs`) and the specification is Z3 (`z3-scala/src/main/scala/bandit/domain/Video.scala`). This
folder holds the Manim scenes, one per take, made after the script is approved:

- `timeline.py`: scene 1.2, *steal like an artist*.

Render a take inside `nix develop .#manim` (Manim, ffmpeg and LaTeX, pinned by `flake.lock`):
`manim -qh papers/contextual-bandits/script/animation/<take>.py <Scene>`.

The numbers the animations show come from [`../results.md`](../results.md),
written by `cabal run video`.
