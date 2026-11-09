"""Trecho 3.3 do roteiro: o teste A/B como regra de bandit.

Um teste A/B/n manda cada visitante para uma variante por sorteio, com a
mesma probabilidade 1/K. O teorema `epsGreedy_one_is_ab_test`
(`lean/ContextualBandit/Theorems.lean`) prova: `epsGreedy 1 = uniform K`.
Este arquivo confere a igualdade em Python, para qualquer estimativa.
"""

from __future__ import annotations

from fractions import Fraction

from bandit import Estimate, eps_greedy, uniform


def teste_ab(k: int) -> list[Fraction]:
    """A alocação do período de teste: 1/K por variante."""
    return uniform(k)


if __name__ == "__main__":
    # Estimativas quaisquer: o teste A/B não olha para elas.
    est = [Estimate(Fraction(9, 10), Fraction(0)), Estimate(Fraction(1, 10), Fraction(1)),
           Estimate(Fraction(1, 2), Fraction(1, 3))]
    ab = teste_ab(3)
    eps1 = eps_greedy(Fraction(1))(est)
    print("teste A/B/3        ", ab)
    print("epsGreedy 1 (Lean) ", eps1)
    print("iguais?            ", ab == eps1)
    # Com eps = 0, a mesma regra vira o "commit": tudo na melhor variante.
    print("epsGreedy 0        ", eps_greedy(Fraction(0))(est), " (= greedy)")
