"""The language invariant of the repository, checked with Z3.

The rule (AGENTS.md, "Language", the owner, 2026-11-09): every file is in English, except a
file whose path carries `pt-BR`, which is in Brazilian Portuguese. As a formula, for every
tracked text file f:

    portuguese(f)  <->  marked_pt_br(f)

`portuguese(f)` comes from a count of stop words, with fenced code blocks and inline code left
out (a quoted prompt or a command is not the file's prose): a file is Portuguese when its
Portuguese stop words are more than twice its English ones (files with fewer than 20 stop words
of either language are not judged: data, short code, lists). `marked_pt_br(f)` is true when
`pt-BR` is in the path.

Z3 gets one Boolean per file for each side, fixed to the values measured, and is asked for a
model of the negation of the rule. "unsat" means that no file breaks it. "sat" gives the files
that do, from the model.

    python3 z3/language.py          # one line per file that breaks the rule; exit code 1 if any
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

from z3 import Bool, BoolVal, Not, Or, Solver, Xor, sat

ROOT = Path(__file__).resolve().parent.parent

PORTUGUESE = re.compile(
    r"\b(de|que|não|para|uma|com|é|os|as|do|da|em|um|são|mais|por|como|se|dos|das|ao|pela|pelo"
    r"|cada|também|mesmo|isso|essa|esse)\b", re.IGNORECASE)
ENGLISH = re.compile(
    r"\b(the|of|and|is|with|that|for|to|in|this|are|from|by|as|it|on|be|or|at|an)\b",
    re.IGNORECASE)

# Not judged: binaries, other people's files, generated HTML, and formats with no prose of ours.
SKIPPED = re.compile(
    r"\.(png|jpg|jpeg|gif|webp|pdf|svg|lock|json|html|bib|tex|toml|cabal|csv|tsv|parquet|cff|nix|jsonc)$"
    r"|^(LICENSES|vendor)/")
CODE = re.compile(r"```.*?```|`[^`\n]*`", re.DOTALL)

MINIMUM = 20  # stop words of both languages together, below which a file is not judged


def tracked_text_files() -> list[Path]:
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True)
    return [Path(line) for line in out.stdout.split() if not SKIPPED.search(line)]


def is_portuguese(path: Path) -> bool | None:
    """True, False, or None when the file has too few stop words to judge."""
    try:
        text = (ROOT / path).read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return None
    prose = CODE.sub(" ", text)
    pt = len(PORTUGUESE.findall(prose))
    en = len(ENGLISH.findall(prose))
    if pt + en < MINIMUM:
        return None
    return pt > 2 * en


def is_marked(path: Path) -> bool:
    return "pt-BR" in str(path)


def main() -> int:
    solver = Solver()
    broken = []
    judged = 0
    for path in tracked_text_files():
        portuguese = is_portuguese(path)
        if portuguese is None:
            continue
        judged += 1
        name = str(path)
        p, m = Bool(f"portuguese[{name}]"), Bool(f"marked[{name}]")
        solver.add(p == BoolVal(portuguese), m == BoolVal(is_marked(path)))
        broken.append(Xor(p, m))   # the negation of  p <-> m  for this file

    solver.add(Or(*broken))        # some file breaks the rule?
    result = solver.check()
    if result == sat:
        model = solver.model()
        for x in broken:
            if model.eval(x):
                name = x.arg(0).decl().name()[len("portuguese["):-1]
                print(f"FAIL  {name}: " + ("Portuguese, but its path has no pt-BR"
                                           if model.eval(x.arg(0)) else "marked pt-BR, but not Portuguese"))
        print(f"\n{sum(1 for x in broken if model.eval(x))} file(s) break the language rule")
        return 1
    print(f"OK    {judged} files judged: every Portuguese file is marked pt-BR, and only those ({result})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
