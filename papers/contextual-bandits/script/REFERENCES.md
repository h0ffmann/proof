---
title: 'Reference log for "Roteiro: CMAB, teste A/B e RSI, em 30 minutos"'
status: draft
date: 2026-11-09
---

# Reference log

Every entry in [`refs.bib`](refs.bib) was fetched before it was cited. This log records what was
checked and how, so a reviewer can repeat the check. `tools/fabric refs-check` fails when a
`refs.bib` key has no row here, or a row's key is not in `refs.bib`.

Status values: `verified` (source fetched, details match), `partial` (source fetched, a detail
could not be confirmed), `unverified` (not fetched; must not be cited).

| Key | Status | Checked against | Note |
|---|---|---|---|
| wikipedia2026mab | verified | the article, 2026-11-09 | the name comes from the slot machine; Robbins formulated the version of 1952; the contextual bandit is "a useful generalization of the multi-armed bandit" |
| wikipedia2026ab | verified | the article, 2026-11-09 | "'A/B testing' is a shorthand for a simple randomized controlled experiment"; the same probability for each variant |
| wikipedia2026steal | partial | the article, 2026-11-09 | Austin Kleon, 2012, Workman; the quotation "nothing is original…" was not checked against the book |
| li2010contextual | partial | arXiv abstract page 1003.0146, 2026-11-09 | title, four authors, year and DOI match; the quotation on offline evaluation is from the abstract; the page does not name the WWW 2010 venue |
| anthropic2026builds | verified | the essay, 2026-11-09 | the definition of recursive self-improvement, "is not inevitable", the speed-ups (about 3x in May 2025, about 52x in April 2026), the code review that caught about a third of the errors behind past incidents, "direction-setting was the only meaningful role a human played" |
| bhavsar2026sia | partial | the review, 2026-11-09 | a review of arXiv 2605.27276, not the paper: the "Feedback-Agent", harness edits against weight updates, PPO, GRPO and DPO, the deterministic evaluator |
| motta2024bandit | verified | the post, 2026-11-09 | the hackday of 2017, Scala, John Myles White's book, "ainda é usado"; "escolher uma foto" and "a melhor posição para colocar publicidade"; the date 2024-09-28 |
| oliveira2018globo | verified | the slides, 2026-11-09 | slide 40 reads "MAB ML PARA AB RL"; the author's title at globo.com; the move to Uber was not found anywhere and is marked `[a confirmar]` |
| jebara2018artwork | verified | the talk page, 2026-11-09 | Tony Jebara, 2018: "about 20 million requests per second at peak", "this massive amount of regret", the A/B test before the rollout to 130 million members |
| dezeen2017netflix | partial | the article, 2026-11-09 | the artwork changes with the viewer's habits and the information "was revealed on the service's blog"; the article's own date is in its address (2017-12-20) and not in its text; the Netflix post itself did not answer on 2026-11-09 and is cited through this article and through the repository's note |
| myshell2024openvoice2 | verified | the model card, 2026-11-09 | six native languages; the input of the tone colour converter can be in any language |
| myshell2024melotts | verified | the repository README, 2026-11-09 | the list of languages has no Portuguese |
| coqui2024xtts | verified | the documentation, 2026-11-09 | 17 languages, `pt` among them |
| rhasspy2023piper | verified | the folder at tag v1.0.0, 2026-11-09 | `pt/pt_BR/faber/medium` exists; the other pt-BR voices were not listed |
| manim | verified | the repository, 2026-11-09 | the Manim Community fork of Grant Sanderson's library; the owner gave the address |
| hoffmann2026note | verified | the file in this repository, 2026-11-09 | sections 3 and 4 and the sources 1 to 5 of the note; the Netflix facts of the script are the note's |
| hoffmann2026proof | verified | this repository, 2026-11-09 | the code the script points to: `lean/ContextualBandit/Video.lean`, `haskell/src/Video.hs`, `haskell/src/Pi.hs`, `haskell/app/Video.hs`, `z3/video.py` |
