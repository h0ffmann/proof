# How Nixtla could help {#sec:nixtla}

Nixtla maintains a set of open-source Python libraries for forecasting, all under the Apache-2.0
licence, and a pretrained foundation model. Each one maps to a part of this study.

| Need in this study | Nixtla tool | What it adds |
|---|---|---|
| Fast statistical baselines (seasonal naive, ETS, ARIMA) for thousands of channel-slot series | StatsForecast [@nixtla2026statsforecast] | Baselines with cross-validation in a few lines; a fair floor for every model |
| XGBoost with lag features | MLForecast [@nixtla2026mlforecast] | Lags, rolling means and exogenous variables built for any scikit-learn-style model, including XGBoost and LightGBM |
| Neural models | NeuralForecast [@nixtla2026neuralforecast] | More than 30 models (NHITS, TFT, PatchTST and others) with exogenous and static covariates; a stronger DNN arm than our perceptron |
| Coherent forecasts across channels | HierarchicalForecast [@olivares2022hierarchicalforecast] | Reconciliation (BottomUp, TopDown, MinTrace, ERM) and probabilistic coherent forecasts |
| A second foundation model | TimeGPT [@garza2023timegpt] | Zero-shot forecasts from a pretrained model, a benchmark for Timestral |

: Nixtla tools and the parts of this study they cover. {#tbl:nixtla}

We used one of them. HierarchicalForecast reconciled the XGBoost forecasts so that the three
channels and the outside option add up to the pool. The result is a fair test of "coherence after
the fact" against JCS's "coherence by construction". In our benchmark reconciliation did not help.
MinTrace with structural weights left the big-show error at 21.4% (21.3% before) and raised the
all-slot error from 15.1% to 16.6% ([@tbl:results]). The pool and outside-option forecasts carry
their own errors, and reconciliation spreads them over the channels.

Three uses look more promising than the one we tried.

1. **Reconcile JCS with real hierarchies.** Real panels report audiences by region and by
   demographic group. HierarchicalForecast can keep a national JCS forecast coherent with its
   regional parts, a hierarchy that JCS alone does not handle.
2. **Rebuild the baselines with less code.** StatsForecast and MLForecast would replace our
   hand-written lag features and seasonal naive forecast, and their cross-validation would give a
   rolling test over many origins instead of our single split.
3. **Stress-test the foundation-model arm.** Running TimeGPT next to Timestral, with the rivals'
   line-up as known-future covariates where the model accepts them, would show whether a
   foundation model can learn the competition that JCS writes down by hand.
