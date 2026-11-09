"""Narra o roteiro (os arquivos de ../prose/): XTTS v2 diz as palavras em pt-BR; o OpenVoice troca o timbre.

Uso:
    python3 narrar.py ../prose referencia.wav saida/
    python3 narrar.py ../prose              # só conta as palavras de cada fala

Para cada cena, o script lê o parágrafo que começa com "**Fala.**", sintetiza com o
XTTS v2 (`language="pt"`, com a própria referência como `speaker_wav`) e passa o áudio
pelo conversor de timbre do OpenVoice V2 (`ToneColorConverter`). O OpenVoice V2 não tem
base em português; por isso a base vem do XTTS (ver o roteiro, seção "Voz").

Checkpoints: `checkpoints_v2/converter/{config.json,checkpoint.pth}` do OpenVoice V2.
Este arquivo não foi executado no ambiente em que foi escrito (sem GPU, modelos de GB).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

FALA = re.compile(r"^\*\*Fala\.\*\*\s*(.+)$")
BLOCO = re.compile(r"^# (?!.*\{\.unnumbered\})")   # um bloco numerado do roteiro (CMAB, A/B, RSI)
CENA = re.compile(r"^## ")                           # uma cena dentro do bloco


def arquivos(roteiro: Path) -> list[Path]:
    """Os arquivos do roteiro: a pasta prose/ em ordem, ou um arquivo só."""
    return sorted(roteiro.glob("*.md")) if roteiro.is_dir() else [roteiro]


def falas(roteiro: Path) -> list[tuple[str, str]]:
    """[(número da cena, "N.M"), texto da fala)] na ordem do roteiro.

    O pandoc numera as seções; aqui a numeração é a mesma: o primeiro bloco numerado é 1,
    a primeira cena dele é 1.1. Uma fala pode ocupar mais de uma linha no arquivo.
    """
    out: list[tuple[str, str]] = []
    bloco = cena = 0
    atual: list[str] | None = None

    def fecha() -> None:
        nonlocal atual
        if atual is not None:
            texto = re.sub(r"\[a confirmar:[^\]]*\]", "", " ".join(atual))  # não se lê o marcador
            texto = texto.replace("⚠", "").replace("*", "")
            out.append((f"{bloco}.{cena}", " ".join(texto.split())))
            atual = None

    for arquivo in arquivos(roteiro):
        for linha in arquivo.read_text(encoding="utf-8").splitlines():
            if not linha.strip():
                fecha()
            elif BLOCO.match(linha):
                fecha(); bloco += 1; cena = 0
            elif CENA.match(linha):
                fecha(); cena += 1
            elif m := FALA.match(linha):
                atual = [m.group(1)]
            elif atual is not None:
                atual.append(linha)
        fecha()
    return out


def main(roteiro: Path, referencia: Path, saida: Path) -> None:
    import torch  # noqa: WPS433 (importado aqui para `falas` funcionar sem torch)
    from openvoice import se_extractor
    from openvoice.api import ToneColorConverter
    from TTS.api import TTS

    device = "cuda" if torch.cuda.is_available() else "cpu"
    saida.mkdir(parents=True, exist_ok=True)

    base = TTS("tts_models/multilingual/multi-dataset/xtts_v2").to(device)
    conversor = ToneColorConverter("checkpoints_v2/converter/config.json", device=device)
    conversor.load_ckpt("checkpoints_v2/converter/checkpoint.pth")
    alvo_se, _ = se_extractor.get_se(str(referencia), conversor, vad=False)

    for cena, texto in falas(roteiro):
        bruto = saida / f"cena-{cena}.base.wav"
        final = saida / f"cena-{cena}.wav"
        base.tts_to_file(text=texto, file_path=str(bruto), speaker_wav=[str(referencia)], language="pt")
        fonte_se, _ = se_extractor.get_se(str(bruto), conversor, vad=False)
        conversor.convert(audio_src_path=str(bruto), src_se=fonte_se, tgt_se=alvo_se,
                          output_path=str(final), message="@MyShell")
        print(final)


if __name__ == "__main__":
    if len(sys.argv) == 2:
        total = 0
        for cena, texto in falas(Path(sys.argv[1])):
            print(f"{cena}: {len(texto.split())} palavras")
            total += len(texto.split())
        print(f"total: {total} palavras, cerca de {total / 130:.0f} min a 130 palavras/min")
        sys.exit(0)
    if len(sys.argv) != 4:
        sys.exit("uso: narrar.py ../prose referencia.wav saida/")
    main(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))
