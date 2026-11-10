"""Take 1.5, model and rule kept apart (prose-pt-BR/01-cmab.md): two boxes joined only by the arrow of
the estimates; the history and the context enter the model, never the rule (`policy_factors`).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manim import *  # noqa: E402,F403
from common import *  # noqa: E402,F403


class Take15(Take):
    TAKE = "1.5"

    def construct(self):
        self.title()
        model = VGroup(box(3.6, 2.2, BELIEF), T("t1_5.model", 36, BELIEF)).move_to([-3.4, 0.3, 0])
        rule = VGroup(box(3.0, 2.2, CHOICE), T("t1_5.rule", 36, CHOICE)).move_to([3.6, 0.3, 0])
        link = Arrow(model.get_right(), rule.get_left(), buff=0.1, color=WHITE, stroke_width=5)
        link_tag = T("t1_5.link", 26).next_to(link, UP, buff=0.15)
        self.play(Create(model[0]), Write(model[1]), Create(rule[0]), Write(rule[1]))
        self.play(GrowArrow(link), FadeIn(link_tag))

        history = VGroup(*[Square(0.28, color=MUTED, fill_opacity=0.6) for _ in range(6)])
        history.arrange(RIGHT, buff=0.08).move_to([-3.4, 2.7, 0])
        h_tag = T("t1_5.history", 24, MUTED).next_to(history, LEFT, buff=0.25)
        context = T("t1_5.context", 24, MUTED).move_to([-3.4, -2.2, 0])
        self.play(FadeIn(history), FadeIn(h_tag), FadeIn(context))
        self.play(LaggedStart(*[s.animate.move_to(model[0].get_top() + 0.3 * DOWN).scale(0.3)
                                .set_opacity(0) for s in history], lag_ratio=0.15), run_time=2)
        self.play(context.animate.next_to(model[0], DOWN, buff=0.1), run_time=1)
        never = DashedLine(h_tag.get_right() + 3.5 * RIGHT, rule[0].get_top(), color=REGRET)
        cross = Cross(scale_factor=0.25, stroke_color=REGRET).move_to(never.get_center())
        self.play(Create(never), Create(cross))
        decision = T("t1_5.decision", 28, CHOICE).next_to(rule, DOWN, buff=0.6)
        self.play(GrowArrow(Arrow(rule.get_bottom(), decision.get_top(), buff=0.05, color=CHOICE)),
                  FadeIn(decision))
        self.wait(3)

        theorem = VGroup(T("t1_5.theorem", 30), code("policy_factors")).arrange(DOWN, buff=0.15)
        theorem.to_edge(DOWN, buff=0.3)
        self.play(Write(theorem[0]), FadeIn(theorem[1]))
        self.wait(6)
        tab = T("t1_5.tabular", 26, BELIEF).move_to(theorem)
        self.play(FadeOut(theorem), FadeIn(tab), FadeOut(never), FadeOut(cross))
        self.wait(5)

        # Three models, one rule.
        for name in label("t1_5.models"):
            new = raw(name, 26, BELIEF)
            if new.width > 3.3:
                new.scale_to_fit_width(3.3)
            new.move_to(model[0])
            self.play(Transform(model[1], new), Indicate(rule[0], color=CHOICE, scale_factor=1.03))
            self.wait(2)
        same = T("t1_5.same_rule", 30, CHOICE).move_to(tab)
        self.play(FadeOut(tab), Write(same))
        self.fill()
