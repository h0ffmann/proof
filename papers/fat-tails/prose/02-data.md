# Data and method {#sec:data}

**Prices.** We use daily closes of the S&P 500 from 3 January 1950 to 30 October 2026, which give
19,330 daily log returns $r_t = \log P_t - \log P_{t-1}$. The data joins two public copies of
Yahoo Finance's `^GSPC` series held on GitHub: one for 1950 to 2014 and one for 2015 to 2026. Both
copies agree with the FRED series `SP500` to eight significant digits on every day where they
overlap (1,001 and 413 days). For comparison we also use the Nasdaq 100 and the Nikkei 225 from
January 2015 to 30 October 2026 (2,974 and 2,888 returns). The data and the script are in the
`fat-tails/` directory of this repository.

**Volatility.** Daily volatility clusters: calm weeks follow calm weeks and wild weeks follow wild
weeks. We estimate the volatility forecast for day $t$ with an exponentially weighted moving
average,

$$\sigma_t^2 = \lambda\,\sigma_{t-1}^2 + (1-\lambda)\,r_{t-1}^2, \qquad \lambda = 0.94,$$

the RiskMetrics convention. The *devolatilised* return $z_t = r_t / \sigma_t$ removes most of the
clustering. The tail estimators in [@Sec:alpha] assume independent observations, so they are more
reliable on $z_t$ than on $r_t$. We drop the first 250 days of $z_t$ as a burn-in.

**Diagnostics.** We compute the metrics of [@taleb2020scoft] that apply to a single return
series:

- the kurtosis and the share of the fourth moment that comes from the largest observations;
- the max-to-sum (MS) ratio $R_n^p = \max_{i \le n} |X_i|^p / \sum_{i \le n} |X_i|^p$ for
  $p = 1, \dots, 4$;
- the Hill estimator of the tail exponent $\alpha$ [@hill1975tail] across thresholds, with the
  Zipf (log-log survival) and mean-excess plots;
- Taleb's $\kappa$ metric, which measures how fast sums approach the Gaussian;
- value at risk (VaR) and expected shortfall (ES) under a Gaussian and under a power-law tail
  fitted with the Weissman extrapolation [@weissman1978quantiles].

The book also discusses the Lindy effect. Lindy concerns the life expectancy of things such as
firms and technologies, not daily returns, so we leave it out.
