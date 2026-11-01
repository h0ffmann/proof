# Which moments exist? {#sec:moments}

If kurtosis is unstable, perhaps the fourth moment does not exist. The MS plot tests this without
assuming a model. For independent draws, $R_n^p \to 0$ as $n$ grows if and only if
$E|X|^p < \infty$ [@taleb2020scoft]. When the moment is infinite, new record observations keep
taking a large share of the sum, and the ratio keeps jumping back up.

![MS plot of S&P 500 daily returns for $p = 1$ to 4. Blue: the index. Grey: a Gaussian sample of
the same length. The ratio tends to 0 only if the $p$-th moment is finite.](../fat-tails/figures/ms_plot.png){#fig:ms width=100%}

[@Fig:ms] gives a graded answer. For $p = 1$ the ratio is 0.002 at the end of the sample: the mean
is finite. For $p = 2$ it is 0.027 and falling, with one visible jump in 1987: the variance is
finite but its estimate still moves with single days. For $p = 3$ the ratio is 0.19, and for
$p = 4$ it is 0.52. These do not converge. In the $p = 4$ panel, after 70 years and more than 19,000
observations, one day still holds half of the sum. The Gaussian sample reaches zero within a few
hundred days in every panel.

This pattern is what a power law with tail exponent $\alpha$ between 2 and 4 predicts: moments of
order below $\alpha$ are finite, and moments at or above $\alpha$ are infinite or so heavy that a
sample cannot estimate them. [@Sec:alpha] measures $\alpha$ directly.
