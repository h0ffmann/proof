# Introduction {#sec:introduction}

A contextual bandit receives a context, selects one of $K$ arms, observes a reward for that arm
only, and updates what it knows. @li2010contextual applied this model to news recommendation with LinUCB, an
upper confidence bound (UCB) rule over a linear reward model. UCB for finitely many arms goes back at least to the finite-time analysis of
@auer2002finite.

Most implementations mix two concerns in one loop: the statistics that estimate each arm, and
the rule that turns those estimates into a choice. We separate them. A *reward model* keeps a
belief, updates it with each observation, and reports for each context and arm an estimate
$(m, w)$: a predicted mean $m$ and an uncertainty width $w$. A *decision rule* sees only the
vector of estimates and returns a probability for each arm. It sees neither the context nor the
history.

This separation makes the decision layer a small, closed object. Its statements are about finite
vectors of rationals, so they can be proved exactly and for every $K$, with no probability theory.
The probabilistic part of a regret analysis then reduces to two questions about the model: is it
calibrated, and how fast do its widths shrink?

**Contribution.** We prove twelve results about the decision layer, for every $K \ge 1$ and
every rational estimate ([@Sec:rules; @Sec:optimism]), and two propositions about rules built
from it ([@Sec:composite]). The twelve results are:

1. greedy, UCB and $\varepsilon$-greedy with $0 \le \varepsilon \le 1$ return probability
   distributions (three results);
2. $\varepsilon$-greedy gives the greedy arm exactly $1 - \varepsilon + \varepsilon/K$ and every
   other arm $\varepsilon/K$; so every arm has at least $\varepsilon/K$, and $\varepsilon = 1$ is
   the uniform allocation of an A/B/$n$ test (three results);
3. greedy and UCB select a maximiser of their score, and UCB with $\beta = 0$ is greedy (three
   results);
4. the optimism lemma: on the calibration event, the arm that UCB selects loses at most
   $2\beta w$ against any arm; the same bound with $2\delta$ holds for greedy under a
   $\delta$-accurate model (two results);
5. the policy depends on the history only through the model's belief (one result).

Each result has a written proof here and a machine-checked proof in Agda [@agda2025safe]. The
Agda files are the specification of the repository that holds this paper, and a Haskell
implementation follows them name for name ([@Sec:mechanisation]).

**Scope.** The results are deterministic. The optimism lemma is the step of a UCB or LinUCB
regret proof that holds in every round on the calibration event; @lattimore2020bandit [Eq. (19.10)] write it as one line of
the proof of their LinUCB bound. The two
other steps of that proof are probabilistic: calibration holds for all rounds with probability
at least $1 - \delta$, and the sum of the widths grows like $\sqrt{dT \log T}$ (the elliptical
potential lemma, [@lattimore2020bandit, Lemma 19.4]). We do not prove either step
([@Sec:discussion]). The theorems are about exact rationals; they say nothing about rounding in
the floating-point implementation.

**Related work.** @degenne2026leanbandits leads a Lean formalisation of stochastic multi-armed bandits, which addresses the probabilistic side that we leave open. Our
contribution is narrower: a decision layer that is closed under the model boundary, proved for
every $K$, and mirrored by running code.
