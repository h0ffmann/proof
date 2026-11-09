# CMAB (0:00 a 10:00)

## Gancho (0:00 a 1:00)

**Fala.** Todo agente que aprende precisa de um mecanismo de decisão com estrutura de
recompensa. Ele tem uma crença de hoje: "esta opção agrada em 67 % das vezes". Aí chega um sinal
novo do usuário: gostou, não gostou. A pergunta é sempre a mesma: a crença nova ainda escolhe a
mesma coisa que a crença de hoje? Se sim, nada muda. Se não, o agente muda, e muda por evidência,
não por palpite. Esse mecanismo tem nome: bandit contextual de múltiplos braços, CMAB. Ele é
velho, de 1952, e está no centro de um assunto que começou a ser padronizado em 2026: a
automelhoria recursiva, RSI. Num ambiente real você sempre vai querer comparar a sua crença atual
com uma crença nova, a do usuário. Hoje as interfaces agênticas já leem esse sinal direto da
conversa, e fazem coisas que não cabem neste vídeo. ⚠ `[a confirmar: você citou "Side Agents" da
Anthropic; eu não achei uma fonte primária com esse nome. Qual é a referência?]` Neste vídeo
cabem três coisas: o CMAB, o teste A/B e a RSI. Dez minutos para cada, com código para cada
frase.

**Tela.** Duas barras: "crença atual" e "crença nova", com a seta de escolha mudando de uma opção
para a outra. Em baixo, os três títulos dos blocos.

**Código.** `haskell/app/Video.hs`, `beliefs`, com a regra de `betaBernoulli` em
`haskell/src/Models.hs`. A saída em `results.md`: a crença atual escolhe a opção 0 (0,67);
depois de 4 sinais positivos para a opção 1 e 2 negativos para a 0, a crença nova escolhe a
opção 1 (0,62). "Mudou de ideia? True". A invariante R1 em Lean: `User`, a recompensa é o input
do usuário, em [0, 1].

## Steal like an artist: de onde eu tirei isso (1:00 a 3:00)

