"""Take 2.2, the A/B test is a bandit rule (prose-pt-BR/02-teste-ab.md): a slider of epsilon over
the epsilon-greedy mixture e/K + (1 - e)[a = best]. At 1 the three bars are equal (the draw of an
A/B test, `epsGreedy_one_is_ab_test`); at 0 one bar is left (greedy). Then three schedules of
epsilon over time: a jump, a constant, a slow fall.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manim import *  # noqa: E402,F403
from common import *  # noqa: E402,F403

K = 3
BEST = 1


class Take22(Take):
    TAKE = "2.2"

    def construct(self):
        self.title()
        head = T("t2_2.headline", 40, CHOICE).move_to([0, 2.6, 0])
        mix = T("t2_2.mix", 30).next_to(head, DOWN, buff=0.35)
        self.play(Write(head))
        self.play(FadeIn(mix))

        eps = ValueTracker(1.0)

        def bars():
            e = eps.get_value()
            ps = [e / K + (1 - e) * (a == BEST) for a in range(K)]
            g = belief_bars(ps, ["0", "1", "2"], height=2.6, spacing=1.6, baseline=-2.6, color=CHOICE,
                            x=-2.0)
            return g

        group = always_redraw(bars)
        slider = NumberLine(x_range=[0, 1, 0.5], length=3.6, include_numbers=False, color=GREY_B)
        slider.move_to([4.0, -1.2, 0])
        ends = VGroup(raw("0", 26).next_to(slider.n2p(0), DOWN), raw("1", 26).next_to(slider.n2p(1), DOWN))
        knob = always_redraw(lambda: Dot(slider.n2p(eps.get_value()), color=CHOICE, radius=0.12))
        e_tag = always_redraw(lambda: M(r"\varepsilon = " + f"{eps.get_value():.2f}".replace(".", "{,}"), 32)
                              .next_to(slider, UP, buff=0.35))
        self.play(FadeIn(group), Create(slider), FadeIn(ends), FadeIn(knob), FadeIn(e_tag))
        note = VGroup(T("t2_2.theorem", 28), code("epsGreedy_one_is_ab_test")).arrange(DOWN, buff=0.12)
        note.next_to(slider, DOWN, buff=0.7)
        self.play(FadeIn(note))
        self.wait(5)
        self.play(eps.animate.set_value(0.0), run_time=5)
        note2 = VGroup(T("t2_2.greedy", 28), code("epsGreedy_zero")).arrange(DOWN, buff=0.12).move_to(note)
        self.play(Transform(note, note2))
        self.wait(4)
        self.play(eps.animate.set_value(0.1), run_time=2)
        self.wait(2)
        self.play(eps.animate.set_value(1.0), run_time=3)
        self.wait(2)

        # How epsilon falls over time: three schedules.
        self.play(FadeOut(VGroup(group, slider, ends, knob, e_tag, note)), mix.animate.scale(0.8))
        ax = Axes(x_range=[0, 10, 5], y_range=[0, 1.1, 0.5], x_length=8, y_length=3.6, tips=False,
                  axis_config={"color": GREY_B}).shift(1.0 * DOWN + 1.2 * LEFT)
        xl = T("t2_2.time", 24, MUTED).next_to(ax.x_axis, DOWN, buff=0.2)
        yl = M(r"\varepsilon", 30).next_to(ax.y_axis, UP, buff=0.1)
        self.play(Create(ax), FadeIn(xl), FadeIn(yl))
        curves = [
            ax.plot(lambda t: 1.0 if t < 5 else 0.0, x_range=[0, 10, 0.01], discontinuities=[5],
                    color=REGRET, use_smoothing=False),
            ax.plot(lambda t: 0.1, x_range=[0, 10], color=BELIEF),
            ax.plot(lambda t: math.exp(-t / 3), x_range=[0, 10], color=CHOICE),
        ]
        tags = label("t2_2.curves")
        legend = VGroup()
        for c, tag in zip(curves, tags):
            legend.add(VGroup(Line(ORIGIN, 0.5 * RIGHT, color=c.get_color(), stroke_width=5), raw(tag, 24))
                       .arrange(RIGHT, buff=0.2))
        legend.arrange(DOWN, aligned_edge=LEFT, buff=0.25).next_to(ax, RIGHT, buff=0.4)
        for c, l in zip(curves, legend):
            self.play(Create(c), FadeIn(l), run_time=1.5)
            self.wait(2)
        question = T("t2_2.question", 36, CHOICE).next_to(legend, DOWN, buff=0.6)
        self.play(Write(question))
        self.fill()
