"""Take 2.1, what an A/B test is (prose-pt-BR/02-teste-ab.md): a queue of visitors split into three
equal paths by a draw; at the end a gate closes two of them. Then the three virtues.
The draw is a picture; the seed is fixed so every render is the same.
"""

import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manim import *  # noqa: E402,F403
from common import *  # noqa: E402,F403


class Take21(Take):
    TAKE = "2.1"

    def construct(self):
        self.title()
        rng = random.Random(7)
        names = label("t2_1.variants")
        ys = [1.4, 0.0, -1.4]
        start = np.array([-5.6, 0, 0])
        fork = np.array([-3.0, 0, 0])
        lanes = VGroup(*[VGroup(Line(fork, [-1.6, y, 0], color=MUTED), Line([-1.6, y, 0], [4.4, y, 0], color=MUTED))
                         for y in ys])
        tags = VGroup(*[raw(n, 36).move_to([5.0, y, 0]) for n, y in zip(names, ys)])
        entry = Line(start, fork, color=MUTED)
        who = T("t2_1.visitors", 24, MUTED).next_to(start, UP, buff=0.3)
        draw = T("t2_1.draw", 28, BELIEF).to_edge(DOWN, buff=0.6)
        self.play(Create(entry), Create(lanes), FadeIn(tags), FadeIn(who))
        self.play(Write(draw))

        def walk(lane: int, run_time: float = 1.6):
            d = Dot(start, radius=0.09, color=WHITE)
            path = VMobject().set_points_as_corners([start, fork, [-1.6, ys[lane], 0], [4.2, ys[lane], 0]])
            return d, MoveAlongPath(d, path, run_time=run_time, rate_func=linear)

        counts = [0, 0, 0]
        for _ in range(4):
            moves = []
            for _ in range(6):
                lane = rng.randrange(3)
                counts[lane] += 1
                d, m = walk(lane)
                self.add(d)
                moves.append(m)
            self.play(LaggedStart(*moves, lag_ratio=0.15), run_time=2.5)
            self.remove(*[m.mobject for m in moves])
        self.wait(2)

        # Decide: the gate closes two lanes; everyone goes to the best one.
        best = 1
        decide = T("t2_1.decide", 28, CHOICE).move_to(draw)
        gates = VGroup(*[Line([-1.6, y + 0.35, 0], [-1.6, y - 0.35, 0], color=REGRET, stroke_width=8)
                         for i, y in enumerate(ys) if i != best])
        self.play(FadeOut(draw), FadeIn(decide), Create(gates), lanes[best].animate.set_color(CHOICE),
                  tags[best].animate.set_color(CHOICE))
        moves = []
        for _ in range(8):
            d, m = walk(best)
            self.add(d)
            moves.append(m)
        self.play(LaggedStart(*moves, lag_ratio=0.15), run_time=3)
        self.remove(*[m.mobject for m in moves])
        etc = T("t2_1.etc", 30).next_to(decide, UP, buff=0.25)
        self.play(FadeIn(etc))
        self.wait(5)

        scene = VGroup(entry, lanes, tags, who, gates, decide, etc)
        self.play(scene.animate.scale(0.55).to_edge(LEFT, buff=0.4))
        virtues = VGroup(*[raw(f"{i + 1}.\\ " + v, 32) for i, v in enumerate(label("t2_1.virtues"))])
        virtues.arrange(DOWN, aligned_edge=LEFT, buff=0.5).move_to([3.6, 0, 0])
        for v in virtues:
            self.play(Write(v))
            self.wait(3)
        self.fill()
