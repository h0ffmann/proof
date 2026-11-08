#!/usr/bin/env python3
"""The logo: a neural network flowing into the universal quantifier.

The same drawing as h0ffmann/awesome-neurosymbolic-ai (`scripts/draw_banner.py`),
by the same author; this is that script, with its outputs next to this file.

The pen and the method follow pirsig's (`crates/pirsig-drawings`), through
piabrota/nix-os (`drawings/pen.nix`), ported here to Python: each stroke is a
list of hand-placed points with a brush width at each; a Catmull-Rom spline
runs through them; each piece is a cubic Bézier cut in four so the width
changes smoothly; and each quarter is one Desmos parametric expression,
``(a+bt+ct^2+dt^3, e+ft+gt^2+ht^3)`` for ``0 <= t <= 1``.

One geometry, two outputs, one check:

    python3 docs/logo/logo.py          # writes docs/logo/logo.svg + docs/logo/logo.desmos.json
    python3 docs/logo/logo.py --check  # fails if the committed files are not the
                                           # output of this script, or if any Desmos
                                           # expression strays >0.01 from its line

The look is picasso's: one ink, #1f2328 on light pages and #e6edf3 on dark
ones (prefers-color-scheme), round ends, nothing else.

Stdlib only; no dependencies.
"""

from __future__ import annotations

import json
import math
import re
import sys
from pathlib import Path

W, H = 960.0, 240.0
INK_LIGHT, INK_DARK = "#1f2328", "#e6edf3"
HERE = Path(__file__).resolve().parent
SVG_PATH = HERE / "logo.svg"
JSON_PATH = HERE / "logo.desmos.json"

Pt = tuple[float, float]
Bezier = tuple[Pt, Pt, Pt, Pt]


# ----------------------------------------------------------------------------
# Pen: Catmull-Rom -> cubic Béziers -> quarters with smooth width
# ----------------------------------------------------------------------------

def catmull_rom(points: list[Pt]) -> list[Bezier]:
    """Uniform Catmull-Rom through all points, as cubic Béziers."""
    if len(points) < 2:
        raise ValueError("a stroke needs at least two points")
    ext = [points[0], *points, points[-1]]
    out: list[Bezier] = []
    for p0, p1, p2, p3 in zip(ext, ext[1:], ext[2:], ext[3:]):
        c1 = (p1[0] + (p2[0] - p0[0]) / 6.0, p1[1] + (p2[1] - p0[1]) / 6.0)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6.0, p2[1] - (p3[1] - p1[1]) / 6.0)
        out.append((p1, c1, c2, p2))
    return out


def _lerp(a: Pt, b: Pt, t: float) -> Pt:
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def split(b: Bezier, t: float) -> tuple[Bezier, Bezier]:
    """De Casteljau split of a cubic Bézier at t."""
    p0, p1, p2, p3 = b
    q0, q1, q2 = _lerp(p0, p1, t), _lerp(p1, p2, t), _lerp(p2, p3, t)
    r0, r1 = _lerp(q0, q1, t), _lerp(q1, q2, t)
    s = _lerp(r0, r1, t)
    return (p0, q0, r0, s), (s, r1, q2, p3)


def quarters(b: Bezier) -> list[Bezier]:
    a, rest = split(b, 0.25)
    c, rest = split(rest, 1.0 / 3.0)
    d, e = split(rest, 0.5)
    return [a, c, d, e]


def coeffs(b: Bezier) -> tuple[tuple[float, float, float, float], tuple[float, float, float, float]]:
    """Power-basis coefficients (a, b, c, d) per axis for p(t), 0 <= t <= 1."""
    p0, p1, p2, p3 = b

    def axis(i: int) -> tuple[float, float, float, float]:
        return (
            p0[i],
            3.0 * (p1[i] - p0[i]),
            3.0 * (p2[i] - 2.0 * p1[i] + p0[i]),
            p3[i] - 3.0 * p2[i] + 3.0 * p1[i] - p0[i],
        )

    return axis(0), axis(1)


def stroke(points_w: list[tuple[float, float, float]]) -> list[tuple[Bezier, float]]:
    """A brushed stroke: Catmull-Rom pieces cut in four, each with its width."""
    pts = [(x, y) for x, y, _ in points_w]
    widths = [w for _, _, w in points_w]
    pieces: list[tuple[Bezier, float]] = []
    for i, b in enumerate(catmull_rom(pts)):
        w1, w2 = widths[i], widths[i + 1]
        for j, q in enumerate(quarters(b)):
            pieces.append((q, w1 + (w2 - w1) * (j + 0.5) / 4.0))
    return pieces


