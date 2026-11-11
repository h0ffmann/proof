"""Take 3.5, what is not a bandit and what can go wrong (prose-pt-BR/03-rsi.md): two plain warnings,
with the lemma `ucb-gap` and its premise `Calibrated` beside them (agda/src/ContextualBandit/Theorems.agda).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manim import *  # noqa: E402,F403
from common import *  # noqa: E402,F403


def warning(key: str) -> VGroup:
    sign = Triangle(color=REGRET, stroke_width=5).scale(0.45)
    bang = raw("!", 36, color=REGRET).move_to(sign.get_center() + 0.05 * DOWN)
    return VGroup(VGroup(sign, bang), T(key, 30)).arrange(RIGHT, buff=0.4)


class Take35(Take):
    TAKE = "3.5"

    def construct(self):
        self.title()
        ws = VGroup(warning("t3_5.one_step"), warning("t3_5.gameable")).arrange(DOWN, aligned_edge=LEFT, buff=0.9)
        ws.move_to([0, 1.0, 0])
        for w in ws:
            self.play(FadeIn(w[0], scale=1.5), Write(w[1]), run_time=1.5)
            self.wait(8)
        lemma = VGroup(T("t3_5.lemma", 34, BELIEF),
                       VGroup(code("Calibrated"), code("ucb-gap")).arrange(RIGHT, buff=0.5))
        lemma.arrange(DOWN, buff=0.2).move_to([0, -1.6, 0])
        frame = SurroundingRectangle(lemma, color=BELIEF, buff=0.25)
        self.play(Write(lemma[0]), FadeIn(lemma[1]), Create(frame))
        self.wait(6)
        without = T("t3_5.without", 28, REGRET).to_edge(DOWN, buff=0.35)
        self.play(FadeIn(without))
        self.fill()
