# Introduction {#sec:introduction}

A forecast of one channel's audience ignores a plain fact: the people who watch a big show on one
channel are not watching its rivals in the same hour. A model of each channel alone cannot see a
rival's final or premiere, so when one happens, every other channel of the slot is over-forecast.
Estimating the channels of a slot together, with their neighbours, should help. This paper asks
when it does, and answers exactly for one cheap joint step.

The step is the simplest correction there is. Forecast each channel alone, forecast the total of
the slot, and move every channel's forecast by the same amount so that they add up to the total.
It costs one sum and one division per slot. Our main result is an identity, not a bound: for every
slot of $C$ rows, the squared error that the step removes, times $C$, equals $S^2 - \varepsilon^2$,
where $S$ is the error of the sum of the independent forecasts and $\varepsilon$ the error of the
forecast of the total. The step gains exactly when the total is forecast better than the sum, and
loses exactly when it is not. From the identity follow a gain of at least $C\delta^2$ under a common
bias $\delta$, which is the shape of a big show's effect on its rivals; a band in which no single
channel gets worse; a cost at which the step stops paying; and the same statements over many slots.

**Contributions.**

1. The gain identity ([@eq:gain]) and seven consequences ([@Sec:gain]), each with a written proof
   and a machine-checked proof in Agda under `--safe`, over exact rationals, for every number of
   rows.
2. The properties of a multiplicative joint model, the Joint Competitive Share model (JCS), proved
   the same way ([@Sec:shares]): coherence with its pool forecast, independence of irrelevant
   alternatives, diversion and exact inversion of shares.
3. A measurement of the identity's condition on a simulated prime-time benchmark of three markets
   ([@Sec:benchmark]). The identity holds slot by slot on `Double`. The condition held on 30% to
   81% of slots, depending on the grouping, and its failure explains every loss we measured. With
   the actual total, the step lowers the WAPE of XGBoost with rival features from 21.1% to 16.2%
   on big shows; with the totals our models forecast, it raises the channels' error.
4. A public-ratings pipeline for the US, the UK and Brazil and a protocol to test the condition on
   real slots, with the reasons it cannot be tested on the public lists yet ([@Sec:real]).

**What this paper is not.** All forecasting numbers come from simulated data. The theorems are
about the squared error of the numbers of a slot, not about expectations, not about WAPE, and not
about floating-point rounding. They tell a forecaster what to measure before using the step:
whether $|\varepsilon| \le |S|$ on the history of the slots at hand.
