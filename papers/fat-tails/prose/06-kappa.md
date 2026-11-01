# Does time cure fat tails? {#sec:kappa}

A common defence of Gaussian models is the central limit theorem. Daily returns are fat-tailed,
the argument goes, but monthly returns are sums of about 21 daily ones, so they should be close to
Gaussian. Taleb's $\kappa$ metric tests how fast this happens [@taleb2020scoft]. Let $M(n)$ be the
mean absolute deviation of a sum of $n$ returns. Then

$$\kappa(n_0, n) = 2 - \frac{\log n - \log n_0}{\log \big( M(n) / M(n_0) \big)}.$$

For a Gaussian, $M(n)$ grows like $\sqrt{n}$ and $\kappa = 0$. For a Cauchy distribution
($\alpha = 1$), $M(n)$ grows like $n$, there is no diversification at all, and $\kappa = 1$. Values
in between measure how much more data a fat-tailed process needs to reach the precision that a
Gaussian gives.

![$\kappa(1, n)$ for sums of $n$ days. Blue: S&P 500. Green: the same daily returns in random order,
which keeps their distribution but removes volatility clustering. Orange: a Student $t$ with
$\alpha = 3$.](../fat-tails/figures/kappa.png){#fig:kappa width=90%}

For two-day sums the S&P 500 has $\kappa(1,2) = 0.24$, far outside the Gaussian 90% band of
$[-0.05, 0.05]$ and close to a Student $t$ with $\alpha = 3$ (0.29). [@Fig:kappa] then shows a
surprise. For longer sums the index's $\kappa$ falls towards zero: 0.07 at 10 days, 0.03 at 30 and
0.02 at 100. The shuffled series stays high, between 0.12 and 0.21 at 30 days, as a fat-tailed
independent series should. Read naively, the figure says that monthly S&P 500 returns are nearly
Gaussian.

They are not. [@Tbl:aggregation] looks at the shape of the sums directly.

| days summed | kurtosis | kurtosis, shuffled | MAD/SD | MAD/SD, shuffled |
|---:|---:|---:|---:|---:|
| 1 | 28.2 | 28.2 | 0.668 | 0.668 |
| 2 | 10.2 | 17.2 | 0.711 | 0.706 |
| 10 | 7.5 | 6.1 | 0.736 | 0.746 |
| 30 | 7.8 | 4.9 | 0.722 | 0.771 |
| 100 | 6.0 | 2.8 | 0.726 | 0.804 |

: Shape of $n$-day sums of S&P 500 returns. A Gaussian has kurtosis 3 and MAD/SD $= 0.798$.
"Shuffled" uses the same daily returns in random order. {#tbl:aggregation}

The shuffled sums behave as the central limit theorem says: kurtosis falls to 2.8 at 100 days, and
the ratio of mean absolute deviation to standard deviation climbs to the Gaussian 0.798. The real
sums stop improving. Thirty-day sums keep a kurtosis of 7.8, and the MAD/SD ratio stays near 0.72
at every horizon. Volatility clustering explains this. A bad day tends to arrive with other bad
days, so a month that contains one crash day often contains several, and the monthly return
inherits the fat tail.

This also explains the low $\kappa$. $\kappa$ compares how $M(n)$ grows with $n$. If the shape of
the sum stops changing after a few days, $M(n)$ grows like $\sqrt{n}$ from then on, and
$\kappa(1,n)$ drifts towards zero, although the sums are far from Gaussian. A low $\kappa$ at long
horizons here means "no further convergence", not "already Gaussian". This is the
*preasymptotics* of the book's subtitle: the central limit theorem holds in the limit, and the
limit is out of reach.

The practical consequence is direct. A common practice scales a daily Gaussian VaR by $\sqrt{t}$
to get a $t$-day VaR. That is wrong twice: the daily tail is not Gaussian, and summing days does
not make it Gaussian.
