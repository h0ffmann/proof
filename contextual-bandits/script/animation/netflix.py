"""Take 1.7, the complex example, Netflix (prose-pt-BR/01-cmab.md): one title, three covers; a
subscriber with a history and a country; the yellow arrow picks a cover, the play comes or not,
and the blue bar of that cover for that profile moves. The 20 M requests per second are Tony
Jebara's figure (2018), as the script cites it. The bar moves are a picture, not a result.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manim import *  # noqa: E402,F403
from common import *  # noqa: E402,F403

COVER_COLORS = [PURPLE_B, TEAL_D, ORANGE]


def subscriber(colors, country: str) -> VGroup:
    head = Circle(radius=0.3, color=WHITE)
    body = Arc(radius=0.55, start_angle=0, angle=PI, color=WHITE).next_to(head, DOWN, buff=0.05)
    tape = VGroup(*[Square(0.26, color=c, fill_color=c, fill_opacity=0.8) for c in colors])
    tape.arrange(RIGHT, buff=0.05).next_to(body, DOWN, buff=0.25)
    flag = VGroup(Rectangle(width=0.7, height=0.42, color=WHITE), raw(country, 20))
    flag[1].move_to(flag[0])
    flag.next_to(head, RIGHT, buff=0.3)
    g = VGroup(head, body, tape, flag)
    g.tape = tape
    return g


class Take17(Take):
    TAKE = "1.7"

    def construct(self):
        self.title()
        covers = VGroup()
        for name, c in zip(label("t1_7.covers"), COVER_COLORS):
            r = RoundedRectangle(corner_radius=0.1, width=1.4, height=2.0, color=c, fill_color=c,
                                 fill_opacity=0.35)
            covers.add(VGroup(r, raw(name, 22).next_to(r, DOWN, buff=0.12)))
        covers.arrange(RIGHT, buff=0.6).move_to([2.6, 0.9, 0])
        self.play(LaggedStart(*[FadeIn(c, shift=0.2 * UP) for c in covers], lag_ratio=0.3))

        bars = VGroup(*[bar(v, height=1.6, width=0.5) for v in (0.4, 0.4, 0.4)])
        for b, c in zip(bars, covers):
            b.move_to(c.get_bottom() + 1.95 * DOWN, aligned_edge=DOWN)
        self.play(*[GrowFromEdge(b, DOWN) for b in bars])

        who = subscriber([RED_C, BLUE_C, RED_C, GREEN_C, RED_C], "BR").move_to([-4.2, 0.6, 0])
        tag = T("t1_7.subscriber", 24, MUTED).next_to(who, UP, buff=0.2)
        self.play(FadeIn(who), FadeIn(tag))
        self.wait(2)

        for pick_i, played, other in ((2, True, None), (0, False, [BLUE_C, GREEN_C, BLUE_C])):
            if other is not None:
                new_tape = VGroup(*[Square(0.26, color=c, fill_color=c, fill_opacity=0.8) for c in other])
                new_tape.arrange(RIGHT, buff=0.05).move_to(who.tape)
                # Another profile has its own bars: they start again from the prior.
                fresh = VGroup(*[bar(0.4, height=1.6, width=0.5).move_to(b, aligned_edge=DOWN) for b in bars])
                self.play(Transform(who.tape, new_tape), Transform(who[3][1], raw("JP", 20).move_to(who[3][1])),
                          Transform(bars, fresh))
            arrow = choice_arrow(covers[pick_i][0])
            self.play(GrowArrow(arrow))
            if played:
                mark = Triangle(color=TRUTH, fill_color=TRUTH, fill_opacity=1).rotate(-PI / 2).scale(0.3)
                word = T("t1_7.play", 24, TRUTH)
            else:
                mark = Cross(scale_factor=0.3, stroke_color=REGRET)
                word = T("t1_7.noplay", 24, REGRET)
            mark.move_to(covers[pick_i][0])
            word.next_to(mark, DOWN, buff=0.2)
            self.play(FadeIn(mark, scale=2), FadeIn(word))
            target = bar(0.75 if played else 0.2, height=1.6, width=0.5).move_to(bars[pick_i], aligned_edge=DOWN)
            self.play(Transform(bars[pick_i], target), run_time=1.2)
            self.wait(3)
            self.play(FadeOut(arrow), FadeOut(mark), FadeOut(word))

        parts = VGroup(T("t1_7.context", 26), T("t1_7.arms", 26), T("t1_7.reward", 26))
        parts.arrange(DOWN, aligned_edge=LEFT, buff=0.2).to_edge(DOWN, buff=0.3).shift(3.2 * LEFT)
        self.play(LaggedStart(*[FadeIn(p, shift=0.2 * RIGHT) for p in parts], lag_ratio=0.5), run_time=3)
        rate = VGroup(T("t1_7.rate", 26, CHOICE), T("t1_7.rate_source", 18, MUTED)).arrange(DOWN, aligned_edge=RIGHT)
        rate.to_corner(UR, buff=0.4)
        self.play(FadeIn(rate))
        self.wait(6)
        same = T("t1_7.same", 30, CHOICE).next_to(parts, RIGHT, buff=1.2)
        self.play(Write(same))
        self.fill()
