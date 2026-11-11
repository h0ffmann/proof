# The identity on a simulated benchmark {#sec:benchmark}

**All data in this section are synthetic.** No number describes a real channel.

**The benchmark.** The generator of `tv-audience/python/simulate.py` builds three markets
(labelled UK, US and BR) with three placeholder channels each and three prime-time slots a day,
from 2 January 2023 to 31 October 2026. The pool of a slot follows the hour, the day, the season,
holidays and a 3.5% yearly fall of linear viewing, and a big show raises it. Shares follow a
multinomial logit of the channels' programmes: series in 13-week seasons, six genres, and about
31 events per channel a year with heavy-tailed strength. Every forecast is made 7 days ahead. The
test period, 1 January to 31 October 2026, has 2,736 slots, 8,208 channel-slots and 129 big
shows. The full description and the comparison of five forecasters on it are in the repository's
earlier preprint (`papers/tv-audience/`). There, XGBoost [@chen2016xgboost] with the rivals'
line-up as features had the lowest WAPE over all slots (15.1%), and JCS the lowest on big shows
(20.1% against 21.3%), with a paired day-bootstrap 95% interval of the difference that includes
zero (-3.3 to +0.6 points).

**What we measure.** We take three independent channel models of that comparison: XGBoost on the
channel's own features, XGBoost with the rival features, and a multilayer perceptron (DNN). Each
predicts the log audience as a change from the channel's 4-week level. The outside row's forecast
and the pool forecast come from two further XGBoost models of the same experiment. We apply the
joint step of [@eq:step] in two groupings. In the first, the rows are the three channels and the
outside audience, $C = 4$, and $p$ is the pool forecast. In the second, the rows are the three
channels, $C = 3$, and $p$ is the pool forecast minus the outside forecast. For each grouping we
also take the actual total as $p$, an oracle with $\varepsilon = 0$ that bounds what a better
pool model could give. `tv-audience/python/joint_step.py` reuses the experiment's functions and
seed and writes `tv-audience/joint_step.md`; its shell, `nix develop .#tv-joint`, pins Python,
NumPy, pandas, SciPy, scikit-learn and XGBoost through the repository's `flake.lock`.

| Model | $C$ | $p$ | Cond. | SSE all | SSE ch. | SSE big | WAPE | big |
|:--|:--|:--|--:|--:|--:|--:|--:|--:|
| XR | 4 | fc. | 76.7% | 0.840 | 1.350 | 0.799 | 19.7 | 22.5 |
| XR | 4 | actual | 100% | 0.813 | 1.272 | 0.743 | 19.2 | 21.4 |
| XR | 3 | fc. | 30.2% | 1.668 | 1.668 | 1.101 | 22.4 | 23.6 |
| XR | 3 | actual | 100% | 0.804 | 0.804 | 0.730 | 14.1 | 16.2 |
| X | 3 | actual | 100% | 0.784 | 0.784 | 0.674 | 14.6 | 16.6 |
| DNN | 3 | actual | 100% | 0.658 | 0.658 | 0.683 | 16.7 | 18.6 |

: The joint step on the simulated test set (2,736 slots). X is XGBoost, XR XGBoost with rival
features. $C = 4$ is the channels with the outside row and $p$ the pool forecast (fc.); $C = 3$ is the
channels alone and $p$ the pool forecast minus the outside forecast (fc.); "actual" is the actual
total.
Cond. is the share of slots with $\lvert\varepsilon\rvert \le \lvert S\rvert$. The SSE columns (all rows,
channel rows, all rows of the big-show slots) are
SSE joint over SSE alone, below 1 when the step gains; big-show slots are the 129 slots with a big
show. WAPE, in percent, is over the channel rows only, after the joint step, over all slots and on big
shows; alone it is 15.0 and 21.1 for XR, 15.5 and 21.8 for X, 20.7 and 27.6 for the DNN. `tv-audience/joint_step.md` has all
twelve rows. {#tbl:joint}

**The identity holds on `Double`.** On every one of the twelve runs, both sides of [@eq:gain]
agree slot by slot within a relative error of $3 \times 10^{-13}$, and every slot with
$|\varepsilon| \le |S|$ has $\mathrm{SSE}' \le \mathrm{SSE}$, as Corollary 3 says.

**The condition decides the sign, and it often fails.** With the pool forecast and the outside
row, the condition holds on 76% to 81% of slots, and the total SSE of the four rows falls by 14%
to 16%. With the channels alone and $p$ = pool minus outside forecast, it holds on only 30% of
slots for the two XGBoost models (51% for the DNN), and the SSE rises by 16% to 67%. The derived
forecast of the channels' total is worse than the sum of the channel forecasts, so Theorem 2
predicts the loss, and the loss is what we measure.

**Gaining on the theorem's objective is not gaining on the reported metric.** In the first
grouping the SSE of all four rows falls, but the SSE of the three channels rises, by 22% to 35%
for the XGBoost models, and their WAPE rises from 15.0% to 19.7%. The outside audience is the
largest row (39% to 47% of the pool in the three markets), and its errors dominate: for XGBoost
with rivals, the outside row has an SSE of 33,550 against 14,622 for the three channels together.
The joint step spreads a common share of that error over every row. Theorem 2 is a statement
about the SSE of the rows in the group, and it says nothing about a subset of them.

**With a good total, the step pays, and most on big shows.** With the actual total of the
channels, every slot gains (Corollary 4). The SSE falls by 20% for XGBoost with rivals, and the
WAPE falls from 15.0% to 14.1% over all slots and from 21.1% to 16.2% on big shows. For both XGBoost
models the gain is larger on the 129 big-show slots (SSE ratio 0.674 and 0.730) than over all
slots (0.784 and 0.804), as Corollary 5 leads one to expect: a big show adds a common bias to its
rivals' forecasts. For the DNN it is not (0.683 against 0.658).
The oracle is not a forecast. It says how much a pool model as good as the actual
total could give, and so how much is worth spending on that model (Proposition 7).

**Reproduction.** The DNN's WAPE reproduces `results.json` to the reported digit. The XGBoost
models do not quite: over all slots they agree within 0.1 points, but on contested big shows the
model with rivals gives 22.1% here and 23.5% in `results.json`. The pinned XGBoost of the Nix
shell is not the one that wrote `results.json`, and we did not find which one that was. The
comparison above is internal to one run, so it does not depend on this. No interval is given for
the ratios in [@tbl:joint]: they come from one simulated test set.
