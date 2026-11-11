# Decision rules and their distributions {#sec:rules}

**Rules.** For $b \in [K]$ let $\delta_b(a) = 1$ if $a = b$ and $0$ otherwise. Let
$u_K(a) = \iota(K)$ be the uniform decision, and for $\omega \in \mathbb{Q}$ let
$\mathrm{mix}_\omega(d_1, d_2)(a) = \omega\, d_1(a) + (1 - \omega)\, d_2(a)$. The UCB score of an
estimate at scale $\beta \in \mathbb{Q}$ is $s_\beta(m, w) = m + \beta w$. For $K \ge 1$ define
$$g(\mathrm{est}) = \mathrm{argmax}_a\, m_a, \qquad
  \hat a_\beta(\mathrm{est}) = \mathrm{argmax}_a\, s_\beta(\mathrm{est}_a),$$
where $\mathrm{est}_a = (m_a, w_a)$, and the three rules
$$\mathrm{greedy} = \delta_{g}, \qquad \mathrm{ucb}_\beta = \delta_{\hat a_\beta}, \qquad
  \mathrm{eps}_\varepsilon = \mathrm{mix}_\varepsilon(u_K, \delta_{g}).$$
Thompson sampling is greedy on means that the model samples from its posterior. The sample is the
model's job, so the rule is the argmax of [@Sec:setting] and needs no result of its own.

**Lemma 2** (mass). For decisions $d, d_1, d_2$ on $[K]$ and $c, \omega \in \mathbb{Q}$:

(a) $\mathrm{mass}(d_1 + d_2) = \mathrm{mass}(d_1) + \mathrm{mass}(d_2)$ and
$\mathrm{mass}(c\, d) = c\, \mathrm{mass}(d)$;

(b) $\mathrm{mass}(a \mapsto c) = \underline{K}\, c$;

(c) $\mathrm{mass}(\delta_b) = 1$ for every $b \in [K]$;

(d) $\mathrm{mass}(u_K) = 1$ when $K \ge 1$;

(e) $\mathrm{mass}(\mathrm{mix}_\omega(d_1, d_2)) = \omega\, \mathrm{mass}(d_1) + (1 - \omega)\,
\mathrm{mass}(d_2)$.

*Proof.* Each part is an induction on $K$. For $K = 0$ every mass is $0$. For $K + 1$ the list of
values is $d(0)$ followed by the values of $d \circ \mathrm{succ}$ on $[K]$, so
$\mathrm{mass}(d) = d(0) + \mathrm{mass}(d \circ \mathrm{succ})$. Part (a) then follows from
$(x + y) + (z + t) = (x + z) + (y + t)$ and from distributivity. Part (b) follows from
$c + \underline{K} c = (1 + \underline{K}) c$. For (c), induct on $b$: if $b = 0$ the head is $1$
and the tail is the constant $0$, of mass $\underline{K} \cdot 0 = 0$ by (b); if $b = b' + 1$ the
head is $0$ and the tail is $\delta_{b'}$ on $[K]$. Part (d) is (b) with
$c = 1/\underline{K}$, and $\underline{K} \ne 0$ because $\underline{K+1} = 1 + \underline{K}$
and $\underline{K} \ge 0$. Part (e) is (a) twice. \hfill\rule{0.5em}{0.5em}

**Theorem 1** (validity). Let $K \ge 1$ and let $\mathrm{est}$ be any estimate vector.

(a) $\mathrm{greedy}(\mathrm{est})$ is valid.

(b) $\mathrm{ucb}_\beta(\mathrm{est})$ is valid for every $\beta \in \mathbb{Q}$.

(c) $\mathrm{eps}_\varepsilon(\mathrm{est})$ is valid for every $\varepsilon$ with
$0 \le \varepsilon \le 1$.

*Proof.* A point mass $\delta_b$ has values in $\{0, 1\}$ and mass $1$ by Lemma 2(c), which gives
(a) and (b). For (c), each value is $\varepsilon\, \iota(K) + (1 - \varepsilon)\, \delta_g(a)$, a
sum of two products of non-negative numbers: $\varepsilon \ge 0$, $\iota(K) > 0$,
$1 - \varepsilon \ge 0$ and $\delta_g(a) \ge 0$. By Lemma 2(e), (d) and (c) the mass is
$\varepsilon \cdot 1 + (1 - \varepsilon) \cdot 1 = 1$. \hfill\rule{0.5em}{0.5em}

Neither the scale $\beta$ nor the widths need a sign in (b): any argmax gives a point mass.

**Theorem 2** (exploration of $\varepsilon$-greedy). Let $K \ge 1$, $\varepsilon \in \mathbb{Q}$
and $a \in [K]$.

(a) $\mathrm{eps}_\varepsilon(\mathrm{est})(a) = 1 - \varepsilon + \varepsilon/K$ if $a = g(\mathrm{est})$,
and $\varepsilon/K$ otherwise.

(b) If $\varepsilon \le 1$, then $\mathrm{eps}_\varepsilon(\mathrm{est})(a) \ge \varepsilon/K$.

(c) $\mathrm{eps}_1(\mathrm{est})(a) = 1/K$: with $\varepsilon = 1$ the rule is the uniform
allocation of an A/B/$n$ test, whatever the estimates.

*Proof.* (a) The value is $\varepsilon/K + (1 - \varepsilon)\, \delta_g(a)$, and
$\delta_g(a) \in \{0, 1\}$ according to the case. (b) In the second case of (a) the bound is an
equality. In the first case $1 - \varepsilon \ge 0$, so
$\varepsilon/K \le (1 - \varepsilon) + \varepsilon/K$. (c) The value is
$1 \cdot \iota(K) + 0 \cdot \delta_g(a) = \iota(K)$. \hfill\rule{0.5em}{0.5em}

Part (b) needs only $\varepsilon \le 1$; a negative $\varepsilon$ makes the bound weaker but
still true. Part (c) is the sense in which an A/B/$n$ test is a bandit that does not use what it
learns.
