---
id: "202611010013"
title: "Bandits contextuais de múltiplos braços"
type: literature
status: partial
source:
  - https://netflixtechblog.com/artwork-personalization-c589f074ad76
  - https://www.aicouncil.com/talks/artwork-personalization-at-netflix
  - https://aicouncil.com/a-multi-armed-bandit-framework-for-recommendations-at-netflix
tags: [bandit-contextual, teste-ab, rsi, netflix, z3, haskell, roteiro]
created: 2026-11-01T00:13Z
updated: 2026-11-09
---

# Bandits contextuais de múltiplos braços

Padrão de escrita: gramatico, nível `smart-note + descritivo`. Versão em inglês: [MULTI_ARMED_CONTEXTUAL_BANDIT.md](MULTI_ARMED_CONTEXTUAL_BANDIT.md). Nota vizinha: [README.md](README.md). Roteiro do vídeo de 30 minutos: [papers/contextual-bandits/script/](papers/contextual-bandits/script/README.md).

Leitura estimada: ~19 min (3779 palavras, 68 links, 0 blocos de código)

Esta nota segue a ordem do roteiro do vídeo. O vídeo tem três blocos de 10 minutos: **CMAB**, **teste A/B** e **RSI**. Cada seção desta nota tem o número da cena do roteiro, por exemplo "cena 1.3". Os números citados vêm de [`results.md`](papers/contextual-bandits/script/results.md), que `cabal run video` escreve.

## 0. Mapa para a edição do vídeo

Cada figura abaixo é um diagrama do archify. O PNG serve de referência na edição; o HTML é o diagrama interativo, para gravar a tela ou exportar em SVG. A fonte das figuras, nos dois idiomas, é [`docs/diagrams/src/build_candidates.py`](docs/diagrams/src/build_candidates.py). `just diagrams` e `just images` geram de novo os arquivos.

