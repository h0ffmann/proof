"""Cenas 1.3 e 1.4 do roteiro: o exemplo simples. A recompensa é o input do usuário.

Cena 1.3, UM braço (single-armed): só o algoritmo de Leibniz. O agente tem a
aproximação π(N), que o usuário já avaliou. A cada rodada ele decide:
  * aproveitar (exploitation): mostrar π(N) de novo; a recompensa é a de sempre;
  * explorar (exploration): gastar um termo, calcular π(N+1), mostrar, e ouvir o usuário.
Com um braço só, explorar é "ir mais fundo no mesmo braço". É a forma mais
simples de ver o dilema: ficar com o que se tem, ou pagar para saber mais.

Cena 1.4, DOIS braços (multi-armed): Leibniz e Ramanujan. Cada um é um braço. A cada rodada o agente escolhe
um braço, acrescenta UM termo àquela soma e mostra a aproximação ao usuário.
O usuário responde se está bom, e com quantos dígitos. Essa resposta é a
recompensa. O agente não sabe matemática: ele só vê o que o usuário disse.

* Leibniz (1674): π/4 = 1 − 1/3 + 1/5 − 1/7 + …  Cerca de 10^n termos para n dígitos.
* Ramanujan (1914): 1/π = (2√2 / 9801) · Σ (4k)! (1103 + 26390 k) / ((k!)^4 · 396^(4k)).
  Cerca de 8 dígitos por termo.

Modos:
    python3 pi.py                 # usuário simulado: recompensa = 1 − |aproximação − π|, entre 0 e 1
    python3 pi.py --interativo    # você é o usuário: responda com o número de dígitos certos,
                                  # ou "s"/"n" (bom / não)

A regra de decisão é `eps_greedy` de `bandit.py`, a mesma da sorveteria e do
Lean. Só a recompensa mudou: aqui ela é uma pessoa.
"""

from __future__ import annotations

import random
import sys
from decimal import Decimal, getcontext
from fractions import Fraction
from math import factorial

from bandit import Tabular, draw, eps_greedy

getcontext().prec = 60
PI = Decimal("3.14159265358979323846264338327950288419716939937510582097494")


def digitos_corretos(x: Decimal) -> int:
    """Quantos dígitos de `x` coincidem com π, contando a partir do 3."""
    n = 0
    for ca, cb in zip(str(PI), str(x)):
        if ca != cb:
            break
        if ca != ".":
            n += 1
    return n


class Leibniz:
    nome = "Leibniz"

    def __init__(self) -> None:
        self.k = 0
        self.soma = Decimal(0)

    def termo(self) -> Decimal:
        self.soma += Decimal((-1) ** self.k) / Decimal(2 * self.k + 1)
        self.k += 1
        return 4 * self.soma


class Ramanujan:
    nome = "Ramanujan"

    def __init__(self) -> None:
        self.k = 0
        self.soma = Decimal(0)
        self.fator = 2 * Decimal(2).sqrt() / Decimal(9801)

    def termo(self) -> Decimal:
        k = self.k
        num = Decimal(factorial(4 * k)) * Decimal(1103 + 26390 * k)
        den = Decimal(factorial(k)) ** 4 * Decimal(396) ** (4 * k)
        self.soma += num / den
        self.k += 1
        return 1 / (self.fator * self.soma)


def usuario_simulado(aprox: Decimal) -> Fraction:
    """Um usuário que dá nota pela distância: 1 − |aprox − π|, entre 0 e 1, com 4 casas."""
    nota = max(Decimal(0), 1 - abs(aprox - PI))
    return Fraction(str(round(nota, 4)))


def usuario_real(aprox: Decimal) -> Fraction:
    """Mostra a aproximação e lê a resposta: um número de dígitos, ou s/n."""
    print(f"  aproximação: {str(aprox)[:20]}")
    resposta = input("  está bom? (dígitos certos, ou s/n): ").strip().lower()
    if resposta in ("s", "sim"):
        return Fraction(1)
    if resposta in ("n", "nao", "não", ""):
        return Fraction(0)
    return min(Fraction(int(resposta), 10), Fraction(1))


APROVEITAR, EXPLORAR = 0, 1


