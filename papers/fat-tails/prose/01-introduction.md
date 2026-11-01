# A calm Friday {#sec:introduction}

On Friday 30 October 2026 the S&P 500 closed at 7,580. Its volatility forecast for the next
trading day was 0.76%. That is lower than the average since 1950, which is 1.00%. A risk desk
that trusts the Gaussian distribution reads this as good news. With $\sigma = 0.76\%$, a 1-in-100
day costs 1.8%, a 1-in-1,000 day costs 2.3%, and a 1-in-10,000 day costs 2.8%. On that reading, a
3% daily loss happens about once in a century.

The same index fell 22.9% on Monday 19 October 1987. Measured against the volatility forecast it
had that morning, the fall was a 12-sigma event. A Gaussian assigns a 12-sigma loss a probability
near $10^{-33}$. A Gaussian with the full-sample volatility puts the return period of that day at
$10^{114}$ years. The universe is about $1.4 \times 10^{10}$ years old.

Taleb's *Statistical Consequences of Fat Tails* [@taleb2020scoft] argues that this is not bad luck
but the wrong model. In a fat-tailed world, rare events dominate the statistics. The sample mean,
variance and kurtosis converge slowly or not at all. Risk numbers fitted to the body of the
distribution are blind to the tail. The book gives a set of diagnostics that test these claims on
data. This paper applies them to the S&P 500 and asks one practical question:

> **How wrong is a Gaussian risk number for the S&P 500 today?**

We follow the diagnostics in the order that a sceptical reader would ask for them.
[@Sec:data] describes the data. [@Sec:kurtosis] shows that kurtosis, the usual "fatness" number,
is decided by one day. [@Sec:moments] asks which moments exist at all. [@Sec:alpha] measures the
tail exponent. [@Sec:kappa] asks whether summing days makes the problem go away.
[@Sec:risk] turns the tail into risk numbers for today and compares three indexes.
[@Sec:discussion] lists what the study cannot say.