| Cena | Tempo | Figura archify (referência) | Desmos | Código |
|---|---|---|---|---|
| 1.1 Gancho | 0:00 a 1:00 | [bandit-round](docs/diagrams/img/pt-BR/bandit-round.png) ([html](docs/diagrams/pt-BR/bandit-round.html)) | — | `beliefs` em `haskell/app/Video.hs` |
| 1.2 Steal like an artist | 1:00 a 3:00 | [bandit-timeline](docs/diagrams/img/pt-BR/bandit-timeline.png) ([html](docs/diagrams/pt-BR/bandit-timeline.html)) | — | `animation/timeline.py` (a fazer) |
| 1.3 π e você, um braço | 3:00 a 5:00 | [pi-arms](docs/diagrams/img/pt-BR/pi-arms.png) ([html](docs/diagrams/pt-BR/pi-arms.html)) | [`1-3-pi.txt`](papers/contextual-bandits/script/desmos/1-3-pi.txt) | `singleArmed`; `step` em `z3-scala/src/main/scala/bandit/domain/Video.scala` |
| 1.4 O nome, letra por letra | 5:00 a 6:30 | [pi-arms](docs/diagrams/img/pt-BR/pi-arms.png) ([html](docs/diagrams/pt-BR/pi-arms.html)) | [`1-3-pi.txt`](papers/contextual-bandits/script/desmos/1-3-pi.txt) | `multiArmed`; `haskell/src/Pi.hs` |
| 1.5 Modelo e regra | 6:30 a 7:30 | [bandit-architecture](docs/diagrams/img/pt-BR/bandit-architecture.png) ([html](docs/diagrams/pt-BR/bandit-architecture.html)) | [`1-5-width.txt`](papers/contextual-bandits/script/desmos/1-5-width.txt) | `policy_factors` em `z3-scala/src/main/scala/bandit/domain/Theorems.scala` |
| 1.6 Explorar e aproveitar | 7:30 a 8:30 | — | [`1-6-ucb.txt`](papers/contextual-bandits/script/desmos/1-6-ucb.txt) | `greedy`, `epsGreedy`, `ucb`; `ucb_zero` |
| 1.7 A Netflix | 8:30 a 10:00 | [bandit-architecture](docs/diagrams/img/pt-BR/bandit-architecture.png) ([html](docs/diagrams/pt-BR/bandit-architecture.html)) | — | `bayesLinear` em `haskell/src/Models.hs` |
| 2.1 O que é um teste A/B | 10:00 a 11:30 | [ab-test-vs-bandit](docs/diagrams/img/pt-BR/ab-test-vs-bandit.png) ([html](docs/diagrams/pt-BR/ab-test-vs-bandit.html)) | [`2-1-ab.txt`](papers/contextual-bandits/script/desmos/2-1-ab.txt) | `uniform`; `etc_before` |
| 2.2 O teste A/B é uma regra de bandit | 11:30 a 13:00 | [ab-test-vs-bandit](docs/diagrams/img/pt-BR/ab-test-vs-bandit.png) ([html](docs/diagrams/pt-BR/ab-test-vs-bandit.html)) | [`2-2-epsilon.txt`](papers/contextual-bandits/script/desmos/2-2-epsilon.txt) | `epsGreedy_one_is_ab_test`, `etc_after` |
| 2.3 O custo da espera | 13:00 a 15:00 | — | [`2-3-regret.txt`](papers/contextual-bandits/script/desmos/2-3-regret.txt) | `abVsBandit` |
| 2.4 O contexto personaliza | 15:00 a 16:30 | [ab-test-vs-bandit](docs/diagrams/img/pt-BR/ab-test-vs-bandit.png) ([html](docs/diagrams/pt-BR/ab-test-vs-bandit.html)) | — | `abVsBandit`, "A/B sem contexto" |
| 2.5 O que o A/B faz melhor | 16:30 a 18:00 | [bandit-round](docs/diagrams/img/pt-BR/bandit-round.png) ([html](docs/diagrams/pt-BR/bandit-round.html)) | [`2-5-propensity.txt`](papers/contextual-bandits/script/desmos/2-5-propensity.txt) | `policy` |
| 2.6 Resumo do bloco | 18:00 a 20:00 | [bandit-architecture](docs/diagrams/img/pt-BR/bandit-architecture.png) ([html](docs/diagrams/pt-BR/bandit-architecture.html)) | — | `z3-scala/src/main/scala/bandit/domain/Theorems.scala` |
| 3.1 Três palavras | 20:00 a 21:30 | [rsi-loop](docs/diagrams/img/pt-BR/rsi-loop.png) ([html](docs/diagrams/pt-BR/rsi-loop.html)) | — | `outer`, `innerEps` em `z3-scala/src/main/scala/bandit/domain/Video.scala` |
| 3.2 O menor ciclo recursivo | 21:30 a 24:00 | [rsi-loop](docs/diagrams/img/pt-BR/rsi-loop.png) ([html](docs/diagrams/pt-BR/rsi-loop.html)) | — | `rsiLoop` |
| 3.3 O bandit na RSI de verdade | 24:00 a 26:30 | [rsi-loop](docs/diagrams/img/pt-BR/rsi-loop.png) ([html](docs/diagrams/pt-BR/rsi-loop.html)) | — | `rsiLoop` |
| 3.4 Crença atual contra crença nova | 26:30 a 28:00 | [bandit-round](docs/diagrams/img/pt-BR/bandit-round.png) ([html](docs/diagrams/pt-BR/bandit-round.html)) | [`3-4-beta.txt`](papers/contextual-bandits/script/desmos/3-4-beta.txt) | `beliefs`; `betaBernoulli` |
| 3.5 O que não é bandit | 28:00 a 29:00 | [bandit-architecture](docs/diagrams/img/pt-BR/bandit-architecture.png) ([html](docs/diagrams/pt-BR/bandit-architecture.html)) | — | `calibrated`, `ucb_gap` |
| 3.6 Fecho e créditos | 29:00 a 30:00 | — | — | `PROMPTS.md` |

As figuras são referências para a edição. O estilo final do vídeo é o do roteiro: Manim, fundo escuro, azul para a crença, amarelo para a escolha, vermelho para o arrependimento. O archify não faz esse estilo; ele dá a estrutura que a animação segue.

## Bloco 1. CMAB (0:00 a 10:00)

### 1.1 O problema (cena 1.1)

O sistema escolhe uma opção para cada requisição. Cada opção é um **braço**.
O sistema conhece alguns dados da requisição. Esses dados são o **contexto**.
Depois da escolha, o sistema recebe uma **recompensa**. Um clique ou uma reprodução é uma recompensa.
O sistema não vê a recompensa dos braços que não escolheu.

O sistema repete este ciclo muitas vezes:

