# A multiplicative joint model: competitive shares {#sec:shares}

The additive step of [@Sec:gain] corrects independent forecasts after the fact. A second way to
estimate a slot's channels together is to build the joint structure into the model. The Joint
Competitive Share (JCS) model does this. It forecasts the pool $\hat P$ of the slot and splits it
between the $C$ channels and the outside audience with a multinomial logit, the standard model of
choice between differentiated products [@berry1994estimating]:

$$\hat A_c = \hat P\, s_c, \qquad s_c = \frac{w_c}{1 + \sum_{k=1}^{C} w_k}, \qquad
s_0 = \frac{1}{1 + \sum_{k=1}^{C} w_k}, \qquad w_c = \exp(u_c) .$$ {#eq:jcs}

The utility $u_c$ of a channel depends on its own programme and on its rivals' line-up. Viewing
choice models of this kind go back to the audience flow model of Rust and Alpert
[@rust1984audience]. The neurosymbolic variant adds a small network to a linear utility,
$u_c = \beta^\top z_c + b + v^\top \sigma(W z_c + b_1)$, and keeps [@eq:jcs] unchanged.

For every list of weights $w_k \ge 0$ and every pool forecast $\hat P \ge 0$, the following hold.
Each is a line or two of algebra on [@eq:jcs], and each is proved in Agda.

| Property | Statement |
|---|---|
| Accounting | $\sum_c \hat A_c + \hat P s_0 = \hat P$: channels and outside add up to the pool forecast |
| Coherence | $\sum_c s_c < 1$, so $\sum_c \hat A_c \le \hat P$ in every slot |
| Odds | $s_c / s_0 = w_c$, so the log-odds of a channel against the outside is its utility |
| IIA | $s_a w_b = s_b w_a$: the ratio of two shares does not depend on the rivals |
| A new rival | adding a channel with weight $r \ge 0$ never raises another channel's share |
| Own and cross | a larger $w_a$ raises $s_a$ and lowers every rival's share |
| Diversion | when channel $a$ leaves, every other share becomes $s_b / (1 - s_a)$ |
| Inversion | every vector of shares with $\sum_c s_c < 1$ is fitted exactly by $w_c = s_c / (1 - \sum_k s_k)$ |
| Nesting | the neurosymbolic utility with $v = 0$ is the linear one, and with $\lvert\sigma\rvert \le 1$ it differs from it by at most $\sum \lvert v_j \rvert$ |

: Properties of the share model, for every slot. {#tbl:jcs}

*Proof of diversion.* Write $D = 1 + \sum_k w_k$ and $D_{-a} = D - w_a$. The share of $b$ without
$a$ is $w_b / D_{-a}$. With $a$, $s_b = w_b / D$ and $1 - s_a = D_{-a}/D$, so
$s_b / (1 - s_a) = w_b / D_{-a}$.

**The two joint steps are different.** JCS is joint by construction: its forecasts are coherent
with $\hat P$ for every set of utilities, which the fitted logit and network inherit. But it is
multiplicative: it scales shares, it does not shift forecasts by a common amount, so Theorem 2 is
not a statement about it. Conversely, the additive step can move a forecast below zero, which a
share model never does. [@Sec:benchmark] measures the additive step; JCS itself is measured in the
earlier preprint, with the numbers quoted there. A gain identity for the multiplicative
split, in the style of [@eq:gain], is open.
