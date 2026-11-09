# Como ler este roteiro {.unnumbered}

Padrão de escrita: português técnico controlado (PTC, kayquer/portugues-tecnico-controlado), nível
leve, destinatário humano. A fala é em primeira pessoa, porque o vídeo é uma explicação minha. As
regras PTC-1 (quem faz, aparece), PTC-7 (número, data e unidade), PTC-8 (ortografia de 1990) e
PTC-9 (sem ruído de texto gerado) valem em toda linha. Frase com no máximo 35 palavras. A nota
vizinha deste roteiro é `MULTI_ARMED_CONTEXTUAL_BANDIT.pt-BR.md`, na raiz do repositório
[@hoffmann2026note].

Cada cena é **um take**: um arquivo de áudio (`voz/narrar.py` escreve `cena-N.M.wav`), um arquivo
de vídeo (`take-N.M.mp4`) e um corte na edição. Nenhum take depende do anterior; a ordem é a
deste documento. Cada cena tem quatro partes. **Fala** é o texto que a voz lê. **Tela** é o que
aparece. **Desmos**, quando a cena tem um gráfico que um controle deslizante explica melhor que
uma animação pronta: a expressão está em `desmos/`, para colar na calculadora gráfica e gravar a
tela. **Código** é o arquivo que sustenta a cena: tudo o que a fala afirma sobre o método tem uma
função em Haskell (`haskell/src/Video.hs`, `haskell/src/Pi.hs`, `haskell/app/Video.hs`) ou um
teorema em Lean (`lean/ContextualBandit/Video.lean`, as invariantes R1 a R5 dos requisitos do
autor). Os números citados estão em `resultados.md`, escrito por `cabal run video`. Python só faz
animação (Manim), em `codigo/`. Todos os caminhos são relativos à raiz do repositório
h0ffmann/proof [@hoffmann2026proof], ou à pasta deste roteiro,
`papers/contextual-bandits/roteiro/`.

Duração: 30 minutos, em três blocos de 10 minutos: **CMAB** (0:00 a 10:00), **teste A/B** (10:00
a 20:00) e **RSI** (20:00 a 30:00). A fala tem cerca de 130 palavras por minuto; cada cena traz a
duração prevista.

Estilo: o de 3Blue1Brown (Grant Sanderson). Fundo escuro, uma ideia por tela, os objetos se
transformam em vez de cortar, texto curto na tela e a fala carrega o argumento. Cores: azul para
o que o modelo acredita, amarelo para a escolha, vermelho para o arrependimento. O personagem π
de 3b1b não aparece: é dele. As animações são feitas com Manim, a biblioteca que Grant Sanderson
criou e que a Manim Community mantém [@manim]. Os créditos (cena 3.6) nomeiam 3Blue1Brown,
Manim, Claude Code, os modelos Claude que fizeram este material, o custo total e a lista de
prompts (`PROMPTS.md`).

Marcadores: `[a confirmar: …]` é uma informação que o original não deu e que eu não inventei. ⚠
é uma afirmação que eu não confirmei numa fonte primária.

# Voz {.unnumbered}

A narração é sintetizada, em português do Brasil, e depois recebe o timbre de uma voz de
referência com o OpenVoice. Dois fatos limitam a montagem:

- O OpenVoice V2 sintetiza, por si, só inglês, espanhol, francês, chinês, japonês e coreano
  [@myshell2024openvoice2]. O gerador de base que ele usa, o MeloTTS, não tem português
  [@myshell2024melotts].
- O OpenVoice separa a fala em duas partes: um gerador de base, que diz as palavras, e um
  conversor de timbre, que troca a cor da voz. A entrada do conversor "pode estar em qualquer
  idioma" [@myshell2024openvoice2]. Então a base vem de outro gerador, com português do Brasil,
  e o OpenVoice só clona o timbre.

A base é o XTTS v2 (Coqui), com `language="pt"`; ele aceita 17 idiomas e português é um deles
[@coqui2024xtts]. Alternativa mais leve: a voz `pt_BR-faber-medium` do Piper
[@rhasspy2023piper]. ⚠ Eu não listei as outras vozes pt-BR do Piper.

A voz de referência é a minha, gravada por mim: 30 s de leitura limpa, sem música, em
`voz/referencia.wav`. `[a confirmar: quer a sua voz, ou uma voz de locutor neutra? Uma voz de
pessoa real pede autorização dela.]`

**Código.** `voz/narrar.py` lê as cenas deste roteiro (os arquivos de `prose/`), sintetiza cada
**Fala** com o XTTS v2 e passa o áudio pelo conversor de timbre do OpenVoice. `voz/requisitos.txt`
lista os pacotes. Eu não executei esse arquivo aqui: os modelos pesam alguns GB e pedem GPU.
