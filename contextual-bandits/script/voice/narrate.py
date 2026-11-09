"""Narrate the script (the files of ../prose-pt-BR/): XTTS v2 speaks the words in pt-BR; OpenVoice changes the timbre.

Use:
    python3 narrate.py ../prose-pt-BR reference.wav out/
    python3 narrate.py ../prose-pt-BR              # only counts the words of each scene

For each scene, the script reads the paragraph that starts with "**Fala.**", makes the speech
with XTTS v2 (`language="pt"`, with the reference voice as `speaker_wav`) and sends the audio
through the tone colour converter of OpenVoice V2 (`ToneColorConverter`). OpenVoice V2 has no
Portuguese base; thus the base comes from XTTS (see the script, section "Voz").

Checkpoints: `checkpoints_v2/converter/{config.json,checkpoint.pth}` of OpenVoice V2.
This file did not run in the environment where it was written (no GPU, models of some GB).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

SPEECH = re.compile(r"^\*\*Fala\.\*\*\s*(.+)$")
BLOCK = re.compile(r"^# (?!.*\{\.unnumbered\})")   # a numbered block of the script (CMAB, A/B, RSI)
SCENE = re.compile(r"^## ")                          # a scene inside the block


def files(script: Path) -> list[Path]:
    """The files of the script: the folder prose-pt-BR/ in order, or one file."""
    return sorted(script.glob("*.md")) if script.is_dir() else [script]


def speeches(script: Path) -> list[tuple[str, str]]:
    """[(scene number "N.M", text of the speech)] in the order of the script.

    Pandoc numbers the sections; the numbers here are the same: the first numbered block is 1,
    its first scene is 1.1. A speech can take more than one line in the file.
    """
    out: list[tuple[str, str]] = []
    block = scene = 0
    current: list[str] | None = None

    def close() -> None:
        nonlocal current
        if current is not None:
            text = re.sub(r"\[a confirmar:[^\]]*\]", "", " ".join(current))  # the marker is not read
            text = text.replace("⚠", "").replace("*", "")
            out.append((f"{block}.{scene}", " ".join(text.split())))
            current = None

    for file in files(script):
        for line in file.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                close()
            elif BLOCK.match(line):
                close()
                block += 1
                scene = 0
            elif SCENE.match(line):
                close()
                scene += 1
            elif m := SPEECH.match(line):
                current = [m.group(1)]
            elif current is not None:
                current.append(line)
        close()
    return out


def main(script: Path, reference: Path, out: Path) -> None:
    import torch  # noqa: WPS433 (imported here so that `speeches` works without torch)
    from openvoice import se_extractor
    from openvoice.api import ToneColorConverter
    from TTS.api import TTS

    device = "cuda" if torch.cuda.is_available() else "cpu"
    out.mkdir(parents=True, exist_ok=True)

    base = TTS("tts_models/multilingual/multi-dataset/xtts_v2").to(device)
    converter = ToneColorConverter("checkpoints_v2/converter/config.json", device=device)
    converter.load_ckpt("checkpoints_v2/converter/checkpoint.pth")
    target_se, _ = se_extractor.get_se(str(reference), converter, vad=False)

    for scene, text in speeches(script):
        raw = out / f"scene-{scene}.base.wav"
        final = out / f"scene-{scene}.wav"
        base.tts_to_file(text=text, file_path=str(raw), speaker_wav=[str(reference)], language="pt")
        source_se, _ = se_extractor.get_se(str(raw), converter, vad=False)
        converter.convert(audio_src_path=str(raw), src_se=source_se, tgt_se=target_se,
                          output_path=str(final), message="@MyShell")
        print(final)


if __name__ == "__main__":
    if len(sys.argv) == 2:
        total = 0
        for scene, text in speeches(Path(sys.argv[1])):
            print(f"{scene}: {len(text.split())} words")
            total += len(text.split())
        print(f"total: {total} words, about {total / 130:.0f} min at 130 words/min")
        sys.exit(0)
    if len(sys.argv) != 4:
        sys.exit("use: narrate.py ../prose-pt-BR reference.wav out/")
    main(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))
