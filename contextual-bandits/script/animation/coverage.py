"""What `checks/video-takes.sh` checks, without Manim: every take of the script has exactly one
scene, every scene compiles, every label a scene names is in labels.pt-BR.toml with balanced braces,
and every number the scenes read can be found in results.md.

    python3 contextual-bandits/script/animation/coverage.py
"""

from __future__ import annotations

import re
import sys
import tomllib
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import results  # noqa: E402

KEY = re.compile(r"""["'](t\d_\d\.\w+|blocks\.\w+)["']""")
TAKE = re.compile(r'^    TAKE = "(\d\.\d)"$', re.M)


def lookup(tree: dict, key: str):
    for part in key.split("."):
        tree = tree[part]
    return tree


def strings(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, list):
        for x in node:
            yield from strings(x)
    elif isinstance(node, dict):
        for x in node.values():
            yield from strings(x)


def main() -> int:
    errors: list[str] = []
    labels = tomllib.loads((HERE / "labels.pt-BR.toml").read_text(encoding="utf-8"))

    wanted = results.takes()
    found: dict[str, list[str]] = {}
    for f in sorted(HERE.glob("*.py")):
        text = f.read_text(encoding="utf-8")
        try:
            compile(text, str(f), "exec")
        except SyntaxError as e:
            errors.append(f"{f.name}: does not compile: {e}")
        for take in TAKE.findall(text):
            found.setdefault(take, []).append(f.name)
        for key in KEY.findall(text):
            try:
                lookup(labels, key)
            except (KeyError, TypeError):
                errors.append(f"{f.name}: label {key} is not in labels.pt-BR.toml")
        # Each take's own title: `self.title()` reads t<N>_<M>.title.
        for take in TAKE.findall(text):
            if "self.title()" in text:
                try:
                    lookup(labels, f"t{take.replace('.', '_')}.title")
                except KeyError:
                    errors.append(f"{f.name}: no title for take {take} in labels.pt-BR.toml")

    for take in wanted:
        if take not in found:
            errors.append(f"take {take} of the script has no scene")
    for take, files in found.items():
        if take not in wanted:
            errors.append(f"{', '.join(files)}: take {take} is not in the script")
        if len(files) > 1:
            errors.append(f"take {take} has more than one scene: {', '.join(files)}")

    for s in strings(labels):
        if s.count("{") != s.count("}"):
            errors.append(f"labels.pt-BR.toml: unbalanced braces in {s!r}")

    for name in ("beliefs", "digits", "single_armed", "multi_armed", "regret", "rsi"):
        try:
            getattr(results, name)()
        except Exception as e:  # a section or a column of results.md moved
            errors.append(f"results.md: {name}: {type(e).__name__}: {e}")

    for e in errors:
        print("FAIL ", e)
    if errors:
        return 1
    print(f"OK    {len(wanted)} takes, one scene each; labels and results.md readable")
    return 0


if __name__ == "__main__":
    sys.exit(main())
