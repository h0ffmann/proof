#!/usr/bin/env python3
"""Render a short preview video (default 1:30) of a roteiro (a video script in Markdown).

The roteiro format is the one of contextual-bandits/script/prose-pt-BR/:

    # Block title (0:00 a 10:00)
    ## Scene title (0:00 a 1:00)
    **Fala.** the words the voice reads ...
    **Tela.** what the screen shows ...

Use (from the repository root):

    python3 .claude/skills/roteiro-preview/preview.py SCRIPT [--start 0:00] [--length 1:30]
        [--out build/roteiro-preview] [--tts auto|none|"CMD {out}"] [--size 1280x720] [--fps 30]

SCRIPT is a folder of .md files (read in name order) or one .md file. The preview is the window
[start, start + length] of the script's own timeline: each scene keeps the times its heading
gives, and its Fala is cut into subtitle cues spread over the scene in proportion to the words.
A scene with no times in its heading lasts its words at --wpm (default 130).

Writes, in --out: preview.mp4 (the video), preview.srt (the subtitles), shots.md (the shot list
with times). Needs Python 3.9+, Pillow and ffmpeg. Narration is optional: --tts auto uses Piper
when PIPER_VOICE names a voice model (.onnx), else espeak-ng, else no voice; --tts "CMD {out}"
runs any command that reads text on stdin and writes a WAV to {out}.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import wave
from dataclasses import dataclass, field
from pathlib import Path

TIMES = re.compile(r"\((\d+:\d{2})\s*(?:a|to|-|–)\s*(\d+:\d{2})\)\s*$")
UNNUMBERED = re.compile(r"\{\.unnumbered\}")
PART = re.compile(r"^\*\*(Fala|Tela|Desmos|Código|Code|Screen|Speech)\.\*\*\s*(.*)$")
SPEECH_KEYS = {"Fala", "Speech"}
SCREEN_KEYS = {"Tela", "Screen"}


def seconds(clock: str) -> float:
    """'1:30' -> 90.0; '90' -> 90.0; '1:02:03' -> 3723.0."""
    total = 0.0
    for part in clock.split(":"):
        total = total * 60 + float(part)
    return total


def clock(t: float) -> str:
    t = int(round(t))
    return f"{t // 60}:{t % 60:02d}"


def clean(text: str) -> str:
    """The words as spoken: no citations, no open questions, no Markdown marks."""
    text = re.sub(r"`?\[a confirmar:[^\]]*\]`?", "", text)
    text = re.sub(r"\[(?:see |cf\. )?@[^\]]*\]", "", text)
    text = text.replace("⚠", "").replace("`", "").replace("*", "")
    text = re.sub(r"\s+([,.;:!?])", r"\1", text)
    return " ".join(text.split())


@dataclass
class Scene:
    number: str
    block: str
    title: str
    start: float | None
    end: float | None
    speech: str = ""
    screen: str = ""


@dataclass
class Cue:
    start: float          # time in the script
    end: float
    text: str
    scene: Scene = field(repr=False)


def parse(path: Path) -> list[Scene]:
    files = sorted(path.glob("*.md")) if path.is_dir() else [path]
    scenes: list[Scene] = []
    block_no = scene_no = 0
    block = ""
    part: str | None = None
    lines: list[str] = []

    def close() -> None:
        nonlocal part, lines
        if part and scenes:
            text = clean(" ".join(lines))
            if part in SPEECH_KEYS:
                scenes[-1].speech = (scenes[-1].speech + " " + text).strip()
            elif part in SCREEN_KEYS:
                scenes[-1].screen = (scenes[-1].screen + " " + text).strip()
        part, lines = None, []

    for f in files:
        in_fence = False
        for line in f.read_text(encoding="utf-8").splitlines():
            if line.startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            if line.startswith("# "):
                close()
                if UNNUMBERED.search(line):
                    block = ""
                else:
                    block_no += 1
                    scene_no = 0
                    block = TIMES.sub("", line[2:]).strip()
                continue
            if line.startswith("## "):
                close()
                if UNNUMBERED.search(line) or not block:
                    continue
                scene_no += 1
                head = line[3:].strip()
                m = TIMES.search(head)
                start, end = (seconds(m.group(1)), seconds(m.group(2))) if m else (None, None)
                scenes.append(Scene(f"{block_no}.{scene_no}", block, TIMES.sub("", head).strip(),
                                    start, end))
                continue
            if not line.strip():
                close()
                continue
            m = PART.match(line)
            if m:
                close()
                if scenes and block:
                    part, lines = m.group(1), [m.group(2)]
            elif part:
                lines.append(line)
        close()
    return [s for s in scenes if s.speech or s.screen]


def place(scenes: list[Scene], wpm: float) -> None:
    """Give every scene a start and an end; untimed scenes last their words at wpm."""
    t = 0.0
    for s in scenes:
        if s.start is None or s.end is None or s.end <= s.start:
            words = max(len(s.speech.split()), 8)
            s.start = t if s.start is None else s.start
            s.end = s.start + words * 60 / wpm
        t = s.end


def chunks(text: str, limit: int = 14) -> list[str]:
    """Subtitle-sized pieces: sentences, and long sentences cut at commas or every limit words."""
    out: list[str] = []
    for sentence in re.split(r"(?<=[.!?…])\s+", text):
        words = sentence.split()
        while len(words) > limit:
            cut = limit
            for i in range(limit, limit // 2, -1):
                if words[i - 1].endswith((",", ";", ":")):
                    cut = i
                    break
            out.append(" ".join(words[:cut]))
            words = words[cut:]
        if words:
            out.append(" ".join(words))
    return out


def cues(scenes: list[Scene], start: float, end: float) -> list[Cue]:
    """The cues inside [start, end], each spread over its scene by its share of the words."""
    out: list[Cue] = []
    for s in scenes:
        assert s.start is not None and s.end is not None
        if s.end <= start or s.start >= end:
            continue
        pieces = chunks(s.speech) or [""]
        weights = [max(len(p.split()), 1) for p in pieces]
        span = (s.end - s.start) / sum(weights)
        t = s.start
        for p, w in zip(pieces, weights):
            a, b = t, t + w * span
            t = b
            if b <= start or a >= end:
                continue
            out.append(Cue(max(a, start), min(b, end), p, s))
    return out


# ---------------------------------------------------------------- drawing (3Blue1Brown palette)

BG = (14, 17, 22)
BLUE = (88, 196, 221)
YELLOW = (255, 255, 0)
WHITE = (236, 236, 236)
GREY = (150, 156, 166)
# ROTEIRO_FONT_DIR first: `nix develop .#roteiro-preview` sets it to the pinned DejaVu fonts.
FONT_DIRS = [d for d in [os.environ.get("ROTEIRO_FONT_DIR")] if d] + ["/usr/share/fonts", "/usr/local/share/fonts", "/Library/Fonts", "/System/Library/Fonts",
             str(Path.home() / ".fonts"), str(Path.home() / ".local/share/fonts")]


def font_path(bold: bool) -> str | None:
    names = (["DejaVuSans-Bold.ttf", "LiberationSans-Bold.ttf", "Arial Bold.ttf"] if bold
             else ["DejaVuSans.ttf", "LiberationSans-Regular.ttf", "Arial.ttf"])
    for d in FONT_DIRS:
        for root, _, files in os.walk(d):
            for n in names:
                if n in files:
                    return os.path.join(root, n)
    return None


def wrap(draw, text: str, font, width: int) -> list[str]:
    lines: list[str] = []
    line = ""
    for w in text.split():
        trial = f"{line} {w}".strip()
        if draw.textlength(trial, font=font) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = w
    if line:
        lines.append(line)
    return lines


class Painter:
    def __init__(self, size: tuple[int, int]):
        from PIL import ImageFont
        self.w, self.h = size
        u = self.h / 720
        regular, bold = font_path(False), font_path(True)

        def load(p, s):
            return ImageFont.truetype(p, int(s * u)) if p else ImageFont.load_default()

        self.f_small = load(regular, 20)
        self.f_screen = load(regular, 24)
        self.f_title = load(bold, 38)
        self.f_sub = load(bold, 30)
        self.u = u

    def frame(self, cue: Cue | None, scene: Scene, t_preview: float, total: float,
              t_script: float, label: str):
        from PIL import Image, ImageDraw
        img = Image.new("RGB", (self.w, self.h), BG)
        d = ImageDraw.Draw(img)
        u, m = self.u, int(60 * self.u)
        y = int(40 * u)
        d.text((m, y), f"{scene.number} · {scene.block}".upper(), font=self.f_small, fill=BLUE)
        d.text((self.w - m, y), label, font=self.f_small, fill=GREY, anchor="ra")
        y += int(34 * u)
        for line in wrap(d, scene.title, self.f_title, self.w - 2 * m)[:2]:
            d.text((m, y), line, font=self.f_title, fill=WHITE)
            y += int(48 * u)
        y += int(14 * u)
        d.line([(m, y), (m + int(120 * u), y)], fill=YELLOW, width=max(int(3 * u), 1))
        y += int(24 * u)
        if scene.screen:
            d.text((m, y), "TELA", font=self.f_small, fill=YELLOW)
            y += int(30 * u)
            for line in wrap(d, scene.screen, self.f_screen, self.w - 2 * m)[:7]:
                d.text((m, y), line, font=self.f_screen, fill=GREY)
                y += int(32 * u)
        # subtitles
        if cue and cue.text:
            lines = wrap(d, cue.text, self.f_sub, self.w - 2 * m)[:3]
            y = self.h - int(70 * u) - len(lines) * int(40 * u)
            for line in lines:
                d.text((self.w // 2, y), line, font=self.f_sub, fill=WHITE, anchor="ma")
                y += int(40 * u)
        # progress bar and clocks
        bar_y = self.h - int(14 * u)
        d.rectangle([(0, bar_y), (self.w, self.h)], fill=(30, 34, 42))
        d.rectangle([(0, bar_y), (int(self.w * t_preview / total), self.h)], fill=BLUE)
        d.text((m, bar_y - int(26 * u)), f"{clock(t_preview)} / {clock(total)}",
               font=self.f_small, fill=GREY)
        d.text((self.w - m, bar_y - int(26 * u)), f"roteiro {clock(t_script)}",
               font=self.f_small, fill=GREY, anchor="ra")
        return img


# ---------------------------------------------------------------- voice

def tts_command(choice: str) -> str | None:
    if choice == "none":
        return None
    if choice != "auto":
        return choice
    voice = os.environ.get("PIPER_VOICE")
    if voice and shutil.which("piper"):
        return f"piper -q -m {voice} -f {{out}}"
    for exe in ("espeak-ng", "espeak"):
        if shutil.which(exe):
            return f"{exe} -v pt-br -s 160 -w {{out}}"
    return None


def wav_seconds(path: Path) -> float:
    with wave.open(str(path)) as w:
        return w.getnframes() / w.getframerate()


def ffmpeg(*args: str) -> None:
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args], check=True)


def voice_track(cmd: str, timeline: list[tuple[float, float, Cue | None]], tmp: Path) -> Path:
    """One WAV the length of the preview: each cue spoken at its time, sped up (up to 1.6x) to fit."""
    parts: list[Path] = []
    for i, (a, b, cue) in enumerate(timeline):
        dur = b - a
        seg = tmp / f"seg{i:04d}.wav"
        if cue and cue.text:
            raw = tmp / f"raw{i:04d}.wav"
            subprocess.run(cmd.format(out=str(raw)), shell=True, input=cue.text.encode("utf-8"),
                           check=True, stdout=subprocess.DEVNULL)
            speed = min(max(wav_seconds(raw) / dur, 1.0), 1.6)
            ffmpeg("-i", str(raw), "-af", f"atempo={speed:.3f},apad", "-t", f"{dur:.3f}",
                   "-ar", "24000", "-ac", "1", str(seg))
        else:
            ffmpeg("-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono", "-t", f"{dur:.3f}", str(seg))
        parts.append(seg)
    listing = tmp / "audio.txt"
    listing.write_text("".join(f"file '{p}'\n" for p in parts))
    out = tmp / "voice.wav"
    ffmpeg("-f", "concat", "-safe", "0", "-i", str(listing), "-c", "copy", str(out))
    return out


# ---------------------------------------------------------------- main

def srt_time(t: float) -> str:
    ms = int(round(t * 1000))
    return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d},{ms % 1000:03d}"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("script", type=Path, help="folder of .md files, or one .md file")
    ap.add_argument("--start", default="0:00", help="where the preview starts in the script (m:ss)")
    ap.add_argument("--length", default="1:30", help="length of the preview (m:ss), default 1:30")
    ap.add_argument("--out", type=Path, default=Path("build/roteiro-preview"))
    ap.add_argument("--tts", default="auto", help='auto, none, or a command such as "piper -m v.onnx -f {out}"')
    ap.add_argument("--size", default="1280x720")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--wpm", type=float, default=130.0, help="speech rate for scenes with no times")
    ap.add_argument("--dry-run", action="store_true", help="write shots.md and preview.srt only")
    args = ap.parse_args(argv)

    scenes = parse(args.script)
    if not scenes:
        print(f"roteiro-preview: no scenes with **Fala.** or **Tela.** in {args.script}", file=sys.stderr)
        return 1
    place(scenes, args.wpm)
    start = seconds(args.start)
    length = seconds(args.length)
    script_end = max(s.end for s in scenes)  # type: ignore[type-var]
    end = min(start + length, script_end)
    if end <= start:
        print(f"roteiro-preview: the script ends at {clock(script_end)}, before {args.start}", file=sys.stderr)
        return 1
    total = end - start
    selected = cues(scenes, start, end)

    # The timeline: every cue, and a silent frame for any gap (a scene without speech).
    timeline: list[tuple[float, float, Cue | None]] = []
    t = start
    for c in selected:
        if c.start > t + 1e-6:
            timeline.append((t, c.start, None))
        timeline.append((c.start, c.end, c))
        t = c.end
    if t < end - 1e-6:
        timeline.append((t, end, None))

    def scene_at(t: float) -> Scene:
        for s in scenes:
            if s.start <= t < s.end:  # type: ignore[operator]
                return s
        return scenes[-1]

    args.out.mkdir(parents=True, exist_ok=True)
    srt = []
    n = 0
    for c in selected:
        if c.text:
            n += 1
            srt.append(f"{n}\n{srt_time(c.start - start)} --> {srt_time(c.end - start)}\n{c.text}\n")
    (args.out / "preview.srt").write_text("\n".join(srt), encoding="utf-8")

    shots = [f"# Preview {clock(start)} to {clock(end)} ({clock(total)})", "",
             f"Script: `{args.script}`", "",
             "| Preview | Script | Scene | Title | Words |", "|---|---|---|---|---|"]
    for s in scenes:
        if s.end <= start or s.start >= end:  # type: ignore[operator]
            continue
        a, b = max(s.start, start), min(s.end, end)  # type: ignore[type-var]
        words = sum(len(c.text.split()) for c in selected if c.scene is s)
        shots.append(f"| {clock(a - start)}–{clock(b - start)} | {clock(a)}–{clock(b)} | "
                     f"{s.number} | {s.title} | {words} |")
    words = sum(len(c.text.split()) for c in selected)
    shots += ["", f"Words in the preview: {words} ({words / total * 60:.0f} words/min; "
              f"the script plans {args.wpm:.0f})."]
    (args.out / "shots.md").write_text("\n".join(shots) + "\n", encoding="utf-8")
    print("\n".join(shots))
    if args.dry_run:
        return 0

    if not shutil.which("ffmpeg"):
        print("roteiro-preview: ffmpeg is not on PATH", file=sys.stderr)
        return 1
    w, h = (int(x) for x in args.size.lower().split("x"))
    painter = Painter((w, h))
    cmd = tts_command(args.tts)
    label = "roteiro · prévia" if cmd is None else "roteiro · prévia com voz"

    with tempfile.TemporaryDirectory(prefix="roteiro-preview-") as tmpdir:
        tmp = Path(tmpdir)
        # One still per second of each timeline entry, so that the clocks and the bar move.
        listing: list[str] = []
        k = 0
        for a, b, cue in timeline:
            t = a
            while t < b - 1e-6:
                step = min(1.0 - (t - start) % 1.0, b - t)
                scene = cue.scene if cue else scene_at(t)
                img = painter.frame(cue, scene, t - start, total, t, label)
                p = tmp / f"f{k:05d}.png"
                img.save(p)
                listing.append(f"file '{p}'\nduration {step:.3f}\n")
                k += 1
                t += step
        listing.append(f"file '{tmp / f'f{k - 1:05d}.png'}'\n")
        (tmp / "frames.txt").write_text("".join(listing))
        video = args.out / "preview.mp4"
        inputs = ["-f", "concat", "-safe", "0", "-i", str(tmp / "frames.txt")]
        if cmd:
            inputs += ["-i", str(voice_track(cmd, timeline, tmp))]
        else:
            inputs += ["-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono"]
        ffmpeg(*inputs, "-map", "0:v", "-map", "1:a", "-t", f"{total:.3f}",
               "-vf", f"fps={args.fps},format=yuv420p", "-c:v", "libx264", "-preset", "veryfast",
               "-crf", "23", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", str(video))
    print(f"\nroteiro-preview: {video} ({clock(total)}, {w}x{h}, "
          f"{'voice: ' + cmd.split()[0] if cmd else 'no voice'})")
    print(f"roteiro-preview: {args.out / 'preview.srt'}, {args.out / 'shots.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
