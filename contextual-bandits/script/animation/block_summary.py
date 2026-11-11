"""Take 2.6, the summary of the block (prose-pt-BR/02-teste-ab.md): the A/B test against the CMAB in
three rows (the table of section 2.6 of the note), then the five facts Agda proves for every number of arms,
one line at a time (agda/src/ContextualBandit/Theorems.agda).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manim import *  # noqa: E402,F403
from common import *  # noqa: E402,F403


class Take26(Take):
    TAKE = "2.6"

    def construct(self):
        self.title()
        cols = label("t2_6.cols")
        rows = label("t2_6.rows")
        xs = [-3.8, 0.0, 3.8]
        y0 = 1.8
        header = VGroup(*[raw(c, 32, color=[WHITE, REGRET, CHOICE][i]).move_to([x, y0, 0])
                          for i, (c, x) in enumerate(zip(cols, xs)) if c])
        rule = Line([-5.6, y0 - 0.4, 0], [5.6, y0 - 0.4, 0], color=GREY_B)
        self.play(FadeIn(header), Create(rule))
        cells = VGroup()
        for j, row in enumerate(rows):
            y = y0 - 1.0 - 0.9 * j
            line = VGroup(*[raw(t, 30, color=[MUTED, WHITE, WHITE][i]).move_to([x, y, 0])
                            for i, (t, x) in enumerate(zip(row, xs))])
            cells.add(line)
            self.play(FadeIn(line[0]), FadeIn(line[1]))
            self.play(TransformFromCopy(line[1], line[2]), run_time=1.2)
            self.wait(3)
        self.wait(6)

        self.play(FadeOut(VGroup(header, rule, cells)))
        proved = T("t2_6.proved", 30, BELIEF).move_to([0, 2.6, 0])
        self.play(Write(proved))
        facts = VGroup()
        for i, t in enumerate(label("t2_6.theorems")):
            check = MathTex(r"\checkmark", color=TRUTH, font_size=36)
            facts.add(VGroup(check, raw(t, 30)).arrange(RIGHT, buff=0.3))
        facts.arrange(DOWN, aligned_edge=LEFT, buff=0.4).next_to(proved, DOWN, buff=0.6)
        for f in facts:
            self.play(FadeIn(f[0], scale=1.5), Write(f[1]), run_time=1.5)
            self.wait(5)
        lemma = code("ucb-gap", 22).next_to(facts[-1], RIGHT, buff=0.3)
        self.play(FadeIn(lemma))
        open_ = T("t2_6.open", 28, REGRET).to_edge(DOWN, buff=0.4)
        self.play(FadeIn(open_))
        self.fill()
