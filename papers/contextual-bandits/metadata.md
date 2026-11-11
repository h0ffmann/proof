---
title: "Contextual bandits as a verified specification"
subtitle: "A Z3 model of the decision layer, ported to Haskell"
author:
  - name: Matheus Hoffmann
    orcid: 0009-0009-1056-7661
date: "November 2026"
version: "v0 (draft, not peer reviewed)"
keywords:
  - contextual bandits
  - LinUCB
  - Z3
  - formal specification
  - A/B testing
abstract: |
  A contextual bandit is split into two layers: a probabilistic model that reports a mean and an
  uncertainty for each arm, and a decision rule that turns those estimates into a probability for
  each arm. We specify the decision layer in Z3 and port it to Haskell. For every real value of
  the estimates and for up to five arms, Z3 finds no counterexample to the following statements:
  greedy, UCB and epsilon-greedy return probability distributions; epsilon-greedy gives every arm
  at least epsilon/K, and with epsilon = 1 it is the uniform allocation of an A/B/n test; greedy
  and UCB pick a maximiser of their score; and the UCB optimism lemma, the deterministic core of
  UCB and LinUCB regret proofs, holds: with a calibrated model the arm UCB picks loses at most
  2 beta w against the best arm. These are solver checks, not proofs in a proof assistant. No
  proof language is adopted yet; the author leans to Agda, closer to Haskell than Lean 4, used
  together with Z3. The probabilistic parts of a regret bound are left open.
lang: en-US
papersize: a4
fontsize: 11pt
geometry:
  - top=25mm
  - bottom=25mm
  - left=28mm
  - right=28mm
---