def ring(cx: float, cy: float, r: float, w: float) -> list[tuple[Bezier, float]]:
    """A circle as four Béziers (kappa approximation), constant width."""
    k = 0.5522847498307936 * r
    quads = [
        ((cx + r, cy), (cx + r, cy + k), (cx + k, cy + r), (cx, cy + r)),
        ((cx, cy + r), (cx - k, cy + r), (cx - r, cy + k), (cx - r, cy)),
        ((cx - r, cy), (cx - r, cy - k), (cx - k, cy - r), (cx, cy - r)),
        ((cx, cy - r), (cx + k, cy - r), (cx + r, cy - k), (cx + r, cy)),
    ]
    return [(q, w) for q in quads]


# ----------------------------------------------------------------------------
# The drawing: a 3-4-3 network, three sweeps, and the universal quantifier
# ----------------------------------------------------------------------------

L1 = [(90.0, 70.0), (90.0, 120.0), (90.0, 170.0)]
L2 = [(205.0, 52.0), (205.0, 97.0), (205.0, 143.0), (205.0, 188.0)]
L3 = [(320.0, 70.0), (320.0, 120.0), (320.0, 170.0)]
R = 9.0


def edge(a: Pt, b: Pt) -> list[tuple[float, float, float]]:
    """A thin synapse between two nodes, bowing gently with its slope."""
    x1, y1 = a[0] + R + 4.0, a[1]
    x2, y2 = b[0] - R - 4.0, b[1]
    bow = (y2 - y1) * 0.07
    return [(x1, y1, 0.9), ((x1 + x2) / 2.0, (y1 + y2) / 2.0 + bow, 1.7), (x2, y2, 0.9)]


def drawing() -> list[tuple[Bezier, float]]:
    pieces: list[tuple[Bezier, float]] = []

    # Synapses first, so the rings ink over them at the joins.
    for a in L1:
        for b in L2:
            pieces += stroke(edge(a, b))
    for a in L2:
        for b in L3:
            pieces += stroke(edge(a, b))

    # Neurons.
    for cx, cy in [*L1, *L2, *L3]:
        pieces += ring(cx, cy, R, 3.0)

    # Three sweeps out of the network. The outer two braid across the middle
    # and lift off the page; the middle one runs on and becomes the crossbar
    # of the quantifier — the network writes the symbol.
    sx = L3[0][0] + R + 4.0
    pieces += stroke([
        (sx, 70.0, 1.1), (440.0, 86.0, 1.9), (525.0, 134.0, 2.4),
        (620.0, 112.0, 1.6), (688.0, 109.0, 0.7),
    ])
    pieces += stroke([
        (sx, 170.0, 1.1), (475.0, 156.0, 1.9), (585.0, 110.0, 2.4),
        (655.0, 132.0, 1.6), (696.0, 140.0, 0.7),
    ])
    pieces += stroke([
        (sx, 120.0, 1.1), (450.0, 123.5, 1.7), (555.0, 121.0, 2.2),
        (640.0, 125.0, 2.9), (700.0, 125.8, 3.6), (734.0, 126.5, 4.4),
        (771.0, 126.0, 5.2), (808.0, 127.0, 3.4),
    ])

    # The universal quantifier, brushed in two strokes; its bar is the sweep above.
    pieces += stroke([(690.0, 52.0, 3.8), (731.0, 124.0, 7.0), (772.0, 194.0, 3.2)])
    pieces += stroke([(854.0, 52.0, 3.8), (813.0, 124.0, 7.0), (772.0, 194.0, 3.2)])

    return pieces


# ----------------------------------------------------------------------------
# Outputs
# ----------------------------------------------------------------------------

def fmt(v: float) -> str:
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def fmt3(v: float) -> str:
    s = f"{v:+.3f}"
    return "+0.000" if s == "-0.000" else s


def to_svg(pieces: list[tuple[Bezier, float]], ink: str | None = None) -> str:
    """The SVG. With no ink, one ink per color scheme; with one, that ink only."""
    alt = "A neural network flowing into the universal quantifier"
    if ink is None:
        style = (
            "path{stroke:" + INK_LIGHT + ";fill:none;stroke-linecap:round}"
            "@media (prefers-color-scheme:dark){path{stroke:" + INK_DARK + "}}"
        )
    else:
        style = "path{stroke:" + ink + ";fill:none;stroke-linecap:round}"
    head = (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {fmt(W)} {fmt(H)}" '
        f'width="{fmt(W)}" height="{fmt(H)}" role="img" aria-label="{alt}">\n'
        f"<style>{style}</style>\n"
    )
    body = []
    for (p0, p1, p2, p3), w in pieces:
        d = (
            f"M {fmt(p0[0])} {fmt(p0[1])} C {fmt(p1[0])} {fmt(p1[1])} "
            f"{fmt(p2[0])} {fmt(p2[1])} {fmt(p3[0])} {fmt(p3[1])}"
        )
        body.append(f'<path d="{d}" stroke-width="{fmt(w)}"/>')
    return head + "\n".join(body) + "\n</svg>\n"


