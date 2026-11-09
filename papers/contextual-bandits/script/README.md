# The video script: CMAB, A/B tests and RSI, in 30 minutes

The script is a Paper Fabric paper inside the folder of the paper on bandits: `metadata.md`, one
file per block in `prose-pt-BR/`, `refs.bib` and `REFERENCES.md`. `just script` builds
`pdf/contextual-bandits-script-pt-BR.pdf` with pandoc and XeLaTeX (inside `nix develop`). The PDF
is not committed. The Brazilian Portuguese edition is the one written so far (the owner asked for
it first); the English edition is issue #18. Every other file of this folder is in English, as the
language rule of `AGENTS.md` asks.

| File | What it is |
|---|---|
| `prose-pt-BR/00-metadata.md` | the Portuguese title, abstract and keywords; `metadata.md` has the English ones and the shared layout |
| `prose-pt-BR/00-como-ler.md` | how to read the script, and the section on the voice |
| `prose-pt-BR/01-cmab.md`, `02-teste-ab.md`, `03-rsi.md` | the three blocks of 10 minutes, one scene per take, each with the words (Fala), the screen (Tela), the Desmos graph and the code (Código) |
| `prose-pt-BR/04-creditos.md` | the credits, the list of points to confirm, and the statement on the use of AI |
| `refs.bib`, `REFERENCES.md` | the sources, and what was checked in each one |
| `results.md` | the numbers the narration quotes, as the video's screens show them; written by `cabal run video` (`haskell/app/Video.hs`) |
| `desmos/` | the expressions of the interactive graphs, one file per scene that uses one |
| `voice/narrate.py` | the narration: XTTS v2 in pt-BR, the timbre from OpenVoice; `python3 voice/narrate.py prose-pt-BR` counts the words |
| `animation/` | the Manim animations, one per take (Python only draws) |
| `PROMPTS.md` | the prompts that made all of this, as typed, with the time of each one |

The code behind each sentence is in `z3/video.py` (the invariants R1 to R5, proved by
refutation), `z3/theorems.py` (the decision rules) and `haskell/src/Video.hs`,
`haskell/src/Pi.hs` and `haskell/app/Video.hs` (the mirror and the experiments).
