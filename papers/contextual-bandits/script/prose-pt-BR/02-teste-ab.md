# Teste A/B (10:00 a 20:00)

## O que é um teste A/B (10:00 a 11:30)

**Fala.** A Wikipedia define: "'A/B testing' is a shorthand for a simple randomized controlled
experiment" [@wikipedia2026ab]. Você tem K variantes. Cada visitante cai numa variante por
sorteio, com a mesma probabilidade. Depois de um tempo, a equipe olha os números, escolhe a
melhor variante e manda todo mundo para ela. Duas fases: sortear, depois decidir. Em inglês,
*explore-then-commit*. O teste A/B tem três virtudes que explicam por que ele dominou a web por
vinte anos. Ele é simples de montar: um sorteio e uma contagem. Ele é simples de ler: a diferença
entre as médias é o efeito. E ele é simples de defender: a alocação é fixa, e ninguém mexeu nela
durante o teste. Guardem essas três virtudes. O bandit troca as duas primeiras por velocidade e
paga na terceira.

**Tela.** Uma fila de visitantes dividida em três caminhos iguais; no fim, um portão fecha dois
caminhos.

**Desmos.** `desmos/2-1-ab.txt`: duas Bernoulli com `p_A` e `p_B` em controles; `n` visitantes
por variante; o intervalo de confiança das duas médias encolhe quando `n` cresce.

**Código.** Z3: `uniform(K)` em `z3-scala/src/main/scala/bandit/domain/Bandit.scala`; a invariante R3, `etc` em `z3-scala/src/main/scala/bandit/domain/Video.scala`, com
`etc_before`: antes da troca, a alocação é `uniform`. Haskell: `etc` em `haskell/src/Video.hs`.

## O teste A/B é uma regra de bandit (11:30 a 13:00)

**Fala.** Agora a ponte. A ε-gulosa com ε igual a 1 ignora o modelo e sorteia cada sabor com
probabilidade 1 sobre K. Isso é o período de teste de um teste A/B/n. Não é uma analogia: é o
teorema `epsGreedy_one_is_ab_test`, provado no repositório. E a segunda fase, decidir e ficar na
melhor, é a ε-gulosa com ε igual a 0, a gulosa. Então um teste A/B é uma política de bandit com
um ε que pula de 1 para 0 num dia marcado. Eu gosto desse jeito de ver, porque ele transforma uma
discussão de time, "A/B ou bandit?", numa escolha de um número: como ε deve cair ao longo do
tempo. De 1 para 0 num salto, é o teste A/B. Constante em 0,1, é a ε-gulosa. Caindo devagar, é
um esquema intermediário. A pergunta deixa de ser qual ferramenta e passa a ser qual curva.

**Tela.** Um controle deslizante de ε. Em 1, as três barras iguais. Em 0, uma barra só. O título:
"teste A/B = ε de 1 para 0".

**Desmos.** `desmos/2-2-epsilon.txt`: a mistura `e/K + (1-e)·[a = melhor]` para três braços; o
controle `e` de 0 a 1 é a cena inteira.

**Código.** Z3: `epsGreedy_one_is_ab_test` (ε = 1 é o sorteio uniforme) em `z3-scala/src/main/scala/bandit/domain/Theorems.scala`;
`epsGreedy_zero` (ε = 0 é a gulosa), `etc_after` e `etc_valid` em `z3-scala/src/main/scala/bandit/domain/Video.scala`. Haskell: `etc 10 3`
dá `[1/3, 1/3, 1/3]` e `etc 10 10` dá `[0, 1, 0]`, conferidos contra os exemplos do Z3 no spec check.

## O custo da espera (13:00 a 15:00)

**Fala.** O que o teste A/B custa? Durante toda a fase de sorteio, dois terços dos clientes veem
um sabor pior. Esse custo tem nome: arrependimento. É a soma, rodada a rodada, da média do melhor
sabor menos a média do sabor escolhido. Tony Jebara, da Netflix, chamou o ciclo "coletar dados
por meses, treinar, depois testar" de "a massive amount of regret" [@jebara2018artwork]. Para
medir, eu simulei uma sorveteria: três sabores, uma vitrine com espaço para um, e taxas secretas,
as do repositório. De manhã, o sabor 1 vende para 12 % dos clientes; de noite, o sabor 2 vende
para 15 %. A política não conhece essas taxas; eu conheço porque escrevi a simulação. Com 5.000
clientes, metade na fase de sorteio, o teste A/B acumula 129 de arrependimento. A ε-gulosa com ε
igual a 0,1 acumula 76. A UCB com β igual a 2 acumula 20. Mesma sorveteria, mesmo modelo, só a
regra mudou. Por que o teste A/B custa tanto? Porque ele é cego durante metade do tempo, por
decisão. Na rodada 100 ele já sabe que o sabor 0 vende mal de manhã, e continua mandando um terço
dos clientes para ele até a rodada 2.500. A ε-gulosa manda só um trinta avos. A UCB manda
enquanto a largura daquele sabor ainda é grande, e para quando a largura encolhe. A diferença de
129 para 20 é a diferença entre ignorar e usar a informação que já chegou.

**Tela.** Quatro curvas de arrependimento acumulado subindo; a do teste A/B sobe reta até a
metade e depois quase para; a da UCB fica embaixo.

**Desmos.** `desmos/2-3-regret.txt`: o arrependimento esperado do teste A/B em forma
fechada, `(T/2)·g + 0`, contra o da ε-gulosa, `T·e·g`, com `g` o salto médio e `e` em controle;
mostra em que ε as duas retas se cruzam.

