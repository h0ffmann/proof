# Discussion and limits {#sec:discussion}

**What the identity is for.** It turns a design question into a measurement. Before a forecaster
adds a joint step to independent channel models, they can compute, on past slots, how often the
forecast of the group's total is closer to the actual total than the sum of the channel forecasts.
That share, and the size of $S^2 - \varepsilon^2$, is the whole answer for squared error. On our
benchmark it says no for the totals our models forecast, and yes, with a large margin on big
shows, for a good total. The useful object is therefore a good forecast of the total of exactly the
group being corrected: the channels alone, not the pool with the outside audience in it.

**Relation to reconciliation.** Projection methods of hierarchical forecasting adjust the total
and its parts together [@hyndman2011optimal; @wickramasuriya2019mint], and Panagiotelis et al.
show that a projection onto the coherent subspace improves accuracy for a class of distance-based
losses [@panagiotelis2021geometric]. In that setting the actual values are coherent with the
subspace. Our step keeps an external total fixed, so the plane it projects onto contains the truth
only when the total is exact. The identity measures the price of that difference, slot by slot.

**Limits.** We list what the results do not cover.

1. *Simulated data.* The benchmark's generator follows a multinomial logit of the kind JCS assumes,
   which may favour joint models. No real slot was scored.
2. *Squared error.* The identity is about SSE. WAPE, the metric of our tables, is not covered, and
   [@Sec:benchmark] shows that the two can move in opposite directions.
3. *The group, not each member.* A slot can gain while one channel loses; Proposition 6 needs a band
   of errors to exclude that.
4. *Additive, not multiplicative.* JCS reconciles by shares. A gain identity for the multiplicative
   split is open. The additive step can also give a negative forecast: between 9 and 49 of the
   8,208 channel forecasts in our runs.
5. *No probability.* The statements are about the numbers of a slot. A statement in expectation,
   for example under a model of the errors of the pool forecast, would need measure theory that the
   Agda development does not have.
6. *Rounding.* Agda proves the statements over exact rationals; the experiment runs on doubles,
   where we checked the identity numerically.

**Next.** A weighted version of the step, which moves each channel in proportion to its own
uncertainty, should have a gain identity of the same form in a weighted norm; we have not proved it,
and it is the natural next statement. On data, the next step is the frozen-forecast protocol of [@Sec:real] on slots
where every channel and the pool are published.

# Statements {.unnumbered}

**Code and data.** The Agda proofs, the Python experiment, the Haskell tools and the source of
this paper are in the author's repository `proof`: `agda/src/TvAudience/`, `tv-audience/`,
`tools/tv-audience/`, `tools/tv-ratings/` and `papers/tv-joint-estimation/`. All forecasting data
are simulated by `tv-audience/python/simulate.py`.

**Use of AI.** An AI coding assistant (Claude Code) helped write the Agda proofs, the code and this
text, under the author's direction. Agda checks every proof under `--safe`. The author is
responsible for the statements and the text.

**Competing interests.** None.
