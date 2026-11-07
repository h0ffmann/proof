# The logo

![proof](proof.svg)

Two signs from logic, drawn as pen strokes.

- **⊢**, the turnstile: "proves". A vertical and a horizontal stroke, each slightly bowed by a sine
  so it reads as drawn, not typeset.
- **∎**, the tombstone (Halmos's end-of-proof mark), filled by 16 hatch lines at heights
  $y_k = 1 - r^k$ with $r = 2^{-1/2}$. Every two lines close half of the gap that is left, so the
  box is full only in the limit, the way an induction finishes. Each line is
  $y(x) = y_k + a_k \sin(2\pi f x + \varphi_k)$: its width is 0.6 of the gap above it and its
  wobble $a_k$ shrinks with that gap. The bottom lines are waves; the top ones are flat.

Read together: *it proves, and it is done*. The waves are a nod to `ocean-waves/`.

`python3 docs/logo/logo.py` writes [`proof.svg`](proof.svg) again. The SVG changes its colours for
dark mode with `prefers-color-scheme`.
