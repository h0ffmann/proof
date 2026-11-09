"""How much of WAVEWATCH III chaceon translated, and how much of that its switches build, with Z3.

Two numbers, both in Fortran code lines of `model/src/*.F90` at chaceon's WW3 pin (lines that are not
blank, not a `!` comment and not a preprocessor line, the unit of chaceon's `scripts/port_summary.py`):

* **Translated**: the lines of the routines that `rust/ports.tsv` lists, a row being a routine with
  Rust. Each row's status is its evidence, weakest first: `translated`, `routine`, `host`, `spirv`.
* **Integrated**: the translated lines that a chaceon switch file compiles in. WW3 picks its physics
  and its I/O with `#ifdef W3_<SWITCH>` blocks; a switch file (`switches/switch_chaceon_shrd`, the
  port's target, and one file per capture build) lists the switches that are on.

Z3 decides the switches. A line's condition is the formula, over one Boolean per `W3_` macro, of
its file being built (WW3's CMake rules: `switches.json`, `src_list.cmake`, `CMakeLists.txt`) and of its
preprocessor blocks (`#ifdef`, `#ifndef`, `#if defined ... && ... || !...`, `#elif`, `#else`, nested).
A switch file compiles the line when the switch set implies the condition: Z3 finds no counterexample
(`unsat`). A line is dead when no switch set that `check_switches.cmake` accepts compiles it. Macros
that are not switches (`TEST_*`, `ENABLE_*`, `COAMPS`, `NOCGTABLE`...) are off, as in a WW3 build with
no `-D` flag.

    python3 port-audit/coverage.py           # fetch the pins into port-audit/.cache, print the tables
    python3 port-audit/coverage.py --write   # also write them into port-audit/README.md
    python3 port-audit/coverage.py --check   # exit 1 when README.md is stale
    python3 port-audit/coverage.py --chaceon DIR --ww3 DIR   # use checkouts already on disk
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

from z3 import And, Bool, BoolVal, If, Implies, Not, Or, Solver, Sum, sat, unsat

HERE = Path(__file__).resolve().parent
CACHE = HERE / ".cache"
README = HERE / "README.md"
BEGIN, END = "<!-- coverage:begin -->", "<!-- coverage:end -->"

CHACEON_URL = "https://github.com/h0ffmann/chaceon"
CHACEON_COMMIT = "fe531e1e64950c0f3ce7987ae4ed0325a56adfbe"  # the same pin as chaceon.py
WW3_URL = "https://github.com/metocean/WW3"
WW3_COMMIT = "92e2cf66af6e15ae80eb12562f2b05d4a2d75df5"  # chaceon's WW3 submodule at CHACEON_COMMIT

TARGET = "switch_chaceon_shrd"
EVIDENCE = ["translated", "routine", "host", "spirv"]  # weakest first, as in rust/ports.tsv


# --------------------------------------------------------------------------------------
# The pins


def fetch(url: str, commit: str, into: Path, sparse: list[str]) -> Path:
    """A shallow checkout of one commit, only the paths in `sparse`. Reused when it is at the commit."""
    git = ["git", "-C", str(into)]
    if (into / ".git").exists():
        head = subprocess.run(git + ["rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
        if head == commit:
            return into
    into.mkdir(parents=True, exist_ok=True)
    run = lambda *a: subprocess.run(git + list(a), check=True, capture_output=True)  # noqa: E731
    if not (into / ".git").exists():
        run("init", "-q")
        run("remote", "add", "origin", url)
    run("sparse-checkout", "set", "--no-cone", *sparse)
    run("fetch", "-q", "--depth", "1", "--filter=blob:none", "origin", commit)
    run("checkout", "-q", "FETCH_HEAD")
    return into


# --------------------------------------------------------------------------------------
# The preprocessor, as Z3 formulas

MACRO = re.compile(r"[A-Za-z_]\w*")


def macro(name: str):
    return Bool(name)


def condition(text: str):
    """The expression of `#if` or `#elif` as a Z3 formula. `defined X`, `defined(X)`, `!`, `&&`, `||`,
    parentheses. A bare name is defined-ness too: WW3's switches are defined to nothing."""
    tokens = re.findall(r"defined\s*\(\s*\w+\s*\)|defined\s+\w+|&&|\|\||!|\(|\)|\w+", text)
    pos = 0

    def peek():
        return tokens[pos] if pos < len(tokens) else None

    def take():
        nonlocal pos
        pos += 1
        return tokens[pos - 1]

    def primary():
        t = take()
        if t == "!":
            return Not(primary())
        if t == "(":
            e = disjunction()
            assert take() == ")", text
            return e
        if t.startswith("defined"):
            return macro(MACRO.findall(t)[1])
        if t.isdigit():
            return BoolVal(int(t) != 0)
        return macro(t)

    def conjunction():
        e = primary()
        while peek() == "&&":
            take()
            e = And(e, primary())
        return e

    def disjunction():
        e = conjunction()
        while peek() == "||":
            take()
            e = Or(e, conjunction())
        return e

    e = disjunction()
    assert pos == len(tokens), f"cannot read #if {text!r}"
    return e


