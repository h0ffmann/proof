"""Shared look of the takes: colours, the TeX template, the words on screen, and the length of each take.

The style is the script's (prose-pt-BR/00-como-ler.md, "Estilo"): a dark background, one idea per
screen, objects that transform instead of cuts. Blue is what the model believes, yellow is the
selection, red is the regret. The words on screen are Brazilian Portuguese, so they live in
`labels.pt-BR.toml`, not here (AGENTS.md, "Language").
"""

from __future__ import annotations

import tomllib
from pathlib import Path

from manim import (
    DOWN, LEFT, RIGHT, UP, UL, UR, DL, DR, ORIGIN,
    BLUE, BLUE_C, BLUE_E, GREY_B, GREY_D, RED, RED_C, WHITE, YELLOW, YELLOW_C, GREEN_C,
    Arrow, FadeIn, FadeOut, MathTex, Rectangle, Scene, Tex, TexTemplate, VGroup, Write,
)

HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent

BELIEF = BLUE_C      # what the model believes
CHOICE = YELLOW      # the selection
REGRET = RED_C       # the regret
MUTED = GREY_B       # sources, captions
TRUTH = GREEN_C      # a value the simulation knows and the agent does not (pi, the secret rates)

# Babel's `brazilian` and T1 fonts for the accents. Manim's own preamble loads babel for English,
# and two babel calls clash, so the preamble is written whole.
TEMPLATE = TexTemplate(
    preamble="\n".join([
        r"\usepackage[brazilian]{babel}",
        r"\usepackage[T1]{fontenc}",
        r"\usepackage{amsmath}",
        r"\usepackage{amssymb}",
        r"\newcommand{\q}[1]{``#1''}",  # a quotation; TOML literal strings cannot hold a '
    ])
)

from results import takes  # noqa: E402  (kept free of Manim, so the check can read it)

_LABELS = tomllib.loads((HERE / "labels.pt-BR.toml").read_text(encoding="utf-8"))


def label(key: str):
    """The words on screen for `key`, as `take.name` (for example `1.1.title`)."""
    node = _LABELS
    for part in key.split("."):
        node = node[part]
    return node


def T(key: str, size: float = 36, color=WHITE, **kwargs) -> Tex:
    """A `Tex` of the label `key`."""
    return Tex(label(key), tex_template=TEMPLATE, font_size=size, color=color, **kwargs)


def raw(tex: str, size: float = 36, color=WHITE, **kwargs) -> Tex:
    """A `Tex` of TeX that is not a word (a number, a code name)."""
    return Tex(tex, tex_template=TEMPLATE, font_size=size, color=color, **kwargs)


def M(tex: str, size: float = 36, color=WHITE, **kwargs) -> MathTex:
    return MathTex(tex, tex_template=TEMPLATE, font_size=size, color=color, **kwargs)


def code(name: str, size: float = 24, color=MUTED) -> Tex:
    """A name from the code, in typewriter, as the script's Code paragraph gives it."""
    return raw(r"\texttt{" + name.replace("_", r"\_") + "}", size=size, color=color)


def decimal(x: float, places: int = 2) -> str:
    """A number with a decimal comma, as Portuguese writes it (PTC-7)."""
    return f"{x:.{places}f}".replace(".", "{,}")


class Take(Scene):
    """A take of the video: `TAKE` names its scene in the script, and `fill` holds the last frame
    until the take is as long as the narration the script plans for it."""

    TAKE = ""  # each take sets it, as "N.M"

    def title(self, key: str | None = None) -> Tex:
        """The title of the take, in the upper left corner, written and kept."""
        t = T(key or f"t{self.TAKE.replace('.', '_')}.title", size=30, color=MUTED)
        t.to_corner(UL, buff=0.4)
        self.play(FadeIn(t, shift=0.2 * DOWN), run_time=0.8)
        return t

    def fill(self) -> None:
        target = takes()[self.TAKE]
        left = target - self.renderer.time
        if left > 0:
            self.wait(left)


def bar(value: float, height: float = 3.0, width: float = 0.8, color=BELIEF) -> Rectangle:
    """A bar of `value` in [0, 1], standing on its lower edge."""
    r = Rectangle(width=width, height=max(value * height, 1e-3), color=color,
                  fill_color=color, fill_opacity=0.75, stroke_width=2)
    return r


def choice_arrow(target, color=CHOICE) -> Arrow:
    """The yellow arrow of the selection, pointing down at `target`."""
    return Arrow(target.get_top() + 1.1 * UP, target.get_top() + 0.1 * UP, buff=0, color=color,
                 stroke_width=8, max_tip_length_to_length_ratio=0.35)


def box(width: float, height: float, color=WHITE) -> Rectangle:
    return Rectangle(width=width, height=height, color=color, stroke_width=3)


__all__ = [
    "BELIEF", "CHOICE", "REGRET", "MUTED", "TRUTH", "TEMPLATE", "Take", "T", "M", "raw", "code",
    "label", "decimal", "takes", "bar", "choice_arrow", "box",
]


def belief_bars(values, names, height: float = 3.0, spacing: float = 2.4, baseline: float = -1.6,
                color=BELIEF, places: int = 2, x: float = 0.0) -> VGroup:
    """Bars of `values` in [0, 1], side by side on one baseline, with each value above its bar and
    each name (TeX) below. The group has `.bars`, `.values` and `.names`, so a Transform to a second
    group moves each part to its new place."""
    n = len(values)
    bars, nums, tags = VGroup(), VGroup(), VGroup()
    for i, (v, name) in enumerate(zip(values, names)):
        cx = x + (i - (n - 1) / 2) * spacing
        b = bar(v, height=height, color=color)
        b.move_to([cx, baseline, 0], aligned_edge=DOWN)
        bars.add(b)
        nums.add(raw(decimal(v, places), size=32, color=color).next_to(b, UP, buff=0.15))
        tags.add(raw(name, size=28))
        tags[-1].next_to([cx, baseline, 0], DOWN, buff=0.25)
    g = VGroup(bars, nums, tags)
    g.bars, g.values, g.names = bars, nums, tags
    return g


def fmt_eps(text: str) -> str:
    """An epsilon as results.md prints it (`1.0e-2`), as the screen shows it (`0{,}01`)."""
    return f"{float(text):g}".replace(".", "{,}")


__all__ += ["belief_bars", "fmt_eps"]


def pick(g: VGroup, i: int) -> Arrow:
    """The arrow of the selection over bar `i` of a `belief_bars` group, above its value."""
    return choice_arrow(VGroup(g.bars[i], g.values[i]))


__all__ += ["pick"]


def axis_numbers(axis, values, places: int = 1, size: float = 20):
    """Numbers on an axis with a decimal comma (Manim's own numbers print a point)."""
    axis.add_labels({v: raw(decimal(v, places), size) for v in values})
    return axis


__all__ += ["axis_numbers"]
