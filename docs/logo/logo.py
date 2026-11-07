"""Draw docs/logo/proof.svg: a turnstile and a tombstone, from equations.

    ⊢   "proves": a vertical stroke and a horizontal stroke.
    ∎   the end of a proof (Halmos's tombstone), filled by hatch lines at
        y_k = 1 - 2^-k, k = 0..11: every line closes half of the gap that is
        left, so the box is full only in the limit. Each line is a pen stroke,
        y(x) = y_k + a sin(2 pi f x + phi_k), with a small wobble that also
        halves as k grows.

Run `python3 docs/logo/logo.py`; it writes proof.svg next to this file.
"""

from math import pi, sin
from pathlib import Path

VX, VY, W, H = 24, 30, 216, 140  # the drawing's bounding box, with a margin
INK_LIGHT, INK_DARK = "#1b3a5c", "#e6eef7"
ACCENT_LIGHT, ACCENT_DARK = "#2a78d6", "#5ea3f0"


def stroke(points, width, cls):
    d = "M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in points)
    return f'<path class="{cls}" d="{d}" stroke-width="{width:.2f}"/>'


def pen_line(x0, x1, y, amp, phase, n=60):
    return [(x0 + (x1 - x0) * i / n, y + amp * sin(2 * pi * 1.5 * i / n + phase)) for i in range(n + 1)]


def main():
    parts = []
    # Turnstile, slightly bowed so it reads as drawn, not typeset.
    parts.append(stroke([(52 + 1.5 * sin(pi * t / 40), 52 + 2.4 * t) for t in range(41)], 11, "ink"))
    parts.append(stroke([(52 + 1.35 * t, 100 + 1.2 * sin(pi * t / 40)) for t in range(41)], 11, "ink"))
    # Tombstone: outline, then the hatch lines that converge on its top edge.
    x0, x1, top, bottom = 136, 216, 60, 140
    side = bottom - top
    parts.append(f'<rect class="box" x="{x0}" y="{top}" width="{x1 - x0}" height="{side}" rx="3" stroke-width="5"/>')
    r = 2 ** -0.5
    inner = side - 14  # the hatching lives inside the outline's stroke
    for k in range(16):
        y = bottom - 7 - inner * (1 - r ** k)
        gap = inner * r ** k * (1 - r)
        parts.append(stroke(pen_line(x0 + 9, x1 - 9, y, 0.18 * gap, 0.9 * k), max(0.5, 0.6 * gap), "accent"))
    style = f"""<style>
  .ink {{ fill: none; stroke: {INK_LIGHT}; stroke-linecap: round; stroke-linejoin: round; }}
  .accent {{ fill: none; stroke: {ACCENT_LIGHT}; stroke-linecap: round; }}
  .box {{ fill: none; stroke: {INK_LIGHT}; }}
  @media (prefers-color-scheme: dark) {{
    .ink, .box {{ stroke: {INK_DARK}; }}
    .accent {{ stroke: {ACCENT_DARK}; }}
  }}
</style>"""
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{VX} {VY} {W} {H}" width="{W}" height="{H}" '
           f'role="img" aria-label="proof: a turnstile and a tombstone filled by halving lines">\n'
           f"<title>proof</title>\n{style}\n" + "\n".join(parts) + "\n</svg>\n")
    out = Path(__file__).with_name("proof.svg")
    out.write_text(svg)
    print(out)


if __name__ == "__main__":
    main()
