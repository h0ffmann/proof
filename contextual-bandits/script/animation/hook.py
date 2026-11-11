"""Take 1.1, the hook (prose-pt-BR/01-cmab.md, "Gancho").

Two bars, the current belief and the new one; the yellow arrow of the selection moves from one
option to the other. The numbers are `beliefs` in results.md.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manim import *  # noqa: E402,F403
from common import *  # noqa: E402,F403
import results  # noqa: E402


class Take11(Take):
    TAKE = "1.1"

    def construct(self):
        b = results.beliefs()
        (cur, cur_pick), (new, new_pick) = b["current"], b["new"]
        names = label("t1_1.options")
        self.title()

        bars = belief_bars(cur, names)
        head = T("t1_1.current", 34, BELIEF).move_to([0, 2.3, 0])
        self.play(FadeIn(head), *[GrowFromEdge(r, DOWN) for r in bars.bars], FadeIn(bars.names))
        self.play(FadeIn(bars.values))
        arrow = pick(bars, cur_pick)
        self.play(GrowArrow(arrow))
        self.wait(4)

        # The user's signals: four for option 1, two against option 0.
        signals = [(1, "t1_1.liked", TRUTH)] * 4 + [(0, "t1_1.disliked", REGRET)] * 2
        for i, (target, key, color) in enumerate(signals):
            s = T(key, 26, color).move_to([5.2, 1.5 - 0.5 * (i % 4), 0])
            self.play(FadeIn(s, shift=0.3 * LEFT), run_time=0.35)
            self.play(s.animate.scale(0.4).move_to(bars.bars[target].get_top()).set_opacity(0),
                      run_time=0.5)
            self.remove(s)

        question = T("t1_1.question", 30).to_edge(DOWN, buff=0.5)
        self.play(Write(question))
        self.wait(2)
        after = belief_bars(new, names)
        self.play(Transform(bars, after), Transform(head, T("t1_1.new", 34, BELIEF).move_to(head)),
                  run_time=2)
        self.play(arrow.animate.move_to(pick(after, new_pick)), run_time=1.5)
        self.play(Transform(question, T("t1_1.changed", 30, CHOICE).move_to(question)))
        self.wait(4)

        name = T("t1_1.name", 36).move_to([0, 0.5, 0])
        self.play(FadeOut(VGroup(bars, head, arrow, question)), FadeIn(name))
        blocks = VGroup(*[box(3.2, 1.0) for _ in range(3)]).arrange(RIGHT, buff=0.6).shift(1.6 * DOWN)
        words = VGroup(*[T(f"blocks.{k}", 34).move_to(r) for k, r in zip(("cmab", "ab", "rsi"), blocks)])
        self.play(LaggedStart(*[Create(r) for r in blocks], lag_ratio=0.3),
                  LaggedStart(*[Write(w) for w in words], lag_ratio=0.3), run_time=3)
        self.wait(3)
        self.play(blocks[0].animate.set_color(CHOICE), words[0].animate.set_color(CHOICE))
        self.fill()
