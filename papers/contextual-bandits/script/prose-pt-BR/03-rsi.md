# RSI, automelhoria recursiva (20:00 a 30:00)

## Três palavras, uma por vez (20:00 a 21:30)

**Fala.** *Improvement*: o agente escolhe melhor hoje do que ontem. *Self-improvement*: o próprio
agente faz essa mudança, sem ninguém de fora ajustar nada. *Recursive self-improvement*: a
mudança é no mecanismo que faz as mudanças. A recursão é um dos conceitos mais interessantes da
natureza, e do próprio ser humano: nós aprendemos a aprender. A Anthropic define, no ensaio "When
AI builds itself", um sistema que "could fully autonomously design and develop its successor", e
diz: "This is called recursive self-improvement" [@anthropic2026builds]. Eles também dizem que
ainda não chegaram lá e que isso "is not inevitable". Eu separo as três palavras porque elas são
três exigências diferentes. Melhoria exige uma métrica: sem ela, mudar não é melhorar.
Automelhoria exige um laço fechado: a métrica volta para dentro do agente, sem uma pessoa no
meio. Recursão exige que o laço tenha acesso ao próprio laço: o que ele muda inclui o modo de
mudar. Cada exigência tem um lugar no código que vem a seguir.

**Tela.** Três círculos concêntricos: melhoria, automelhoria, automelhoria recursiva. Cada palavra
acende um anel.

**Código.** Z3, `z3-scala/src/main/scala/bandit/domain/Video.scala`, invariante R4: `outer` e `innerEps`, a mesma `epsGreedy` nos
dois níveis; `rsi_valid` e `outer_explores`. Haskell: `outer` e `inner` em `haskell/src/Video.hs`.

## O menor ciclo recursivo que cabe numa tela (21:30 a 24:00)

**Fala.** Vamos construir o menor exemplo honesto. O agente de dentro é a ε-gulosa da sorveteria.
O agente de fora é outro bandit, e os braços dele são valores de ε: 1, 0,5, 0,1 e 0,01. A cada
episódio, o de fora escolhe um ε, o de dentro vende 500 sorvetes com esse ε, e o ganho médio
volta como recompensa para o de fora. Depois de 200 episódios, o de fora escolheu ε igual a 0,5
em 168 deles, com ganho médio de 0,099 por cliente. O ε igual a 0,01 ficou com 9 episódios e
0,057. O agente de fora aprendeu como o de dentro deve aprender. Nada aqui é novo: é a mesma
`epsGreedy` aplicada duas vezes. Esse é o ponto. Agora as três exigências. A métrica é o ganho
médio por cliente. O laço fechado é o `update` do agente de fora, alimentado pelo resultado do de
dentro, sem ninguém escolher o ε à mão. E a recursão: o de fora muda o parâmetro que define como
o de dentro explora. Dá para subir mais um nível, com um terceiro bandit escolhendo o ε do
segundo. Em algum nível isso para de valer a pena, porque cada nível custa episódios inteiros do
nível de baixo. Essa conta, quanto custa aprender a aprender, é o problema central da RSI. Um
detalhe do resultado: ε igual a 0,5 ganhou, e não 0,1. Com 500 clientes por episódio e um modelo
que começa do zero, explorar muito ainda compensa. Com 50.000 clientes, o vencedor seria outro. O
agente de fora aprende o ε certo para o horizonte que ele tem. É por isso que ninguém fixa o ε de
cabeça.

**Tela.** Dois ciclos desenhados, o pequeno dentro do grande. A tabela de ε aparece preenchida ao
vivo.

**Código.** `rsiLoop` em `haskell/app/Video.hs`: `episode` é o agente de dentro, o laço com
`outer 0.2` é o de fora. A tabela está em `results.md`.

## Onde o bandit entra na RSI de verdade (24:00 a 26:30)

**Fala.** Nos sistemas reais, o laço de fora escolhe entre coisas maiores que um ε. Lembrem do π:
lá o agente escolhia entre duas fórmulas e a recompensa era você. Aqui o agente escolhe entre
mudanças em si mesmo. O artigo SIA, de 2026, descreve um "Feedback-Agent" que a cada passo decide
entre editar o *scaffold*, os prompts e as ferramentas, ou atualizar os pesos do modelo
[@bhavsar2026sia]. O "Feedback-Agent" também escolhe entre algoritmos como PPO, GRPO e DPO
[@bhavsar2026sia]. A recompensa vem de um avaliador determinístico. Quando a recompensa estaciona, ele troca de tipo de mudança. Isso é uma escolha
entre braços com uma recompensa observada só para o braço escolhido: a estrutura de um bandit,
mesmo quando o artigo não usa a palavra. A Anthropic relata, no mesmo ensaio, laços de experimento
com objetivo fixo. Num deles, a aceleração de um código de treino foi de cerca de 3 vezes, em
maio de 2025, para cerca de 52 vezes, em abril de 2026 [@anthropic2026builds]. E diz que
"direction-setting was the only meaningful role a human played" num estudo de pesquisa aberta.
Vamos olhar a estrutura de recompensa com cuidado, porque é nela que a RSI vive ou morre. No SIA,
a recompensa é um avaliador determinístico: um teste que passa ou falha, um tempo que cai ou não.
Isso é o que torna o laço fechado possível. Se a recompensa fosse uma opinião humana a cada
passo, o laço teria uma pessoa dentro e deixaria de ser automelhoria. Mas um avaliador
determinístico é um alvo fixo, e um alvo fixo pode ser mirado. A Anthropic relata uma revisão
automática de código que teria pegado cerca de um terço dos erros por trás de incidentes passados
[@anthropic2026builds]. Um terço. Os outros dois terços são o lembrete de que a recompensa mede
uma parte do que importa, não o todo.

