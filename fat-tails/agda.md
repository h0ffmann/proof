# Fat tails in Agda

The metrics of [`python/fat_tails.py`](python/fat_tails.py) are defined again in Agda, in
[`agda/src/FatTails/`](../agda/src/FatTails.agda), with their properties proved. The Python stays
as it is and still writes [`results.json`](results.json), so the numbers of the paper do not
change. A Haskell tool, [`tools/fat-tails/`](../tools/fat-tails/Main.hs), runs the same
definitions on the data and compares them with the Python output.

## What is exact, and what is not

Every Agda statement is about a finite list of exact rationals (`Data.Rational`), under
`--safe --without-K`: no postulate, and no proof is left out. It is not real analysis and it is
not probability:

- No statement is about a random variable, an expectation, a limit as n grows, or a
  distribution. "R → 0 if and only if E|X|ᵖ is finite" (the MS plot) and "κ = 0 for a Gaussian"
  are Taleb's results about random samples. They are not proved here.
- ℚ has no logarithm, no square root and no real power. So κ itself (two logarithms), the EWMA
  sigma (a square root), the Hill estimator on raw prices (logarithms) and the Weissman quantile
  (a real power) are not defined in Agda. Agda defines the rational part of each one: the MAD
  ratio M(n)/M(1) that κ reads, the EWMA variance, the Hill estimator on the logarithms, and the
  shortfall factor α/(α − 1).
- The data are floating-point numbers. The tool computes on `Double`, with `log` and `sqrt`
  where Agda has none, and checks the Python numbers within a relative tolerance of 1e-9. An Agda
  proof says nothing about rounding.

## Modules and theorems

| Module | Defines | Proves |
|---|---|---|
| `Sample` | `size`, `sumMap`, `sum`, `mean`, `maxMap`, the total division `_/₀_` | sums and maxima under scaling, `mean-scale`, `mean-shift`, `mean-ge`, `div-cancelˡ` |
| `Moments` | `mad` (`mad_of_sums(x, 1)`), `kurtosis` (`stats.kurtosis(x, fisher=False)`) | `mad-scale` (MAD(cx) = \|c\| MAD(x)), `mad-shift`, `kurtosis-scale` (c ≠ 0), `kurtosis-shift`, `cauchy-schwarz` (Σf)² ≤ n Σf², `kurtosis-ge-one` (kurtosis ≥ 1 for a sample with spread; two points give 1) |
| `MaxSum` | `msRatio p` = max \|x\|ᵖ / Σ \|x\|ᵖ (`ms_final`), `topShare = msRatio 4` (`share_of_4th_moment_top_day`) | `msRatio-le-one`, `msRatio-size-ge-one` (n R ≥ 1, so R ≥ 1/n), `msRatio-scale` (no change under c ≠ 0) |
| `Kappa` | `blockSums`, `madOfSums` (M(n)), `kappaRatio` (M(n)/M(1)) | `kappaRatio-scale`, `madOfSums-le`: M(k) ≤ k M(1) for whole blocks of k days, so the ratio is at most k and κ(1, k) ≤ 1 when the ratio is above 1 |
| `Tail` | `hillGap`, `hillAlpha` (on logarithms), `esFactor` = α/(α − 1), `expectedShortfall`, `exceed` (days beyond k sigmas) | `hillGap-shift` (a unit change does not change α), `hillGap-nonneg`, `esFactor-gt-one` (ES > VaR for α > 1), `esFactor-antitone` (a fatter tail gives a larger factor), `es-ge-var`, `tailMean-ge`, `exceed-antitone`, `exceed-le-length` |
| `Ewma` | `ewma` (RiskMetrics variances, λ = `riskMetricsλ` = 47/50), `zSq` = x²/var | `ewma-nonneg`, `ewma-le` (no forecast above the larger of the start and the largest x²), `ewma-scale`, `zSq-scale` |
| `Examples` | eight returns with one −12 % day | every metric by `refl`: kurtosis 7418/1369, top share 576/577, M(2)/M(1) = 18/11 ≤ 2, ES factor 15/11 at α = 3.75 |

## Run

```bash
bash checks/agda.sh          # every Agda root type-checks, FatTails among them (nix develop .#agda)
bash checks/fat-tails.sh     # the tool: self-test, then the spec check and the data check (nix develop .#haskell)
```

The tool prints one line for each number. The spec check computes the 20 examples of
`Examples.agda` on `Rational` and needs each one to be equal. The data check computes 109 numbers
of `results.json` on `Double` for the four samples: the S&P 500 since 1950 and since 2015, the
Nasdaq 100 and the Nikkei 225. For each sample it checks the kurtosis, the top day's share, the MS
ratios for p = 1 to 4 and κ(1, n). It checks the Hill α at three tail fractions, on raw losses and
on devolatilised losses and gains, and the α that the risk table uses. It also checks the EWMA
sigma for the next day, the counts beyond 3 to 6 sigmas, and ES/VaR. The
self-test changes one expected example and needs that line to fail.

The tool takes M(1) of κ over the whole sample, as `fat_tails.py` does. `kappaRatio` in Agda takes
it over the whole blocks only; the two are the same when the length is a multiple of n.
