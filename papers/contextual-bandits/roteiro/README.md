# Roteiro do vídeo: CMAB, teste A/B e RSI, em 30 minutos

O roteiro é um paper do Paper Fabric, dentro da pasta do paper sobre bandits: `metadata.md`, um
arquivo por bloco em `prose/`, `refs.bib` e `REFERENCES.md`. `just roteiro` monta
`pdf/contextual-bandits-roteiro.pdf` com pandoc e XeLaTeX (dentro de `nix develop`). O PDF não é
commitado.

| Arquivo | O que é |
|---|---|
| `prose/00-como-ler.md` | como ler o roteiro, e a seção "Voz" |
| `prose/01-cmab.md`, `prose/02-teste-ab.md`, `prose/03-rsi.md` | os três blocos de 10 minutos, uma cena por take, com Fala, Tela, Desmos e Código |
| `prose/04-creditos.md` | os créditos, a lista "a confirmar" e a declaração sobre o uso de IA |
| `refs.bib`, `REFERENCES.md` | as fontes, e o que foi conferido em cada uma |
| `resultados.md` | os números que a fala cita, escritos por `cabal run video` (`haskell/app/Video.hs`) |
| `desmos/` | as expressões dos gráficos interativos, uma por cena que os usa |
| `voz/narrar.py` | a narração: XTTS v2 em pt-BR, timbre pelo OpenVoice; `python3 voz/narrar.py prose` conta as palavras |
| `codigo/` | as animações Manim, uma por take (Python só desenha) |
| `PROMPTS.md` | os prompts que fizeram tudo isto, com a hora de cada um |

O código que sustenta cada frase está em `lean/ContextualBandit/Video.lean` (as invariantes R1 a
R5, provadas), `z3/video.py` (as mesmas invariantes, por refutação) e `haskell/src/Video.hs`,
`haskell/src/Pi.hs` e `haskell/app/Video.hs` (o espelho e os experimentos).
