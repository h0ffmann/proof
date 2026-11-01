# What this study cannot say {#sec:discussion}

The diagnostics agree with each other. Kurtosis is unstable ([@Sec:kurtosis]), the third and
fourth moments do not converge ([@Sec:moments]), the left tail is a power law with $\alpha$ near 3
([@Sec:alpha]), and summing days does not make returns Gaussian ([@Sec:kappa]). At today's
volatility, the Gaussian understates the 1-in-10,000-day loss by a factor of 2.6 and the expected
loss beyond it by 3.3 ([@Sec:risk]). The study has five limits.

1. **The threshold of Hill.** $\hat\alpha$ depends on $k$. We report a range (1% to 5% of days)
   and a standard error, but a dozen extreme days drive the far tail. Fitting at the 1% or the 5%
   threshold instead of 2.5% gives $\hat\alpha = 4.0$ or 3.2, and moves the 99.99% VaR from 7.2%
   to 6.7% or 9.0%. Every choice stays at least 2.3 times the Gaussian 2.8%.
2. **The volatility model.** EWMA with $\lambda = 0.94$ is simple. It reacts to a crash only after
   the first bad day, and it does not model leverage (volatility rises more after falls than after
   gains). A GARCH-type model would change the devolatilised tail slightly.
3. **One-day horizon.** [@Tbl:risk] covers one day. [@Sec:kappa] shows why $\sqrt{t}$ scaling of
   these numbers to longer horizons is not valid. Longer horizons need their own tail fit.
4. **Data.** The prices come from two GitHub copies of Yahoo Finance. They agree with FRED on the
   days we could check, but we did not check every day before 2015. Closing prices miss intraday
   losses.
5. **Not a forecast.** The numbers describe the size of a rare loss, not its timing. A power-law
   tail says that a 7% day is a 1-in-10,000-day event at today's volatility. It does not say when.

The central claim does not depend on these choices. Every Hill estimate in this paper, for every
index, threshold and window, lies between 2.4 and 4.4. In that range a Gaussian understates the
far tail by a factor of two or more.

# Statements {.unnumbered}

**Not investment advice.** This is an educational study of statistical methods. It does not
recommend any trade or position.

**Use of AI.** Claude (Anthropic), an AI assistant, wrote the analysis code, ran it, and drafted
this text at the author's request. The author is responsible for the content.

**Reproducibility.** `python3 fat-tails/python/fat_tails.py` regenerates every number, table and
figure from the CSV files in `fat-tails/data/`.
