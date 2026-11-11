# Introduction {#sec:introduction}

A contextual bandit selects one action for each request, observes a reward for that action only,
and updates its model. Li, Chu, Langford and Schapire applied this model to personalized news
article recommendation [@li2010contextual].

This repository splits the agent into two layers. A probabilistic model reports a mean and an
uncertainty for each arm. A decision rule turns those estimates into a probability for each arm.
The Z3 specification in `z3/` proves properties of the decision rules, for every real estimate
and up to five arms, and `haskell/` ports them. Z3 is used for now, and no proof assistant is
adopted yet ([@Sec:prover]); an earlier Lean 4 package was removed in November 2026. [@Sec:proved]
lists what is checked.

# No proof language is adopted yet {#sec:prover}

This paper does not adopt a proof language. Z3 is a solver: it checks each statement by a search
for a counterexample, and it gives no proof term that a reader can check again. The checks in
[@Sec:proved] are therefore Z3 checks, not proofs in a proof assistant.

The choice of a proof assistant is open. The owner is inclined to use Agda together with Z3.
Agda is a dependently typed language with a syntax close to Haskell, and the owner knows Haskell
better than Lean 4. Thus an Agda specification would be nearer to the Haskell port in `haskell/`.
The Lean 4 package of this model was removed in November 2026, and no Agda code exists yet.

# What is proved {#sec:proved}

| Theorem | Statement |
|---|---|
| `epsGreedy_valid` | ε-greedy returns a probability distribution for $0 \le \varepsilon \le 1$ |
| `epsGreedy_one_is_ab_test` | ε-greedy with $\varepsilon = 1$ is the uniform allocation of an A/B/n test |
| `ucb_gap` | with a calibrated model, UCB's arm is within $2\beta \cdot w$ of the best arm |

: Three of the statements in `z3-scala/src/main/scala/bandit/domain/Theorems.scala`. {#tbl:proved}

[@Tbl:proved] is a sample of the list in the repository's README. Mechanised work on
stochastic bandits in Lean is in progress elsewhere [@degenne2026leanbandits].
