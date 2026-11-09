"""Trecho 1 do roteiro (o gancho): crença atual contra crença nova.

Um agente tem uma crença sobre cada opção: "esta resposta agrada em 70 % das
vezes". O usuário manda um sinal (gostou / não gostou). O agente atualiza a
crença. É o `update` de um `RewardModel` (`lean/ContextualBandit/Interface.lean`),
com o modelo Beta-Bernoulli de `haskell/src/Models.hs` (`betaBernoulli`).

A pergunta do gancho é: a crença NOVA, com o sinal do usuário, ainda escolhe a
mesma opção que a crença ATUAL? Se não, o agente muda. Esse é o mecanismo de
decisão com estrutura de recompensa que um ciclo de automelhoria usa.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from bandit import argmax


@dataclass(frozen=True)
class Crenca:
    """Beta(alpha, beta): alpha = 1 + sucessos, beta = 1 + fracassos."""

    alpha: float = 1.0
    beta: float = 1.0

    def atualizar(self, recompensa: float) -> "Crenca":
        """`update` do Beta-Bernoulli: alpha += r, beta += 1 - r."""
        return Crenca(self.alpha + recompensa, self.beta + 1 - recompensa)

    @property
    def media(self) -> float:
        return self.alpha / (self.alpha + self.beta)

    @property
    def largura(self) -> float:
        """Desvio-padrão da posteriori, como em `Models.hs`."""
        n = self.alpha + self.beta
        return math.sqrt(self.alpha * self.beta / (n * n * (n + 1)))


def escolha(crencas: list[Crenca]) -> int:
    """A regra gulosa sobre as médias (Lean: `greedy`)."""
    return argmax([c.media for c in crencas])


if __name__ == "__main__":
    # Duas respostas possíveis de um agente: curta (0) e longa (1).
    atual = [Crenca(8, 4), Crenca(6, 6)]  # a crença de hoje: a curta agrada mais
    print("crença atual  ", [f"{c.media:.2f}±{c.largura:.2f}" for c in atual],
          "-> escolhe", escolha(atual))
    # O usuário de hoje gostou 4 vezes da longa e não gostou 2 vezes da curta.
    nova = list(atual)
    for _ in range(4):
        nova[1] = nova[1].atualizar(1.0)
    for _ in range(2):
        nova[0] = nova[0].atualizar(0.0)
    print("crença nova   ", [f"{c.media:.2f}±{c.largura:.2f}" for c in nova],
          "-> escolhe", escolha(nova))
    print("mudou de ideia?", escolha(atual) != escolha(nova))
