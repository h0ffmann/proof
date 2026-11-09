# Introduction {#sec:introduction}

A contextual bandit selects one action for each request, observes a reward for that action only,
and updates its model. Li, Chu, Langford and Schapire applied this model to personalized news
article recommendation [@li2010contextual].

This repository splits the agent into two layers. A probabilistic model reports a mean and an
uncertainty for each arm. A decision rule turns those estimates into a probability for each arm.
The Z3 specification in `z3/` proves properties of the decision rules, for every real estimate
and up to five arms, and `haskell/` ports them. (It was a Lean 4 package until November 2026; the
repository's `docs/decisions/0001-z3-over-lean.md` records why it moved.) [@Sec:proved] lists what is proved.

# What is proved {#sec:proved}

| Theorem | Statement |
|---|---|
| `epsGreedy_valid` | ε-greedy returns a probability distribution for $0 \le \varepsilon \le 1$ |
| `epsGreedy_one_is_ab_test` | ε-greedy with $\varepsilon = 1$ is the uniform allocation of an A/B/n test |
| `ucb_gap` | with a calibrated model, UCB's arm is within $2\beta \cdot w$ of the best arm |

: Three of the statements in `z3/theorems.py`. {#tbl:proved}

[@Tbl:proved] is a sample of the list in the repository's README. Mechanised work on
stochastic bandits in Lean is in progress elsewhere [@degenne2026leanbandits].