1. O sistema recebe o contexto `c`.
2. O sistema escolhe um braço `a`.
3. O sistema recebe a recompensa `r` só do braço `a`.
4. O sistema atualiza o modelo com `(c, a, r)`.

A regra que escolhe o braço é a **política**.
O objetivo é maximizar a recompensa total.

O gancho do vídeo mostra o passo 4. O agente tem uma crença de hoje: a opção 0 agrada em 67 % das vezes, a opção 1 em 50 %. Chegam 4 sinais positivos para a opção 1 e 2 negativos para a opção 0. A crença nova diz 0,57 e 0,62, e a escolha muda para a opção 1. O agente muda por evidência, não por palpite.

| Termo | Significado | Exemplo (imagens da Netflix) |
|---|---|---|
| Contexto | Dados conhecidos antes da escolha | Histórico de visualização, país |
| Braço | Uma opção | Uma imagem de um título |
| Recompensa | Resultado do braço escolhido | O assinante reproduz o título |
| Política | Regra que leva do contexto ao braço | Modelo que escolhe a imagem |
| Arrependimento (*regret*) | Soma, em todas as rodadas, da recompensa do melhor braço menos a recompensa do braço escolhido | Reproduções que o sistema perdeu |

[![Uma rodada de um bandit contextual](docs/diagrams/img/pt-BR/bandit-round.png)](docs/diagrams/pt-BR/bandit-round.html)

*Figura 1. Uma rodada: decidir, agir, aprender. Feita com archify. Referência das cenas 1.1, 2.5 e 3.4. Clique na figura para abrir o diagrama interativo.*

### 1.2 De onde vem a ideia (cena 1.2)

A cena 1.2 é uma linha do tempo. O roteiro chama a cena de *steal like an artist*, a partir do livro de Austin Kleon, de 2012. Os marcos são estes:

| Ano | Marco |
|---|---|
| 1952 | Herbert Robbins formula o problema do bandit de múltiplos braços. |
| 2010 | Li, Chu, Langford e Schapire publicam o LinUCB. O contexto é um vetor [6]. |
| 2012 | Austin Kleon publica *Steal Like an Artist*. |
| 2017 | A globo.com cria um serviço de bandit num *hackday*, em Scala [9]. |
| 2017-12 | A Netflix publica "Artwork Personalization at Netflix" [1][2]. |
| 2018 | Renan Moreira de Oliveira, da globo.com, mostra o slide "MAB ML PARA AB RL" [10]. |
| 2024 | Tiago Motta conta que o serviço da globo.com "ainda é usado" [9]. |
| 2026 | O bandit aparece no laço de automelhoria dos agentes (bloco 3). |

O roteiro conferiu as fontes de 1952, de 2012, da globo.com e de 2026. O registro dessa conferência está em [`REFERENCES.md`](papers/contextual-bandits/script/REFERENCES.md). ⚠ Esta nota não abriu de novo essas fontes; ela usa o registro do roteiro. O amigo de 2018 da cena 1.2 não entra na figura: o roteiro ainda marca o nome e o mês como `[a confirmar]`.

[![Linha do tempo do bandit, de 1952 a 2026](docs/diagrams/img/pt-BR/bandit-timeline.png)](docs/diagrams/pt-BR/bandit-timeline.html)

*Figura 2. A linha do tempo da cena 1.2. Feita com archify. As datas têm precisão de ano ou de mês; o archify mostra o dia 1.*

### 1.3 π e você: um braço, depois três (cenas 1.3 e 1.4)

O exemplo simples do vídeo é o cálculo de π. Você é a recompensa.

Com um braço só, o braço é a série de Leibniz. A cada rodada, o agente faz uma de duas coisas:

- **Aproveitar**: o agente mostra a aproximação π(N) de novo.
- **Explorar**: o agente calcula mais um termo e mostra π(N+1).

Você dá uma nota de 0 a 1 pela distância até π. O agente não lê a fórmula; ele só sabe a sua nota. Em 20 rodadas, com ε = 0,2, o agente aproveitou 9 vezes, com nota média 0,14, e explorou 11 vezes, com nota média 0,76. O agente terminou em π(12).

Com três braços, entram duas alavancas: Gauss-Legendre, que dobra os dígitos a cada passo (3, 8, 19, 41), e Ramanujan, que acerta 7 dígitos com 1 termo e 48 com 6. Em 20 rodadas, o agente puxou Ramanujan 16 vezes, Gauss-Legendre 3 vezes e Leibniz 1 vez. Gauss-Legendre e Ramanujan empatam com nota 1,00. A regra gulosa desempata pelo primeiro máximo, e por isso o agente fica com Ramanujan.