**Fala.** Nada aqui é meu. Austin Kleon escreveu em 2012, em *Steal Like an Artist*: "nothing is
original… all creative work builds on what came before" [@wikipedia2026steal]. Esta é a minha
linha do tempo com essa ideia. Em 2018 eu ouvi falar de bandit pela primeira vez, de um amigo do
trabalho. `[a confirmar: quem, e em que mês de 2018?]` Em dezembro de 2017 a Netflix tinha
publicado "Artwork Personalization at Netflix": a imagem de cada título, escolhida para cada
assinante por um bandit contextual [@dezeen2017netflix; @hoffmann2026note]. Eu li depois. Em
2018, Renan Moreira de Oliveira, engenheiro de dados da globo.com, apresentou "Machine Learning
na globo.com", com um slide chamado "MAB ML PARA AB RL" [@oliveira2018globo]. `[a confirmar: ele
foi para a Uber? Eu não encontrei a confirmação.]` Tiago Motta, também da globo.com, conta que o
serviço de bandit deles nasceu num hackday em 2017, em Scala, inspirado no livro de John Myles
White, e que ele "ainda é usado" no portal. Ele publicou isso em 2024 [@motta2024bandit]. E em
2026 o bandit aparece dentro dos ciclos de automelhoria dos agentes: o laço que decide o que mudar
no próprio agente é um laço de escolha com recompensa parcial. Essa é a parte nova. O resto é
roubo bem creditado. A linha do tempo tem um buraco de 58 anos entre Robbins, em 1952
[@wikipedia2026mab], e o LinUCB, em 2010 [@li2010contextual]. Nesse buraco o problema ficou na
estatística e na economia; a internet deu a ele milhões de rodadas por dia, e aí ele virou
engenharia. Reparem na ordem: a teoria veio primeiro, a Netflix depois, a globo.com quase junto,
e eu por último. Nenhum desses passos inventou o anterior. Cada um pegou o anterior e mudou uma
coisa: o contexto, a escala, a infraestrutura, e agora o alvo do laço.

**Tela.** Linha do tempo animada (Manim), um marco por vez: 1952 Robbins formula o problema ·
2010 LinUCB (Li, Chu, Langford, Schapire) · 2012 *Steal Like an Artist* · 2017-12 Netflix · 2017
hackday da globo.com · 2018 o amigo, e os slides da globo.com · 2024 o post de Tiago Motta · 2026
RSI. Cada marco entra com a fonte em letra pequena.

**Código.** `animation/timeline.py`, uma cena Manim com os marcos acima, a fazer depois da
aprovação deste roteiro. As fontes estão na lista de referências.

## O método de escolha, no exemplo simples: π e você, um braço só (3:00 a 5:00)

**Fala.** Vamos começar pelo exemplo mais simples que eu consegui, e com você no meio dele. Dois
algoritmos calculam π. O de Leibniz, de 1674: π sobre 4 é 1, menos um terço, mais um quinto,
menos um sétimo, e assim por diante. Bonito, e lento: com 100.000 termos ele acerta 5 dígitos. O
de Ramanujan, de 1914, o matemático indiano: 1 sobre π é uma soma em que cada termo tem fatoriais
e a constante 26.390. Um termo só acerta 7 dígitos; seis termos acertam 48. Guardem Ramanujan
para a próxima cena. Agora só Leibniz, um braço só: o *single-armed bandit*. O agente tem uma
aproximação, π de N, que você já viu e já avaliou. A cada rodada ele decide uma de duas coisas.
Aproveitar: mostrar π de N de novo, e receber a mesma resposta de sempre. Ou explorar: gastar um
termo, calcular π de N mais 1, mostrar, e ouvir o que você diz. Você responde: está bom? Com
quantos dígitos? Essa resposta é a recompensa. O agente não sabe matemática. Ele não lê a
fórmula. Ele só sabe o que você disse da aproximação que ele mostrou. Esse é o dilema inteiro,
com um braço só: ficar com o que se tem, ou pagar para saber mais. Na simulação, o usuário dá uma
nota pela distância até π, de 0 a 1. Em 20 rodadas o agente aproveitou 9 vezes e explorou 11, e
chegou a π de 12; a nota média de explorar foi 0,76, a de aproveitar 0,14. Faz sentido: com
Leibniz, cada termo novo ainda agrada um pouco mais, e explorar continua pagando. No modo
interativo, você é o usuário, e a tabela é a sua. O ciclo é sempre o mesmo: decidir, mostrar,
receber a sua resposta, atualizar a crença, decidir de novo. A regra que decide é a política.

**Tela.** Uma soma de Leibniz crescendo, estilo 3b1b, oscilando em volta de π. Dois botões:
"π(N)" e "π(N+1)". Um balão "está bom?" com a resposta do usuário entrando como número. Abaixo,
as duas barras de crença do agente, azul, uma por ação, e a seta amarela da escolha.

**Desmos.** `desmos/1-3-pi.txt`: a soma parcial `L(n)` contra a reta `y = π`, e os dígitos
corretos `−log10|L(n) − π|`; o controle `N` anda termo a termo. A cena 1.4 usa o mesmo arquivo
com `R(n)`, de Ramanujan.

**Código.** Lean, `lean/ContextualBandit/Video.lean`: `SA`, `step`, e os teoremas `step_exploit`
(aproveitar não gasta termo), `step_explore_n` (explorar gasta exatamente um),
`step_explore_reward` (a nota não cai) e `step_reward_bounded` (a nota fica em [0, 1]);
`leibnizEven_lt_succ`, as somas pares de Leibniz crescem. Haskell, `haskell/src/Video.hs` (os
mesmos nomes) e `haskell/src/Pi.hs` (`leibnizS`, `digitsCorrect`); a simulação é `singleArmed`
em `haskell/app/Video.hs`. A tabela de dígitos por termo e a de 20 rodadas estão em
`results.md`.

## O nome, letra por letra: de um braço a vários (5:00 a 6:30)

**Fala.** B de bandit. A máquina caça-níquel é o "one-armed bandit", o bandido de um braço só,
porque ela leva o seu dinheiro. M e A de multi-armed: agora são várias alavancas lado a lado,
cada uma com um prêmio médio que ninguém conhece. Herbert Robbins formulou essa versão em 1952
[@wikipedia2026mab]. No nosso exemplo entram mais duas alavancas. A de Gauss, o príncipe dos
matemáticos: o algoritmo de Gauss-Legendre, pela média aritmético-geométrica, dobra os dígitos a
cada passo: 3, 8, 19, 41. E a de Ramanujan, o matemático indiano, que eu chamo de rei: 7 dígitos
por termo, 48 em seis. Agora explorar não é só ir mais fundo em Leibniz: é puxar outra alavanca
para ver o que ela rende. Na simulação, com o mesmo usuário, em 20 rodadas o agente puxou
Ramanujan 16 vezes, Gauss-Legendre 3 e Leibniz 1, e terminou com 61, 19 e 0 dígitos certos. Ele
não leu as fórmulas; ele ouviu você. Uma observação honesta: com nota pela distância,
Gauss-Legendre e Ramanujan empatam em 1,00 depois do primeiro termo; o agente ficou com Ramanujan
porque a regra gulosa desempata pelo primeiro máximo. Para separar os dois, a nota teria de ser
por dígito. C de contextual: antes de puxar, você vê um dado da rodada, por exemplo manhã ou
noite. A Wikipedia chama isso de "a useful generalization of the multi-armed bandit"
[@wikipedia2026mab]. No código, cada letra é um tipo: M e A são a lista de braços, `Arm`, e C é o tipo do
contexto `c` em `RewardModel c b`. Esse é o ambiente, o que paga. A escolha fica em outro
arquivo, `DecisionRule`, de propósito. O exemplo de π não
tem contexto, por isso ele é um MAB e não um CMAB. Uma observação sobre o nome: a palavra bandit
assusta, mas ela só diz que a máquina está contra você. A palavra que importa é contextual. Sem
contexto, a melhor alavanca é uma só para o mundo inteiro. Com contexto, a melhor alavanca muda a
cada rodada, e a política precisa aprender uma função: do contexto para a alavanca. No LinUCB o
contexto é um vetor de números, e a função é linear [@li2010contextual]. Na sorveteria o contexto
tem dois valores, manhã e noite, e a função é uma tabela.

**Tela.** As letras C, M, A, B aparecem uma a uma; cada uma vira uma peça do desenho: uma
alavanca (Leibniz), três alavancas (entram Gauss-Legendre e Ramanujan), um relógio ao lado. A
soma de Ramanujan cola em π no primeiro termo; a de Gauss-Legendre dobra os dígitos a cada passo;
a de Leibniz oscila.

**Código.** `haskell/src/Pi.hs`: `leibnizS`, `gaussLegendreS`, `ramanujanS`, `sqrtRat`; a
simulação é `multiArmed` em `haskell/app/Video.hs`. Lean: `ramTerm_pos` e `ramSum_lt_succ`, cada
termo de Ramanujan é positivo e as somas parciais crescem; `ramApprox_anti`, a aproximação desce
para π por cima. O ambiente com contexto do bloco 2 é `rate` e `shop` em `haskell/app/Video.hs`.

## Modelo e regra, separados (6:30 a 7:30)

**Fala.** O repositório divide o agente em duas camadas. O modelo de recompensa guarda uma crença
e, para cada sabor, dá duas coisas: a média prevista e uma largura, a incerteza. A regra de
decisão vê só essas estimativas. Ela nunca vê o histórico nem o contexto. Essa fronteira é um
teorema do repositório, `policy_factors`: dois históricos com a mesma crença dão a mesma decisão.
Por isso você troca o modelo sem mexer na regra, e troca a regra sem mexer no modelo. O modelo
deste vídeo é tabular: uma soma e uma contagem por sabor e por contexto; a média é soma sobre
contagem; a largura é 1 sobre contagem mais 1. Em Haskell o repositório tem três modelos:
Beta-Bernoulli, regressão linear bayesiana, e um invólucro para qualquer modelo que você já
tenha, desde que ele devolva média e desvio. Regra de decisão é a mesma para os três. Isso é o
que a fronteira compra.

**Tela.** Duas caixas: "modelo" à esquerda, "regra" à direita, ligadas só por uma seta "(média,
largura) por sabor". O histórico entra só na caixa da esquerda.

**Desmos.** `desmos/1-5-width.txt`: a largura `1/(n+1)` e a largura real `1/sqrt(n)` no mesmo
gráfico, com `n` de 1 a 100. As duas caem; a do Lean é racional, para o `#eval` ser exato.

