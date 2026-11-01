# Risk on 2 November 2026 {#sec:risk}

We now return to the question of [@Sec:introduction]. Write tomorrow's loss as
$L = \sigma \cdot Z$, where $\sigma = 0.76\%$ is today's volatility forecast and $Z$ is a
standardised loss. The Gaussian model takes $Z \sim N(0,1)$. The fat-tailed model takes the
empirical distribution of the devolatilised losses $z_t$ and extends its tail with a power law of
exponent $\hat\alpha = 3.75$. The Weissman estimator [@weissman1978quantiles] gives the quantile at
exceedance probability $p$ as

$$\hat q_p = X_{(k+1)} \left( \frac{k}{n p} \right)^{1/\hat\alpha},$$

and for a power law the expected shortfall is $\mathrm{ES}_p = \hat q_p \cdot \alpha/(\alpha-1)$.

| one-day level | Gaussian VaR | power-law VaR | ratio | Gaussian ES | power-law ES | ratio |
|---|---:|---:|---:|---:|---:|---:|
| 99% | 1.76% | 2.10% | 1.2 | 2.01% | 2.86% | 1.4 |
| 99.9% | 2.33% | 3.87% | 1.7 | 2.54% | 5.28% | 2.1 |
| 99.99% | 2.81% | 7.16% | 2.6 | 2.99% | 9.77% | 3.3 |

: One-day S&P 500 loss quantiles (VaR) and expected shortfall (ES) at the EWMA volatility forecast
for 2 November 2026 ($\sigma = 0.76\%$). {#tbl:risk}

[@Tbl:risk] contains the paper's main result. At the 99% level the two models nearly agree; the
Gaussian is 20% low. This is why Gaussian VaR survives in practice: it is tested at levels where
it works. At 99.9%, a level that a daily risk report reaches about once in four years, the
Gaussian is 40% too low. At 99.99% the power law gives a loss of 7.2%, 2.6 times the Gaussian
2.8%, and an expected loss beyond that point of 9.8%, 3.3 times the Gaussian. The error grows
with the level because the two tails diverge: the Gaussian falls like $e^{-x^2/2}$, the power law
like $x^{-3.75}$.

The history agrees with the power law. Since 1951, the S&P 500 had 19 days with a loss beyond 5
times the volatility forecast for that day. A Gaussian expects 0.005 such days in 75 years, one per
14,000 years. It had 9 days beyond 6 sigma, where a Gaussian expects $2 \times 10^{-5}$. On raw
returns, the power-law fit gives the 1987 crash a return period of about 160 years: rare, but
inside the span of recorded markets. The Gaussian gives $10^{114}$ years.

A calm reading today does not mean a thin tail. The fat-tailed model already uses today's low
$\sigma$; the extra risk comes from $Z$, not from $\sigma$. A high $\sigma$ does not explain the
worst days either. On the morning of 19 October 1987 the forecast was 1.9%, high (the top 3% of
days since 1950) but far from the 22.9% that followed.

## Three indexes since 2015 {#sec:indexes}

| index | kurt. | top day | $\hat\alpha$ | $\sigma$ | Gauss | power |
|---|---:|---:|---:|---:|---:|---:|
| S&P 500 | 18.9 | 31% | 2.8 ± 0.3 | 0.76% | 2.33% | 5.41% |
| Nasdaq 100 | 10.6 | 24% | 3.2 ± 0.4 | 1.47% | 4.55% | 9.16% |
| Nikkei 225 | 10.7 | 28% | 3.9 ± 0.5 | 1.68% | 5.20% | 8.73% |

: The same diagnostics on January 2015 to October 2026 for three indexes. "Top day" is the largest
day's share of $\sum r^4$; $\hat\alpha$ is the Hill estimate on devolatilised losses at the 2.5%
threshold; $\sigma$ is the EWMA forecast for 2 November 2026; "Gauss" and "power" are the one-day 99.9% VaR under each model.
{#tbl:indexes}

[@Tbl:indexes] repeats the analysis on a common, shorter window. Three points stand out. First,
the S&P 500's tail is *fatter* in the last eleven years than over the full history: $\hat\alpha$
is 2.8 instead of 3.75. March 2020 (four of the six worst days, including $-12.8\%$ on 16 March) and
4 April 2025 ($-6.2\%$) drive this. Fitted on this window, the 99.9% one-day loss at today's
volatility is 5.4%, 2.3 times the Gaussian number. Second, the Nasdaq 100 and the Nikkei 225 are
about twice as volatile as the S&P 500 today, so their Gaussian and power-law numbers are both
higher. Third, all three tails are fat: no index has $\hat\alpha$ above 4, and on all three the
largest single day carries a quarter or more of the fourth moment.

The window matters. Eleven years hold only about 70 days in the top 2.5%, so these $\hat\alpha$
values have standard errors of 0.3 to 0.5. This is itself one of Taleb's points: the tail is the
part of the distribution about which a sample says least.