O exemplo de π não tem contexto. Por isso, o exemplo de π é um MAB, e não um CMAB.

[![π e você: um braço, depois três](docs/diagrams/img/pt-BR/pi-arms.png)](docs/diagrams/pt-BR/pi-arms.html)

*Figura 3. O ciclo do π: o agente escolhe, mostra, e a sua nota atualiza a crença. Feita com archify. Referência das cenas 1.3 e 1.4.*

### 1.4 O nome, letra por letra (cena 1.4)

- **B**, de *bandit*: a máquina caça-níquel é o *one-armed bandit*.
- **M** e **A**, de *multi-armed*: várias alavancas, cada uma com um prêmio médio desconhecido.
- **C**, de contextual: antes de puxar a alavanca, o agente vê um dado da rodada, por exemplo manhã ou noite.

Sem contexto, a melhor alavanca é uma só. Com contexto, a melhor alavanca muda a cada rodada, e a política aprende uma função do contexto para a alavanca. No LinUCB, essa função é linear [6]. Na sorveteria do vídeo, a função é uma tabela com duas linhas: manhã e noite.

### 1.5 Modelo e regra, separados (cena 1.5)

O repositório divide o agente em duas camadas:

- O **modelo de recompensa** guarda uma crença. Para cada braço, o modelo dá uma média e uma largura de incerteza.
- A **regra de decisão** vê só essas estimativas. A regra nunca vê o histórico nem o contexto.

A afirmação `policy_factors` em Z3 prova essa fronteira: dois históricos com a mesma crença dão a mesma decisão. O modelo do vídeo é tabular: a média é soma sobre contagem, e a largura é `1/(n+1)`.

[![Camadas de modelo e de decisão](docs/diagrams/img/pt-BR/bandit-architecture.png)](docs/diagrams/pt-BR/bandit-architecture.html)

*Figura 4. A camada de modelo, a camada de decisão e a spec em Z3. Feita com archify. Referência das cenas 1.5, 1.7, 2.6 e 3.5.*

### 1.6 Explorar e aproveitar (cena 1.6)

O sistema faz duas coisas ao mesmo tempo:

- **Aproveitar**: o sistema escolhe o braço com a maior recompensa estimada.
- **Explorar**: o sistema escolhe outros braços para coletar dados sobre eles.

Um sistema que só aproveita pode ficar preso num braço ruim. Depois de poucas observações, a estimativa de um braço bom pode ficar baixa demais. Nesse caso, o sistema nunca mais escolhe esse braço.
Um sistema que só explora perde recompensa nos braços ruins.

Cada regra deste repositório equilibra os dois lados de um jeito:

| Regra | Como a regra explora | Código |
|---|---|---|
| Gulosa | A regra não explora | `greedy` |
| ε-gulosa | A regra escolhe um braço aleatório com probabilidade ε | `epsGreedy ε` |
| UCB / LinUCB | A regra soma um bônus de incerteza, β vezes a largura, à estimativa | `ucb β` |
| Amostragem de Thompson | A regra sorteia uma média da posteriori e escolhe a maior | `thompsonArm` |

Com β = 0, a UCB é a gulosa. A afirmação `ucb_zero` em Z3 prova isso.

### 1.7 O exemplo complexo: a Netflix (cena 1.7)

#### Personalização de imagens

A Netflix escolhe, para cada assinante, a imagem que mostra para cada título. O post "Artwork Personalization at Netflix" do Netflix Tech Blog (2017-12) descreve esse sistema. Os autores são Ashok Chandrashekar, Fernando Amat, Justin Basilico e Tony Jebara [1][2].

Numa palestra de abertura de 2018, Tony Jebara deu estes dados sobre o sistema [3]:

- O contexto é o histórico de visualização e o país do assinante.
- O braço é a imagem. A recompensa é uma reprodução.
- O sistema usa aprendizado *online* e bandits contextuais.
- O sistema recebe cerca de 20 milhões de requisições de imagem por segundo, no pico.
- A equipe usa *replay* para avaliar uma política nova *offline*.

