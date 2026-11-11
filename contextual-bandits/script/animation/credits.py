"""Take 3.6, close and credits (prose-pt-BR/03-rsi.md): the three titles again, each with the file
that holds its code, then the credits screen. The total cost is a point to confirm in the script
(04-creditos.md), and the screen says so until it is filled.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manim import *  # noqa: E402,F403
from common import *  # noqa: E402,F403

FILES = [
    "z3-scala/src/main/scala/bandit/domain/Bandit.scala",
    "haskell/app/Video.hs",
    "z3-scala/src/main/scala/bandit/domain/Video.scala",
]


class Take36(Take):
    TAKE = "3.6"

    def construct(self):
        self.title()
        lines = VGroup()
        for sentence, f in zip(label("t3_6.summary"), FILES):
            lines.add(VGroup(raw(sentence, 32, color=CHOICE), code(f, 20))
                      .arrange(DOWN, aligned_edge=LEFT, buff=0.12))
        lines.arrange(DOWN, aligned_edge=LEFT, buff=0.5).move_to(ORIGIN)
        for l in lines:
            self.play(FadeIn(l, shift=0.2 * RIGHT), run_time=1.2)
            self.wait(4)
        self.wait(3)

        self.play(FadeOut(lines))
        credits = VGroup(*[raw(c, 30) for c in label("t3_6.credits")]).arrange(DOWN, buff=0.35)
        credits.move_to([0, 0.3, 0])
        self.play(LaggedStart(*[FadeIn(c, shift=0.2 * UP) for c in credits], lag_ratio=0.5), run_time=5)
        steal = T("t3_6.steal", 34, CHOICE).to_edge(DOWN, buff=0.5)
        self.wait(5)
        self.play(Write(steal))
        self.fill()
