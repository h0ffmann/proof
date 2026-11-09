# Créditos {.unnumbered}

| O quê | De quem | Como entra |
|-----|-----------|----------|
| Estilo visual | 3Blue1Brown, Grant Sanderson | citado na fala e na tela de créditos; sem o personagem π |
| Animações | Manim (Manim Community) [@manim] | `animation/timeline.py` e os takes |
| Gráficos interativos | Desmos, calculadora gráfica | `desmos/` |
| Voz | XTTS v2 (Coqui) [@coqui2024xtts] e OpenVoice V2 (MyShell) [@myshell2024openvoice2] | `voice/narrate.py` |
| Roteiro, código, animações | Claude Code (Anthropic): Claude Sonnet 5.5 (teste do Manim), Claude Fable 5.1 (roteiro, Z3, Haskell) | a partir dos prompts em `PROMPTS.md` |
| Invariantes | Z3 (`z3-scala/src/main/scala/Video.scala`, R1 a R5; `z3-scala/src/main/scala/Theorems.scala`, as regras) e o espelho em Haskell | conferidas pelo spec check de `app/Main.hs` e por `just z3` |
| Custo total | `[a confirmar: preencher só no fim da produção]` | tela de créditos |

: O que este vídeo tomou emprestado, de quem, e onde isso entra.

# A confirmar {.unnumbered}

- Cena 1.1: a referência de "Side Agents" da Anthropic.
- Cena 1.2: o nome do amigo e o mês de 2018.
- Cena 1.2: Renan Moreira de Oliveira foi para a Uber?
- Cena 1.4: os epítetos "príncipe dos matemáticos" (Gauss) e "rei" (Ramanujan, do autor) não têm
  fonte aberta neste roteiro. ⚠
- Seção Voz: a voz de referência (a do autor, ou um locutor).
- Cena 3.6: o custo total, no fim da produção.

# Declaração sobre o uso de IA {.unnumbered}

Este roteiro, o código em Z3 e em Haskell que sustenta o roteiro e este documento foram escritos
com o Claude Code (Anthropic), pelos modelos Claude Sonnet 5.5 e Claude Fable 5.1. Os modelos
partiram dos prompts do autor, listados em `PROMPTS.md` com a hora de cada um. O autor revisou e
aprovou o rascunho em 9 de novembro de 2026. Toda fonte citada foi lida antes de ser citada; `REFERENCES.md`, ao lado
deste documento, diz o que foi conferido em cada uma.