O vídeo compara a Netflix com o π. No π, você é a recompensa e sabe disso. Na Netflix, você é a recompensa e não sabe. A escala obriga o modelo a generalizar: o repositório tem o modelo `bayesLinear`, em que a média é um produto escalar entre o contexto e os pesos do braço.

#### A Netflix ainda usa bandits?

As fontes primárias que esta nota confirmou são de 2017 e 2018. Esta nota não encontrou uma fonte primária da Netflix que confirme o uso atual (2026). O Netflix Tech Blog tem a tag "contextual-bandit", mas esta nota não leu os posts dessa tag. ⚠ Não afirme que a Netflix usa bandits hoje sem uma fonte mais recente.

## Bloco 2. Teste A/B (10:00 a 20:00)

### 2.1 O que é um teste A/B (cena 2.1)

Um teste A/B/n tem `K` variantes. O teste manda cada usuário para uma variante por sorteio, com probabilidades iguais. No fim do teste, a equipe escolhe a melhor variante e manda todos os usuários para ela. O procedimento tem duas fases: sortear, depois decidir. Em inglês, o nome é *explore-then-commit*.

O teste A/B tem três virtudes: ele é simples de montar, simples de ler e simples de defender.

### 2.2 O teste A/B é uma regra de bandit (cena 2.2)

1. **O período de teste é a regra ε-gulosa com ε = 1.** Cada braço recebe probabilidade `1/K`. Essa é a alocação aleatória uniforme. A afirmação `epsGreedy_one_is_ab_test` em Z3 (`z3-scala/src/main/scala/bandit/domain/Theorems.scala`) prova isso.
2. **A fase de decisão é a regra ε-gulosa com ε = 0**, a gulosa. A afirmação `epsGreedy_zero` prova isso.
3. **O teste A/B completo é um ε que pula de 1 para 0 num dia marcado.** A invariante R3 (`etc` em `z3-scala/src/main/scala/bandit/domain/Video.scala`) prova as duas fases: `etc_before` e `etc_after`.

Com essa visão, a pergunta "A/B ou bandit?" vira outra: como ε deve cair ao longo do tempo.

[![Teste A/B como caso particular de bandit](docs/diagrams/img/pt-BR/ab-test-vs-bandit.png)](docs/diagrams/pt-BR/ab-test-vs-bandit.html)

*Figura 5. O teste A/B e o ciclo do bandit. Feita com archify. Referência das cenas 2.1, 2.2 e 2.4.*

### 2.3 O custo da espera (cena 2.3)

O vídeo simula uma sorveteria: três sabores, dois contextos (manhã e noite), 5.000 clientes, média de 20 sementes. O teste A/B usa metade dos clientes na fase de sorteio.

| Política | Arrependimento |
|---|---|
| Teste A/B (T/2, depois decide) | 128,8 |
| Teste A/B sem contexto | 178,9 |
| ε-gulosa, ε = 0,1 | 76,4 |
| UCB, β = 2 | 19,5 |

O bandit muda a alocação durante o teste. O bandit manda mais tráfego para os braços que parecem melhores. Por isso, o arrependimento durante o teste é menor. Jebara chama o ciclo "coletar dados por meses, treinar, depois testar" de "a massive amount of regret" [3].

### 2.4 O contexto personaliza o teste (cena 2.4)

Um teste A/B encontra uma única melhor variante para todos os usuários. Um bandit contextual encontra a melhor variante para cada contexto. Na sorveteria, o teste A/B sem contexto tem 178,9 de arrependimento, contra 128,8 do teste que separa manhã e noite. Um teste A/B por segmento de usuários é um caso particular de bandit contextual.

### 2.5 O que o teste A/B ainda faz melhor (cena 2.5)

A alocação aleatória fixa dá uma estimativa simples e sem viés do efeito. O bandit muda a alocação, e por isso a média simples dos registros tem viés. Para avaliar um bandit *offline*, registre a probabilidade de cada escolha. Depois, use *replay* ou ponderação pelo inverso da propensão (IPW). A função `policy` devolve a distribuição inteira, e essa distribuição é a propensão que o registro precisa.

A Netflix ainda usou um teste A/B para aprovar o sistema de imagens antes da implantação [3]. Portanto, o bandit não substituiu o teste A/B. O bandit substituiu o ciclo lento dentro do teste.

### 2.6 Resumo do bloco (cena 2.6)

O teste A/B é uma política específica dentro do modelo de bandit. Essa política não usa contexto, usa alocação uniforme fixa e toma uma única decisão no fim. O bandit contextual relaxa as três escolhas.

