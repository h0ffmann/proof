---
title: "Script: CMAB, A/B tests and RSI, in 30 minutes"
subtitle: "The contextual bandit, the A/B test and recursive self-improvement in an explainer video, with an invariant in Agda or a function in Haskell behind each sentence"
author:
  - name: Matheus Hoffmann
    orcid: 0009-0009-1056-7661
date: "9 November 2026"
version: "v0, draft"
lang: en-US
keywords:
  - contextual bandit
  - A/B test
  - recursive self-improvement
  - Agda
  - Haskell
  - video script
abstract: |
  This is the script of a 30-minute video, in three blocks of 10 minutes: the contextual
  multi-armed bandit (CMAB), the A/B test and recursive self-improvement (RSI). Each scene is one
  take, with the words spoken, what the screen shows, the interactive graph when one helps, and
  the code that supports the scene. Everything the narration says about the method has a
  statement proved in Agda (`agda/src/ContextualBandit/Video.agda`, the invariants R1 to R5; `agda/src/ContextualBandit/Theorems.agda`, the decision
  rules) or a function in Haskell (`haskell/src/Video.hs`, `haskell/src/Pi.hs`,
  `haskell/app/Video.hs`) in the repository h0ffmann/proof. The simple example is the computation
  of pi, with the viewer as the reward; the complex example is the choice of artwork at Netflix.
  The Brazilian Portuguese edition (`prose-pt-BR/`) is the one written so far; the English edition
  is issue #18.
papersize: a4
fontsize: 11pt
geometry:
  - top=25mm
  - bottom=25mm
  - left=28mm
  - right=28mm
header-includes:
  - |
    \ifPDFTeX\else
    \usepackage{newunicodechar}
    \newfontfamily\symbolfont{DejaVu Sans}
    \newunicodechar{⚠}{{\symbolfont ⚠}}
    \newunicodechar{π}{\ensuremath{\pi}}
    \newunicodechar{ε}{\ensuremath{\varepsilon}}
    \newunicodechar{β}{\ensuremath{\beta}}
    \newunicodechar{α}{\ensuremath{\alpha}}
    \fi
---
