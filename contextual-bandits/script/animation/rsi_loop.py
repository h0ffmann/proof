"""Take 3.2, the smallest recursive loop that fits on a screen (prose-pt-BR/03-rsi.md): the inner
loop (epsilon-greedy selling 500 ice creams) inside the outer loop (a bandit whose arms are values
of epsilon). The table fills as the episodes run; its final numbers are `rsiLoop` in results.md.
The counts grow in proportion to their final values while the table fills: a way to show the
table arrive, not the order in which the episodes went.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manim import *  # noqa: E402,F403
from common import *  # noqa: E402,F403
import results  # noqa: E402


def loop(radius: float, color, center) -> VGroup:
    arcs = VGroup(
        Arc(radius=radius, start_angle=PI / 2 + 0.25, angle=PI - 0.5, color=color, stroke_width=5).add_tip(tip_length=0.25),
        Arc(radius=radius, start_angle=3 * PI / 2 + 0.25, angle=PI - 0.5, color=color, stroke_width=5).add_tip(tip_length=0.25),
    )
    return arcs.move_to(center)


class Take32(Take):
    TAKE = "3.2"

    def construct(self):
        self.title()
        rows = results.rsi()
        total = sum(n for _, n, _ in rows)
        c = np.array([-3.4, -0.3, 0])
        outer = loop(2.6, CHOICE, c)
        inner = loop(1.1, BELIEF, c)
        o_tag = T("t3_2.outer", 26, CHOICE).next_to(outer, UP, buff=0.15)
        i_tag = T("t3_2.inner", 24, BELIEF).move_to(c + 0.25 * UP)
        sells = T("t3_2.sells", 20, BELIEF).move_to(c + 0.25 * DOWN)
        picks = T("t3_2.picks", 22, CHOICE).move_to(c + 1.95 * LEFT)
        gain = T("t3_2.gain", 22, CHOICE).move_to(c + 1.95 * RIGHT)
        self.play(Create(inner), FadeIn(i_tag), FadeIn(sells))
        self.play(Rotate(inner, -TAU, about_point=c), run_time=2)
        self.play(Create(outer), FadeIn(o_tag))
        self.play(FadeIn(picks), FadeIn(gain))
        self.play(Rotate(outer, -TAU, about_point=c), Rotate(inner, -2 * TAU, about_point=c), run_time=3)

        # The table of epsilons, filling while the episodes run.
        x0 = 1.2
        header = VGroup(*[raw(h, 26, color=MUTED) for h in label("t3_2.header")])
        for k, h in enumerate(header):
            h.move_to([x0 + 1.9 * k, 2.0, 0])
        self.play(FadeIn(header))
        progress = ValueTracker(0.0)
        cells = VGroup()
        for i, (eps, n, g) in enumerate(rows):
            y = 1.3 - 0.65 * i
            e = raw(fmt_eps(eps), 28).move_to([x0, y, 0])
            count = always_redraw(lambda n=n, y=y: raw(str(round(n * progress.get_value())), 28)
                                  .move_to([x0 + 1.9, y, 0]))
            mean = raw(decimal(g, 3), 28, color=BELIEF).move_to([x0 + 3.8, y, 0])
            cells.add(VGroup(e, count, mean))
        self.play(FadeIn(VGroup(*[c_[0] for c_ in cells])), FadeIn(VGroup(*[c_[1] for c_ in cells])))
        episodes = always_redraw(lambda: VGroup(raw(str(round(total * progress.get_value())), 26),
                                                T("t3_2.episodes", 22, MUTED)).arrange(RIGHT, buff=0.12)
                                 .move_to([x0 + 1.9, -1.6, 0]))
        self.add(episodes)
        self.play(progress.animate.set_value(1.0), Rotate(outer, -4 * TAU, about_point=c),
                  Rotate(inner, -8 * TAU, about_point=c), run_time=10, rate_func=linear)
        self.play(FadeIn(VGroup(*[c_[2] for c_ in cells])))
        best = max(range(len(rows)), key=lambda i: rows[i][1])
        frame = SurroundingRectangle(VGroup(cells[best][0], cells[best][2]), color=CHOICE, buff=0.15)
        self.play(Create(frame))
        self.wait(6)
        same = T("t3_2.same", 28).to_edge(DOWN, buff=0.75)
        self.play(Write(same))
        self.wait(6)
        horizon = T("t3_2.horizon", 28, CHOICE).to_edge(DOWN, buff=0.25)
        self.play(Write(horizon))
        self.fill()
