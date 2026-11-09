# Prompts

Os prompts que fizeram este diretório, como foram digitados, em ordem, com a hora em UTC. O
modelo que respondeu está na segunda coluna. O custo total entra aqui no fim da produção.

| Hora (UTC) | Modelo | O que fez |
|---|---|---|
| 2026-11-09 01:35 | Claude Sonnet 5.5 | instalou o Manim e renderizou `SquareToCircle` (teste) |
| 2026-11-09 02:15 a 02:26 | Claude Fable 5.1 | pesquisou, escreveu `ROTEIRO.pt-BR.md`, `codigo/`, `voz/`, `desmos/` |

Custo total: `[a confirmar: preencher no fim]`.

## 1. 2026-11-09 01:35

```text
from manim import *


class SquareToCircle(Scene):
    def construct(self):
        circle = Circle()
        square = Square()
        square.flip(RIGHT)
        square.rotate(-3 * TAU / 8)
        circle.set_fill(PINK, opacity=0.5)

        self.play(Create(square))
        self.play(Transform(square, circle))
        self.play(FadeOut(square))

render it for me with sonnet
```

## 2. 2026-11-09 02:15

```text
agora faca um script para uma explicacao minha sobre CMAB contextual armed bandit. Faca pesquisa breve na internet, e faca uma pesquisa profunda em h0ffmann/proof pelos arquivos e textos do  contextual bandit.
Every piece written must have its associated source code. ELI5 style. PTBR only first. Use o portugues tecnico controrlado do kayquer do github

0. Voices using OpenVoice, most commonly used voice narrator, brazilian portuguese remember

1. Gancho, porque é importante - é um mecanismo de decisao que contém a estrutura de reward, muito usada em mecanismos de RSI, Recursive Self Improvement. Em um ambiente real provavelmente vc sempre vai querer querer comparar seu belief atual vs um novo believe do usuario. E hoje as interfaces agenticas sao muito capazes nao só de entender como está sendo sua experiencia, como coisas mais interessantes que nao cabem nesse video, como os Side Agents da Anthropic.
2. Finalmente um dos assuntos que eu tenho estudado tem ganhado renome, vamos dizer, esta sendo padronizado, Recursive Self Improvement. Improvement, Self-improvement, recursive self improviment. 


A recursividade é um dos conceitos mais interessantes da natureza nao só do mundo como do proprio ser humano

1. Explicacao comeca numa introducao sobre o método de escolha.
2. Porque desse nome feito, letra por letra
3. Introducao sobre testes A/B
4. Porque CMAB é um teste A/B generalizado
```

## 3. 2026-11-09 02:15

```text
E crie um PR com o que vc fizer no h0ffmann/proof na mesma pasta do contextual-bandit
```

## 4. 2026-11-09 02:18

```text
deve ter animacao do steal like an artist, explicando onde isso veio, que eu ouvi de um amigo do trabalho pela primeira vez em 2018, depois vi o artigo da netflix sobre isso em XXXX e o post do engenheiro da globo eu acho que foi pro uber renan XXXX (fazer busca) e agora mostrar na timeline 2026 como CMAB se encaixa em 2026
```

## 5. 2026-11-09 02:20

```text
CMAB, A/B, RSI

O video inteiro deve cobrir esses 3 assuntos com profundidade. 10 minutos pra cada
```

## 6. 2026-11-09 02:21

```text
me mostre o roteiro completo antes de fazer a animacao manim
```

## 7. 2026-11-09 02:21

```text
Eu queria fazer algumas partes do video com desmos, faca uma sugestao
```

## 8. 2026-11-09 02:22

```text
e quando for fazer o video, faca take por take,  para facilitar edicao
```

## 9. 2026-11-09 02:26

```text
O video deve ter o estilo do 3b1b e ele deve ser citado, assim como o manim, claude code, Fable, custo total (so atualize no final), list de prompts
```