Duas equipes usam o bandit em produção, segundo as fontes:

- **Netflix, *billboard***: o banner grande no topo da página inicial recomenda um único título. Uma palestra de 2018, de Jaya Kawale e Elliot Chow, descreve um *framework* de bandit com a regra ε-gulosa [4][5]. A exploração sorteia um título com probabilidade uniforme e dá dados sem viés para o treino. A equipe avaliou as políticas *offline* com *replay* e *online* com testes A/B. Motivo: o catálogo, a popularidade e o interesse dos assinantes mudam, e os modelos em lote se adaptam devagar demais.
- **globo.com**: o serviço de bandit serve para "escolher uma foto" e "a melhor posição para colocar publicidade", nas palavras de Tiago Motta [9].

Regra prática do vídeo: use o teste A/B quando a decisão é uma só e precisa ser defendida. Use o bandit quando a decisão se repete milhares de vezes por dia e o custo de cada erro é pequeno. Use os dois quando puder: o bandit por dentro, o teste A/B por fora.

O Z3 prova cinco fatos para até cinco braços e todo valor real das estimativas: toda regra devolve uma distribuição válida; a ε-gulosa dá a cada braço pelo menos ε/K; a gulosa e a UCB escolhem um máximo; a ε-gulosa com ε = 1 é o teste A/B; e, com um modelo calibrado, o braço da UCB perde no máximo 2β vezes a largura (`ucb_gap`). A cota de arrependimento probabilística fica aberta.

## Bloco 3. RSI, automelhoria recursiva (20:00 a 30:00)

### 3.1 Três palavras (cena 3.1)

| Palavra | O que o agente faz | O que a palavra exige |
|---|---|---|
| *Improvement* | O agente escolhe melhor hoje do que ontem | Uma métrica |
| *Self-improvement* | O próprio agente faz a mudança | Um laço fechado, sem pessoa no meio |
| *Recursive self-improvement* | A mudança é no mecanismo que faz as mudanças | Acesso do laço ao próprio laço |

A Anthropic define RSI, no ensaio "When AI builds itself", como um sistema que "could fully autonomously design and develop its successor" [11].

### 3.2 O menor ciclo recursivo (cena 3.2)

O agente de dentro é a ε-gulosa da sorveteria. O agente de fora é outro bandit; os braços dele são valores de ε: 1; 0,5; 0,1; 0,01. A cada episódio, o agente de fora escolhe um ε, o agente de dentro atende 500 clientes com esse ε, e o ganho médio volta como recompensa para o agente de fora.

| ε do agente de dentro | Episódios escolhidos (de 200) | Ganho médio por cliente |
|---|---|---|
| 1,0 | 11 | 0,080 |
| 0,5 | 168 | 0,099 |
| 0,1 | 12 | 0,085 |
| 0,01 | 9 | 0,057 |

O agente de fora aprende como o agente de dentro deve aprender. A mesma `epsGreedy` funciona nos dois níveis. A invariante R4 em Z3 prova isso: `rsi_valid` e `outer_explores`. O ε = 0,5 ganha porque o horizonte é curto, 500 clientes por episódio, e o modelo começa do zero.

[![Automelhoria recursiva: um bandit que ajusta um bandit](docs/diagrams/img/pt-BR/rsi-loop.png)](docs/diagrams/pt-BR/rsi-loop.html)

*Figura 6. O laço de fora escolhe o ε do laço de dentro. Feita com archify. Referência das cenas 3.1, 3.2 e 3.3.*

### 3.3 O bandit na RSI de verdade (cena 3.3)

Nos sistemas reais, os braços do laço de fora são mudanças no próprio agente. O artigo SIA, de 2026, descreve um "Feedback-Agent" que escolhe entre editar o *scaffold*, os prompts e as ferramentas, ou atualizar os pesos do modelo [12]. Um avaliador determinístico dá a recompensa. Essa é a estrutura de um bandit: uma escolha entre braços, com recompensa observada só para o braço escolhido. ⚠ O roteiro leu o SIA por uma resenha, não pelo PDF.

A Anthropic relata uma aceleração de um código de treino de cerca de 3 vezes, em maio de 2025, para cerca de 52 vezes, em abril de 2026 [11]. A Anthropic também relata uma revisão automática de código que teria pegado cerca de um terço dos erros por trás de incidentes passados [11]. Os outros dois terços lembram que a recompensa mede só uma parte do que importa.