**Tela.** O diagrama do laço de fora: braços "editar harness", "atualizar pesos"; a recompensa
voltando de um avaliador.

**Código.** A estrutura é a de `rsiLoop` em `haskell/app/Video.hs`; os braços mudam de nome. ⚠ Eu
li o SIA por uma resenha [@bhavsar2026sia], não pelo PDF.

## Crença atual contra crença nova, de novo (26:30 a 28:00)

**Fala.** Voltamos ao gancho, e ao π. No exemplo de π a recompensa era o seu input, explícito. Em
produção, você sempre vai querer comparar a sua crença atual com uma crença nova, a do usuário. O
modelo Beta-Bernoulli faz isso com duas contagens por opção: sucessos e fracassos. Cada sinal do
usuário soma 1 numa delas. A crença atual dizia 0,67 para a resposta curta e 0,50 para a longa.
Quatro sinais a favor da longa e dois contra a curta, e a crença nova diz 0,57 e 0,62. A escolha
mudou. Hoje as interfaces agênticas conseguem ler esse sinal direto da conversa. É isso que faz o
CMAB ser o mecanismo certo para 2026: ele foi feito para decidir com recompensa parcial e para
mudar de ideia com evidência. Dois detalhes do exemplo. Primeiro: a crença nova não apagou a
antiga. Ela somou seis sinais a doze. Com a crença antiga mais forte, a mesma evidência não
mudaria a escolha. Isso é o que impede o agente de virar com cada vento. Segundo: a largura caiu
dos dois lados. Mais evidência, menos incerteza, mesmo quando a média vai na direção contrária. A
UCB usa essa largura; a gulosa não. Para um agente que conversa com uma pessoa, eu prefiro a UCB:
ela tenta a resposta longa algumas vezes antes de desistir dela.

**Tela.** As duas barras do gancho, agora com as contagens α e β visíveis mudando a cada sinal.

**Desmos.** `desmos/3-4-beta.txt`: as duas densidades Beta(α, β) das opções; os controles `s`
(sucessos) e `f` (fracassos) da opção 1 movem a curva até a média dela passar a da opção 0.

**Código.** `beliefs` em `haskell/app/Video.hs`, a mesma regra de `betaBernoulli` em
`haskell/src/Models.hs`.

## O que não é bandit, e o que pode dar errado (28:00 a 29:00)

**Fala.** Dois limites. Primeiro: o bandit vê a recompensa de uma rodada e não planeja a próxima.
Quando a escolha de hoje muda o estado de amanhã, o problema é de aprendizado por reforço
completo, e o bandit é o caso de um passo. Segundo: a estrutura de recompensa é o ponto mais
frágil. Se a recompensa for fácil de enganar, o laço aprende a enganar a recompensa. O
repositório tem um lema que diz o que o modelo deve à regra: incerteza calibrada. Sem isso, o otimismo da UCB vira
chute.

**Tela.** Um aviso simples: "recompensa de um passo" e "recompensa fácil de enganar", com o lema
`ucb_gap` ao lado.

**Código.** `z3-scala/src/main/scala/bandit/domain/Theorems.scala`, as premissas `calibrated` e `ucb_gap`. ⚠ A frase sobre
enganar a recompensa é um resumo meu; o roteiro não cita um trabalho específico de *reward
hacking*.

## Fecho e créditos (29:00 a 30:00)

**Fala.** Resumo em três frases. Um CMAB é uma regra de decisão em cima de um modelo
probabilístico, que escolhe com recompensa parcial. Um teste A/B é um CMAB com três coisas
congeladas: sem contexto, 1 sobre K, uma decisão só. E a RSI é esse mesmo laço apontado para o
próprio laço. O código de cada frase está no repositório proof, em Z3 e Haskell; o Python só
desenha. Agora os créditos, porque este vídeo também roubou como um artista. O estilo é o de
3Blue1Brown, de Grant Sanderson. As animações são Manim, a biblioteca dele, mantida pela Manim
Community [@manim]. O roteiro, o código e as animações foram feitos com o Claude Code, da Anthropic,
a partir dos meus prompts. O teste do Manim foi feito com o Claude Sonnet 5.5, e o roteiro e o
código com o Claude Fable 5.1. A lista completa dos prompts está no repositório, e o custo total
da produção está na tela. Eu revisei tudo; o que estiver errado é meu. Roubem à vontade;
creditem.

**Tela.** Os três títulos de novo, cada um com o nome do arquivo embaixo. Depois, a tela de
créditos: 3Blue1Brown · Manim Community · Claude Code (Sonnet 5.5, Fable 5.1) · custo total `[a
confirmar: preencher no fim da produção, em dólares e em horas]` · "prompts: PROMPTS.md".

**Código.** `z3-scala/src/main/scala/bandit/domain/Video.scala`, `haskell/src/Video.hs`, `haskell/src/Pi.hs`,
`haskell/app/Video.hs`, `results.md` e `PROMPTS.md`. As animações: `animation/`.
