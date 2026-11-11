# Fat tails in equity indexes

Diagnostics from Nassim Taleb's *Statistical Consequences of Fat Tails*
(Incerto technical volume, [arXiv:2001.10488](https://arxiv.org/abs/2001.10488)),
run on daily S&P 500 closes from 1950 to 30 October 2026, plus the Nasdaq 100
and Nikkei 225 since 2015. The question: how wrong is a Gaussian risk number
for the S&P 500 right now?

The preprint [`papers/fat-tails`](../papers/fat-tails/metadata.md) tells the same story in full,
with every figure. It is not peer reviewed. A built copy is
[`papers/fat-tails/fat-tails.pdf`](../papers/fat-tails/fat-tails.pdf); `just paper fat-tails`
rebuilds it.

Educational only. Not investment advice.

The metrics are also defined over exact rationals in Agda, with their properties proved, and a
Haskell tool checks the Agda definitions against `results.json`: see [`agda.md`](agda.md).

```bash
pip install numpy pandas scipy matplotlib
python3 fat-tails/python/fat_tails.py   # writes results.md, results.json, figures/*.png
```

All numbers below come from [`results.md`](results.md) and
[`results.json`](results.json).

## Data

`data/sp500.csv` joins two public copies of Yahoo Finance's `^GSPC` closes kept
on GitHub (1950 to 2014 and 2015 to 30 Oct 2026). Both match FRED's `SP500`
series to 8 digits wherever they overlap (1,001 and 413 days). `data/ndx.csv`
and `data/n225.csv` come from the same 2015+ source. Returns are daily log
returns.

"EWMA sigma" is the RiskMetrics volatility (λ = 0.94). "Devolatilised" means a
daily return divided by the EWMA sigma forecast for that day; that removes most
volatility clustering, so the tail estimators see something closer to i.i.d.

## What each metric says

| Metric (book chapter idea) | S&P 500, 1950-2026 | Gaussian value | Reading |
|---|---|---|---|
| Kurtosis | 28.2 | 3 | Large, but see the next row. |
| Share of the 4th moment from the single largest day (19 Oct 1987) | 52% | ~0 for large n | One day out of 19,330 decides the kurtosis. Drop it and kurtosis halves to 14.4. Year-by-year kurtosis ranges from 2.6 to 57. Kurtosis is not a usable number here. |
| MS plot, max/sum of \|X\|^p at the end | p=1: 0.002, p=2: 0.027, p=3: 0.19, p=4: 0.52 | goes to 0 | Mean and variance look finite. The 3rd and 4th moments do not converge ([figure](figures/ms_plot.png)). |
| Hill tail exponent α, raw daily losses | 2.7 to 3.1 (tail fraction 1% to 5%) | ∞ | Power-law tail with α near 3. Consistent with the MS plot: moments of order ≥ 3 are infinite or barely finite. |
| Hill α, devolatilised losses | 3.2 to 4.1, 3.75 ± 0.17 at 2.5% | ∞ | Even after removing volatility clustering, the tail is a power law ([figure](figures/hill.png)). Gains are thinner (α ≈ 5). |
| Zipf plot and mean excess | straight log-log tail; mean excess rises with the threshold | curved; mean excess falls | Both are power-law signatures ([figure](figures/zipf_mean_excess.png)). |
| κ(1,2) | 0.24 | 0 | Daily returns are far from the Gaussian basin; a Student t with α = 3 gives 0.29. |
| κ(1,30) | 0.03 | 0 | Looks Gaussian, but for the wrong reason: see below. |
| Days beyond 5 conditional sigmas | 19 | 0.005 | Under a Gaussian with the right *current* volatility, the expected count over 75 years is 0.005 (one such day per ~14,000 years). There were 19. |
| Return period of 19 Oct 1987 (−22.9%) | power law: ~160 years | 10^114 years | Gaussian risk calls a once-in-a-lifetime day impossible. |

### κ and aggregation

κ(1,n) = 2 − log n / log(M(n)/M(1)), with M(n) the mean absolute deviation of an
n-day sum. It measures how far the MAD of a sum grows faster than √n.

For the S&P 500 κ drops toward 0 after a few days, while the same returns
shuffled (same daily distribution, no volatility clustering) stay at 0.13 to
0.24, like a Student t with α = 3 ([figure](figures/kappa.png)). The reason:
with clustering, sums of many days stay fat-tailed. 30-day sums have kurtosis
7.8 (shuffled: 4.9), and 100-day sums 6.0 (shuffled: 2.8). The ratio MAD/SD
stays near 0.72 at every horizon instead of climbing to the Gaussian 0.798. So
MAD scales like √n (κ ≈ 0), but the shape never becomes Gaussian. Monthly
returns are not safer than daily ones in shape, so "√t scaling of a Gaussian
daily VaR" is wrong twice: wrong daily tail, and no central-limit rescue.

## Risk now

The EWMA sigma forecast for 2 November 2026 is 0.76% per day (last year 0.81%,
since 1950 1.00%): a calm market. The table puts today's sigma through two
models of the standardised loss: a Gaussian, and a power law fitted to the
devolatilised tail (Hill α = 3.75, Weissman extrapolation; expected shortfall
ES = VaR · α/(α−1)).

| one-day level | Gaussian VaR | power-law VaR | ratio | Gaussian ES | power-law ES | ratio |
|---|---|---|---|---|---|---|
| 99% | 1.76% | 2.10% | 1.2x | 2.01% | 2.86% | 1.4x |
| 99.9% | 2.33% | 3.87% | 1.7x | 2.54% | 5.28% | 2.1x |
| 99.99% | 2.81% | 7.16% | 2.6x | 2.99% | 9.77% | 3.3x |

The gap grows the further out you look, which is the book's main point: at the
99% level the Gaussian is only 20% off, and at the 1-in-10,000-days level it
understates the loss by 2.6x and the expected loss beyond it by 3.3x. A low
current sigma does not make the tail thin: 1987 started from an ordinary sigma
and was a 12-sigma day measured against its own EWMA forecast.

### Other indexes, 2015 to 2026

| index | kurtosis | top day's share of 4th moment | α (devol, 2.5%) | EWMA σ now | 99.9% VaR Gaussian / power law |
|---|---|---|---|---|---|
| S&P 500 | 18.9 | 31% | 2.8 ± 0.3 | 0.76% | 2.33% / 5.41% |
| Nasdaq 100 | 10.6 | 24% | 3.2 ± 0.4 | 1.47% | 4.55% / 9.16% |
| Nikkei 225 | 10.7 | 28% | 3.9 ± 0.5 | 1.68% | 5.20% / 8.73% |

Over the last eleven years alone the S&P 500 tail is *fatter* (α ≈ 2.8) than
over the full history, mostly because of March 2020 and April 2025. Fitted on
that window, the 99.9% one-day loss at today's sigma is 2.3 times the Gaussian
number. The Nasdaq 100 and Nikkei 225 are about twice as volatile as the S&P 500
right now, and their tails are fat too.

## Caveats

- α from Hill depends on the threshold; the tables quote 1% to 5% tails and a
  standard error α/√k. A dozen extreme days drive everything in the far tail.
- The EWMA sigma reacts to a crash only after the first bad day.
- The Lindy effect from the book is about lifetimes of things (firms,
  technologies), not daily returns, so it is not computed here.
- Two data sources are GitHub mirrors of Yahoo Finance; FRED and Stooq were not
  reachable from the machine that ran this. The FRED cross-check above is on
  overlapping days.