def single_armed(rodadas: int, interativo: bool, seed: int = 3) -> None:
    """Um braço (Leibniz). Duas ações: mostrar π(N) de novo, ou calcular π(N+1)."""
    rng = random.Random(seed)
    lz = Leibniz()
    atual = lz.termo()  # π(1)
    recompensa_atual = usuario_real(atual) if interativo else usuario_simulado(atual)
    modelo = Tabular(2)
    modelo.update("acao", APROVEITAR, recompensa_atual)
    modelo.update("acao", EXPLORAR, recompensa_atual)  # começa sem preferência
    vezes = [0, 0]
    for r in range(1, rodadas + 1):
        acao = draw(eps_greedy(Fraction(1, 5))(modelo.estimates("acao")), rng)
        vezes[acao] += 1
        if acao == APROVEITAR:
            recompensa = recompensa_atual  # o usuário vê a mesma aproximação; diz o mesmo
            if interativo:
                print(f"rodada {r}: aproveitar, mostra π({lz.k}) de novo")
        else:
            candidato = lz.termo()
            if interativo:
                print(f"rodada {r}: explorar, calcula π({lz.k})")
            recompensa = usuario_real(candidato) if interativo else usuario_simulado(candidato)
            if recompensa >= recompensa_atual:
                atual, recompensa_atual = candidato, recompensa
        modelo.update("acao", acao, recompensa)
    print("| ação | vezes | média da recompensa |")
    print("|---|---|---|")
    for a, nome in ((APROVEITAR, "aproveitar π(N)"), (EXPLORAR, "explorar π(N+1)")):
        print(f"| {nome} | {vezes[a]} | {float(modelo.estimate('acao', a).mean):.2f} |".replace(".", ","))
    print(f"\nπ(N) no fim: N = {lz.k}, {digitos_corretos(atual)} dígitos certos")


def rodar(rodadas: int, interativo: bool, seed: int = 3) -> None:
    rng = random.Random(seed)
    braços = [Leibniz(), Ramanujan()]
    modelo = Tabular(2)
    puxadas = [0, 0]
    ultimo = [Decimal(0), Decimal(0)]
    for r in range(1, rodadas + 1):
        if r <= 2:
            i = r - 1  # as duas primeiras rodadas puxam um braço cada, para o modelo ter algo
        else:
            i = draw(eps_greedy(Fraction(1, 5))(modelo.estimates("pi")), rng)
        aprox = braços[i].termo()
        ultimo[i] = aprox
        puxadas[i] += 1
        if interativo:
            print(f"rodada {r}: o agente escolheu {braços[i].nome} (termo {braços[i].k})")
            recompensa = usuario_real(aprox)
        else:
            recompensa = usuario_simulado(aprox)
        modelo.update("pi", i, recompensa)
    print()
    print("| braço | puxadas | média da recompensa do usuário | dígitos certos no fim |")
    print("|---|---|---|---|")
    for i, b in enumerate(braços):
        e = modelo.estimate("pi", i)
        print(f"| {b.nome} | {puxadas[i]} | {float(e.mean):.2f} | {digitos_corretos(ultimo[i])} |"
              .replace(".", ","))


if __name__ == "__main__":
    print("| termos | Leibniz: dígitos certos | Ramanujan: dígitos certos |")
    print("|---|---|---|")
    lz, rm = Leibniz(), Ramanujan()
    for n in range(1, 6):
        print(f"| {n} | {digitos_corretos(lz.termo())} | {digitos_corretos(rm.termo())} |")
    lz = Leibniz()
    for _ in range(100_000):
        x = lz.termo()
    print(f"| 100.000 | {digitos_corretos(x)} | (6 termos bastam para 48) |")
    print()
    interativo = "--interativo" in sys.argv
    quem = "usuário real" if interativo else "usuário simulado: nota = 1 − |aproximação − π|"
    print(f"cena 1.3, um braço (Leibniz): aproveitar π(N) ou explorar π(N+1) · {quem} · 20 rodadas, ε = 0,2")
    print()
    single_armed(20, interativo)
    print()
    print(f"cena 1.4, dois braços (Leibniz, Ramanujan) · {quem} · 20 rodadas, ε = 0,2")
    rodar(20, interativo)
