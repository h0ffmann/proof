"""Take 3.1, three words one at a time (prose-pt-BR/03-rsi.md): three concentric rings, improvement,
self-improvement and recursive self-improvement; each word lights its ring and names what it
requires.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manim import *  # noqa: E402,F403
from common import *  # noqa: E402,F403


class Take31(Take):
    TAKE = "3.1"

    def construct(self):
        self.title()
        center = np.array([-3.0, -0.3, 0])
        radii = [2.6, 1.75, 0.9]
        rings = VGroup(*[Circle(radius=r, color=GREY_D, stroke_width=4).move_to(center) for r in radii])
        words = label("t3_1.rings")
        needs = label("t3_1.needs")
        self.play(Create(rings), run_time=2)
        lines = VGroup()
        for i, (ring, word, need) in enumerate(zip(rings, words, needs)):
            tag = raw(str(i + 1), 26, color=CHOICE).next_to(ring.point_at_angle(PI / 2), DOWN, buff=0.12)
            line = VGroup(raw(f"{i + 1}.\\ " + word, 32, color=CHOICE), raw(need, 26, color=WHITE))
            line.arrange(DOWN, aligned_edge=LEFT, buff=0.12)
            line.move_to([3.4, 1.6 - 1.5 * i, 0], aligned_edge=LEFT).shift(1.6 * LEFT)
            lines.add(line)
            self.play(ring.animate.set_color(CHOICE).set_stroke(width=8), FadeIn(tag))
            self.play(Write(line), run_time=1.5)
            self.wait(6)
            self.play(ring.animate.set_color(BELIEF).set_stroke(width=4), tag.animate.set_color(BELIEF),
                      line[0].animate.set_color(BELIEF))
        quote = T("t3_1.quote", 28, MUTED).to_edge(DOWN, buff=0.35)
        self.play(FadeIn(quote))
        codes = VGroup(code("outer"), code("innerEps"), code("rsi_valid")).arrange(RIGHT, buff=0.4)
        codes.next_to(quote, UP, buff=0.3)
        self.play(FadeIn(codes))
        self.fill()
