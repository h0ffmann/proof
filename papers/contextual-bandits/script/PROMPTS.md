# Prompts

The prompts that made this folder, as typed, in order, with the time in UTC. The model that
answered is in the second column. The total cost goes here at the end of the production. The
prompts are quoted as they were written, most of them in Portuguese; the prose of this file is
English, as the language rule of `AGENTS.md` asks.

| Time (UTC) | Model | What it did |
|---|---|---|
| 2026-11-09 01:35 | Claude Sonnet 5.5 | installed Manim and rendered `SquareToCircle` (a test) |
| 2026-11-09 02:15 to 02:30 | Claude Fable 5.1 | researched, wrote the script (today in `prose-pt-BR/`), `voice/`, `desmos/` |
| 2026-11-09 02:41 to 02:58 | Claude Fable 5.1 | `lean/ContextualBandit/Video.lean` (R1 to R5), `haskell/src/Video.hs`, `Pi.hs`, `app/Video.hs`; the Python of the script left, it stays for the animation only; issues #18 to #21 and piabrota/nix-os#172 |
| 2026-11-09 03:03 to 03:15 | Claude Fable 5.1 | the PR in the `bipr` format; the script became a paper (`metadata.md`, `prose-pt-BR/`, `refs.bib`, `REFERENCES.md`, `just script`); the Haskell rewritten for reading; `z3/video.py` |
| 2026-11-09 03:24 | Claude Fable 5.1 | the language rule in `AGENTS.md` and `z3/language.py`; every file of this folder except the script itself in English; the Portuguese files renamed with `pt-BR` |

Total cost: `[a confirmar: fill in at the end]`.

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

## 10. 2026-11-09 02:27

```text
Use como exemplo para o algoritmo de pi, tanto com equacao do liebniz, tanto com a equacao do indiano que eh muito mais precisa
```

## 11. 2026-11-09 02:27 a 02:28

```text
A ideia é o reward ser o input do usuario
se a aproximacao de pi esta bom, com digitos
e todo o codigo disso deve estar anexado tambem
esse seria o exemplo simples, pra ir pro exemplo mais complexo, da netflix
```

## 12. 2026-11-09 02:30

```text
exploitation = pi (N)
exploration pi = pi(N+1)
esse seria o single armed ...
```

## 13. 2026-11-09 02:41

```text
eu gostei, é um bom draft, ja aprovei, mark this PR as PTBR [] .
crie invariants baseadas nos meus requisitos, como simbolos,em lean ou z3. Eu acho que ja existe codigo Lean no repositorio sobre CMAB, atualize ele, e o haskell tb
```

## 14. 2026-11-09 02:41

```text
A equacao do Pi sera feita em Haskell
O principe dos matemáticos
Animacao PY, codigo real Haskell
```

## 15. 2026-11-09 02:42 a 02:44

```text
create issue for EN version of CMAB screenplay/video
create issue on how make screenplay mobile friendly
```

## 16. 2026-11-09 02:52

```text
King of Mathematicians, the indian guy with pi equation, this must be noted in english. Another invariant. Every code and code comment must be pure ASD-STE100
symbolic invariant
```

## 17. 2026-11-09 02:53 a 02:58

```text
create issue to add my own record on mac about the claude project behind CMAB conscruction without Claude Code CLI
create another issue to index this youtube final video in piabrota/nix-os website to be exposed in cmab.piabrota.art. This cite must index the h0ffmann/proof repository (SRC) (create issue in piabrota/nix-os as well), have a explanation of 10 minutes about CMAB and the video
```

## 18. 2026-11-09 03:03

```text
use piabrota gramatico bipr skill
```

```text
por this PR
```

## 19. 2026-11-09 03:07

```text
renderize o MD como paper, com paper quality do h0ffmann/proof (pandoc)
```

```text
md do roteiro
```

## 20. 2026-11-09 03:12 a 03:13

```text
the haskell code in the PR is horrivel, impossivel to read. Improve it. Write like a Sr. Haskell dev (Ponytail audit)
```

```text
This equations should be easy to read, ergonomic
```

## 21. 2026-11-09 03:15

```text
add z3 implementation
```

## 22. 2026-11-09 03:24

```text
tem varios arquivos em portugues ainda no repositorio, achava que isso era uma invariant no AGENTS.md, faca essa invariant em z3 tb
```