def latex(b: Bezier) -> str:
    """One quarter as one Desmos parametric expression, y up."""
    (xa, xb, xc, xd), (ya, yb, yc, yd) = coeffs(b)
    ya, yb, yc, yd = H - ya, -yb, -yc, -yd  # Desmos uses y up
    x = f"{xa:.3f}{fmt3(xb)}t{fmt3(xc)}t^{{2}}{fmt3(xd)}t^{{3}}"
    y = f"{ya:.3f}{fmt3(yb)}t{fmt3(yc)}t^{{2}}{fmt3(yd)}t^{{3}}"
    return f"\\left({x},{y}\\right)"


def to_desmos(pieces: list[tuple[Bezier, float]]) -> str:
    exprs = [
        {
            "type": "expression",
            "id": str(i + 1),
            "color": INK_LIGHT,
            "latex": latex(b),
            "parametricDomain": {"min": "0", "max": "1"},
            "domain": {"min": "0", "max": "1"},
        }
        for i, (b, _) in enumerate(pieces)
    ]
    state = {
        "version": 11,
        "graph": {"viewport": {"xmin": -20, "xmax": W + 20, "ymin": -20, "ymax": H + 20}},
        "expressions": {"list": exprs},
    }
    return json.dumps(state, indent=1) + "\n"


# ----------------------------------------------------------------------------
# Check: committed files are this script's output; every expression holds its line
# ----------------------------------------------------------------------------

LATEX_RE = re.compile(
    r"\\left\((?P<xa>-?[\d.]+)(?P<xb>[+-][\d.]+)t(?P<xc>[+-][\d.]+)t\^\{2\}(?P<xd>[+-][\d.]+)t\^\{3\},"
    r"(?P<ya>-?[\d.]+)(?P<yb>[+-][\d.]+)t(?P<yc>[+-][\d.]+)t\^\{2\}(?P<yd>[+-][\d.]+)t\^\{3\}\\right\)"
)


def check(pieces: list[tuple[Bezier, float]]) -> int:
    bad = 0
    for name, path, want in ((
        "svg", SVG_PATH, to_svg(pieces)), ("desmos", JSON_PATH, to_desmos(pieces)),
    ):
        if not path.exists() or path.read_text(encoding="utf-8") != want:
            print(f"check: {path} is not the output of docs/logo/logo.py — rerun it.")
            bad += 1

    # Read the expressions back from their LaTeX and hold them to the geometry.
    worst = 0.0
    state = json.loads(JSON_PATH.read_text(encoding="utf-8")) if JSON_PATH.exists() else {}
    exprs = state.get("expressions", {}).get("list", [])
    if len(exprs) != len(pieces):
        print(f"check: {len(exprs)} expressions vs {len(pieces)} pieces.")
        return bad + 1
    for e, (b, _) in zip(exprs, pieces):
        m = LATEX_RE.fullmatch(e["latex"])
        if not m:
            print(f"check: unparseable latex in expression {e['id']}")
            bad += 1
            continue
        g = {k: float(v) for k, v in m.groupdict().items()}
        (xa, xb, xc, xd), (ya, yb, yc, yd) = coeffs(b)
        for t in (0.0, 0.25, 0.5, 0.75, 1.0):
            ex = g["xa"] + g["xb"] * t + g["xc"] * t * t + g["xd"] * t ** 3
            ey = g["ya"] + g["yb"] * t + g["yc"] * t * t + g["yd"] * t ** 3
            gx = xa + xb * t + xc * t * t + xd * t ** 3
            gy = H - (ya + yb * t + yc * t * t + yd * t ** 3)
            worst = max(worst, abs(ex - gx), abs(ey - gy))
    if worst > 0.01:
        print(f"check: a Desmos expression strays {worst:.4f} from its line (limit 0.01).")
        bad += 1
    if not bad:
        print(f"check: OK — {len(pieces)} pieces, worst expression deviation {worst:.4f}.")
    return bad


def main() -> int:
    pieces = drawing()
    if "--check" in sys.argv:
        return check(pieces)
    SVG_PATH.write_text(to_svg(pieces), encoding="utf-8")
    JSON_PATH.write_text(to_desmos(pieces), encoding="utf-8")
    print(f"wrote {SVG_PATH.name} and {JSON_PATH.name} — {len(pieces)} pieces.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
