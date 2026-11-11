# Validation of tv-audience in Haskell

A Haskell pipeline that runs [`tv-audience/python/experiment.py`](../../tv-audience/python/experiment.py)
as it is, and then computes its numbers again. It answers three questions:

1. Are the scores of `results.json` the scores of the forecasts?
2. Are the forecasts of the two JCS models the ones their fitted weights give?
3. Do the theorems of [`agda/src/TvAudience/`](../../agda/src/TvAudience.agda) hold on the
   numbers of the run, and do the Haskell definitions mean what the Agda definitions mean?

```bash
tools/tv-validate/run.sh               # the experiment, then every property and every line
tools/tv-validate/run.sh --self-test   # changes to the run that one line each must catch
tools/tv-validate/run.sh -- -p metrics # one group (a Tasty pattern)
bash checks/tv-validate.sh             # the first two, as `just check` runs them
```

`run.sh` enters `nix develop .#tv-validate` ([`nix/tv-validate.nix`](../../nix/tv-validate.nix)) by
itself. The first run takes about 75 s: 50 s for the experiment, 20 s for the build, 5 s for the
checks.

## How it works

[`export.py`](export.py) imports the experiment and calls its `main()`. It copies no line of it. It
wraps `evaluate`, `fit_logit`, `fit_neural_logit`, `fit_pool` and `reconcile_mint` to keep their
arguments and results, and reads the weights of the neurosymbolic model from the closure that
`fit_neural_logit` returns. It writes the test rows with every model's forecast, the panel, the
share designs, the fitted weights, the 500 day resamples of the bootstrap, and the `results.json`
of this run.

