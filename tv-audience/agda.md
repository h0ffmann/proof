# TV audience forecasting in Agda

The quantities of [`python/experiment.py`](python/experiment.py) are defined again in Agda, in
[`agda/src/TvAudience/`](../agda/src/TvAudience.agda), with their properties proved. The Python
stays as it is and still writes [`results.json`](results.json) and [`results.md`](results.md), so
the numbers of the paper do not change. A Haskell tool, [`tools/tv-audience/`](../tools/tv-audience/Main.hs),
runs the same definitions with the same names and compares them with the Python output.

## What is exact, and what is not

Every Agda statement is about finite lists of exact rationals (`Data.Rational`), under
`--safe --without-K`: no postulate, and no proof is left out. These stay outside Agda:

- **Training.** XGBoost, the MLP, the logit of JCS and the neural utility of the neurosymbolic
  JCS are fitted by the Python. Agda has no fitted weight. It proves what holds for every tree
  ensemble and for every set of utilities, so the theorems cover the fitted models too.
- **Logarithms and exponentials.** ℚ has neither. The models predict a log audience and
  forecast `exp(lag_mean + f(x))`, and JCS uses the weights `exp(u)`. Agda takes the weights as
  numbers ≥ 0 and the level as a mean of whatever the series holds.
- **Probability.** The bootstrap intervals (500 resamples of days), the percentiles and the
  simulation of `simulate.py` are random. No statement here is about a distribution. The one fact
  Agda states about the bootstrap is that a model's paired difference against itself is 0 on
  every resample.
- **MinT and Timestral.** The reconciliation and the foundation model are libraries. They are not
  defined here.
- **Rounding.** The data are floating-point numbers. The tool computes on `Double` and checks the
  Python numbers within a relative tolerance of 1e-9. An Agda proof says nothing about rounding.

## Modules and theorems

| Module | Defines | Proves |
|---|---|---|
| `Wape` | `wape` (`wape(y, yhat)`), `mae`, `mse` (RMSE²), `scale` (a change of unit) | `wape-nonneg`, `wape-perfect` (0 for a perfect forecast), `wape-scale` (no unit enters it), `wape-++-le` (a pooled WAPE is at most the worse of its two parts), `wape-diff-self`, `wape-mae` (WAPE = MAE / mean \|y\|) |
| `Baselines` | `lag`, `seasonalNaive` (`exp(lag7)`), `lagMean` (`lag_mean`), `horizon = 7` | `seasonalNaive-causal` and `lagMean-causal` (two series that agree up to day t − 7 give the same forecast for day t), `seasonalNaive-weekly` (exact on a weekly series), `lagMean-const`, `lagMean-between` |
| `Split` | `train`, `test` (`date < TEST_START`, `date >= TEST_START`) | `split-length` (every row once), `train-before`, `test-after`, `train-before-test` |
| `Panel` | `rating`, `put`, `share`, `outside`, `overPool`, `countOver` (`slots_over_pool`) | `rating-share-put` (rating = share × PUT), `shares-outside` (the shares and the outside share add up to 1), `coherent-shares`, `countOver-coherent` |
| `Jcs` | `denom`, `jcsShare`, `jcsShares`, `jcsOutside`, `jcsForecast` (`_softmax_out`, pool × share) | `jcs-sum`, `jcs-inside-lt-one`, `jcs-coherent` and `jcs-countOver` (the channel forecasts of a slot never add up to more than its pool forecast), `jcsShare-mono`, `jcs-iia` (the ratio of two shares does not depend on the rivals), `jcs-rival` (a new rival never raises a share) |
| `Winner` | `winner` (the first largest, as `idxmax`), `hit`, `accuracy` (`winner_acc_*`) | `winner-scale` (no change under c > 0), `jcs-winner` (the JCS winner is the largest weight, whatever the pool), `accuracy-nonneg`, `accuracy-le-one`, `accuracy-perfect` |
| `Trees` | `Tree`, `eval`, `predict` (base + Σ leaves), `lo`, `hi` | `eval-between`, `predict-between`, `eval-same` and `predict-same` (piecewise constant: rows on the same side of every split get the same prediction), `predict-++` (boosting rounds add up) |
| `Examples` | a slot of three channels, a JCS slot, a tree | every definition by `refl`: WAPE 3/20 in millions and in thousands, the JCS shares 2/9, 4/9, 1/9 with outside 2/9, a rival that takes the first channel from 2/9 to 1/6 |

`jcs-coherent` compares the forecasts with the pool forecast. The results table compares them
with the observed pool, so its 0.0 % for JCS is a measurement, not this theorem.

## Run

```bash
bash checks/agda.sh          # every Agda root type-checks, TvAudience among them (nix develop .#agda)
bash checks/tv-audience.sh   # the tool: self-test, then the spec, data and table checks
```

The tool prints one line for each number. The spec check computes the 28 examples of
`Examples.agda` on `Rational` and needs each one to be equal. The data check reads the 8208 test
rows, which [`export.py`](../tools/tv-audience/export.py) writes from the Python's own `simulate`
and `build_features` (`nix develop .#data`). On them it computes the seasonal naive WAPE of all
slots, of big shows and of contested big shows, the row counts, both winner accuracies and the
share of slots over the pool, and compares each with `results.json`. The other models need fitted
weights that the experiment does not write, so for them the check asks only what the theorems
say: n(contested) ≤ n(big) ≤ n(all), WAPE ≥ 0, accuracies in [0, 1] that are whole numbers of
the 2736 slots, and the paired interval of XGBoost + rivals against itself is [0, 0]. The table
check needs every row of `results.md` to be its `results.json` numbers, rounded. The self-test
changes one expected example and needs that line to fail.
