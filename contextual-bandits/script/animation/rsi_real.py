"""Take 3.3, where the bandit enters real RSI (prose-pt-BR/03-rsi.md): the outer loop of the SIA
paper's Feedback-Agent (read through a review, as the script warns), whose arms are kinds of change
and whose reward comes back from a deterministic evaluator. Then the two numbers the script quotes
from Anthropic's essay, and the warning that a fixed target can be aimed at.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manim import *  # noqa: E402,F403
from common import *  # noqa: E402,F403


def node(key_or_tex: str, color, width: float = 3.4, is_key: bool = True) -> VGroup:
    text = T(key_or_tex, 26, color) if is_key else raw(key_or_tex, 26, color=color)
    frame = RoundedRectangle(corner_radius=0.15, width=max(width, text.width + 0.5), height=0.9, color=color)
    return VGroup(frame, text.move_to(frame))


class Take33(Take):
    TAKE = "3.3"

    def construct(self):
        self.title()
        agent = node("t3_3.agent", CHOICE, 4.2).move_to([0, 2.2, 0])
        arms = VGroup(*[node(a, WHITE, is_key=False) for a in label("t3_3.arms")]).arrange(RIGHT, buff=2.4)
        arms.move_to([0, 0.1, 0])
        algos = T("t3_3.algos", 22, MUTED).next_to(arms[1], DOWN, buff=0.15)
        judge = node("t3_3.judge", TRUTH, 4.0).move_to([0, -2.0, 0])
        self.play(FadeIn(agent))
        picks = VGroup(*[Arrow(agent.get_bottom(), a.get_top(), buff=0.1, color=CHOICE) for a in arms])
        self.play(LaggedStart(*[GrowArrow(p) for p in picks], lag_ratio=0.3), FadeIn(arms), FadeIn(algos))
        to_judge = VGroup(*[Arrow(a.get_bottom(), judge.get_top(), buff=0.1, color=GREY_B)
                           for a in (arms[0], VGroup(arms[1], algos))])
        self.play(FadeIn(judge), *[GrowArrow(t) for t in to_judge])
        # The reward goes back around the right of the arms, so it crosses none of them.
        x = arms.get_right()[0] + 0.6
        a, b = judge.get_right() + 0.1 * RIGHT, agent.get_right() + 0.1 * RIGHT
        back = VGroup(Line(a, [x, a[1], 0]), Line([x, a[1], 0], [x, b[1], 0]),
                      Arrow([x, b[1], 0], b, buff=0, max_tip_length_to_length_ratio=0.1)).set_color(BELIEF)
        reward = T("t3_3.reward", 24, BELIEF).next_to(back[1], RIGHT, buff=0.15)
        self.play(Create(back), FadeIn(reward))
        for k in (0, 1, 0):
            self.play(Indicate(picks[k], color=CHOICE), Indicate(arms[k][0], color=CHOICE), run_time=1)
            self.play(Indicate(back, color=CHOICE, scale_factor=1.0), run_time=1)
        bandit = T("t3_3.bandit", 26, CHOICE).to_edge(DOWN, buff=0.35)
        self.play(Write(bandit))
        self.wait(10)

        diagram = VGroup(agent, arms, algos, judge, picks, to_judge, back, reward)
        self.play(FadeOut(bandit), diagram.animate.scale(0.6).to_edge(LEFT, buff=0.4).shift(0.2 * DOWN))
        facts = VGroup(T("t3_3.speedup", 26), T("t3_3.third", 26)).arrange(DOWN, aligned_edge=LEFT, buff=0.5)
        facts.move_to([3.2, 1.2, 0])
        source = T("t3_3.source", 18, MUTED).next_to(facts, DOWN, aligned_edge=LEFT, buff=0.3)
        for f in facts:
            self.play(Write(f), run_time=1.5)
            self.wait(6)
        self.play(FadeIn(source))

        target = VGroup(*[Circle(radius=r, color=c, stroke_width=4) for r, c in ((0.75, REGRET), (0.5, WHITE), (0.25, REGRET))])
        target.move_to([3.2, -1.4, 0])
        dart = Arrow(target.get_center() + 2.4 * LEFT + 0.6 * UP, target.get_center(), buff=0, color=CHOICE)
        fixed = T("t3_3.fixed", 26, REGRET).next_to(target, DOWN, buff=0.25)
        self.play(Create(target))
        self.play(GrowArrow(dart), FadeIn(fixed))
        self.fill()