**Código.** Lean: `lean/ContextualBandit/Interface.lean` (`RewardModel`, `Estimate`,
`DecisionRule`, `policy`) e `Theorems.lean` (`policy_factors`). Haskell:
`haskell/src/ContextualBandit.hs`, os mesmos nomes; o modelo tabular do vídeo é `tabular` em
`haskell/app/Video.hs`.

## Explorar e aproveitar (7:30 a 8:30)

**Fala.** Aproveitar é escolher o sabor com a maior média. Explorar é escolher outro, para
aprender. Quem só aproveita pode ficar preso: depois de três clientes, a média de um sabor bom
pode estar baixa demais, e ele nunca mais sai da gaveta. Quem só explora perde venda nos sabores
ruins. Três regras equilibram isso. A gulosa não explora. A ε-gulosa sorteia um sabor qualquer
com probabilidade ε e, no resto, é gulosa. A UCB soma à média um bônus de incerteza, β vezes a
largura: ela é otimista com o que conhece pouco. Com β igual a zero, a UCB vira a gulosa. O
repositório prova isso: `ucb_zero`. Há uma quarta regra, a amostragem de Thompson: em vez da
média, ela sorteia uma média plausível da crença de cada sabor e escolhe a maior. Um sabor com
crença larga sorteia valores altos de vez em quando, e por isso é explorado. No repositório ela
está em Haskell, `thompsonArm`, porque precisa de um modelo que saiba sortear.

