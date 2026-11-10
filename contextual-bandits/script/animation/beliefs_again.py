"""Take 3.4, current belief against new belief, again (prose-pt-BR/03-rsi.md): the two Beta beliefs
of the hook, with their counts alpha and beta moving at each signal of the user. The counts are those
of `beliefs` in haskell/app/Video.hs; the means they give are checked against results.md before
anything is drawn, so the two cannot drift apart.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manim import *  # noqa: E402,F403
from common import *  # noqa: E402,F403
import results  # noqa: E402

# haskell/app/Video.hs, `beliefs`: (successes + 1, failures + 1) of the short and the long answer,
# then two signals against the short one and four for the long one.
CURRENT = [(8, 4), (6, 6)]
SIGNALS = [(1, 1)] * 4 + [(0, 0)] * 2   # (option, reward)


def density(a: float, b: float):
    log_norm = math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
    return lambda x: math.exp(log_norm + (a - 1) * math.log(x) + (b - 1) * math.log(1 - x))


def check():
    """The means of these counts must be the ones results.md prints, to its two decimals."""
    got = results.beliefs()
    counts = [list(c) for c in CURRENT]
    for opt, r in SIGNALS:
        counts[opt][0] += r
        counts[opt][1] += 1 - r
    for (a, b), m in zip(CURRENT, got["current"][0]):
        assert round(a / (a + b), 2) == m, "the counts of `beliefs` changed in haskell/app/Video.hs"
    for (a, b), m in zip(counts, got["new"][0]):
        assert round(a / (a + b), 2) == m, "the counts of `beliefs` changed in haskell/app/Video.hs"


class Take34(Take):
    TAKE = "3.4"

    def construct(self):
        check()
        self.title()
        names = label("t3_4.options")
        colors = [BELIEF, CHOICE]
        counts = [ValueTracker(0) for _ in range(4)]   # alpha0, beta0, alpha1, beta1
        for t, v in zip(counts, [CURRENT[0][0], CURRENT[0][1], CURRENT[1][0], CURRENT[1][1]]):
            t.set_value(v)

        ax = Axes(x_range=[0, 1, 0.5], y_range=[0, 3.6, 1], x_length=6.4, y_length=3.8, tips=False,
                  axis_config={"color": GREY_B}).shift(2.4 * LEFT + 0.6 * DOWN)
        axis_numbers(ax.x_axis, [0.5, 1.0])
        self.play(Create(ax))

        def curve(i):
            a, b = counts[2 * i].get_value(), counts[2 * i + 1].get_value()
            return ax.plot(density(a, b), x_range=[0.005, 0.995, 0.005], color=colors[i], stroke_width=4)

        def mean_line(i):
            a, b = counts[2 * i].get_value(), counts[2 * i + 1].get_value()
            m = a / (a + b)
            return DashedLine(ax.c2p(m, 0), ax.c2p(m, 3.4), color=colors[i])

        curves = [always_redraw(lambda i=i: curve(i)) for i in range(2)]
        means = [always_redraw(lambda i=i: mean_line(i)) for i in range(2)]

        def table():
            rows = VGroup()
            for i in range(2):
                a, b = counts[2 * i].get_value(), counts[2 * i + 1].get_value()
                rows.add(VGroup(
                    raw(names[i], 26, color=colors[i]),
                    VGroup(T("t3_4.alpha", 26), raw(f"{a:.0f}", 26)).arrange(RIGHT, buff=0.1),
                    VGroup(T("t3_4.beta", 26), raw(f"{b:.0f}", 26)).arrange(RIGHT, buff=0.1),
                    raw(decimal(a / (a + b)), 26, color=colors[i]),
                ).arrange(RIGHT, buff=0.35))
            return rows.arrange(DOWN, aligned_edge=LEFT, buff=0.35).move_to([4.0, 1.2, 0])

        tab = always_redraw(table)
        head = T("t3_4.current", 30, MUTED).move_to([4.0, 2.4, 0])
        self.play(*[Create(c) for c in curves], *[Create(m) for m in means], FadeIn(tab), FadeIn(head))
        cur = results.beliefs()["current"][1]
        arrow = Arrow(ORIGIN, 0.6 * DOWN, color=CHOICE, buff=0).next_to(means[cur].get_top(), UP, buff=0.05)
        self.play(GrowArrow(arrow))
        self.wait(5)

        for opt, r in SIGNALS:
            word = T("t3_4.liked" if r else "t3_4.disliked", 24, TRUTH if r else REGRET)
            word.move_to([4.0, -0.4, 0])
            self.play(FadeIn(word, shift=0.2 * UP), run_time=0.4)
            target = counts[2 * opt] if r else counts[2 * opt + 1]
            self.play(target.animate.increment_value(1), FadeOut(word), run_time=1.0)

        new = results.beliefs()["new"][1]
        self.play(Transform(head, T("t3_4.new", 30, MUTED).move_to(head)),
                  arrow.animate.next_to(means[new].get_top(), UP, buff=0.05))
        self.wait(4)
        notes = VGroup(T("t3_4.added", 26), T("t3_4.narrower", 26)).arrange(DOWN, aligned_edge=LEFT, buff=0.3)
        notes.move_to([4.0, -1.6, 0])
        for n in notes:
            self.play(Write(n))
            self.wait(5)
        self.fill()