DIRECTIVE = re.compile(r"^\s*#\s*(\w+)\s*(.*?)\s*$")


def guards(lines: list[str]) -> list:
    """For each line, the formula under which the preprocessor keeps it (None for a directive line)."""
    out, stack = [], []  # stack of (guard of the enclosing block, condition of this branch, any earlier branch)
    current = BoolVal(True)
    for line in lines:
        d = DIRECTIVE.match(line)
        kind = d.group(1) if d else None
        if kind in ("if", "ifdef", "ifndef"):
            arg = d.group(2)
            c = condition(arg) if kind == "if" else macro(arg.split()[0])
            c = Not(c) if kind == "ifndef" else c
            stack.append((current, c, c))
            current = And(current, c)
        elif kind == "elif":
            outer, _, earlier = stack.pop()
            c = And(Not(earlier), condition(d.group(2)))
            stack.append((outer, c, Or(earlier, c)))
            current = And(outer, c)
        elif kind == "else":
            outer, _, earlier = stack.pop()
            stack.append((outer, Not(earlier), BoolVal(True)))
            current = And(outer, Not(earlier))
        elif kind == "endif":
            current = stack.pop()[0]
        if d:
            out.append(None)
        else:
            out.append(current)
    assert not stack, "unbalanced #if"
    return out


def is_code(line: str) -> bool:
    s = line.strip()
    return bool(s) and not s.startswith(("!", "#"))


# --------------------------------------------------------------------------------------
# WW3's build rules, as Z3 constraints (model/src/cmake/: switches.json, check_switches.cmake,
# src_list.cmake, and the program lists of model/src/CMakeLists.txt)

# Executables CMakeLists.txt always builds, and those it builds when NetCDF is found (chaceon has it).
PROGRAMS = ["ww3_strt", "ww3_grid", "ww3_bound", "ww3_outf", "ww3_outp", "ww3_trck", "ww3_grib", "ww3_gint",
            "gx_outf", "gx_outp", "ww3_uprstr", "ww3_shel", "ww3_prep", "ww3_gspl", "ww3_multi", "ww3_systrk",
            "ww3_ounf", "ww3_ounp", "ww3_bounc", "ww3_trnc", "ww3_prnc"]


def switch(name: str):
    return macro(f"W3_{name}")


class Rules:
    """The build of one switch set. `valid` is check_switches.cmake: per category of switches.json,
    "one" means exactly one option, "upto1" at most one, "upto2" at most two; an option's `conflicts`
    must be off; each string of `requires` must be on, and of an array inside it, one. `built[f]` is
    the condition under which CMake compiles the file f of model/src."""

    def __init__(self, ww3: Path):
        cmake = ww3 / "model/src/cmake"
        cats = json.loads((cmake / "switches.json").read_text())
        self.options = sorted({o["name"] for c in cats for o in c["valid-options"]})
        valid = []
        built: dict[str, list] = defaultdict(list)
        for c in cats:
            on = [switch(o["name"]) for o in c["valid-options"]]
            count = Sum([If(v, 1, 0) for v in on])
            valid.append({"one": count == 1, "upto1": count <= 1, "upto2": count <= 2}[c["num_switches"]])
            for o in c["valid-options"]:
                me = switch(o["name"])
                for x in o.get("conflicts", []):
                    valid.append(Implies(me, Not(switch(x))))
                for r in o.get("requires", []):
                    need = Or([switch(y) for y in r]) if isinstance(r, list) else switch(r)
                    valid.append(Implies(me, need))
                for f in o.get("build_files", []):
                    built[f].append(me)
        self.valid = And(valid)
        core = re.search(r"set\(ftn_src(.*?)\)", (cmake / "src_list.cmake").read_text(), re.S).group(1).split()
        pdlib = And(switch("PDLIB"), Or(switch("SCOTCH"), switch("METIS")))
        self.built = defaultdict(lambda: BoolVal(False))
        for f, conds in built.items():
            self.built[f] = Or(conds)
        for f in core + [p + ".F90" for p in PROGRAMS]:
            self.built[f] = BoolVal(True)
        self.built["ww3_prtide.F90"] = switch("TIDE")
        self.built["w3ounfmetamd.F90"] = BoolVal(True)  # NetCDF found, as in chaceon's build
        for f in ("pdlib_field_vec.F90", "w3profsmd_pdlib.F90"):
            self.built[f] = Or(self.built[f], pdlib)


