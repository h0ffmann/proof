"""Take 1.2, steal like an artist (prose-pt-BR/01-cmab.md): the timeline of the idea, one milestone
at a time, each with its source in small letters. The 58 years between Robbins and LinUCB are a
dashed stretch of the line, not drawn to scale.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manim import *  # noqa: E402,F403
from common import *  # noqa: E402,F403


class Take12(Take):
    TAKE = "1.2"

    def construct(self):
        title = self.title()
        quote = T("t1_2.quote", 34).move_to(ORIGIN)
        self.play(Write(quote), run_time=2)
        self.wait(4)
        self.play(quote.animate.scale(0.7).to_corner(UR, buff=0.4))

        stones = label("t1_2.milestones")
        x0, top = -5.6, 2.3
        ys = [top] + [top - 1.25 - 0.58 * i for i in range(len(stones) - 1)]
        solid = Line([x0, ys[1], 0], [x0, ys[-1] - 0.2, 0], color=WHITE, stroke_width=3)
        dashed = DashedLine([x0, ys[0], 0], [x0, ys[1], 0], color=MUTED, stroke_width=3)
        self.play(Create(dashed), Create(solid), run_time=1.5)

        for i, ((year, what, source), y) in enumerate(zip(stones, ys)):
            dot = Dot([x0, y, 0], color=CHOICE if i == len(stones) - 1 else BELIEF, radius=0.09)
            yr = raw(year, 30, color=dot.get_color()).next_to(dot, LEFT, buff=0.25)
            text = raw(what, 28).next_to(dot, RIGHT, buff=0.35)
            src = raw(source, 18, color=MUTED).next_to(text, RIGHT, buff=0.3).align_to(text, DOWN)
            self.play(FadeIn(dot, scale=2), FadeIn(yr), Write(text), run_time=1.2)
            self.play(FadeIn(src), run_time=0.5)
            if i == 0:
                gap = T("t1_2.gap", 22, MUTED).next_to(dashed, RIGHT, buff=0.35)
                self.play(FadeIn(gap))
            self.wait(4)

        end = T("t1_2.end", 30, CHOICE).to_edge(DOWN, buff=0.35)
        self.play(Write(end))
        self.fill()
