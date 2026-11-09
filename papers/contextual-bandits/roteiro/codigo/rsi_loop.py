"""Trecho 2 do roteiro: um ciclo de automelhoria recursiva, do tamanho de uma tela.

Improvement: um agente escolhe melhor do que ontem.
Self-improvement: o próprio agente faz essa mudança, sem ninguém de fora.
Recursive self-improvement: a mudança é no mecanismo que faz as mudanças.

Aqui o agente de dentro é a regra ε-gulosa de `bandit.py`. O agente de fora é
OUTRO bandit, cujos braços são valores de ε. A recompensa do agente de fora é
o ganho que o agente de dentro obteve com aquele ε. O de fora aprende qual ε
dá o de dentro melhor; o de dentro aprende qual sabor vender. Dois ciclos, um
dentro do outro: a recursão.

Nada aqui é novo: é `epsGreedy` aplicado duas vezes. O ponto do roteiro é esse.
"""

from __future__ import annotations

import random
from fractions import Fraction

from bandit import Tabular, draw, eps_greedy
from nome import SORVETERIA

EPSILONS = (Fraction(1), Fraction(1, 2), Fraction(1, 10), Fraction(1, 100))
CONTEXTOS = ("manha", "noite")


def episodio(eps: Fraction, rodadas: int, rng: random.Random) -> Fraction:
    """O agente de dentro: vende `rodadas` sorvetes com um ε fixo. Devolve o ganho."""
    modelo = Tabular(3)
    ganho = Fraction(0)
    for _ in range(rodadas):
        c = rng.choice(CONTEXTOS)
        a = draw(eps_greedy(eps)(modelo.estimates(c)), rng)
        r = SORVETERIA.puxar(c, a, rng)
        modelo.update(c, a, r)
        ganho += r
    return ganho


if __name__ == "__main__":
    rng = random.Random(2026)
    meta = Tabular(len(EPSILONS))  # o agente de fora: um braço por ε
    for episodio_n in range(200):
        i = draw(eps_greedy(Fraction(1, 5))(meta.estimates("eps")), rng)
        ganho = episodio(EPSILONS[i], rodadas=500, rng=rng)
        meta.update("eps", i, ganho / 500)  # recompensa: ganho médio por rodada
    print("| ε do agente de dentro | vezes escolhido | ganho médio por rodada |")
    print("|---|---|---|")
    for i, eps in enumerate(EPSILONS):
        s, n = meta.table.get(("eps", i), (Fraction(0), 0))
        media = float(s / n) if n else 0.0
        print(f"| {float(eps):g} | {n} | {media:.3f} |".replace(".", ","))
