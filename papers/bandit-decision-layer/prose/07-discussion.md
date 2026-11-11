# Discussion and open problems {#sec:discussion}

**What is proved.** For every number of arms and every rational estimate, the three standard
decision rules return distributions, $\varepsilon$-greedy explores with the stated
probabilities, the deterministic rules select maximisers, and UCB on a calibrated model loses at
most twice its confidence radius in each round. These facts are usually taken as obvious and
left unproved. They are also where an implementation goes wrong: a tie broken differently in two
places, an $\varepsilon/K$ computed with the wrong $K$, a width with the wrong sign. A machine
proof against the same definitions that the code copies removes that class of error from the
exact model.

**What is not proved.** Three gaps separate these results from a regret bound.

1. *Calibration with high probability.* Theorem 4 assumes that $\mu_a$ lies within
   $\beta w_a$ of $m_a$. For a linear model this event holds for all rounds with probability at
   least $1 - \delta$ under sub-Gaussian noise, for a suitable $\beta_t$ (a self-normalised
   martingale bound, [@lattimore2020bandit, Chapter 20]). A proof needs measure theory, which the
   Agda development does not have.
2. *The elliptical potential lemma.* The sum $\sum_t \min(1, \lVert x_t \rVert^2_{V_{t-1}^{-1}})$
   is at most $2d \log(1 + T L^2/(d\lambda))$ [@lattimore2020bandit, Lemma 19.4]. This is a
   deterministic statement about positive definite matrices and determinants, and a natural next
   target for the same exact setting.
3. *Floating point.* The theorems do not describe the `Double` implementation. A statement about
   rounding would need a model of IEEE arithmetic.

A Thompson sampling statement is open as well: the decision of Thompson sampling is the
distribution of the argmax of a posterior sample, which needs a distribution over vectors, not a
rule on one vector.

# Statements {.unnumbered}

**Code and data.** The Agda specification, the Haskell implementation and the source of this
paper are in the author's repository `proof`: `agda/src/ContextualBandit/`, `haskell/` and
`papers/bandit-decision-layer/`. There are no data.

**Use of AI.** An AI coding assistant (Claude Code) helped write the Agda proofs, the Haskell
code and this text, under the author's direction. Agda checks every proof under `--safe`. The
author is responsible for the statements and the text.

**Competing interests.** None.
