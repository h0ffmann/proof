"""Lines of code per language, as badges written into README.md between two markers.

The badges sit between `<!-- loc:start -->` and `<!-- loc:end -->` in README.md, one per language
with the most code first, and a last one for the total. They are generated: edit this script, not
the badges. The mechanism follows h0ffmann/awesome-neurosymbolic-ai (a
standard-library Python script fills a marker in the README, and a workflow runs it and commits
the result).

What counts: every file tracked by git, outside `vendor/` (other people's code), whose extension
names a programming language below. A line of code is a line that is not blank and not only a
comment. Line comments and block comments are recognised per language; a block comment that opens
after code on the same line leaves that line counted.

    python3 scripts/loc.py           # rewrite the badges in README.md
    python3 scripts/loc.py --check   # exit code 1 if the badges in README.md are out of date
    python3 scripts/loc.py --print   # print the badges only
"""

from __future__ import annotations

import subprocess
import sys
from urllib.parse import quote
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
START = "<!-- loc:start -->"
END = "<!-- loc:end -->"
SKIP_DIRS = ("vendor/",)
COLOR = "1b3a5c"  # the colour of the badges in the README's header

# language: (extensions or file names, line comment prefixes, block comment (open, close) pairs)
LANGUAGES: dict[str, tuple[tuple[str, ...], tuple[str, ...], tuple[tuple[str, str], ...]]] = {
    "Scala": ((".scala", ".sbt"), ("//",), (("/*", "*/"),)),
    "Python": ((".py",), ("#",), ()),
    "Lean 4": ((".lean",), ("--",), (("/-", "-/"),)),
    "Haskell": ((".hs",), ("--",), (("{-", "-}"),)),
    "Rust": ((".rs",), ("//",), (("/*", "*/"),)),
    "Gleam": ((".gleam",), ("//",), ()),
    "Zig": ((".zig",), ("//",), ()),
    "Erlang": ((".erl",), ("%",), ()),
    "Shell": ((".sh",), ("#",), ()),
    "Nix": ((".nix",), ("#",), (("/*", "*/"),)),
    "JavaScript": ((".js", ".mjs"), ("//",), (("/*", "*/"),)),
    "TeX": ((".tex",), ("%",), ()),
    "just": (("justfile", ".just"), ("#",), ()),
    "ASP (clingo)": ((".lp",), ("%",), (("%*", "*%"),)),
    "TPTP": ((".p",), ("%",), (("/*", "*/"),)),
}

# Simple Icons slugs for the badges' logos, where one exists
LOGOS = {
    "Scala": "scala",
    "Python": "python",
    "Haskell": "haskell",
    "Rust": "rust",
    "Gleam": "gleam",
    "Zig": "zig",
    "Erlang": "erlang",
    "Shell": "gnubash",
    "Nix": "nixos",
    "JavaScript": "javascript",
    "TeX": "latex",
}


def language_of(path: str) -> str | None:
    name = path.rsplit("/", 1)[-1]
    for lang, (exts, _, _) in LANGUAGES.items():
        if name in exts or any(name.endswith(e) for e in exts if e.startswith(".")):
            return lang
    return None


def count_code(text: str, line: tuple[str, ...], blocks: tuple[tuple[str, str], ...]) -> int:
    """Lines that are not blank and not only a comment."""
    n = 0
    close: str | None = None  # the closing token of the block comment we are in, if any
    for raw in text.splitlines():
        s = raw.strip()
        code = False
        while s:
            if close is not None:
                i = s.find(close)
                if i < 0:
                    s = ""
                    break
                s = s[i + len(close):].strip()
                close = None
                continue
            # a block opener first: clingo's `%*` also starts with its line comment `%`
            opened = next(((o, c) for o, c in blocks if s.startswith(o)), None)
            if opened is not None:
                close = opened[1]
                s = s[len(opened[0]):]
                continue
            if any(s.startswith(p) for p in line):
                break
            code = True  # code first; a comment later on the line does not matter
            break
        n += code
    return n


def tracked_files() -> list[str]:
    out = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True)
    return [p for p in out.stdout.decode().split("\0") if p and not p.startswith(SKIP_DIRS)]


def measure() -> dict[str, tuple[int, int]]:
    """language -> (files, lines of code)."""
    totals: dict[str, tuple[int, int]] = {}
    for path in tracked_files():
        lang = language_of(path)
        if lang is None:
            continue
        _, line, blocks = LANGUAGES[lang]
        text = (ROOT / path).read_text(encoding="utf-8", errors="replace")
        files, loc = totals.get(lang, (0, 0))
        totals[lang] = (files + 1, loc + count_code(text, line, blocks))
    return totals


def badge(label: str, message: str, logo: str | None) -> str:
    """A shields.io static badge in Markdown; `-` and `_` are doubled as shields asks."""
    def esc(t: str) -> str:
        return quote(t.replace("-", "--").replace("_", "__").replace(" ", "_"), safe="_")
    url = f"https://img.shields.io/badge/{esc(label)}-{esc(message)}-{COLOR}?style=flat-square"
    if logo:
        url += f"&logo={logo}&logoColor=white"
    return f"![{label}: {message}]({url})"


def render(totals: dict[str, tuple[int, int]]) -> list[str]:
    ranked = sorted(totals.items(), key=lambda kv: (-kv[1][1], kv[0]))
    all_loc = sum(loc for _, (_, loc) in ranked)
    all_files = sum(files for _, (files, _) in ranked)
    lines = [
        badge(lang, f"{loc:,} lines · {100 * loc / all_loc:.1f}%", LOGOS.get(lang))
        for lang, (files, loc) in ranked
    ]
    lines.append(badge("total", f"{all_loc:,} lines in {all_files} files", None))
    return lines


def splice(readme: str, badges: list[str]) -> str:
    lines = readme.splitlines()
    try:
        a, b = lines.index(START), lines.index(END)
    except ValueError:
        sys.exit(f"README.md needs the markers {START} and {END}, on lines of their own")
    if b < a:
        sys.exit(f"{END} comes before {START} in README.md")
    return "\n".join(lines[: a + 1] + badges + lines[b:]) + "\n"


def main(argv: list[str]) -> int:
    badges = render(measure())
    if "--print" in argv:
        print("\n".join(badges))
        return 0
    old = README.read_text(encoding="utf-8")
    new = splice(old, badges)
    if "--check" in argv:
        if new != old:
            print("README.md: the lines-of-code badges are out of date; run `just loc`")
            return 1
        print("README.md: the lines-of-code badges are current")
        return 0
    if new != old:
        README.write_text(new, encoding="utf-8")
        print("README.md: lines-of-code badges updated")
    else:
        print("README.md: lines-of-code badges already current")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
