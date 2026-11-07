# Five forecasters {#sec:models}

All models forecast 7 days ahead and share one feature set ([@tbl:features]). The *own* features
describe the channel's programme and history. The *rival* features describe the other channels in
the same slot. A seasonal naive forecast, the audience of the same channel and hour 7 days
earlier, sets the floor.

| Group | Features |
|---|---|
| Own | market, channel, genre, episode type, hype, $\log(1+\text{hype})$, log audience 7, 14, 21 and 28 days earlier and their mean, last audience of the same series, new-series flag, hour, day of week, day of year (sine and cosine), holiday flag |
| Rival | number of rivals with the same genre, highest and summed rival hype, rivals' log audience 7 days earlier, log pool 7 days earlier and its 4-week mean |

: Features available 7 days before broadcast. {#tbl:features}

## XGBoost

XGBoost [@chen2016xgboost] fits gradient-boosted regression trees. Its target is the log
audience minus the channel's 4-week mean log audience in that hour, so the trees learn changes
from a level, not the level itself. We use 600 trees of depth 6, learning rate 0.03, row and
column subsampling of 0.8 and L2 penalty 5. We fit it twice: with the own features only, and with
the rival features added. The second version tells us how much a single-channel model gains from
seeing its rivals, without any structure.

## Deep neural network

The DNN is a multilayer perceptron with three hidden layers (128, 64 and 32 units), the same
target and the own features, trained with Adam, an L2 penalty of $10^{-3}$ and early stopping on
a 10% validation split (scikit-learn).

## Mistral Timestral

Timestral is Mistral AI's family of time-series foundation models, released on the Hugging Face
Hub in four sizes from 5 to 209 million parameters [@mistral2026timestral]. It forecasts zero-shot:
it is pretrained on many series and not fitted to ours. It returns 21 quantiles per step, takes up
to 32,768 past steps and accepts past, known-future and categorical covariates. We use the largest
model, `mistralai/Timestral-209M`. For each forecast origin, its context is the full log-audience
history of each channel and hour up to 7 days before the target. We take the median of step 7.

Timestral is the foundation-model counterpart of the earlier idea of prompting a general language
model with a series written as text [@gruver2023llmtime]. We first planned that route with a
Mistral chat model [@jiang2023mistral]. A model trained on time series is the fairer comparison.

**This arm did not run for this draft.** The compute environment blocked the Hugging Face Hub,
which hosts the weights, and the PyTorch package index. The runner (`run_timestral` in
`tv-audience/python/experiment.py`) is in place and skips itself when the model cannot load, so
[@Sec:results] reports Timestral as "not run". We do not stand in a guess for its numbers. Our
runner also uses the history alone. Feeding the rivals' line-up as known-future covariates is the
natural next step, and the one that would test Timestral on the competition question.

## Joint Competitive Share (JCS) model

JCS forecasts the two factors of [@eq:split] separately and multiplies them.

1. **Pool.** XGBoost, with the settings above, forecasts the log pool of the slot as a change from
   its 4-week mean. Its features are the calendar, the pool history and the highest and summed
   hype of the line-up, so a big show can raise the pool.
2. **Shares.** A multinomial logit ([@eq:logit]) gives the shares of all $C$ channels and the
   outside option at once. The utility is linear in: channel dummies (brand), genre-by-hour
   dummies, episode-type dummies, $\log(1+\text{hype})$, the channel's log-odds share 7 days
   earlier and over 4 weeks (lead-in and habit), the number of same-genre rivals, the highest and
   summed rival hype, the new-series flag, the holiday flag and a market-specific time trend for
   the outside option. We fit it by maximum likelihood on the observed shares (a fractional
   multinomial logit), with L-BFGS and a small L2 penalty.

The forecast for channel $c$ is $\hat A_{cj} = \hat P_j \hat s_{cj}$. By construction, the three
forecasts of a slot never add up to more than the forecast pool, and a stronger rival lowers
every other channel's forecast.

## Neurosymbolic JCS

Neurosymbolic models join a neural network to symbolic knowledge or rules
[@garcez2020neurosymbolic]. JCS is a natural host. The symbolic part stays fixed: one pool, one
softmax per slot with an outside option, and audience equal to pool times share. The neural part
learns the utility. We add a one-layer network (32 tanh units) to the linear utility of JCS:
$u_{cj} = \beta^\top x_{cj} + w^\top \tanh(W x_{cj} + b)$. We train it through the softmax with
the same likelihood, using Adam for 60 epochs on mini-batches of 512 slots, in plain NumPy. The
network can find interactions, for example between genre, hour and hype, that the linear utility
misses. It cannot break conservation or the competition between channels.

## Reconciliation of independent forecasts

A third way to make independent forecasts coherent is to reconcile them after the fact. We
forecast the outside audience of each slot with XGBoost, take the XGBoost-with-rivals channel
forecasts and the pool forecast, and reconcile the hierarchy $\text{pool} = \sum_c A_c +
\text{outside}$ with MinTrace [@wickramasuriya2019mint] in its structurally weighted form, as
implemented in Nixtla's HierarchicalForecast [@olivares2022hierarchicalforecast].

## Metrics

We report the weighted absolute percentage error,
$\text{WAPE} = \sum |A - \hat A| / \sum A$, over all test channel-slots, over the 129 big shows,
and over the 46 big shows in contested slots. A 95% interval for the big-show WAPE comes from 500
bootstrap resamples of test days. The same resamples give paired intervals for the difference
between each model and XGBoost with rivals. *Winner accuracy* is the share of slots in which the
model ranks the true leader first. A broadcaster cares about this number when two big shows meet.
