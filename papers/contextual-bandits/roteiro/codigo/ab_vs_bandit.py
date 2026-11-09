"""Trecho 3.4 do roteiro: o CMAB é o teste A/B generalizado.

Quatro políticas, mesma sorveteria (`nome.py`), mesmo modelo tabular
(`bandit.py`), T rodadas, média de várias sementes:

1. teste A/B: explora T/2 rodadas com 1/K, depois fica na melhor (explore-then-commit);
2. ε-gulosa, ε = 0,1;
3. UCB, β = 2;
4. A/B sem contexto: ignora manhã e noite e escolhe UMA variante para todos.

A métrica é o arrependimento esperado: a soma, por rodada, de
(melhor média do contexto − média do braço escolhido). Quanto menor, melhor.
"""

from __future__ import annotations

import random
from fractions import Fraction

from bandit import Decision, Estimate, Tabular, draw, eps_greedy, greedy, ucb, uniform
from nome import SORVETERIA

CONTEXTOS = ("manha", "noite")
K = 3


def media_real(c: str, a: int) -> float:
    return SORVETERIA.por_contexto[c].alavancas[a].p


def melhor(c: str) -> float:
    return max(media_real(c, a) for a in range(K))


def rodar(politica: str, t: int, seed: int) -> float:
    rng = random.Random(seed)
    modelo = Tabular(K)
    sem_contexto = Tabular(K)  # para a política 4: um único contexto, "todos"
    arrependimento = 0.0
    for rodada in range(t):
        c = rng.choice(CONTEXTOS)
        if politica == "teste A/B (T/2, depois commit)":
            est = modelo.estimates(c)
            d: Decision = uniform(K) if rodada < t // 2 else greedy(est)
        elif politica == "eps-gulosa 0,1":
            d = eps_greedy(Fraction(1, 10))(modelo.estimates(c))
        elif politica == "UCB beta=2":
            d = ucb(Fraction(2))(modelo.estimates(c))
        elif politica == "A/B sem contexto (T/2, depois commit)":
            est = sem_contexto.estimates("todos")
            d = uniform(K) if rodada < t // 2 else greedy(est)
        else:
            raise ValueError(politica)
        a = draw(d, rng)
        r = SORVETERIA.puxar(c, a, rng)
        modelo.update(c, a, r)
        sem_contexto.update("todos", a, r)
        arrependimento += melhor(c) - media_real(c, a)
    return arrependimento


POLITICAS = (
    "teste A/B (T/2, depois commit)",
    "A/B sem contexto (T/2, depois commit)",
    "eps-gulosa 0,1",
    "UCB beta=2",
)

if __name__ == "__main__":
    T, SEMENTES = 5000, 20
    print(f"T = {T}, média de {SEMENTES} sementes, 2 contextos x 3 braços")
    print("| política | arrependimento |")
    print("|---|---|")
    for p in POLITICAS:
        media = sum(rodar(p, T, s) for s in range(1, SEMENTES + 1)) / SEMENTES
        print(f"| {p} | {media:.1f} |".replace(".", ","))
