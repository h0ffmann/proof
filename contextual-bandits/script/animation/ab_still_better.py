"""Take 2.5, what the A/B test still does better (prose-pt-BR/02-teste-ab.md): with a fixed
allocation the plain mean of the log is unbiased; with an allocation that moves it is biased, and
weighting each record by 1/p corrects it. Then the replay: a log of uniform choices, a new policy,
the rounds where they agree count, the others are dropped. The positions of the means are a
picture, not a measurement; `policy` returns the whole distribution, the propensity to log.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manim import *  # noqa: E402,F403
from common import *  # noqa: E402,F403

LOG = [0, 2, 1, 1, 0, 2, 1, 0, 2]   # the arm of each logged round, drawn uniformly
NEW = [1, 2, 1, 0, 0, 1, 1, 2, 2]   # what the new policy would select in that round


def panel(x: float, fixed: bool) -> VGroup:
    """Allocation over five periods (stacked bars of three arms) and a line of the true mean."""
    cols = VGroup()
    for k in range(5):
        good = 1 / 3 if fixed else 1 / 3 + 0.12 * k
        rest = (1 - good) / 2
        stack = VGroup(*[Rectangle(width=0.45, height=2.4 * h, stroke_width=1, color=c, fill_color=c,
                                   fill_opacity=0.6) for h, c in ((rest, MUTED), (good, BELIEF), (rest, GREY_D))])
        stack.arrange(UP, buff=0)
        cols.add(stack)
    cols.arrange(RIGHT, buff=0.15, aligned_edge=DOWN).move_to([x, 0.2, 0])
    return cols


class Take25(Take):
    TAKE = "2.5"

    def construct(self):
        self.title()
        left, right = panel(-3.4, True), panel(3.4, False)
        lt = T("t2_5.fixed", 26).next_to(left, UP, buff=0.3)
        rt = T("t2_5.moving", 26).next_to(right, UP, buff=0.3)
        self.play(FadeIn(left, lag_ratio=0.2), FadeIn(lt))
        self.play(FadeIn(right, lag_ratio=0.2), FadeIn(rt))

        def mean_marks(cols, offset):
            y_true = cols.get_bottom()[1] - 0.7
            line = Line([cols.get_left()[0], y_true, 0], [cols.get_right()[0], y_true, 0], color=TRUTH)
            dot = Dot([cols.get_center()[0] + offset, y_true, 0], color=CHOICE, radius=0.11)
            return line, dot

        l_line, l_dot = mean_marks(left, 0.0)
        r_line, r_dot = mean_marks(right, 0.0)
        self.play(Create(l_line), Create(r_line), FadeIn(l_dot), FadeIn(r_dot))
        self.play(r_dot.animate.shift(0.9 * RIGHT).set_color(REGRET), run_time=1.5)
        self.wait(4)
        weight = T("t2_5.weight", 26, CHOICE).next_to(r_line, DOWN, buff=0.4)
        self.play(FadeIn(weight))
        self.play(r_dot.animate.shift(0.9 * LEFT).set_color(CHOICE), run_time=1.5)
        self.wait(4)

        # The replay.
        self.play(FadeOut(VGroup(left, right, lt, rt, l_line, r_line, l_dot, r_dot, weight)))
        head = T("t2_5.replay", 34, CHOICE).move_to([0, 2.7, 0])
        cols = VGroup(T("t2_5.logged", 24, MUTED), T("t2_5.new", 24, MUTED)).arrange(RIGHT, buff=1.2)
        cols.move_to([-2.6, 2.0, 0])
        self.play(FadeIn(head), FadeIn(cols))
        rows = VGroup()
        for i, (a, b) in enumerate(zip(LOG, NEW)):
            y = 1.4 - 0.45 * i
            row = VGroup(raw(str(a), 28).move_to([cols[0].get_x(), y, 0]),
                         raw(str(b), 28, color=CHOICE).move_to([cols[1].get_x(), y, 0]))
            rows.add(row)
        self.play(LaggedStart(*[FadeIn(r[0]) for r in rows], lag_ratio=0.1))
        for (a, b), row in zip(zip(LOG, NEW), rows):
            self.play(FadeIn(row[1]), run_time=0.4)
            if a == b:
                mark = T("t2_5.counts", 22, TRUTH)
            else:
                mark = T("t2_5.dropped", 22, MUTED)
                self.play(row.animate.set_opacity(0.35), run_time=0.3)
            mark.next_to(row, RIGHT, buff=1.0)
            self.play(FadeIn(mark), run_time=0.3)
        price = T("t2_5.price", 28).move_to([3.9, 0.2, 0])
        self.play(Write(price))
        self.wait(4)
        policy = code("policy", 26).next_to(price, DOWN, buff=0.4)
        self.play(FadeIn(policy))
        netflix = T("t2_5.netflix", 26, BELIEF).move_to([3.9, -1.6, 0])
        self.play(FadeIn(netflix))
        self.fill()
