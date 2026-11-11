"""Take 2.4, context makes the test personal (prose-pt-BR/02-teste-ab.md): two windows, morning and
evening, each with a different winning flavour (flavour 1 in the morning, flavour 2 in the evening,
the shop of haskell/app/Video.hs); one flavour for both loses on one side. The regrets are
`abVsBandit` in results.md.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manim import *  # noqa: E402,F403
from common import *  # noqa: E402,F403
import results  # noqa: E402

WINNER = {"morning": 1, "evening": 2}


def window(name_key: str, winner: int, x: float) -> VGroup:
    frame = box(4.4, 2.6).move_to([x, 0.6, 0])
    name = T(name_key, 28).next_to(frame, UP, buff=0.15)
    scoops = VGroup(*[Circle(radius=0.45, color=WHITE, fill_opacity=0.15) for _ in range(3)])
    scoops.arrange(RIGHT, buff=0.4).move_to(frame).shift(0.25 * UP)
    tags = VGroup(*[raw(f, 20, color=MUTED).next_to(s, DOWN, buff=0.15)
                    for f, s in zip(label("t2_4.flavors"), scoops)])
    g = VGroup(frame, name, scoops, tags)
    g.scoops = scoops
    return g


class Take24(Take):
    TAKE = "2.4"

    def construct(self):
        self.title()
        r = results.regret()
        wins = [window("t2_4.morning", WINNER["morning"], -3.3), window("t2_4.evening", WINNER["evening"], 3.3)]
        self.play(*[FadeIn(w) for w in wins])
        head = T("t2_4.with_context", 28, CHOICE).move_to([0, -1.6, 0])
        arrows = VGroup()
        for w, k in zip(wins, ("morning", "evening")):
            s = w.scoops[WINNER[k]]
            arrows.add(choice_arrow(s).scale(0.6, about_point=s.get_top() + 0.1 * UP))
            self.play(s.animate.set_fill(CHOICE, 0.7).set_color(CHOICE))
        self.play(FadeIn(arrows), FadeIn(head))
        self.wait(5)

        # Without context: one flavour in both windows; it loses on one side.
        one = WINNER["morning"]
        no = T("t2_4.no_context", 28, REGRET).move_to(head)
        self.play(FadeOut(arrows), Transform(head, no),
                  *[w.scoops[i].animate.set_fill(WHITE, 0.15).set_color(WHITE) for w in wins for i in range(3)])
        self.play(*[w.scoops[one].animate.set_fill(MUTED, 0.7) for w in wins])
        miss = Cross(scale_factor=0.4, stroke_color=REGRET).move_to(wins[1].scoops[one])
        self.play(Create(miss))
        self.wait(4)

        values = [r["A/B without context (T/2, then commit)"], r["A/B test (T/2, then commit)"]]
        top = max(values)
        names = [label("t2_4.without"), label("t2_4.with")]
        bars = VGroup()
        for i, (v, n) in enumerate(zip(values, names)):
            b = bar(v / top, height=1.6, width=0.6, color=REGRET)
            b.move_to([-1.0 + 2.6 * i, -3.2, 0], aligned_edge=DOWN)
            bars.add(VGroup(b, raw(decimal(v, 1), 26, color=REGRET).next_to(b, UP, buff=0.1),
                            raw(n, 20, color=MUTED).next_to(b, DOWN, buff=0.1)))
        title = T("t2_4.regret", 24, REGRET).next_to(bars, LEFT, buff=0.6)
        self.play(FadeOut(head), VGroup(*wins, miss).animate.shift(0.8 * UP).scale(0.85))
        self.play(FadeIn(title), *[GrowFromEdge(b[0], DOWN) for b in bars], *[FadeIn(b[1:]) for b in bars])
        self.wait(6)

        vec = VGroup(
            M(r"\hat\mu_a = x^{\top}\theta_a", 34, BELIEF),
            T("t2_4.linucb", 24, MUTED),
        ).arrange(DOWN, buff=0.15).move_to([4.9, -2.2, 0])
        self.play(FadeIn(vec))
        self.fill()
