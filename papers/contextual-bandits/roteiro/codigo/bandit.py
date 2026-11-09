"""O bandit do repositório, em Python e sem dependência.

Espelha, nome por nome, `lean/ContextualBandit/Policies.lean` e
`haskell/src/ContextualBandit.hs`:

* `argmax` fica com o PRIMEIRO máximo (como `argmaxFrom` em Lean);
* `greedy`, `ucb(beta)`, `eps_greedy(eps)` recebem só as estimativas
  (média, largura) de cada braço e devolvem uma probabilidade por braço;
* o modelo `Tabular` é o `tabular` de `Examples.lean`:
  média = soma / contagem, largura = 1 / (contagem + 1).

Este arquivo existe para o roteiro: cada trecho falado aponta para uma
função daqui. A fonte de verdade continua sendo o Lean.
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field
from fractions import Fraction
from typing import Callable, Hashable


@dataclass(frozen=True)
class Estimate:
    """O que o modelo diz de um (contexto, braço): média prevista e incerteza."""

    mean: Fraction
    width: Fraction


Decision = list[Fraction]  # uma probabilidade por braço; soma 1
DecisionRule = Callable[[list[Estimate]], Decision]


def argmax(scores: list[Fraction]) -> int:
    """Índice do maior valor. Em empate, o primeiro (Lean: `argmaxFrom`)."""
    best = 0
    for i, s in enumerate(scores):
        if scores[best] < s:
            best = i
    return best


def point(k: int, b: int) -> Decision:
    """Toda a probabilidade num braço só (Lean: `point`)."""
    return [Fraction(1) if a == b else Fraction(0) for a in range(k)]


def uniform(k: int) -> Decision:
    """1/K para cada braço (Lean: `uniform`). É a alocação de um teste A/B/n."""
    return [Fraction(1, k)] * k


def mix(w: Fraction, d1: Decision, d2: Decision) -> Decision:
    """w * d1 + (1 - w) * d2 (Lean: `mix`)."""
    return [w * p + (1 - w) * q for p, q in zip(d1, d2)]


def greedy(est: list[Estimate]) -> Decision:
    """Só aproveita: o braço com a maior média (Lean: `greedy`)."""
    return point(len(est), argmax([e.mean for e in est]))


def ucb(beta: Fraction) -> DecisionRule:
    """Otimismo: média + beta * largura (Lean: `ucb β`). Com beta = 0 vira `greedy`."""

    def rule(est: list[Estimate]) -> Decision:
        return point(len(est), argmax([e.mean + beta * e.width for e in est]))

    return rule


def eps_greedy(eps: Fraction) -> DecisionRule:
    """Com probabilidade eps sorteia um braço; senão, `greedy` (Lean: `epsGreedy ε`)."""

    def rule(est: list[Estimate]) -> Decision:
        k = len(est)
        return mix(eps, uniform(k), greedy(est))

    return rule


@dataclass
class Tabular:
    """O modelo de `Examples.lean`: uma (soma, contagem) por (contexto, braço)."""

    k: int
    table: dict[tuple[Hashable, int], tuple[Fraction, int]] = field(default_factory=dict)

    def update(self, context: Hashable, arm: int, reward: Fraction) -> None:
        s, n = self.table.get((context, arm), (Fraction(0), 0))
        self.table[(context, arm)] = (s + reward, n + 1)

    def estimate(self, context: Hashable, arm: int) -> Estimate:
        s, n = self.table.get((context, arm), (Fraction(0), 0))
        mean = Fraction(0) if n == 0 else s / n
        return Estimate(mean, Fraction(1, n + 1))

    def estimates(self, context: Hashable) -> list[Estimate]:
        return [self.estimate(context, a) for a in range(self.k)]


def policy(model: Tabular, rule: DecisionRule, context: Hashable) -> Decision:
    """histórico -> contexto -> distribuição sobre braços (Lean: `policy`)."""
    return rule(model.estimates(context))


def draw(decision: Decision, rng: random.Random) -> int:
    """Sorteia um braço de uma distribuição."""
    u = rng.random()
    acc = Fraction(0)
    for a, p in enumerate(decision):
        acc += p
        if u <= acc:
            return a
    return len(decision) - 1


if __name__ == "__main__":
    # A verificação de `Examples.lean`, em Python: os mesmos números do #eval.
    m = Tabular(3)
    history = [
        ("manha", 0, 0), ("manha", 1, 1), ("manha", 1, 1), ("manha", 2, 0),
        ("noite", 0, 0), ("noite", 1, 0), ("noite", 2, 1),
    ]
    for c, a, r in history:
        m.update(c, a, Fraction(r))
    print("greedy manha ", policy(m, greedy, "manha"), " (Lean: [0, 1, 0])")
    print("greedy noite ", policy(m, greedy, "noite"), " (Lean: [0, 0, 1])")
    print("eps 1/10 manha", policy(m, eps_greedy(Fraction(1, 10)), "manha"),
          " (Lean: [1/30, 14/15, 1/30])")
