"""Take 2.3, the cost of the wait (prose-pt-BR/02-teste-ab.md): the cumulative regret of four
policies over T customers. Where each curve ends is `abVsBandit` in results.md (mean of 20 seeds);
its shape is a sketch, and the screen says so. The sketch follows what each rule does: the A/B test
pays during the draw and almost nothing after the switch at T/2 (the A/B test without context pays
the same draw, then keeps paying for the context it ignores); epsilon-greedy pays at a constant rate
(T e g, desmos/2-3-regret.txt); UCB pays less and less as its widths shrink.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manim import *  # noqa: E402,F403
from common import *  # noqa: E402,F403
import results  # noqa: E402

KEYS = ["A/B test (T/2, then commit)", "A/B without context (T/2, then commit)", "epsilon-greedy 0.1",
        "UCB beta = 2"]
COLORS = [REGRET, ORANGE, CHOICE, BELIEF]


def shapes(r: dict) -> list:
    T_, ab, ab0, eps, ucb = r["T"], r[KEYS[0]], r[KEYS[1]], r[KEYS[2]], r[KEYS[3]]
    half = T_ / 2
    return [
        lambda t: ab * min(t, half) / half,
        lambda t: ab * min(t, half) / half + (ab0 - ab) * max(t - half, 0) / half,
        lambda t: eps * t / T_,
        lambda t: ucb * math.log1p(t / 100) / math.log1p(T_ / 100),
    ]


def thousands(x: float) -> str:
    """5000 as Portuguese writes it, 5.000 (PTC-7)."""
    return f"{x:,.0f}".replace(",", ".")


class Take23(Take):
    TAKE = "2.3"

    def construct(self):
        self.title()
        r = results.regret()
        formula = T("t2_3.regret", 32).move_to([0, 2.7, 0])
        self.play(Write(formula), run_time=2)
        self.wait(4)

        top = 25 * math.ceil(max(r[k] for k in KEYS) / 25)
        ax = Axes(x_range=[0, r["T"], r["T"] / 2], y_range=[0, top, 50], x_length=8.2, y_length=4.4,
                  tips=False, axis_config={"color": GREY_B}).shift(0.5 * DOWN + 1.6 * LEFT)
        ax.y_axis.add_numbers(font_size=20, num_decimal_places=0)
        ax.x_axis.add_labels({x: raw(thousands(x), 20) for x in (r["T"] / 2, r["T"])})
        xl = T("t2_3.customers", 24, MUTED).next_to(ax.x_axis, DOWN, buff=0.45)
        yl = T("t2_3.axis", 24, MUTED).rotate(PI / 2).next_to(ax.y_axis, LEFT, buff=0.6)
        switch = DashedLine(ax.c2p(r["T"] / 2, 0), ax.c2p(r["T"] / 2, top), color=MUTED)
        s_tag = T("t2_3.switch", 22, MUTED).next_to(switch, UP, buff=0.1)
        self.play(Create(ax), FadeIn(xl), FadeIn(yl))
        self.play(Create(switch), FadeIn(s_tag))

        names = label("t2_3.policies")
        ends = VGroup()
        for f, key, name, c in zip(shapes(r), KEYS, names, COLORS):
            curve = ax.plot(f, x_range=[0, r["T"], r["T"] / 200], color=c, stroke_width=4)
            end = VGroup(raw(name, 22, color=c), raw(decimal(r[key], 1), 24, color=c)).arrange(RIGHT, buff=0.2)
            ends.add(end)
            self.play(Create(curve), run_time=3, rate_func=linear)
            end.next_to(ax.c2p(r["T"], r[key]), RIGHT, buff=0.2)
            self.play(FadeIn(end))
            self.wait(2)
        # Labels of curves that end close together would overlap: spread them apart.
        order = sorted(range(4), key=lambda i: ends[i].get_y())
        for a, b in zip(order, order[1:]):
            if ends[b].get_y() - ends[a].get_y() < 0.4:
                ends[b].set_y(ends[a].get_y() + 0.4)
        caption = T("t2_3.caption", 20, MUTED).to_corner(DR, buff=0.3)
        self.play(FadeIn(caption))
        self.wait(6)
        quote = T("t2_3.jebara", 30, REGRET).move_to(formula)
        self.play(FadeOut(formula), FadeIn(quote))
        self.fill()