**Tela.** Três colunas com as mesmas estimativas; a seta de cada regra aponta para um sabor; a da
UCB sobe a barra da incerteza.

**Desmos.** `desmos/1-6-ucb.txt`: três pontos (média, largura) e a pontuação `m + b·w` de cada
um; o controle `b` vai de 0 a 3 e o sabor vencedor troca na tela.

**Código.** Lean: `greedy`, `epsGreedy`, `ucb` em `Policies.lean`, `ucb_zero` em
`Theorems.lean`. Haskell: os mesmos nomes em `haskell/src/ContextualBandit.hs`; o spec check de
`haskell/app/Main.hs` confere o `#eval` de `Examples.lean`: `[0, 1, 0]` de manhã, `[0, 0, 1]` de
noite e `[1/30, 14/15, 1/30]` para ε = 1/10.

## O exemplo complexo: a Netflix (8:30 a 10:00)

**Fala.** Do exemplo simples para o complexo. Em dezembro de 2017 a Netflix publicou "Artwork
Personalization at Netflix" [@dezeen2017netflix; @hoffmann2026note]. O problema: para cada
título, há várias imagens de capa; qual mostrar para cada assinante? Monte as peças. O contexto é
o histórico do assinante e o país. Os braços são as imagens. A recompensa é a reprodução: o
assinante deu play ou não. Tony Jebara contou, em 2018, que o sistema recebe cerca de 20 milhões
de pedidos de imagem por segundo no pico [@jebara2018artwork]. É o mesmo ciclo do π, com três
diferenças. O contexto existe, e é grande. A recompensa não é uma pessoa dizendo "está bom": é
uma pessoa agindo, sem saber que está respondendo. E a escala obriga o modelo a generalizar: não
dá para ter uma tabela por assinante. No exemplo de π você era a recompensa e sabia disso. Na
Netflix, você é a recompensa e não sabe. A estrutura de decisão é a mesma. O que muda é de onde
vem o sinal, e esse é o fio que leva até o bloco 3.

**Tela.** Um título, três capas. Um assinante, o histórico dele como uma fita de ícones, o país. A
seta amarela escolhe uma capa; o play aparece ou não; a barra azul daquela capa, para aquele
perfil, sobe ou desce. Em canto, "20 M pedidos/s".

**Código.** O modelo que generaliza é `bayesLinear` em `haskell/src/Models.hs`: a média é um
produto escalar entre o contexto e os pesos do braço. O modelo tabular do vídeo
(`haskell/app/Video.hs`) é a mesma interface com um modelo menor. A Netflix: a nota
`MULTI_ARMED_CONTEXTUAL_BANDIT.pt-BR.md`, seção 4 [@hoffmann2026note].
