# Results on simulated data {#sec:results}

[@Tbl:results] gives the test errors. [@Fig:wape] shows the same numbers. All of them come from
the synthetic benchmark of [@Sec:data].

| Model | WAPE all | WAPE big shows (95% CI) | WAPE contested | Winner acc. | Winner acc., event slots |
|---|---|---|---|---|---|
| Seasonal naive | 19.0% | 55.1% (51.7 to 58.6) | 52.8% | 87.6% | 73.2% |
| XGBoost | 15.5% | 21.7% (18.0 to 25.3) | 25.0% | 89.9% | 84.7% |
| XGBoost + rivals | **15.1%** | 21.3% (17.9 to 24.6) | 23.5% | 89.9% | 88.0% |
| DNN (MLP) | 20.7% | 27.6% (23.3 to 32.0) | 25.8% | 87.4% | 85.2% |
| Mistral Timestral | not run | not run | not run | not run | not run |
| JCS | 16.2% | **20.1%** (16.9 to 23.2) | **20.9%** | 89.3% | 87.1% |
| Neurosymbolic JCS | 15.9% | 22.5% (19.3 to 26.2) | 24.1% | **90.3%** | **88.5%** |
| XGBoost + rivals + MinT | 16.6% | 21.4% (18.0 to 24.7) | 24.7% | 89.9% | 88.0% |

: Test errors, 1 January to 31 October 2026, simulated data. All slots: 8,208 channel-slots. Big
shows: 129. Contested: 46 big shows that meet a rival big show or a same-genre programme. Winner
accuracy: share of the 2,736 slots in which the model ranks the true leader first; event slots
are the 209 slots in which at least one channel airs an event with a positive hype signal. Bold: best in the column. {#tbl:results}

![Weighted absolute percentage error by model. Left: all test channel-slots. Middle: big shows,
with 95% day-bootstrap intervals. Right: big shows in contested slots. Simulated data. Timestral
did not run and is not shown.](../tv-audience/figures/wape.png){#fig:wape width=100%}

## Four findings

**1. On ordinary slots, single-channel XGBoost wins.** XGBoost with rival features has the lowest
error over all slots, 15.1%. JCS is 1.1 points worse; the paired 95% interval of the difference is
+0.9 to +1.5 points ([@tbl:paired]). Most slots hold no event, and there the history of the
channel and hour is the best predictor. Trees use that history more flexibly than the linear
utility of JCS.

**2. On big shows, JCS has the lowest error, but the margin is not yet clear.** JCS cuts the
big-show error from 21.3% to 20.1%, and the contested-slot error from 23.5% to 20.9%. With 129 big
shows, the paired interval of the big-show difference runs from -3.3 to +0.6 points. It includes
zero. A longer test period or a real panel with more events is needed to settle it.

**3. Seeing the rivals helps every model, a little.** Adding rival features to XGBoost lowers its
contested-slot error from 25.0% to 23.5% and lifts winner accuracy in event slots from 84.7% to
88.0%. Structure adds more on contested slots (JCS, 20.9%) than features alone.

**4. The DNN is the weakest learned model.** On the same features and target, the multilayer
perceptron has 20.7% error over all slots, worse than the seasonal naive forecast (19.0%). An
early version with a calendar trend feature did worse still (37.6%): the network extrapolated the
trend outside the training range. Tabular data with strong lag features favour trees, and our
DNN had no structure to lean on.

| Model | All slots | Big shows |
|---|---|---|
| Seasonal naive | +3.2 to +4.6 | +29.5 to +37.3 |
| XGBoost | +0.3 to +0.7 | -0.7 to +1.5 |
| DNN (MLP) | +5.1 to +6.1 | +2.8 to +9.6 |
| JCS | +0.9 to +1.5 | -3.3 to +0.6 |
| Neurosymbolic JCS | +0.4 to +1.2 | -1.7 to +4.2 |
| XGBoost + rivals + MinT | +1.3 to +1.8 | -0.7 to +1.1 |

: Paired 95% day-bootstrap intervals of the WAPE difference against XGBoost with rivals, in
percentage points. Below zero means better than XGBoost with rivals. {#tbl:paired}

## Big shows up close

[@Fig:scatter] plots each big-show forecast against the truth. The seasonal naive forecast fails
on big shows (55.1%) because a big show has a median audience 2.2 times the usual one for its
channel and hour. Every learned model reads the hype signal and the episode type, so all of them
cut that error by more than half.

![Big-show forecasts against actual audiences, log scales, simulated data. Left: XGBoost (own
features). Right: JCS. The dashed line is a perfect
forecast.](../tv-audience/figures/big_shows_scatter.png){#fig:scatter width=85%}

[@Fig:week] shows two weeks of the simulated BR market at 21h. The
forecasts track the spikes. They differ most on the non-event days around them.

![Two weeks of the simulated BR market at 21h. Black: actual audience. Grey bands: days on which
the channel airs an event. Simulated data.](../tv-audience/figures/contested_week.png){#fig:week width=100%}

## The neurosymbolic variant

The neural utility lowers the all-slot error of JCS from 16.2% to 15.9% and gives the best winner
accuracy (90.3% of all slots, 88.5% of event slots). It does worse on big shows (22.5%). Big shows
are rare (1.6% of rows), and the network spends its capacity on the common case. We read this as
a promising but unfinished result: the structure works with a neural utility, but the network
needs either more events or a loss that weights them.

## Coherence

No learned model forecast more viewers for the three channels of a slot than the measured pool
in our test: the outside option takes 44% of the pool on average, which leaves room. The seasonal
naive forecast broke that bound in 0.5% of slots. JCS keeps the bound by construction. In a market
where the main channels hold most of the pool, such as a big final in Brazil, independent
forecasts would break it more often.
