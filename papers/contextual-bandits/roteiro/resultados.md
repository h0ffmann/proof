# Saídas do código do roteiro

Feito por `codigo/rodar.sh` em 2026-11-09, Python 3.13.18.

## `codigo/bandit.py`

```text
greedy manha  [Fraction(0, 1), Fraction(1, 1), Fraction(0, 1)]  (Lean: [0, 1, 0])
greedy noite  [Fraction(0, 1), Fraction(0, 1), Fraction(1, 1)]  (Lean: [0, 0, 1])
eps 1/10 manha [Fraction(1, 30), Fraction(14, 15), Fraction(1, 30)]  (Lean: [1/30, 14/15, 1/30])
```

## `codigo/nome.py`

```text
manha  1000 puxadas por braço -> ganhos [Fraction(58, 1), Fraction(126, 1), Fraction(73, 1)]
noite  1000 puxadas por braço -> ganhos [Fraction(59, 1), Fraction(37, 1), Fraction(144, 1)]
```

## `codigo/teste_ab.py`

```text
teste A/B/3         [Fraction(1, 3), Fraction(1, 3), Fraction(1, 3)]
epsGreedy 1 (Lean)  [Fraction(1, 3), Fraction(1, 3), Fraction(1, 3)]
iguais?             True
epsGreedy 0         [Fraction(1, 1), Fraction(0, 1), Fraction(0, 1)]  (= greedy)
```

## `codigo/gancho_crenca.py`

```text
crença atual   ['0.67±0.13', '0.50±0.14'] -> escolhe 0
crença nova    ['0.57±0.13', '0.62±0.12'] -> escolhe 1
mudou de ideia? True
```

## `codigo/ab_vs_bandit.py`

```text
T = 5000, média de 20 sementes, 2 contextos x 3 braços
| política | arrependimento |
|---|---|
| teste A/B (T/2, depois commit) | 130,0 |
| A/B sem contexto (T/2, depois commit) | 180,0 |
| eps-gulosa 0,1 | 73,5 |
| UCB beta=2 | 25,9 |
```

## `codigo/rsi_loop.py`

```text
| ε do agente de dentro | vezes escolhido | ganho médio por rodada |
|---|---|---|
| 1 | 14 | 0,077 |
| 0,5 | 168 | 0,096 |
| 0,1 | 10 | 0,085 |
| 0,01 | 8 | 0,054 |
```

## `codigo/pi.py`

```text
| termos | Leibniz: dígitos certos | Ramanujan: dígitos certos |
|---|---|---|
| 1 | 0 | 7 |
| 2 | 0 | 16 |
| 3 | 1 | 24 |
| 4 | 0 | 32 |
| 5 | 1 | 40 |
| 100.000 | 5 | (6 termos bastam para 48) |

cena 1.3, um braço (Leibniz): aproveitar π(N) ou explorar π(N+1) · usuário simulado: nota = 1 − |aproximação − π| · 20 rodadas, ε = 0,2

| ação | vezes | média da recompensa |
|---|---|---|
| aproveitar π(N) | 10 | 0,14 |
| explorar π(N+1) | 10 | 0,74 |

π(N) no fim: N = 11, 1 dígitos certos

cena 1.4, dois braços (Leibniz, Ramanujan) · usuário simulado: nota = 1 − |aproximação − π| · 20 rodadas, ε = 0,2

| braço | puxadas | média da recompensa do usuário | dígitos certos no fim |
|---|---|---|---|
| Leibniz | 3 | 0,45 | 1 |
| Ramanujan | 17 | 1,00 | 59 |
```
