# How fat is the tail? {#sec:alpha}

A power-law tail has the form $P(L > x) \approx C x^{-\alpha}$ for large losses $L$. The exponent
$\alpha$ is the one number that matters: the smaller it is, the fatter the tail. Moments of order
$p \ge \alpha$ are infinite. A Gaussian has no finite $\alpha$; its tail falls faster than any
power.

The Hill estimator [@hill1975tail] takes the $k$ largest losses
$X_{(1)} \ge \dots \ge X_{(k+1)}$ and returns

$$\hat\alpha_k = \left( \frac{1}{k} \sum_{i=1}^{k} \log X_{(i)} - \log X_{(k+1)} \right)^{-1}.$$

Its weakness is the choice of $k$. Too few points give noise, too many reach into the body of the
distribution, where the power law does not hold. Taleb's advice is to plot $\hat\alpha_k$ against
$k$ and look for a stable region.

![Hill estimate of the left-tail exponent as a function of the share of days used. Orange: raw
daily losses. Blue: losses divided by the EWMA volatility forecast. The grey band marks
$2 \le \alpha \le 4$.](../fat-tails/figures/hill.png){#fig:hill width=100%}

[@Fig:hill] shows both versions. On raw losses, $\hat\alpha$ is 3.1 at the top 1% of days, 2.8
at 2.5% and 2.7 at 5%. On devolatilised losses it is higher, 4.0, 3.7 and 3.2, because dividing
by $\sigma_t$ removes the extra fatness that volatility clustering creates. Between the 1% and 5%
thresholds the devolatilised estimate stays between 3.2 and 4.1. We use $\hat\alpha = 3.75$ at the
2.5% threshold ($k = 477$, standard error $\alpha/\sqrt{k} = 0.17$). The right tail (gains) is
thinner, with $\hat\alpha \approx 5$: the S&P 500 falls faster than it rises.

Both estimates agree with the MS plot. With $\alpha$ near 3, the variance exists, the third
moment is borderline, and the fourth is infinite.

![Left: Zipf plot of devolatilised losses, log of the survival probability against log of the loss.
A power law is a straight line; the Gaussian (grey) bends down and vanishes near 4 sigma. Right:
mean excess $E[L - u \mid L > u]$. It falls for a thin tail and rises for a power law.](../fat-tails/figures/zipf_mean_excess.png){#fig:zipf width=100%}

[@Fig:zipf] shows the same fact in two pictures that need no estimator. In the Zipf plot, the
index follows the Gaussian up to about 1.5 sigma. Beyond that point the data keeps a straight
line on log-log axes, out past 12 sigma, while the Gaussian curve drops off the chart before 5
sigma. The mean-excess plot is the clearest test for a non-specialist. For a Gaussian, the further
past a threshold you already are, the less extra loss you should expect: the grey curve falls.
For the S&P 500 the curve turns up after 2 sigma. Once a day is bad, the expected extra loss
*grows* with how bad it already is. That is the defining behaviour of a fat tail, and it is the
behaviour that a risk model must capture.