### 3.4 Crença atual contra crença nova (cena 3.4)

O modelo Beta-Bernoulli guarda duas contagens por opção: sucessos e fracassos. Cada sinal do usuário soma 1 numa das contagens. A crença atual dizia 0,67 e 0,50. Depois de 4 sinais a favor da opção 1 e 2 contra a opção 0, a crença nova diz 0,57 e 0,62, e a escolha muda (cena 1.1). A crença nova soma os sinais novos aos antigos; ela não apaga a crença antiga. A largura cai nos dois braços.

### 3.5 O que não é bandit (cena 3.5)

- O bandit vê a recompensa de uma rodada e não planeja a próxima. Quando a escolha de hoje muda o estado de amanhã, o problema é de aprendizado por reforço completo.
- Uma recompensa fácil de enganar ensina o laço a enganar a recompensa. O lema `ucb_gap` depende da premissa `calibrated`: sem incerteza calibrada, o otimismo da UCB não tem garantia. ⚠ O roteiro não cita um trabalho específico de *reward hacking*.

## 4. Ligação com este repositório

| Conceito desta nota | Z3 | Haskell |
|---|---|---|
| Modelo probabilístico | `update`, `estimate`, `posterior` (`Examples.scala`) | `RewardModel`, `Models.hs` |
| Política | `policy` | `policy`, `act` |
| Alocação A/B/n | `epsGreedy(1, est)` = `uniform(K)` | `epsGreedy 1` |
| Teste A/B completo | `etc`, `etc_before`, `etc_after` (`Video.scala`) | `etc` (`Video.hs`) |
| Garantia de exploração | `epsGreedy_explores` | — |
| Arrependimento do UCB numa rodada | `ucb_gap` | `ucb` |
| O modelo é o único caminho do histórico até a decisão | `policy_factors` | `posterior` |
| π como bandit | `step`, `leibnizPair_pos`, `ramTerm_pos` (`Video.scala`) | `Pi.hs`, `singleArmed`, `multiArmed` |
| RSI | `outer`, `innerEps`, `rsi_valid` (`Video.scala`) | `outer`, `inner`, `rsiLoop` |

## 5. Fontes

1. Netflix Tech Blog, "Artwork Personalization at Netflix", 2017-12. <https://netflixtechblog.com/artwork-personalization-c589f074ad76> (esta nota leu um resumo do post, não o texto completo)
2. Dezeen, "Netflix targets different film artworks to suit users' viewing habits", 2017-12-20. <https://www.dezeen.com/2017/12/20/netflix-targets-film-artwork-depending-users-viewing-habits-design-technology/>
3. Tony Jebara, "Artwork Personalization at Netflix", palestra de abertura, 2018. <https://www.aicouncil.com/talks/artwork-personalization-at-netflix>
4. Jaya Kawale e Elliot Chow, "A Multi-Armed Bandit Framework for Recommendations at Netflix", 2018. <https://aicouncil.com/a-multi-armed-bandit-framework-for-recommendations-at-netflix>
5. Slides de [4]. <https://www.slideshare.net/slideshow/a-multiarmed-bandit-framework-for-recommendations-at-netflix/102629078>
6. Li, Chu, Langford e Schapire, "A Contextual-Bandit Approach to Personalized News Article Recommendation" (LinUCB), 2010. <https://arxiv.org/abs/1003.0146>
7. Lattimore e Szepesvári, *Bandit Algorithms*, Cambridge University Press, 2020.
8. O roteiro do vídeo e o registro das fontes dele: [`papers/contextual-bandits/script/`](papers/contextual-bandits/script/README.md), [`refs.bib`](papers/contextual-bandits/script/refs.bib), [`REFERENCES.md`](papers/contextual-bandits/script/REFERENCES.md).
9. Tiago Motta, post sobre o serviço de bandit da globo.com, 2024-09-28. Chave `motta2024bandit` em [8].
10. Renan Moreira de Oliveira, "Machine Learning na globo.com", slides, 2018. Chave `oliveira2018globo` em [8].
11. Anthropic, "When AI builds itself", 2026. Chave `anthropic2026builds` em [8].
12. Resenha do artigo SIA (arXiv 2605.27276), 2026. Chave `bhavsar2026sia` em [8]; status `partial`.