**Código.** `abVsBandit` em `haskell/app/Video.hs`, média de 20 sementes (`results.md`); a
sorveteria é `rate` e `shop`, com as taxas de `haskell/app/Main.hs` (`ctr`). A Netflix: a nota do
repositório, seção 4.1 [@hoffmann2026note], e a palestra de Jebara [@jebara2018artwork].

## O contexto personaliza o teste (15:00 a 16:30)

**Fala.** Um teste A/B acha uma melhor variante para todo mundo. Mas na sorveteria o melhor sabor
de manhã não é o melhor de noite. Um teste A/B que ignora a hora escolhe um sabor só e perde dos
dois lados: 179 de arrependimento, contra 129 do teste que separa manhã e noite. Um teste A/B por
segmento é um caso particular de bandit contextual. O bandit contextual acha a melhor variante
para cada contexto, e o contexto pode ser um vetor com dezenas de dimensões, como em Li, Chu,
Langford e Schapire, em 2010, no LinUCB [@li2010contextual]. Com um vetor, não dá mais para ter
uma tabela por contexto: há contextos demais, e cada um aparece uma vez. O modelo precisa
generalizar entre contextos parecidos. É aí que entra a regressão: a média do sabor é um produto
escalar entre o contexto e um vetor de pesos do sabor, e a largura vem da covariância desses
pesos. A regra de decisão não muda uma linha.

**Tela.** Duas vitrines, manhã e noite, com o sabor vencedor diferente em cada uma. A linha "sem
contexto" com um sabor só nas duas.

**Código.** `abVsBandit` em `haskell/app/Video.hs`, política "A/B sem contexto": o mesmo `etc`
sobre um modelo com um único contexto `()`.

## O que o teste A/B ainda faz melhor (16:30 a 18:00)

**Fala.** Então o teste A/B morreu? Não. A alocação fixa e aleatória dá uma estimativa simples e
sem viés do efeito. O bandit muda a alocação enquanto aprende; a média simples dos registros fica
com viés. Para avaliar um bandit *offline*, você registra a probabilidade de cada escolha e usa
*replay* ou ponderação pelo inverso da propensão. Li e colegas argumentam, em 2010, que "any
bandit algorithm can be reliably evaluated offline using previously recorded random traffic"
[@li2010contextual]. A Netflix ainda aprovou o sistema de imagens com um teste A/B antes de ligar
para todos [@jebara2018artwork]. O bandit substituiu o ciclo lento dentro do teste, não o teste.
O *replay* funciona assim: você tem um registro de rodadas com escolhas uniformes. Para avaliar
uma política nova, você percorre o registro; quando a política nova escolhe o mesmo braço que o
registro, a rodada conta; quando não, a rodada é descartada. A média das rodadas que contaram é
uma estimativa sem viés do que a política nova faria. O preço é jogar fora K menos 1 de cada K
rodadas.

**Tela.** Dois gráficos: "alocação fixa, média sem viés" e "alocação que muda, média com viés", e
a correção por propensão.

**Desmos.** `desmos/2-5-propensity.txt`: a média simples e a média ponderada por `1/p` de uma
amostra em que o braço bom foi escolhido com probabilidade `p`; o controle `p` mostra o viés
aparecer e a correção o desfazer.

**Código.** `policy` em `haskell/src/ContextualBandit.hs` (e em `z3-scala/src/main/scala/bandit/domain/Examples.scala`) devolve a
distribuição inteira, não só o braço: essa distribuição é a propensão que o *replay* precisa
registrar.

## Resumo do bloco (18:00 a 20:00)

**Fala.** O teste A/B é um bandit com três escolhas fixas: sem contexto, alocação uniforme, e uma
decisão só, no fim. O bandit contextual relaxa as três. Ele usa o contexto, muda a alocação a
cada rodada e decide sempre. O preço é a avaliação *offline*, que fica mais difícil. No Brasil, a
globo.com usa um serviço de bandit desde 2017 para "escolher uma foto" e "a melhor posição para
colocar publicidade", nas palavras de Tiago Motta [@motta2024bandit]. Na próxima parte, o bandit
sai do site e entra no agente. Antes, uma regra prática. Use o teste A/B quando a decisão é uma
só e precisa ser defendida: um preço, uma mudança de marca, algo que vai para um comitê. Use o
bandit quando a decisão se repete milhares de vezes por dia e o custo de errar em cada uma é
pequeno: uma imagem, uma posição, uma frase de abertura. E use os dois quando puder: o bandit por
dentro, o teste A/B por fora, como a Netflix. Essa combinação é a que a maioria das equipes acaba
adotando, porque ela fica com a velocidade de um e a defesa do outro. E para fechar o bloco, cinco
fatos sobre tudo isso estão provados pelo Z3, por refutação. Toda regra devolve uma distribuição de
probabilidade. A ε-gulosa dá a cada braço pelo menos ε sobre K. A gulosa e a UCB escolhem um máximo
de verdade. A ε-gulosa com ε igual a 1 é o teste A/B. E o lema do otimismo, `ucb_gap`: se
o modelo é calibrado, o braço da UCB perde no máximo 2 β vezes a largura para o melhor. A parte
probabilística da cota de arrependimento está fora do que o Z3 decide e fica aberta. Eu digo isso para
separar o que este vídeo mostra, a parte determinística e executável, do que ele não mostra.

**Tela.** Tabela de três linhas: contexto, alocação, decisão; coluna A/B e coluna CMAB. Depois, a
tabela de teoremas do README, uma linha por vez.

**Código.** A tabela é a seção 3 da nota `MULTI_ARMED_CONTEXTUAL_BANDIT.pt-BR.md`
[@hoffmann2026note]. Os teoremas estão em `z3-scala/src/main/scala/bandit/domain/Theorems.scala`, provados para até cinco braços e
todo valor real das estimativas. O Python do Manim não prova nada; ele só desenha o que o Z3 provou.
