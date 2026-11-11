# Mechanisation and implementation {#sec:mechanisation}

**Agda.** Every statement of [@Sec:setting; @Sec:rules; @Sec:optimism; @Sec:composite] is
proved in Agda 2.8.0 with its standard library 2.3, in the directory
`agda/src/ContextualBandit/`. Every file starts with `{-# OPTIONS --safe --without-K #-}`. The
flag `--safe` refuses `postulate`, unsolved metavariables, incomplete pattern matches and the
other features that let a statement through without a proof [@agda2025safe]. So a file that
type-checks has no hole. Arms are `Fin K`, values are the standard library's exact rationals
(`Data.Rational`), and the ring identities of the proofs, such as $(x+y)+(z+t) = (x+z)+(y+t)$, go through its
ring solver. Agda has no function extensionality under these flags; therefore every equality of
decisions is stated arm by arm.

| Result | Agda name |
|---|---|
| Lemma 1 | `argmax-spec`, `argmaxFrom-mem`, `argmax-cong` |
| Lemma 2 | `mass-add`, `mass-mul`, `mass-const`, `mass-point`, `mass-uniform`, `mass-mix` |
| Theorem 1 | `greedy-valid`, `ucb-valid`, `epsGreedy-valid` |
| Theorem 2 | `epsGreedy-prob`, `epsGreedy-explores`, `epsGreedy-one-is-ab-test` |
| Theorem 3 | `greedy-is-argmax`, `ucb-is-argmax`, `ucb-zero` |
| Theorem 4 | `ucb-gap` |
| Theorem 5 | `greedy-gap` |
| Theorem 6 | `policy-factors` |
| Proposition 7 | `epsGreedy-zero`, `etc-before`, `etc-after`, `etc-valid` |
| Proposition 8 | `rsi-valid-outer`, `rsi-valid-inner`, `outer-explores` |

: The results of this paper and their Agda proofs. Lemma 1 is in `Argmax.agda`, Lemma 2 and
Theorems 1 to 6 in `Theorems.agda`, and Propositions 7 and 8 in `Video.agda`. {#tbl:agda}

The definitions take 298 lines (`Interface.agda`, `Argmax.agda`, `Policies.agda`) and the
proofs of Theorems 1 to 6 take 240 lines (`Theorems.agda`). `just agda` type-checks every module.

**Computed examples.** Because the rationals are exact, Agda also evaluates decisions, and an
equality between a computed decision and a literal holds by `refl`. `Examples.agda` defines a
tabular model with two contexts and three arms: the mean is the average reward of the pulls of a
pair (context, arm), and the width is $1/(n + 1)$ after $n$ pulls, a rational stand-in for
$1/\sqrt{n}$. After a fixed history of seven observations, greedy in the morning context is
$(0, 1, 0)$ and $\mathrm{eps}_{1/10}$ is $(1/30, 14/15, 1/30)$. The second value is
Theorem 2(a): $1 - 1/10 + 1/30 = 14/15$.

**Haskell.** The implementation in `haskell/` depends only on `base` and `containers`. It keeps
the Agda names (`greedy`, `ucb`, `epsGreedy`, `mix`, `point`, `uniform`, `policy`) and the same
argmax, which keeps the first maximum. It adds what a running agent needs and the
specification does not state: three reward models (Beta-Bernoulli, a Bayesian linear model per
arm, which with `ucb` is LinUCB, and a wrapper around any predictor that returns a mean and a
standard deviation), Thompson sampling through the model's sampler, and a pure SplitMix
generator. Its first output is a check against the Agda examples: it recomputes each literal of
`Examples.agda` and of `Video.agda` and prints `OK` or `MISMATCH`.

The Haskell code uses `Double`. The theorems above are about exact rationals and do not cover
rounding: in floating point the mass of $\mathrm{eps}_\varepsilon$ can differ from $1$ by a few
units in the last place, which is why the categorical sampler gives any leftover mass to the
last arm. LiquidHaskell refinement types add a second, weaker check on the same code. They
state, for example, that `argmax` returns an index below the length of its input and that
`epsGreedy` with $\varepsilon \in [0, 1]$ returns values in $[0, 1]$. LiquidHaskell reads
`Double` as a real number, so these refinements do not cover rounding either.
