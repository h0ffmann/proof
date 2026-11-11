"""Take 1.3, pi and you, one arm (prose-pt-BR/01-cmab.md).

Leibniz's partial sums swing around pi; the agent either shows pi(N) again (exploit) or spends a
term and shows pi(N+1) (explore), and the user's grade is the reward. The counts and the mean
grades are `singleArmed` in results.md. The partial sums are the curve the Desmos file
`desmos/1-3-pi.txt` draws; they are a picture of the series, not a result.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manim import *  # noqa: E402,F403
from common import *  # noqa: E402,F403
import results  # noqa: E402


def leibniz(n: int) -> float:
    return 4 * sum((-1) ** k / (2 * k + 1) for k in range(n))


class Take13(Take):
    TAKE = "1.3"

    def construct(self):
        r = results.single_armed()
        title = self.title()

        lf = M(r"\frac{\pi}{4} = 1 - \frac13 + \frac15 - \frac17 + \cdots", 40)
        lt = T("t1_3.leibniz", 26, MUTED)
        ln = T("t1_3.leibniz_note", 24, MUTED)
        rf = M(r"\frac{1}{\pi} = \frac{2\sqrt2}{9801}\sum_{k\ge 0}"
               r"\frac{(4k)!\,(1103 + 26390k)}{(k!)^4\, 396^{4k}}", 36)
        rt = T("t1_3.ramanujan", 26, MUTED)
        rn = T("t1_3.ramanujan_note", 24, MUTED)
        left = VGroup(lf, lt, ln).arrange(DOWN, buff=0.2)
        right = VGroup(rf, rt, rn).arrange(DOWN, buff=0.2)
        VGroup(left, right).arrange(DOWN, buff=0.8)
        self.play(Write(lf), FadeIn(lt), run_time=2)
        self.play(FadeIn(ln))
        self.wait(3)
        self.play(Write(rf), FadeIn(rt), run_time=2)
        self.play(FadeIn(rn))
        self.wait(4)
        self.play(FadeOut(right), FadeOut(ln), left.animate.scale(0.6).to_corner(UR, buff=0.4))

        # Left: the partial sums of Leibniz around the line y = pi.
        ax = Axes(x_range=[0, 13, 1], y_range=[2.6, 4.1, 0.5], x_length=6.2, y_length=4.2,
                  axis_config={"color": GREY_B, "include_numbers": False}, tips=False)
        ax.to_edge(LEFT, buff=0.6).shift(0.4 * DOWN)
        ax.get_x_axis().add_numbers([1, 4, 8, 12], font_size=20)
        axis_numbers(ax.get_y_axis(), [3.0, 3.5, 4.0])
        pi_line = DashedLine(ax.c2p(0, math.pi), ax.c2p(13, math.pi), color=TRUTH)
        pi_tag = M(r"\pi", 32, TRUTH).next_to(pi_line, RIGHT, buff=0.1)
        self.play(Create(ax), Create(pi_line), FadeIn(pi_tag))
        dots, lines = VGroup(), VGroup()
        for n in range(1, r["n"] + 1):
            d = Dot(ax.c2p(n, leibniz(n)), color=BELIEF, radius=0.06)
            if dots:
                lines.add(Line(dots[-1].get_center(), d.get_center(), color=BELIEF, stroke_width=2))
                self.play(Create(lines[-1]), FadeIn(d), run_time=0.35)
            else:
                self.play(FadeIn(d), run_time=0.35)
            dots.add(d)
        n_tag = VGroup(T("t1_3.end", 26), raw(str(r["n"]), 26)).arrange(RIGHT, buff=0.12)
        n_tag.next_to(ax, DOWN, buff=0.2)
        self.play(FadeIn(n_tag))

        # Right: the two actions, the user's answer, and the agent's belief per action.
        buttons = VGroup()
        for key in ("t1_3.exploit", "t1_3.explore"):
            t = T(key, 28)
            buttons.add(VGroup(RoundedRectangle(corner_radius=0.15, width=t.width + 0.5,
                                                height=0.8, color=WHITE), t))
        buttons.arrange(RIGHT, buff=0.4).move_to([3.6, 1.6, 0])
        for b in buttons:
            b[1].move_to(b[0])
        self.play(LaggedStart(*[FadeIn(b) for b in buttons], lag_ratio=0.3))
        ask = VGroup(RoundedRectangle(corner_radius=0.3, width=2.6, height=0.8, color=TRUTH),
                     T("t1_3.ask", 28, TRUTH))
        ask.next_to(buttons, DOWN, buff=0.4)
        ask[1].move_to(ask[0])
        grade = T("t1_3.grade", 22, MUTED).next_to(ask, DOWN, buff=0.15)
        for i in (1, 0, 1):
            self.play(buttons[i][0].animate.set_color(CHOICE), run_time=0.4)
            self.play(FadeIn(ask, shift=0.2 * UP), run_time=0.4)
            self.play(FadeOut(ask), buttons[i][0].animate.set_color(WHITE), run_time=0.4)
        self.play(FadeIn(ask), FadeIn(grade))
        self.wait(2)

        means = [r["exploit"][1], r["explore"][1]]
        bars = belief_bars(means, ["", ""], height=2.0, spacing=2.4, baseline=-2.6, x=3.6)
        times = VGroup(*[
            VGroup(raw(str(c), 26), T("t1_3.times", 22, MUTED)).arrange(RIGHT, buff=0.1)
            .next_to(b, DOWN, buff=0.15)
            for c, b in zip((r["exploit"][0], r["explore"][0]), bars.bars)])
        mean_tag = T("t1_3.mean", 22, BELIEF).next_to(bars, LEFT, buff=0.3).shift(0.6 * UP)
        rounds = VGroup(raw(str(r["rounds"]), 24), T("t1_3.rounds", 24)).arrange(RIGHT, buff=0.1)
        rounds.next_to(mean_tag, UP, buff=0.4)
        self.play(FadeOut(grade), ask.animate.scale(0.7).next_to(buttons, DOWN, buff=0.2),
                  FadeIn(rounds))
        self.play(*[GrowFromEdge(b, DOWN) for b in bars.bars], FadeIn(bars.values),
                  FadeIn(times), FadeIn(mean_tag), run_time=1.5)
        arrow = pick(bars, 1)
        self.play(GrowArrow(arrow))
        self.wait(7)

        # The cycle: decide, show, receive, update.
        words = label("t1_3.cycle")
        nodes = VGroup(*[raw(w, 30) for w in words])
        for k, node in enumerate(nodes):
            a = PI / 2 - k * TAU / 4
            node.move_to(2.0 * np.array([math.cos(a) * 1.6, math.sin(a), 0]))
        arrows = VGroup(*[
            CurvedArrow(nodes[k].get_center(), nodes[(k + 1) % 4].get_center(),
                        angle=-TAU / 8, color=CHOICE, stroke_width=3)
            for k in range(4)])
        for a in arrows:
            a.scale(0.55)
        everything = VGroup(ax, pi_line, pi_tag, dots, lines, n_tag, buttons, ask, bars, times, mean_tag,
                            rounds, arrow, left)
        self.play(FadeOut(everything))
        self.play(LaggedStart(*[FadeIn(n) for n in nodes], lag_ratio=0.4))
        self.play(LaggedStart(*[Create(a) for a in arrows], lag_ratio=0.4), run_time=3)
        policy = T("t1_3.policy", 32, CHOICE).to_edge(DOWN, buff=0.6)
        self.play(Write(policy))
        for _ in range(2):
            for node in nodes:
                self.play(Indicate(node, color=CHOICE), run_time=0.7)
        self.fill()
