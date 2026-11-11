# The slot and the joint step {#sec:setting}

Take one market, one day and one hour of prime time: a *slot*. In the slot, channels air one
programme each, and the people who watch any TV in the hour form the *pool*. Every viewer of the
pool watches one channel of the slot or something else, which we call the *outside* audience.
The pool is therefore the sum of the channel audiences and the outside audience.

**Rows.** We write the slot as $C \ge 1$ rows. A row $i$ is a pair $(y_i, f_i)$ of exact
rationals: the actual audience $y_i$ and a forecast $f_i$ made by a model of that row alone. When
the group is the whole pool, one row is the outside audience. The error of a row is
$e_i = f_i - y_i$, and

$$T = \sum_i y_i, \qquad F = \sum_i f_i, \qquad \mathrm{SSE} = \sum_i e_i^2 .$$

**The pool forecast.** A separate model forecasts the pool. Its forecast is $p$. We name two
errors of the slot:

$$S = F - T, \qquad \varepsilon = p - T .$$ {#eq:errors}

$S$ is the bias of the independent forecasts as a group: how far their sum is from the actual
total. $\varepsilon$ is the error of the pool forecast.

**The joint step.** The joint estimate sees every row of the slot and the pool forecast. It
moves every forecast by the same amount, so that the forecasts add up to $p$:

$$f'_i = f_i - k, \qquad k = \frac{F - p}{C} .$$ {#eq:step}

This is the Euclidean projection of the vector $(f_1, \dots, f_C)$ onto the hyperplane
$\sum_i x_i = p$. It costs one sum and one division per slot, so it is $O(C)$. We write
$\mathrm{SSE}'$ for the SSE of the forecasts $f'_i$, and call $\mathrm{SSE}$ the error *alone*
and $\mathrm{SSE}'$ the error *joint*.

**Why the question is not trivial.** The forecast reconciliation literature makes base forecasts
coherent after the fact [@hyndman2011optimal; @wickramasuriya2019mint]. Panagiotelis et al. show
that reconciliation by projection is guaranteed to improve accuracy for a class of losses based on
a distance [@panagiotelis2021geometric]. In that setting the actual values are coherent and lie on
the subspace that the forecasts are projected onto. Here they do not: the actual values add up to
$T$, and the step projects onto $\sum_i x_i = p$. When $p \ne T$, the plane of the projection
misses the truth, and the step can make the forecasts worse. [@Sec:gain] says exactly when it
does not.
