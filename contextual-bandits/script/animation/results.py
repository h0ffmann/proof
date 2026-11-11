"""The numbers the takes show, read from `../results.md`, and the length of each take, read from
the headings of the script. Python computes none of the method: `results.md` is written by
`cabal run video` (haskell/app/Video.hs), and a number that is not there is not drawn as a result.

This module does not import Manim, so `checks/video-takes.sh` can run it with a bare Python.
"""

from __future__ import annotations

import re
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent
RESULTS = SCRIPT / "results.md"

HEADING = re.compile(r"^## .*\((\d+):(\d\d) a (\d+):(\d\d)\)\s*$")


def takes() -> dict[str, float]:
    """Every take of the script, `N.M` -> its length in seconds, in the order of the script."""
    out: dict[str, float] = {}
    for block, path in enumerate(sorted((SCRIPT / "prose-pt-BR").glob("0[1-3]-*.md")), start=1):
        scene = 0
        for line in path.read_text(encoding="utf-8").splitlines():
            m = HEADING.match(line)
            if m:
                scene += 1
                a, b, c, d = map(int, m.groups())
                out[f"{block}.{scene}"] = (c * 60 + d) - (a * 60 + b)
    return out


def _section(start: str) -> str:
    """The text of the first `## ` section of results.md whose heading starts with `start`."""
    text = RESULTS.read_text(encoding="utf-8")
    parts = re.split(r"^## ", text, flags=re.M)
    for part in parts:
        if part.startswith(start):
            return part
    raise KeyError(f"results.md has no section that starts with {start!r}")


def _table(start: str) -> list[list[str]]:
    """The rows of the first table in that section, without the header and the rule."""
    rows = [line for line in _section(start).splitlines() if line.startswith("|")]
    return [[c.strip() for c in r.strip("|").split("|")] for r in rows[2:]]


def _floats(s: str) -> list[float]:
    return [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?(?:e-?\d+)?", s)]


def beliefs() -> dict[str, tuple[list[float], int]]:
    """Scenes 1.1 and 3.4: `current` and `new`, each (means, selected option)."""
    sec = _section("Scenes 1.1 and 3.4")
    out = {}
    for key in ("current", "new"):
        line = next(l for l in sec.splitlines() if l.startswith(key))
        means = _floats(line[line.index("["):line.index("]")])
        out[key] = (means, int(line.rsplit(" ", 1)[1]))
    return out


def digits() -> dict[str, list[str]]:
    """Scene 1.3: terms -> correct digits of Leibniz, Gauss-Legendre and Ramanujan."""
    return {r[0]: r[1:] for r in _table("Scene 1.3: correct digits")}


def single_armed() -> dict:
    """Scene 1.3: the times and mean grade of `exploit` and `explore`, and the last N."""
    rows = _table("Scene 1.3: one arm")
    sec = _section("Scene 1.3: one arm")
    end = re.search(r"N = (\d+), (\d+) correct", sec)
    return {
        "exploit": (int(rows[0][1]), float(rows[0][2])),
        "explore": (int(rows[1][1]), float(rows[1][2])),
        "rounds": _rounds("Scene 1.3: one arm"),
        "n": int(end.group(1)),
        "digits": int(end.group(2)),
    }


def _rounds(start: str) -> int:
    heading = next(p for p in re.split(r"^## ", RESULTS.read_text(encoding="utf-8"), flags=re.M)
                   if p.startswith(start)).splitlines()[0]
    return int(re.search(r"(\d+) rounds", heading).group(1))


def multi_armed() -> list[tuple[str, int, float, int]]:
    """Scene 1.4: (arm, pulls, mean grade, correct digits at the end)."""
    return [(r[0], int(r[1]), float(r[2]), int(r[3])) for r in _table("Scene 1.4")]


def regret() -> dict[str, float]:
    """Scenes 2.3 and 2.4: policy -> regret, and `T` -> the number of rounds."""
    sec = _section("Scenes 2.3 and 2.4")
    out = {r[0]: float(r[1]) for r in _table("Scenes 2.3 and 2.4")}
    out["T"] = float(re.search(r"T = (\d+)", sec).group(1))
    return out


def rsi() -> list[tuple[str, int, float]]:
    """Scene 3.2: (epsilon of the inner agent, times selected, mean gain per round)."""
    return [(r[0], int(r[1]), float(r[2])) for r in _table("Scene 3.2")]


if __name__ == "__main__":
    print(takes())
    print(beliefs(), digits(), single_armed(), multi_armed(), regret(), rsi(), sep="\n")
