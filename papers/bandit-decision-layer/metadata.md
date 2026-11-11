---
title: "A decision layer for contextual bandits, proved in Agda"
subtitle: "Validity, exploration and the optimism lemma for every number of arms, with a Haskell implementation"
author:
  - name: Matheus Hoffmann
    orcid: 0009-0009-1056-7661
date: "November 2026"
version: "Preprint v0 (draft, not peer reviewed)"
keywords:
  - contextual bandits
  - upper confidence bound
  - LinUCB
  - epsilon-greedy
  - optimism lemma
  - Agda
  - formal verification
abstract: |
  We separate a contextual bandit into a reward model, which reports a mean and a width for each
  arm, and a decision rule, which sees only these estimates and returns a probability for each
  arm. For this decision layer we state and prove twelve results, for every number of arms
  $K \ge 1$ and every rational estimate. Greedy, UCB and $\varepsilon$-greedy with
  $0 \le \varepsilon \le 1$ return probability distributions. The $\varepsilon$-greedy rule gives
  the greedy arm exactly $1 - \varepsilon + \varepsilon/K$ and every other arm $\varepsilon/K$,
  and with $\varepsilon = 1$ it is the uniform allocation of an A/B/$n$ test. Greedy and UCB
  select a maximiser of their score, and UCB with $\beta = 0$ is greedy. The optimism lemma
  holds: if every true mean $\mu_a$ lies within $\beta w_a$ of the predicted mean, then
  $\mu_a \le \mu_{\hat a} + 2\beta w_{\hat a}$ for the arm $\hat a$ that UCB selects and for
  every arm $a$; a $\delta$-accurate model gives greedy a loss of at most $2\delta$. Finally, the
  policy depends on the history only through the model's belief. We also show that
  explore-then-commit is one decision rule, and that a nested $\varepsilon$-greedy selection of
  $\varepsilon$ is valid and explores. Each statement has a written proof and a machine-checked
  proof in Agda 2.8.0 under `--safe`, over exact rationals, by induction on $K$. A Haskell
  implementation follows the definitions name for name and reproduces the computed examples.
  The probabilistic half of a regret bound, calibration with high probability and the
  elliptical potential lemma, is not proved here.
lang: en-US
papersize: a4
fontsize: 11pt
geometry:
  - top=25mm
  - bottom=25mm
  - left=28mm
  - right=28mm
---