The Haskell package reads those files and builds one [Tasty](https://hackage.haskell.org/package/tasty)
tree. A line says `OK` or `FAIL`. A line that starts with `NOTE` is a measurement, or a comparison
that this run cannot make; it never fails. Two numbers are equal when they differ by at most
1e-9, relative above 1 and absolute below it.

| Group | What it asks | Lines |
|---|---|---|
| `properties` | 31 theorems of `agda/src/TvAudience/` as [Hedgehog](https://hackage.haskell.org/package/hedgehog) properties of the Haskell definitions, on `Rational`, 200 cases each. The two sides must be equal, not close. | 31 |
| `reproduce` | `tv-audience/results.json` against the `results.json` of this run |10 |
| `metrics` | every number of this run's `results.json`, for every model, from the forecasts. They are the three WAPEs, the row counts, the three bootstrap intervals, both winner accuracies and the share of slots over the pool. | 78 |
| `forward` | `forecastSlot` of `Pipeline.agda` on the fitted weights gives the JCS and the neurosymbolic JCS forecasts of all 8208 test rows | 3 |
| `gradient` | the gradient of `fit_logit`'s loss on the 28620 training rows, by reverse-mode automatic differentiation ([ad](https://hackage.haskell.org/package/ad)), equals the gradient that `fit_logit` writes by hand, and its largest component at the fitted weights is below 1e-4 | 4 |
| `theorems` | statements proved in Agda, on the Double numbers of the run: `wape-scale`, `wape-++-le`, `wape-mae`, `seasonalNaive-causal`, `lagMean-causal`, the split, and for both JCS models `pipeline-coherent`, `jcs-accounting`, `jcs-odds`, `pipeline-winner`, `ns-bounded` | 15 |
| `joint` | `Joint.agda` on the 2736 test slots, on exact rationals (`toRational` of each Double): `reconcile-coherent`, `joint-gain`, `joint-le`, `joint-total`, and the measurement that `joint.md` leaves open | 20 |
| `mint` | the MinT reconciliation in closed form | 2 |

The definitions are the ones of [`tools/tv-audience/TvAudience.hs`](../tv-audience/TvAudience.hs),
the mirror of the Agda modules that `checks/tv-audience.sh` already compares with
`Examples.agda`. The package compiles that file; it does not copy it.
[`Joint.hs`](src/TvValidate/Joint.hs) adds the mirror of `Joint.agda`.

## Results (2026-11-11, the pinned shell)

`tools/tv-validate/run.sh`: 163 tests pass, 21 of them are a `NOTE`. `--self-test`: 9 of 9.

- **Scores.** All 72 numbers of the six models that ran come back from the forecasts.
- **Forward pass.** The largest gap to the Python forecasts is 2.9e-13 (JCS) and 4.3e-13
  (neurosymbolic JCS).
- **Gradient.** Automatic differentiation and the hand-written formula differ by at most
  2.5e-17 on the 45 weights. The largest component at the fitted weights is 1.6e-5. SciPy's
  L-BFGS-B stops at 1e-5 by default (`gtol`), so the bound of the line is ten times that. The
  loss is convex, so the weights are at its minimum within that gradient.
- **Lags.** Every `p_naive` is the audience of the same channel and slot 7 days before, and
  every `lag_mean` is the mean log audience of days t-7 to t-28. No test row reads a younger
  audience through these two features.

### The committed numbers

The pinned nixpkgs has XGBoost 3.0.5. With it, the numbers of `tv-audience/results.json` that do
not pass through XGBoost come back within 2e-16 (the seasonal naive and the MLP: 20 numbers). The
others do not: the largest gap is 0.0137 (`wape_clash` of XGBoost + rivals, 23.5 % committed and
22.1 % in the pinned shell). The pipeline prints each of these gaps as a `NOTE`.

The committed file comes from XGBoost 3.4.1. An export made with pip gives every committed
number back within 1e-14, and all 176 tests pass on it. Its versions were Python 3.13.18, NumPy
2.5.4, pandas 3.1.1, SciPy 1.18.1, scikit-learn 1.9.1, XGBoost 3.4.1 and hierarchicalforecast
1.5.3.

```bash
python3 -m venv venv
venv/bin/pip install numpy pandas scipy scikit-learn xgboost==3.4.1 hierarchicalforecast
venv/bin/python tools/tv-validate/export.py /tmp/run-pip
TV_VALIDATE_RUN=/tmp/run-pip tools/tv-validate/run.sh
```

That run is outside Nix. The pinned shell cannot make it: nixpkgs at the locked revision has
neither XGBoost 3.4.1 nor hierarchicalforecast. The two ways to close the gap are a newer nixpkgs,
or a new `results.json` (and paper table) from the pinned shell. Neither is done here.

### The joint step, measured

[`joint.md`](../../tv-audience/joint.md) says that |ε| ≤ |S| is an assumption to measure on data.
On the simulated test set, with XGBoost + rivals as the independent forecasts:

| Group | \|ε\| ≤ \|S\| holds | SSE of the group | SSE of the channel rows | WAPE of the channels |
|---|---|---|---|---|
| 3 channels and the rest of the pool, p = `pool_hat` | 76.7 % of the slots | -16.0 % | +35.0 % | 15.0 % to 19.7 % |
| the 3 channels, p = `pool_hat` - `other_hat` | 30.2 % of the slots | +66.8 % | +66.8 % | 15.0 % to 22.4 % |

The theorems hold in every slot, exactly. The gain of the first group is in the row of the rest
of the pool. The additive step gives every row the same share of the gap, in millions of viewers,
so the channels, which are smaller than the rest of the pool, lose. For big shows the channel WAPE
goes from 21.1 % to 22.5 %, and for contested big shows from 22.1 % to 28.4 %. On this data the
additive joint step does not help the channels. The JCS model shares the pool by shares, not by
this step, and its numbers are the ones of `results.md`.

### MinT in closed form

`MinTrace(method="wls_struct")` on a slot (pool = 3 channels + other) weights the pool by 4 and
each bottom series by 1. So it moves every bottom forecast by (`pool_hat` - Σ bottoms) / 8, half
of the joint step above with the pool moving too. On the pip export, this closed form equals the
forecasts of hierarchicalforecast 1.5.3 within 6e-16 on all 8208 rows, and its 12 scores equal the
committed ones. In the pinned shell the library is missing, the experiment's MinT arm is not run,
and the closed form is scored as a `NOTE`.

## Libraries

AGENTS.md rule 6 keeps Haskell on GHC's own libraries. This package is the agreed exception (the
owner, 2026-11-11). Every version comes from the nixpkgs that `flake.lock` pins; cabal builds
offline, with no Hackage index.

| Library | Version | Used for |
|---|---|---|
| GHC, cabal-install | 9.10.3, 3.16.1.0 | the compiler (language `GHC2021`) and the build |
| [aeson](https://hackage.haskell.org/package/aeson) | 2.2.4.1 | `model.json` and the two `results.json` |
| [cassava](https://hackage.haskell.org/package/cassava) | 0.5.4.1 | the CSV files, by column name |
| [vector](https://hackage.haskell.org/package/vector) | 0.13.2.0 | the rows of the share designs, unboxed |
| [ad](https://hackage.haskell.org/package/ad) | 4.5.6 | the gradient of the logit loss, reverse mode |
| [tasty](https://hackage.haskell.org/package/tasty), [tasty-hunit](https://hackage.haskell.org/package/tasty-hunit) | 1.5.4, 0.10.2 | the tree of lines, patterns, the exit code |
| [hedgehog](https://hackage.haskell.org/package/hedgehog), [tasty-hedgehog](https://hackage.haskell.org/package/tasty-hedgehog) | 1.5, 1.4.0.2 | the properties, with shrinking |
| [optparse-applicative](https://hackage.haskell.org/package/optparse-applicative) | 0.18.1.0 | the command line |
| Python, NumPy, pandas, SciPy, scikit-learn, XGBoost | 3.14.7, 2.5.2, 3.0.4, 1.18.1, 1.9.0, 3.0.5 | the experiment itself |

## Limits

- **Training is not run again.** XGBoost, the MLP and the Adam loop of the neurosymbolic model
  are taken as the Python ran them. The pipeline checks the logit fit (its gradient), and for the
  other models what their forecasts score.
- **The pool model enters as its forecast.** The 600 trees of the pool model are not read, so
  `poolHat` of `Pipeline.agda` is checked with a level of log(`pool_hat`) and no tree.
- **The bootstrap resamples are NumPy's.** `export.py` draws them from the same generator, seed
  and calls as `evaluate`. The pipeline checks the intervals given those days.
- **The simulator is not checked.** `simulate.py` is the source of the data, and nothing here
  says that it is a good model of a TV market.
- **Double, not real numbers.** The Agda theorems are about exact rationals. A line of
  `theorems` shows that a statement also holds on the Doubles of this run within 1e-9; the
  `joint` group and the properties are exact.
