# Setting {#sec:setting}

Fix a number of arms $K \in \mathbb{N}$ and write $[K] = \{0, 1, \dots, K - 1\}$. All
quantities are rationals.

**Estimates and models.** An *estimate* is a pair $e = (m, w) \in \mathbb{Q}^2$, a mean and a
width. A *reward model* over contexts $C$ with belief space $B$ is a triple
$(b_0, u, \hat e)$: a prior $b_0 \in B$, an update $u : B \times (C \times [K] \times \mathbb{Q})
\to B$, and an estimator $\hat e : B \times C \times [K] \to \mathbb{Q}^2$. The *posterior* of a
history $h = (o_1, \dots, o_n)$ is the left fold
$$\mathrm{post}(h) = u(\cdots u(u(b_0, o_1), o_2) \cdots, o_n).$$

**Decisions and rules.** A *decision* is a function $d : [K] \to \mathbb{Q}$. Its *mass* is
$$\mathrm{mass}(d) = \sum_{a \in [K]} d(a),$$
defined as the right fold of $+$ over the list $d(0), \dots, d(K-1)$. A decision is *valid* when
$d(a) \ge 0$ for every $a$ and $\mathrm{mass}(d) = 1$. A *decision rule* is a function from
estimate vectors $\mathrm{est} : [K] \to \mathbb{Q}^2$ to decisions. The *policy* of a model and a
rule is
$$\pi(h, c) = \mathrm{rule}\bigl(a \mapsto \hat e(\mathrm{post}(h), c, a)\bigr).$$

The type of a rule is the boundary of [@Sec:introduction]. A rule cannot read the context or the
history, because it does not receive them.

**The number $K$ as a rational.** Write $\underline{K}$ for $K$ as a rational, defined by
$\underline{0} = 0$ and $\underline{K+1} = 1 + \underline{K}$, and let
$\iota(K) = 1/\underline{K}$ for $K \ge 1$ and $\iota(0) = 0$. The recursive definition makes the
sums of [@Sec:rules] go by induction on $K$ with no cast between $\mathbb{N}$ and $\mathbb{Q}$.

**Argmax.** For a score $f : A \to \mathbb{Q}$ define
$$\mathrm{pick}_f(b, a) = \begin{cases} a & \text{if } f(b) < f(a), \\ b & \text{otherwise,}
\end{cases}$$
and, for a start $b$ and a list $\ell$, the left fold
$\mathrm{argmax}_f(b, [\,]) = b$ and
$\mathrm{argmax}_f(b, a :: \ell) = \mathrm{argmax}_f(\mathrm{pick}_f(b, a), \ell)$. For
$K \ge 1$ let $\mathrm{argmax}\, f = \mathrm{argmax}_f(0, [0, 1, \dots, K - 1])$. The running best
changes only on a strict increase, so ties go to the smallest index. This is a definition, and
the implementation copies it.

**Lemma 1** (argmax). Let $K \ge 1$ and $f : [K] \to \mathbb{Q}$.

(a) $f(a) \le f(\mathrm{argmax}\, f)$ for every $a \in [K]$.

(b) The result of $\mathrm{argmax}_f(b, \ell)$ is $b$ or an element of $\ell$.

(c) If $f(a) = g(a)$ for every $a$, then $\mathrm{argmax}\, f = \mathrm{argmax}\, g$.

*Proof.* Two facts about one step come first: $f(b) \le f(\mathrm{pick}_f(b, a))$ and
$f(a) \le f(\mathrm{pick}_f(b, a))$. Both follow by cases on $f(b) < f(a)$; in the second case
the negation gives $f(a) \le f(b)$ because the order on $\mathbb{Q}$ is total. By induction on
$\ell$ and transitivity, the fold never decreases the score of its start:
$f(b) \le f(\mathrm{argmax}_f(b, \ell))$. Now let $a \in \ell$, so $\ell = \ell_1 \mathbin{+\!\!+}
a :: \ell_2$. By induction on $\ell_1$, $f(a) \le f(\mathrm{pick}_f(b', a)) \le
f(\mathrm{argmax}_f(\mathrm{pick}_f(b', a), \ell_2))$ for the running best $b'$ when $a$ is
reached. Every $a \in [K]$ is in the list $[0, \dots, K - 1]$, which gives (a). Part (b) is an
induction on $\ell$ with the fact that $\mathrm{pick}_f(b, a) \in \{b, a\}$. For (c), each step
compares the same two numbers under $f$ and $g$, so the two folds take the same branch at each
element; induct on $\ell$. \hfill\rule{0.5em}{0.5em}

Part (c) is stated pointwise because the proof assistant runs without function
extensionality ([@Sec:mechanisation]). The same holds for the equalities of decisions below:
two decisions are equal when they agree at every arm.
