# Maximisers and the optimism lemma {#sec:optimism}

**Theorem 3** (maximisers). Let $K \ge 1$.

(a) $m_a \le m_{g(\mathrm{est})}$ for every arm $a$.

(b) $s_\beta(\mathrm{est}_a) \le s_\beta(\mathrm{est}_{\hat a_\beta(\mathrm{est})})$ for every
arm $a$ and every $\beta$.

(c) $\mathrm{ucb}_0(\mathrm{est})(a) = \mathrm{greedy}(\mathrm{est})(a)$ for every arm $a$.

*Proof.* (a) and (b) are Lemma 1(a) for the scores $a \mapsto m_a$ and
$a \mapsto s_\beta(\mathrm{est}_a)$. For (c), $s_0(m, w) = m + 0 \cdot w = m$ at every arm, so
Lemma 1(c) gives $\hat a_0 = g$ and the two point masses coincide. \hfill\rule{0.5em}{0.5em}

Let $\mu : [K] \to \mathbb{Q}$ be the true mean rewards in the current context. The estimates are
*calibrated at scale $\beta$* when
$$m_a - \beta w_a \le \mu_a \le m_a + \beta w_a \qquad \text{for every } a \in [K].$$
They are *$\delta$-accurate* when $m_a - \delta \le \mu_a \le m_a + \delta$ for every $a$.

**Theorem 4** (optimism lemma). Let $K \ge 1$ and $\beta \in \mathbb{Q}$. If the estimates are
calibrated at scale $\beta$ and $\hat a = \hat a_\beta(\mathrm{est})$, then for every arm $a$
$$\mu_a \le \mu_{\hat a} + 2 \beta w_{\hat a}.$$

*Proof.* Write $x = \beta w_{\hat a}$. Then
$$\mu_a \le m_a + \beta w_a \le m_{\hat a} + x = (m_{\hat a} - x) + 2x \le \mu_{\hat a} + 2x.$$
The first step is the upper half of calibration at $a$. The second is Theorem 3(b). The equality
is ring arithmetic. The last step is the lower half of calibration at $\hat a$, with $2x$ added
to both sides. \hfill\rule{0.5em}{0.5em}

The proof never uses the sign of $\beta$ or of the widths. Calibration itself forces
$\beta w_a \ge 0$, since it asks for $m_a - \beta w_a \le m_a + \beta w_a$.

**Theorem 5** (greedy under an accurate model). Let $K \ge 1$ and $\delta \in \mathbb{Q}$. If the
estimates are $\delta$-accurate and $g = g(\mathrm{est})$, then $\mu_a \le \mu_g + 2\delta$ for
every arm $a$.

*Proof.* $\mu_a \le m_a + \delta \le m_g + \delta = (m_g - \delta) + 2\delta \le \mu_g + 2\delta$,
by accuracy at $a$, Theorem 3(a), ring arithmetic and accuracy at $g$. \hfill\rule{0.5em}{0.5em}

**Remark** (where the lemma enters a regret bound). Let rounds $t = 1, \dots, T$ have true means
$\mu^{(t)}$, estimates calibrated at scale $\beta_t$, and UCB arms $A_t$. Theorem 4 applied to a
best arm gives the instantaneous regret
$r_t = \max_a \mu^{(t)}_a - \mu^{(t)}_{A_t} \le 2 \beta_t w^{(t)}_{A_t}$, so
$$\sum_{t=1}^{T} r_t \le 2 \sum_{t=1}^{T} \beta_t\, w^{(t)}_{A_t}$$
on the event that calibration holds in every round. This sum over rounds is a direct consequence
and is not part of the mechanised statements. For LinUCB with a Bayesian linear model the width
is $w = \sigma \lVert x \rVert_{V^{-1}}$, and the proof of Lattimore and Szepesvári's Theorem
19.2 uses this step in the form of their Eq. (19.10) [@lattimore2020bandit]. To finish a regret
bound one needs (i) a probability of at least $1 - \delta$ for the calibration event in every
round, and (ii) a bound on the sum of widths, their Lemma 19.4. Neither is proved here.

**Theorem 6** (the model is the only channel). Let $(b_0, u, \hat e)$ be a reward model and
$\mathrm{rule}$ any decision rule. If two histories have the same posterior,
$\mathrm{post}(h_1) = \mathrm{post}(h_2)$, then $\pi(h_1, c)(a) = \pi(h_2, c)(a)$ for every
context $c$ and arm $a$.

*Proof.* $\pi(h, c) = \mathrm{rule}(a \mapsto \hat e(\mathrm{post}(h), c, a))$ depends on $h$
only through $\mathrm{post}(h)$; apply congruence. \hfill\rule{0.5em}{0.5em}

The proof is one line because the content is in the types: a rule receives estimates and nothing
else. Theorem 6 is what lets a change of model leave Theorems 1 to 5 untouched, and the reverse.
