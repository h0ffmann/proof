"""Trecho 3.2 do roteiro: o nome, letra por letra.

C-M-A-B = Contextual Multi-Armed Bandit.

* Bandit: a máquina caça-níquel, o "one-armed bandit" (Wikipedia, "Multi-armed bandit").
* Multi-Armed: K alavancas, cada uma com um prêmio médio que ninguém conhece.
* Contextual: antes de puxar, o jogador vê um dado da rodada (manhã ou noite).

Cada letra vira um tipo aqui. O `Bandit` abaixo é o AMBIENTE (o que paga);
a escolha fica em `bandit.py`, como no repositório (modelo e regra separados).
"""

from __future__ import annotations

import random
from dataclasses import dataclass
from fractions import Fraction


@dataclass(frozen=True)
class Alavanca:
    """B de Bandit: uma alavanca paga 1 com probabilidade `p`, senão 0. `p` é secreto."""

    p: float

    def puxar(self, rng: random.Random) -> Fraction:
        return Fraction(1) if rng.random() < self.p else Fraction(0)


@dataclass(frozen=True)
class MultiArmed:
    """M e A: K alavancas lado a lado. O jogador escolhe uma por rodada."""

    alavancas: tuple[Alavanca, ...]

    @property
    def k(self) -> int:
        return len(self.alavancas)

    def puxar(self, braco: int, rng: random.Random) -> Fraction:
        return self.alavancas[braco].puxar(rng)


@dataclass(frozen=True)
class Contextual:
    """C: uma máquina diferente para cada contexto. O jogador vê o contexto antes."""

    por_contexto: dict[str, MultiArmed]

    def puxar(self, contexto: str, braco: int, rng: random.Random) -> Fraction:
        return self.por_contexto[contexto].puxar(braco, rng)


# A sorveteria do roteiro: três sabores (braços). De manhã o sabor 1 vende mais,
# de noite o sabor 2. Esses números são as taxas de `haskell/app/Main.hs` (`ctr`).
SORVETERIA = Contextual({
    "manha": MultiArmed((Alavanca(0.05), Alavanca(0.12), Alavanca(0.08))),
    "noite": MultiArmed((Alavanca(0.06), Alavanca(0.04), Alavanca(0.15))),
})

if __name__ == "__main__":
    rng = random.Random(7)
    for c in ("manha", "noite"):
        ganhos = [sum(SORVETERIA.puxar(c, a, rng) for _ in range(1000)) for a in range(3)]
        print(f"{c:6s} 1000 puxadas por braço -> ganhos {ganhos}")
