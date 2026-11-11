# Rules built from the decision layer {#sec:composite}

Two procedures that look different from a bandit are decision rules of [@Sec:rules].

**Explore-then-commit.** An A/B/$n$ test allocates uniformly until a horizon $H$ and then commits
to the arm with the best estimate. As a rule at time $t$,
$$\mathrm{etc}_{H,t} = \begin{cases} \mathrm{eps}_1 & \text{if } t < H, \\ \mathrm{eps}_0 &
\text{otherwise.} \end{cases}$$

**Proposition 7** (explore-then-commit). Let $K \ge 1$, $H, t \in \mathbb{Q}$ and $a \in [K]$.

(a) $\mathrm{eps}_0(\mathrm{est})(a) = \mathrm{greedy}(\mathrm{est})(a)$.

(b) If $t < H$ then $\mathrm{etc}_{H,t}(\mathrm{est})(a) = 1/K$; otherwise
$\mathrm{etc}_{H,t}(\mathrm{est})(a) = \mathrm{greedy}(\mathrm{est})(a)$.

(c) $\mathrm{etc}_{H,t}(\mathrm{est})$ is valid.

*Proof.* (a) $0 \cdot \iota(K) + (1 - 0)\, \delta_g(a) = \delta_g(a)$. (b) By cases on $t < H$,
with Theorem 2(c) in the first case and (a) in the second. (c) By cases, with Theorem 1(c) at
$\varepsilon = 1$ and at $\varepsilon = 0$. \hfill\rule{0.5em}{0.5em}

Explore-then-commit is analysed as a bandit algorithm in its own right
[@lattimore2020bandit, Chapter 6]; Proposition 7 says only that it needs no new decision rule.

**Nested selection of $\varepsilon$.** An outer agent with $M \ge 1$ arms holds one candidate
value $\varepsilon_i$ per arm, and selects among them with $\mathrm{eps}_{\varepsilon_0}$ on its
own estimates. The inner agent then runs $\mathrm{eps}_{\varepsilon_i}$ on $K \ge 1$ arms.

**Proposition 8** (nested selection). Let $0 \le \varepsilon_0 \le 1$ and
$0 \le \varepsilon_i \le 1$ for every $i \in [M]$. Then the outer decision is valid, every
inner decision is valid, and every candidate $i$ has outer probability at least
$\varepsilon_0/M$.

*Proof.* Theorem 1(c) on $[M]$ and on $[K]$, and Theorem 2(b) on $[M]$. \hfill\rule{0.5em}{0.5em}

Both propositions hold for every $K$ and $M$. They are short because the rules compose: a
procedure that is built from valid rules by case analysis or nesting stays valid.
