---
name: roteiro-preview
description: Render a short preview video (1:30 by default) of a roteiro, a video script in Markdown with scenes, **Fala.** and **Tela.** paragraphs, such as papers/contextual-bandits/script/prose-pt-BR/. Use when the user asks to preview, render, "ver", "prévia" or time a roteiro or screenplay, or a window of it.
---

# Roteiro preview

Renders a window of a roteiro (default: the first 1 minute 30 seconds) as an MP4 in the dark
3Blue1Brown style of the script: each frame shows the scene number, block and title, the
**Tela** (what the screen will show) as a storyboard note, and the **Fala** as subtitles timed
to the scene times in the headings. It also writes an `.srt` and a shot list. It is a check of
pace and order before the Manim takes and the narration exist, not the final video.

## Run

From the repository root (or `just sp-preview ARGS`; the skill `sp-preview` is the English alias):

```bash
python3 .claude/skills/roteiro-preview/preview.py papers/contextual-bandits/script/prose-pt-BR
```

Options:

| Option | Default | Meaning |
|---|---|---|
| `--start m:ss` | `0:00` | where the preview starts on the script's timeline |
| `--length m:ss` | `1:30` | how long the preview is (cut at the end of the script) |
| `--out DIR` | `build/roteiro-preview` | output folder (git ignores `build/`) |
| `--tts auto\|none\|"CMD {out}"` | `auto` | narration, see below |
| `--size WxH`, `--fps N` | `1280x720`, `30` | video size and frame rate |
| `--wpm N` | `130` | speech rate for scenes with no times in the heading |
| `--dry-run` | | write only `shots.md` and `preview.srt` (no ffmpeg needed) |

Outputs in `--out`: `preview.mp4`, `preview.srt`, `shots.md`. Print `shots.md` to the user: it
says which scenes the window covers and the words per minute the window asks for, which shows
when a scene has more words than its time allows (the script plans 130 words/min).

Needs Python 3.9+, Pillow and ffmpeg (both are in most images; `pip install pillow` otherwise).

## Narration

`--tts auto` picks the first that works: Piper when `PIPER_VOICE` names a voice model, for
example `pt_BR-faber-medium.onnx` (the light voice the script names in "Voz"); then `espeak-ng`
with `pt-br`; else a silent track. `--tts "CMD {out}"` runs any command that reads the text on
stdin and writes a WAV to `{out}`. Each subtitle cue is spoken at its time and sped up (at most
1.6x) to fit, so the preview always keeps its length. The final voice (XTTS v2 plus OpenVoice) is
`voice/narrate.py` of the script; it needs a GPU and is not used here.

## Script format

The parser reads a folder of `.md` files in name order, or one file:

- `# Block (0:00 a 10:00)` opens a numbered block; `# Title {.unnumbered}` blocks are skipped.
- `## Scene (1:00 a 3:00)` opens scene N.M with its times (`a`, `to` or `-` between them). A
  scene with no times starts where the previous one ends and lasts its words at `--wpm`.
- `**Fala.**` (or `**Speech.**`) and `**Tela.**` (or `**Screen.**`) start the paragraphs; a
  blank line ends them. Citations `[@key]`, `[a confirmar: …]`, `⚠`, backticks and `*` are not
  read or shown.

`example.md` is a small script in this format; `checks/roteiro-preview.sh` uses it.

## Deliver

Give the user `preview.mp4` (and say whether it has a voice), with the `shots.md` table in the
reply. Do not commit the outputs.
