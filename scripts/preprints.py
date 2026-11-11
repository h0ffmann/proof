"""The preprints badge in README.md, counted from the folders of papers/.

The badge is the line `[![preprints: N](...)](papers)` in the header of README.md, found by its
pattern rather than by markers: an HTML comment inside the header's run of badges would split it
into paragraphs and stack the badges. It is generated: edit this script, not the badge. A folder `papers/<slug>/` is a preprint when

- its `metadata.md` has a `version:` line that says "preprint" (docs/paper-fabric.md: a paper
  shared before peer review says so in its version), or
- it has no `metadata.md` and holds a PDF: the paper is shared as a built file whose source lives
  elsewhere (papers/practice-beats-theory).

A folder whose version does not say "preprint" (papers/cycle, a skeleton not for circulation) is
not counted.

    python3 scripts/preprints.py           # rewrite the badge in README.md
    python3 scripts/preprints.py --check   # exit code 1 if the badge in README.md is out of date
    python3 scripts/preprints.py --print   # print the badge and the folders counted
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
PAPERS = ROOT / "papers"
COLOR = "2a78d6"
VERSION = re.compile(r"^version:\s*(.*)$", re.MULTILINE)


def is_preprint(folder: Path) -> bool:
    meta = folder / "metadata.md"
    if meta.is_file():
        m = VERSION.search(meta.read_text(encoding="utf-8"))
        return bool(m) and "preprint" in m.group(1).lower()
    return any(folder.glob("*.pdf"))


def preprints() -> list[str]:
    return sorted(d.name for d in PAPERS.iterdir() if d.is_dir() and is_preprint(d))


def badge(n: int) -> str:
    url = f"https://img.shields.io/badge/preprints-{n}-{COLOR}?style=flat-square"
    return f"[![preprints: {n}]({url})](papers)"


BADGE = re.compile(r"^\[!\[preprints: \d+\]\([^)]*\)\]\(papers\)$", re.MULTILINE)


def splice(readme: str, line: str) -> str:
    if len(BADGE.findall(readme)) != 1:
        sys.exit("README.md needs exactly one line `[![preprints: N](...)](papers)`")
    return BADGE.sub(line, readme)


def main(argv: list[str]) -> int:
    found = preprints()
    line = badge(len(found))
    if "--print" in argv:
        print(line)
        print("\n".join(f"  papers/{s}" for s in found))
        return 0
    old = README.read_text(encoding="utf-8")
    new = splice(old, line)
    if "--check" in argv:
        if new != old:
            print(f"README.md: the preprints badge is out of date ({len(found)} preprints); run `just preprints`")
            return 1
        print(f"README.md: the preprints badge is current ({len(found)} preprints)")
        return 0
    if new != old:
        README.write_text(new, encoding="utf-8")
        print(f"README.md: preprints badge updated to {len(found)}")
    else:
        print("README.md: preprints badge already current")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
