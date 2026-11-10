# Animations

Python only draws. The code of the video is Haskell (`haskell/src/Video.hs`, `haskell/src/Pi.hs`,
`haskell/app/Video.hs`) and the specification is Z3 (`z3-scala/src/main/scala/bandit/domain/Video.scala`).
This folder holds the Manim scenes, one per take of the script, in the style the script asks for
(`prose-pt-BR/00-como-ler.md`, "Estilo"): a dark background, one idea per screen, blue for what the
model believes, yellow for the selection, red for the regret.

## Render

```bash
just takes                 # all 19 takes at 1080p, into build/takes/take-N.M.mp4
just takes -q l 1.3 2.2    # two takes at 480p, to look at a change quickly
```

`just takes` runs `render.sh` inside `nix develop .#manim` (Manim Community 0.21, ffmpeg and
LaTeX, pinned by `flake.lock`). `render.sh` calls `python3 -m manim` and not the `manim` program:
nixpkgs wraps that program with a `PATH` that puts its own small TeX Live first, and that TeX Live
has no `babel-portuges`, so the Portuguese words fail to compile. `build/` is not committed.

Each take lasts as long as the script plans for its narration: `Take.fill` reads the times of the
headings of `prose-pt-BR/` (`## Gancho (0:00 a 1:00)`) and holds the last frame until then.

## Takes

| Take | File | Scene | What it shows |
|---|---|---|---|
| 1.1 Hook | `hook.py` | `Take11` | the current and the new belief; the selection changes |
| 1.2 Steal like an artist | `timeline.py` | `Take12` | the timeline from Robbins (1952) to RSI (2026), each milestone with its source |
| 1.3 π and you, one arm | `pi_one_arm.py` | `Take13` | Leibniz and Ramanujan; exploit π(N) or explore π(N+1); the decision cycle |
| 1.4 The name | `name.py` | `Take14` | C, M, A, B: one lever, three levers and their digits, a clock |
| 1.5 Model and rule | `model_rule.py` | `Take15` | two boxes joined only by the estimates; `policy_factors` |
| 1.6 Explore and exploit | `explore_exploit.py` | `Take16` | greedy, ε-greedy and UCB on the same estimates; `ucb_zero` |
| 1.7 Netflix | `netflix.py` | `Take17` | one title, three covers, a subscriber, the play |
| 2.1 What an A/B test is | `ab_test.py` | `Take21` | visitors split into three lanes; a gate closes two |
| 2.2 The A/B test is a bandit rule | `ab_is_bandit.py` | `Take22` | a slider of ε from 1 to 0; three schedules of ε |
| 2.3 The cost of the wait | `cost_of_waiting.py` | `Take23` | the cumulative regret of four policies |
| 2.4 Context makes the test personal | `context.py` | `Take24` | morning and evening windows; one flavour for both |
| 2.5 What the A/B test does better | `ab_still_better.py` | `Take25` | biased and unbiased means, 1/p, the replay |
| 2.6 Summary | `block_summary.py` | `Take26` | the A/B test against the CMAB; the five facts Z3 proves |
| 3.1 Three words | `three_words.py` | `Take31` | three rings: improvement, self-improvement, recursive |
| 3.2 The smallest recursive loop | `rsi_loop.py` | `Take32` | the inner loop inside the outer one; the table of ε |
| 3.3 The bandit in real RSI | `rsi_real.py` | `Take33` | the Feedback-Agent's outer loop; a fixed target |
| 3.4 Current belief against new belief | `beliefs_again.py` | `Take34` | two Beta densities with α and β moving per signal |
| 3.5 What is not a bandit | `limits.py` | `Take35` | two warnings and the lemma `ucb_gap` |
| 3.6 Close and credits | `credits.py` | `Take36` | the three blocks with their files; the credits |

## Files

| File | What it is |
|---|---|
| `common.py` | the colours, the TeX template (babel `brazilian`, T1 fonts), the `Take` scene, bars and arrows |
| `results.py` | reads `../results.md` and the times of the script's headings; it does not import Manim |
| `labels.pt-BR.toml` | every word on screen, in Brazilian Portuguese, as TeX (AGENTS.md, "Language") |
| `render.sh` | renders the takes into `build/takes/` |
| `coverage.py` | what `checks/video-takes.sh` checks: one scene per take, the labels, the sections of `results.md` |

## Where the numbers come from

Every result a take draws is read from [`../results.md`](../results.md) at render time, so a new
`cabal run video` changes the takes with no edit here. Take 3.4 draws the Beta counts of `beliefs`
(`haskell/app/Video.hs`), which `results.md` does not print: it checks that their means are the ones
`results.md` prints before it draws anything. Three takes draw pictures that are not results, and
say so where a viewer could take them for one:

- 1.6 draws example estimates, marked "estimativas de exemplo" on screen.
- 2.3 ends each regret curve at its value in `results.md`, but the shape between 0 and T is a
  sketch (straight, flat after the switch, or logarithmic), marked "forma: esboço". ⚠ To draw the
  real curves, `cabal run video` would have to write the regret per round.
- 2.5 and the moves of the bars in 1.7 are pictures of the argument, with no number on screen.

The two numbers of 3.3 (≈ 3× to ≈ 52×, ≈ 1/3) and the 20 M requests per second of 1.7 are the
script's quotations of its sources, with the source on screen.
