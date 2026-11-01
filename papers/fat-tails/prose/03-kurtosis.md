# Kurtosis is decided by one day {#sec:kurtosis}

The usual first check of fat tails is the kurtosis, $E[(X-\mu)^4]/\sigma^4$. A Gaussian has
kurtosis 3. The S&P 500 daily returns since 1950 have kurtosis 28.2. That looks like a clear
answer, but Taleb's point is that the number itself is not reliable when tails are fat.

The fourth power gives the largest days an enormous weight. The single largest day, 19 October
1987, contributes 52% of the sum $\sum r_t^4$. The ten largest days contribute 70%. Remove the one
day and the kurtosis halves, from 28.2 to 14.4. Remove ten days and it falls to 9.8. A statistic
that one observation out of 19,330 can halve does not describe the distribution. It describes the
worst day in the sample.

![Left: kurtosis of each calendar year; the grey line is the Gaussian value 3. Right: kurtosis of
all returns from 1950 up to each date. The jump in October 1987 never washes out.](../fat-tails/figures/kurtosis.png){#fig:kurtosis width=100%}

[@Fig:kurtosis] shows the same instability in time. Year by year, kurtosis ranges from 2.6 (a
Gaussian-looking year) to 57 (1987). The median year has 4.4. The right panel follows the
kurtosis of the whole history as data arrives. It drifts down between shocks, as an estimator
should when the true value is finite. Then a single day lifts it by a factor of ten. After 39 more
years of data it has still not come back to its pre-1987 level. Under a Gaussian the curve would
settle near 3 within a few hundred days.

The lesson is the first of the book: in a fat-tailed sample, a high-order moment tells you more
about the largest observation than about the population. We need tools that look at the tail
directly.
