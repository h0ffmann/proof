"""Take 1.4, the name letter by letter (prose-pt-BR/01-cmab.md): B is one lever, M and A are three
(Leibniz, Gauss-Legendre, Ramanujan), C is a clock beside them. The digits per term are the table of
`Pi.hs` in results.md; the pulls and the digits at the end are `multiArmed`.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manim import *  # noqa: E402,F403
from common import *  # noqa: E402,F403
import results  # noqa: E402


def machine(name: str) -> VGroup:
    """A slot machine: a body, a window and a lever, with its name under it."""
    body = RoundedRectangle(corner_radius=0.15, width=1.6, height=2.0, color=WHITE)
    window = Rectangle(width=1.1, height=0.6, color=MUTED).move_to(body).shift(0.35 * UP)
    stick = Line(body.get_right() + 0.3 * DOWN, body.get_right() + 0.35 * RIGHT + 0.6 * UP,
                 color=WHITE, stroke_width=4)
    ball = Dot(stick.get_end(), radius=0.12, color=REGRET)
    tag = raw(name, 26).next_to(body, DOWN, buff=0.2)
    g = VGroup(body, window, VGroup(stick, ball), tag)
    g.window, g.lever = window, VGroup(stick, ball)
    return g


class Take14(Take):
    TAKE = "1.4"

    def construct(self):
        self.title()
        letters = VGroup(*[raw(c, 72) for c in "CMAB"]).arrange(RIGHT, buff=0.5).move_to([0, 2.4, 0])
        self.play(LaggedStart(*[Write(l) for l in letters], lag_ratio=0.3))
        self.wait(1)

        arms = label("t1_4.arms")
        ms = VGroup(*[machine(a) for a in arms]).arrange(RIGHT, buff=1.4).shift(0.3 * DOWN)
        # B: one lever.
        self.play(letters[3].animate.set_color(CHOICE))
        sub = T("t1_4.bandit", 28).next_to(letters, DOWN, buff=0.3)
        one = ms[0].copy().move_to(0.3 * DOWN)
        self.play(FadeIn(sub), FadeIn(one))
        self.play(Rotate(one[2], angle=-PI / 4, about_point=one[2][0].get_start()), run_time=0.5)
        self.play(Rotate(one[2], angle=PI / 4, about_point=one[2][0].get_start()), run_time=0.5)
        self.wait(3)

        # M and A: three levers.
        self.play(letters[1:3].animate.set_color(CHOICE), letters[3].animate.set_color(WHITE),
                  Transform(sub, T("t1_4.multi", 28).move_to(sub)), ReplacementTransform(one, ms[0]))
        self.play(LaggedStart(FadeIn(ms[1]), FadeIn(ms[2]), lag_ratio=0.4))

        table = results.digits()
        rows = [table[str(n)] for n in range(1, 7)]
        cells = None
        for n, row in enumerate(rows, start=1):
            new = VGroup(*[raw(row[i], 34, color=BELIEF).move_to(ms[i].window) for i in range(3)])
            if cells is None:
                cells = new
                self.play(FadeIn(cells), run_time=0.6)
            else:
                self.play(*[Transform(cells[i], new[i]) for i in range(3)], run_time=0.6)
            self.wait(0.6)
        notes = VGroup(T("t1_4.oscillates", 22, MUTED), T("t1_4.doubles", 22, MUTED))
        for i in range(2):
            notes[i].next_to(ms[i], DOWN, buff=0.6)
        self.play(FadeIn(notes[0]), FadeIn(notes[1]))
        self.wait(3)

        # The simulation: pulls and digits at the end.
        sim = results.multi_armed()
        lines = VGroup()
        for (arm, pulls, grade, digits), m in zip(sim, ms):
            lines.add(VGroup(
                VGroup(raw(str(pulls), 28, color=CHOICE), T("t1_4.pulls", 22, MUTED)).arrange(RIGHT, buff=0.1),
                VGroup(raw(str(digits), 28, color=BELIEF), T("t1_4.digits", 22, MUTED)).arrange(RIGHT, buff=0.1),
            ).arrange(DOWN, buff=0.12).next_to(m, DOWN, buff=0.5))
        self.play(FadeOut(notes), LaggedStart(*[FadeIn(l) for l in lines], lag_ratio=0.3))
        best = max(range(3), key=lambda i: sim[i][1])
        self.play(ms[best][0].animate.set_color(CHOICE))
        heard = T("t1_4.heard", 26).to_edge(DOWN, buff=0.25)
        self.play(Write(heard))
        self.wait(6)

        # C: the context, a clock beside the levers.
        self.play(letters[0].animate.set_color(CHOICE), letters[1:3].animate.set_color(WHITE),
                  Transform(sub, T("t1_4.contextual", 28).move_to(sub)), FadeOut(lines), FadeOut(heard),
                  VGroup(ms, cells).animate.scale(0.8).shift(1.4 * RIGHT))
        clock = VGroup(Circle(radius=0.8, color=WHITE),
                       Line(ORIGIN, 0.5 * UP, color=WHITE, stroke_width=4),
                       Line(ORIGIN, 0.65 * RIGHT, color=WHITE, stroke_width=3))
        clock[1:].shift(clock[0].get_center())
        clock.next_to(ms, LEFT, buff=0.9)
        when = VGroup(T("t1_4.morning", 24, CHOICE), T("t1_4.evening", 24, MUTED)).arrange(RIGHT, buff=0.4)
        when.next_to(clock, DOWN, buff=0.3)
        self.play(Create(clock), FadeIn(when))
        self.play(Rotate(clock[1], angle=-PI, about_point=clock[0].get_center()),
                  when[0].animate.set_color(MUTED), when[1].animate.set_color(CHOICE), run_time=2)
        types = T("t1_4.types", 26).to_edge(DOWN, buff=0.35)
        self.play(Write(types))
        self.fill()
