---
name: sp-preview
description: Short English alias of roteiro-preview (screenplay preview). Render a preview video (1:30 by default) of a screenplay or roteiro in Markdown. Use when the user says sp-preview, screenplay preview or script preview.
---

# sp-preview (alias of roteiro-preview)

This skill only redirects. Read and follow `.claude/skills/roteiro-preview/SKILL.md`; it has the
options, the script format and how to deliver the result.

```bash
just sp-preview papers/contextual-bandits/script/prose-pt-BR           # first 1:30
just sp-preview papers/contextual-bandits/script/prose-pt-BR --start 10:00 --length 0:45
```

`just sp-preview ARGS` runs `python3 .claude/skills/roteiro-preview/preview.py ARGS`.