def switch_file(path: Path) -> frozenset[str]:
    return frozenset(path.read_text().split())


class Builds:
    """Decides, by refutation, which builds keep a line. A switch file fixes every `W3_` macro (on when
    listed) and leaves every other macro off: `kept(cond, on)` is the theorem "this switch set implies
    cond". `dead(cond)` asks for a switch set that WW3's rules accept and that keeps the line: `unsat`
    means none exists."""

    def __init__(self, rules: Rules, names: set[str]):
        self.rules = rules
        self.names = sorted(names | {f"W3_{o}" for o in rules.options})
        self.cache: dict = {}
        self.alive: list = []  # a Z3 id is reused once its term is freed: keep every cached term alive
        self.off = [macro(n) == False for n in self.names if not n.startswith("W3_")]  # noqa: E712

    def kept(self, cond, on: frozenset[str]) -> bool:
        key = (cond.get_id(), on)
        if key not in self.cache:
            self.alive.append(cond)
            s = Solver()
            s.add(*[macro(n) == (n[3:] in on) if n.startswith("W3_") else macro(n) == False  # noqa: E712
                    for n in self.names])
            s.add(Not(cond))
            r = s.check()
            assert r in (sat, unsat), r
            self.cache[key] = r == unsat
        return self.cache[key]

    def dead(self, cond) -> bool:
        key = (cond.get_id(), "dead")
        if key not in self.cache:
            self.alive.append(cond)
            s = Solver()
            s.add(self.rules.valid, *self.off, cond)
            self.cache[key] = s.check() == unsat
        return self.cache[key]

    def valid(self, on: frozenset[str]) -> list[str]:
        """The rules a switch file breaks, by name of the rule (empty: CMake accepts it)."""
        s = Solver()
        s.add(*[switch(o) == (o in on) for o in self.rules.options])
        s.add(self.rules.valid)
        if s.check() == sat:
            return []
        return [o for o in sorted(on) if o not in self.rules.options] or ["switches.json"]


# --------------------------------------------------------------------------------------
# The ledger

RANGE = re.compile(r"model/src/([\w.]+\.F90)(?::(\d+)-(\d+))?")


def ledger(chaceon: Path) -> list[tuple[str, str, int, int | None, str]]:
    """Rows of rust/ports.tsv as (routine, file, first, last, status); last None means the whole file."""
    rows = []
    for line in (chaceon / "rust/ports.tsv").read_text().splitlines():
        if line.startswith("#") or line.startswith("routine\t") or not line.strip():
            continue
        routine, where, _, status = line.split("\t")[:4]
        m = RANGE.fullmatch(where)
        assert m and status in EVIDENCE, line
        first, last = (int(m.group(2)), int(m.group(3))) if m.group(2) else (1, None)
        rows.append((routine, m.group(1), first, last, status))
    return rows


# --------------------------------------------------------------------------------------


