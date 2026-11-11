# Mechanisation and implementation {#sec:mechanisation}

**Agda.** Every statement of [@Sec:gain; @Sec:shares] is proved in Agda 2.8.0 with its standard
library 2.3, in `agda/src/TvAudience/`. Every file starts with
`{-# OPTIONS --safe --without-K #-}`, which refuses `postulate` and the other features that let a
statement through without a proof [@agda2025safe]. Values are the standard library's exact
rationals, slots are lists of rows, and every statement is proved for every list by induction,
with the ring solver for the algebraic steps.

| Result | Agda name | Module |
|---|---|---|
| Lemma 1 | `reconcile-coherent` | `Joint` |
| Theorem 2 | `joint-gain` | `Joint` |
| Corollary 3 | `joint-le`, `joint-lt` (the third case, a loss when $\lvert\varepsilon\rvert > \lvert S\rvert$, is read off `joint-gain` and not stated separately) | `Joint` |
| Corollary 4 | `joint-known` | `Joint` |
| Corollary 5 | `joint-common-bias` | `Joint` |
| Proposition 6 | `channel-no-worse` | `Joint` |
| Proposition 7 | `joint-worth` | `Joint` |
| Proposition 8 | `joint-total` | `Joint` |
| Examples of [@Sec:gain] | `bigShow-*`, `uneven-*`, `lopsided-*`, by `refl` | `JointExamples` |
| [@Tbl:jcs] | `jcs-accounting`, `jcs-coherent`, `jcs-odds`, `jcs-iia`, `jcs-rival`, `jcs-own`, `jcs-cross`, `jcs-diversion`, `jcs-invert`, `ns-nests-jcs`, `ns-bounded` | `Jcs`, `JcsTheory`, `Neural` |

: The results of this paper and their Agda proofs. {#tbl:agda}

`Joint.agda` has 336 lines. `TvAudience/` also defines WAPE, the seasonal naive and 4-week-mean
baselines with their causality (two series that agree up to day $t - 7$ give the same forecast for
day $t$), the train and test split, regression trees, and a pipeline that composes the pool model
and the share model for every fitted model, with exp and the activation taken as arguments that
need only be positive and increasing, and bounded by one. `just agda` type-checks every module.

**What Agda does not see.** Training. The XGBoost trees, the network and the logit are fitted in
Python; the theorems hold for every set of weights, so they cover the fitted ones, but they say
nothing about how good the fit is. Logarithms and exponentials, which the rationals do not have.
Probability: no statement is about a distribution or an expectation. And rounding: the
experiment runs on IEEE doubles.

**The bridge to the code.** A Haskell tool, `tools/tv-audience/`, runs the Agda definitions with
the same names. On `Rational` it recomputes the examples of `Examples.agda` exactly. On `Double` it
recomputes the seasonal naive numbers of `results.json` from the test rows within a relative
tolerance of $10^{-9}$, and checks what the theorems say of the other models' numbers there. For
the joint step, `joint_step.py` checks [@eq:gain] slot by slot on `Double`
([@Sec:benchmark]).
