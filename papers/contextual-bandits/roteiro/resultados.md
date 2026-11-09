# Saídas do código do roteiro

Feito por `cabal run video` (haskell/app/Video.hs). Aritmética exata para π; Double para as simulações.

## Cena 1.1 e 3.4: crença atual contra crença nova (`beliefs`)

```text
crença atual  [0,67,0,5] -> escolhe 0
crença nova   [0,57,0,62] -> escolhe 1
mudou de ideia? True
```

## Cena 1.3: dígitos certos por termo (`Pi.hs`)

| termos | Leibniz | Gauss-Legendre | Ramanujan |
|---|---|---|---|
| 1 | 0 | 3 | 7 |
| 2 | 0 | 8 | 16 |
| 3 | 1 | 19 | 24 |
| 4 | 0 | 41 | 32 |
| 5 | 1 | 61 | 40 |
| 6 | 0 | 61 | 48 |
| 100.000 | 5 | · | · |

## Cena 1.3: um braço, Leibniz: aproveitar π(N) ou explorar π(N+1) (`singleArmed`, 20 rodadas, ε = 0,2)

| ação | vezes | média da nota do usuário |
|---|---|---|
| aproveitar π(N) | 9 | 0,14 |
| explorar π(N+1) | 11 | 0,76 |

π(N) no fim: N = 12, 1 dígitos certos

## Cena 1.4: três braços, Leibniz, Gauss-Legendre, Ramanujan (`multiArmed`, 20 rodadas, ε = 0,2)

| braço | puxadas | média da nota do usuário | dígitos certos no fim |
|---|---|---|---|
| Leibniz | 1 | 0,14 | 0 |
| Gauss-Legendre | 3 | 1,00 | 19 |
| Ramanujan | 16 | 1,00 | 61 |

## Cenas 2.3 e 2.4: teste A/B contra as regras de bandit (`abVsBandit`)

T = 5000, média de 20 sementes, 2 contextos x 3 braços
| política | arrependimento |
|---|---|
| teste A/B (T/2, depois commit) | 128,8 |
| A/B sem contexto (T/2, depois commit) | 178,9 |
| eps-gulosa 0,1 | 76,4 |
| UCB beta=2 | 19,5 |

## Cena 3.2: o laço de fora escolhe o ε do laço de dentro (`rsiLoop`, 200 episódios de 500 rodadas)

| ε do agente de dentro | vezes escolhido | ganho médio por rodada |
|---|---|---|
| 1,0 | 11 | 0,080 |
| 0,5 | 168 | 0,099 |
| 0,1 | 12 | 0,085 |
| 1,0e-2 | 9 | 0,057 |