def measure(chaceon: Path, ww3: Path) -> str:
    src = ww3 / "model/src"
    files = {f.name: f.read_text(errors="replace").splitlines() for f in sorted(src.glob("*.F90"))}
    switches = {p.name: switch_file(p) for p in sorted((chaceon / "switches").glob("switch_*"))}
    assert TARGET in switches

    names = set()
    for lines in files.values():
        for line in lines:
            d = DIRECTIVE.match(line)
            if d and d.group(1) in ("if", "ifdef", "ifndef", "elif"):
                names |= set(MACRO.findall(d.group(2))) - {"defined"}
    rules = Rules(ww3)
    builds = Builds(rules, names)

    # The status of each translated line: the strongest row of the ledger that covers it.
    status: dict[tuple[str, int], str] = {}
    for _, f, first, last, st in ledger(chaceon):
        for i in range(first, (last or len(files[f])) + 1):
            if (f, i) not in status or EVIDENCE.index(st) > EVIDENCE.index(status[(f, i)]):
                status[(f, i)] = st

    total = translated = dead = dead_translated = 0
    in_build = defaultdict(int)  # switch file -> code lines it compiles
    integrated = defaultdict(int)  # switch file -> translated code lines it compiles
    by_status = defaultdict(lambda: [0, 0, 0])  # status -> [translated, in TARGET, in some switch file]
    for f, lines in files.items():
        built = rules.built[f]
        for i, (line, g) in enumerate(zip(lines, guards(lines)), start=1):
            if not is_code(line):
                continue
            cond = And(built, g)
            total += 1
            st = status.get((f, i))
            kept = {s for s, on in switches.items() if builds.kept(cond, on)}
            for s in kept:
                in_build[s] += 1
                integrated[s] += bool(st)
            is_dead = builds.dead(cond)
            dead += is_dead
            if st:
                translated += 1
                dead_translated += is_dead
                row = by_status[st]
                row[0] += 1
                row[1] += TARGET in kept
                row[2] += bool(kept)

    pct = lambda a, b: f"{100 * a / b:.0f}%" if b else "-"  # noqa: E731
    target_lines, target_integrated = in_build[TARGET], integrated[TARGET]
    any_integrated = sum(r[2] for r in by_status.values())
    out = [
        f"Generated by `python3 port-audit/coverage.py --write` from chaceon `{CHACEON_COMMIT[:8]}` "
        f"(`rust/ports.tsv`, `switches/`) and WW3 `{WW3_COMMIT[:8]}` (`model/src/*.F90`, {len(files)} files, "
        f"and its CMake rules). Unit: Fortran code lines.",
        "",
        "| WW3 code lines | Lines | Share |",
        "|---|---:|---:|",
        f"| All of `model/src/*.F90` | {total:,} | 100% |",
        f"| **Translated**: in a routine of `rust/ports.tsv` | {translated:,} | {pct(translated, total)} |",
        f"| Compiled by `{TARGET}`, the port's target build | {target_lines:,} | {pct(target_lines, total)} |",
        f"| **Integrated**: translated and compiled by `{TARGET}` | {target_integrated:,} | "
        f"{pct(target_integrated, target_lines)} of the target build |",
        f"| Translated, compiled only by a capture switch file | {any_integrated - target_integrated:,} | "
        f"{pct(any_integrated - target_integrated, translated)} of translated |",
        f"| Translated, compiled by no chaceon switch file | {translated - any_integrated:,} | "
        f"{pct(translated - any_integrated, translated)} of translated |",
        f"| Dead: no switch set that WW3's rules accept compiles it (Z3 `unsat`) | {dead:,} | "
        f"{pct(dead, total)} |",
        "",
        "| Evidence in `rust/ports.tsv` | Translated | Integrated in the target | In some chaceon switch file |",
        "|---|---:|---:|---:|",
    ]
    for st in reversed(EVIDENCE):
        t, i, a = by_status[st]
        out.append(f"| `{st}` | {t:,} | {i:,} | {a:,} |")
    out += ["", "| Switch file | WW3's rules (Z3) | Compiles | Of it translated |", "|---|---|---:|---:|"]
    for s, on in switches.items():
        broken = builds.valid(on)
        verdict = "accepted" if not broken else "breaks " + ", ".join(f"`{b}`" for b in broken)
        out.append(f"| `{s}` | {verdict} | {in_build[s]:,} | {integrated[s]:,} ({pct(integrated[s], in_build[s])}) |")
    unreachable = [o for o in rules.options if not _possible(rules, o)]
    out += ["", f"Translated lines that are dead: {dead_translated:,}. Switch options that no accepted switch "
            f"set can turn on: {', '.join(f'`{o}`' for o in unreachable) or 'none'}."]
    return "\n".join(out).rstrip() + "\n"


def _possible(rules: Rules, option: str) -> bool:
    s = Solver()
    s.add(rules.valid, switch(option))
    return s.check() == sat


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--chaceon", type=Path)
    ap.add_argument("--ww3", type=Path)
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    a = ap.parse_args()

    chaceon = a.chaceon or fetch(CHACEON_URL, CHACEON_COMMIT, CACHE / "chaceon", ["/rust/ports.tsv", "/switches/"])
    ww3 = a.ww3 or fetch(WW3_URL, WW3_COMMIT, CACHE / "WW3", ["/model/src/"])
    table = measure(chaceon, ww3)
    print(table, end="")

    text = README.read_text()
    head, rest = text.split(BEGIN)
    _, tail = rest.split(END)
    fresh = f"{head}{BEGIN}\n\n{table}\n{END}{tail}"
    if a.write:
        README.write_text(fresh)
    elif a.check and fresh != text:
        print(f"coverage: {README.name} is stale; run python3 port-audit/coverage.py --write", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
