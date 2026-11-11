# The gain identity {#sec:gain}

Every statement of this section holds for every slot with $C \ge 1$ rows of exact rationals, and
needs no assumption other than the one it names. [@Sec:mechanisation] gives the Agda name of each.

**Lemma 1 (coherence).** The joint forecasts add up to the pool forecast: $\sum_i f'_i = p$.

*Proof.* $\sum_i f'_i = F - C k = F - (F - p) = p$.

**Theorem 2 (gain identity).** For every slot,

$$C \,(\mathrm{SSE} - \mathrm{SSE}') = S^2 - \varepsilon^2 .$$ {#eq:gain}

*Proof.* The joint error of row $i$ is $e'_i = f'_i - y_i = e_i - k$. Expand the square and sum:
$\mathrm{SSE}' = \mathrm{SSE} - 2k \sum_i e_i + C k^2$. The errors add up to the bias,
$\sum_i e_i = F - T = S$, and the step is $k = (F - p)/C = (S - \varepsilon)/C$, because
$F - p = (F - T) - (p - T)$. So

$$C(\mathrm{SSE} - \mathrm{SSE}') = 2CkS - C^2k^2 = 2(S - \varepsilon)S - (S - \varepsilon)^2 = S^2 - \varepsilon^2 .$$

The identity is exact. It does not bound the gain; it gives it. The joint step trades the
group's bias $S$ for the pool model's error $\varepsilon$, and the trade is worth
$(S^2 - \varepsilon^2)/C$ in squared error. Everything that follows is a consequence.

**Corollary 3 (when it gains).** If $|\varepsilon| \le |S|$, then $\mathrm{SSE}' \le
\mathrm{SSE}$. If $|\varepsilon| < |S|$, then $\mathrm{SSE}' < \mathrm{SSE}$. If
$|\varepsilon| > |S|$, then $\mathrm{SSE}' > \mathrm{SSE}$.

*Proof.* $C > 0$, and $|\varepsilon| \le |S|$ is the same as $\varepsilon^2 \le S^2$. Apply
[@eq:gain].

The condition is a comparison of two numbers of the slot: the pool forecast must be no further
from the actual total than the sum of the independent forecasts. It is not a statement about a
distribution, and it is not guaranteed by any model. It is a measurement, and [@Sec:benchmark]
makes it. A two-row example shows that it is needed. With actual audiences $(1, 1)$, forecasts
$(2, 1)$ and $p = 4$, we have $S = 1$ and $\varepsilon = 2$, and the joint step raises the SSE
from $1$ to $5/2$.

**Corollary 4 (known pool).** With the actual pool, $p = T$, every slot with $S \ne 0$ gains:
$\mathrm{SSE}' = \mathrm{SSE} - S^2/C < \mathrm{SSE}$.

*Proof.* $\varepsilon = 0$ in [@eq:gain].

**Corollary 5 (common bias).** Suppose that every row is over-forecast by at least
$\delta \ge 0$, $e_i \ge \delta$, and that $|\varepsilon| \le \eta$. Then
$C(\mathrm{SSE} - \mathrm{SSE}') \ge (C\delta)^2 - \eta^2$. With an exact pool, the gain is at
least $C \delta^2$.

*Proof.* $S = \sum_i e_i \ge C\delta \ge 0$, so $S^2 \ge (C\delta)^2$, and $\varepsilon^2 \le
\eta^2$. Apply [@eq:gain].

This is the case of a big show. A big show on one channel takes viewers that the rivals' own
models do not see, so every rival is over-forecast. The common part of that error is a bias
$\delta$ on every row. The bound $C\delta^2$ grows with the square of the bias and with the
number of rows, which is the number of channels that contest the slot.

**Proposition 6 (no channel worse, in a band).** Take the actual pool, $p = T$. Suppose that every
error lies in a band $[\ell, h]$ with $0 \le \ell$ and $h \le 2\ell$. Then no row's absolute
error grows: $|e'_i| \le |e_i|$ for every $i$.

*Proof.* With $p = T$ the step is the mean error, $k = S/C$, so $\ell \le k \le h$. For a row
with $e_i \in [\ell, h]$ we have $0 \le k$ and $k \le h \le 2\ell \le 2e_i$, so
$-e_i \le e_i - k \le e_i$, and $|e_i - k| \le e_i = |e_i|$.

Without a band, one row can get worse while the total gets better. With actual audiences
$(1, 1)$, forecasts $(1, 3)$ and $p = 2$, the SSE falls from $4$ to $2$, but the first row goes
from error $0$ to error $-1$. Theorem 2 is about the slot, not about each channel.

**Proposition 7 (cost).** Let the methods cost $c_{\text{alone}}$ and $c_{\text{joint}}$, in the
unit of squared error. If $C(c_{\text{joint}} - c_{\text{alone}}) \le S^2 - \varepsilon^2$, then
$\mathrm{SSE}' + c_{\text{joint}} \le \mathrm{SSE} + c_{\text{alone}}$.

*Proof.* Divide the hypothesis by $C$ and use [@eq:gain].

**Proposition 8 (many slots).** Over a finite list of slots, each with its own pool forecast,
if every slot has $|\varepsilon| \le |S|$, then the total SSE of the joint step is at most the
total SSE alone.

*Proof.* Add Corollary 3 over the slots, by induction on the list.

Proposition 8 needs the condition on every slot. Its converse fails: a total can gain while some
slots lose. The measured total of [@Sec:benchmark] is the sum of [@eq:gain] over all slots,
gains and losses together.

**The worked example.** Three channels with actual audiences $(3, 2, 1)$ and a big show that no
model saw: each is over-forecast by one, $f = (4, 3, 2)$, so $S = 3$ and SSE $= 3$. With the
actual pool, $p = 6$, the joint step returns $(3, 2, 1)$ exactly. With a pool forecast of 7,
$\varepsilon = 1$, and the joint SSE is $1/3$: indeed $3\,(3 - 1/3) = 8 = 3^2 - 1^2$.
