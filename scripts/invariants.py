#!/usr/bin/env python3
"""Check the repository against Invariants.lp.

Read the tracked files, the commits of this branch that main does not have, and the branch name;
write them as facts; solve the facts with Invariants.lp in clingo. The program decides; this script
only reads. Exit 1 when a violation is not waived, or when a waiver excuses nothing.

  scripts/invariants.py               # check the tree
  scripts/invariants.py --facts       # print the facts and stop
  scripts/invariants.py --self-test   # bad facts must give each violation
"""
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                      check=True).stdout.strip()
PROGRAM = os.path.join(ROOT, "Invariants.lp")

ATTRIBUTION = re.compile(r"^\s*(co-authored-by|claude-session|signed-off-by)\s*:|"
                         r"(generated with|requested by)", re.I | re.M)
PAIR = re.compile(r"(?<![\w./-])([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]*[A-Za-z0-9_])")
ISSUE_REF = re.compile(r"(?<![\w./-])([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]+)#\d+")
URL = re.compile(r"github\.com/([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]*[A-Za-z0-9_])")
# The same patterns as scripts/lean-hygiene.sh.
LEAN_HOLE = re.compile(r"\b(sorry|admit)\b")
LEAN_AXIOM = re.compile(r"^\s*((private|protected|noncomputable|unsafe|@\[[^]]*\])\s+)*axiom(\s|$)")
LEAN_NATIVE = re.compile(r"\bnative_decide\b")


def q(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True,
                          check=True).stdout


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8", errors="replace") as f:
        return f.read()


def base_ref():
    for ref in ("origin/main", "main"):
        if subprocess.run(["git", "rev-parse", "-q", "--verify", ref], cwd=ROOT,
                          capture_output=True).returncode == 0:
            return ref
    return None


def facts():
    out = []
    files = [f for f in git("ls-files", "-z").split("\0") if f and os.path.exists(os.path.join(ROOT, f))]
    fs = set(files)
    for f in files:
        out.append(f"file({q(f)}).")
        if f.endswith(".pdf"):
            out.append(f"pdf({q(f)}).")

    for f in files:
        if not f.endswith(".lean") or f.startswith("vendor/"):
            continue
        out.append(f"lean({q(f)}).")
        if os.path.basename(f) == "Examples.lean":
            out.append(f"lean_examples({q(f)}).")
        for n, line in enumerate(read(f).splitlines(), 1):
            for m in LEAN_HOLE.finditer(line):
                out.append(f"lean_token({q(f)}, {n}, {m.group(1)}).")
            if LEAN_AXIOM.search(line):
                out.append(f"lean_token({q(f)}, {n}, axiom).")
            if LEAN_NATIVE.search(line):
                out.append(f"lean_token({q(f)}, {n}, native_decide).")
    for f in files:
        name = os.path.basename(f)
        if name in ("lakefile.toml", "lakefile.lean") and not f.startswith("vendor/"):
            d = os.path.dirname(f)
            out.append(f"lean_package({q(d)}).")
            if os.path.join(d, "lean-toolchain") in fs:
                out.append(f"lean_pinned({q(d)}).")

    base = base_ref()
    commits = git("rev-list", f"{base}..HEAD").split() if base else []
    for c in commits:
        msg = git("log", "-1", "--format=%B", c)
        out.append(f"commit({q(c)}).")
        for m in ATTRIBUTION.finditer(msg):
            out.append(f"commit_trailer({q(c)}, {q((m.group(1) or m.group(2)).lower())}).")
        for a, b in set(PAIR.findall(msg)):
            out.append(f"commit_pair({q(c)}, {q(a)}, {q(b)}).")
        for a, b in set(ISSUE_REF.findall(msg)):
            out.append(f"commit_issue_ref({q(c)}, {q(a)}, {q(b)}).")
        for a, b in set(URL.findall(msg)):
            out.append(f"commit_url({q(c)}, {q(a)}, {q(b)}).")

    branch = git("rev-parse", "--abbrev-ref", "HEAD").strip()
    if branch not in ("HEAD", "main"):
        out.append(f"branch({q(branch)}).")
        for w in re.split(r"[^A-Za-z0-9]+", branch.lower()):
            if w:
                out.append(f"branch_part({q(branch)}, {q(w)}).")
            if w.startswith("session") or w.startswith("cmsg"):
                out.append(f"branch_part({q(branch)}, {q('session')}).")

    if "flake.lock" in fs:
        for name, node in json.loads(read("flake.lock")).get("nodes", {}).items():
            if node.get("locked", {}).get("rev") or node.get("locked", {}).get("narHash"):
                out.append(f"flake_input_locked({q(name)}).")
    if "flake.nix" in fs:
        flake = uncomment(read("flake.nix"))
        sources = [flake]
        # A shell in nix/<name>.nix counts once flake.nix turns each such file into a shell.
        if re.search(r"readDir\s+\./nix", flake):
            out.append("nix_shells_discovered.")
            sources += [uncomment(read(f)) for f in files if re.fullmatch(r"nix/[^/]+\.nix", f)]
        names = set()
        for text in sources:
            for p in re.findall(r"\bpkgs\.([A-Za-z0-9_-]+)", text):
                names.add(p)
                # jdk25, jdk25_headless, temurin-bin-21, z3_4_13: the tool without its version.
                names.add(re.sub(r"(-bin)?([-_]?\d+)+$", "", re.sub(r"_headless$", "", p)))
        for p in sorted(names):
            out.append(f"nix_package({q(p)}).")

    imports = re.findall(r"^\s*import\??\s+['\"]([^'\"]+)['\"]", read("justfile"), re.M) \
        if "justfile" in fs else []
    for f in imports:
        out.append(f"just_import({q(f)}).")
    for f in files:
        if re.fullmatch(r"just/[^/]+\.just", f):
            out.append(f"just_file({q(f)}).")
        if re.fullmatch(r"checks/[^/]+\.sh", f):
            out.append(f"check_script({q(f)}).")
            if re.search(r"^\s*set -euo pipefail", read(f), re.M):
                out.append(f"strict({q(f)}).")

    for f in files:
        if re.fullmatch(r"\.github/workflows/[^/]+\.ya?ml", f):
            for t in triggers(read(f)):
                out.append(f"workflow_trigger({q(f)}, {q(t)}).")

    for f in files:
        if f.endswith(".cabal"):
            text = read(f)
            m = re.search(r"^name:\s*(\S+)", text, re.M)
            if m:
                out.append(f"cabal_package({q(m.group(1))}).")
            for block in re.findall(r"build-depends:\s*((?:.*\n)(?:[ \t]+[^:\n]*\n)*)", text):
                for dep in block.replace("\n", " ").split(","):
                    name = dep.strip().split(" ")[0].split(">")[0].split("<")[0].split("=")[0]
                    if name:
                        out.append(f"cabal_dep({q(f)}, {q(name)}).")
    return out


def uncomment(nix):
    return "\n".join(l.split("#", 1)[0] for l in nix.splitlines())


def triggers(text):
    """The keys under `on:` (or `true:`, as YAML 1.1 reads it), comments left out."""
    lines = [l.split("#", 1)[0].rstrip() for l in text.splitlines()]
    found = []
    for i, line in enumerate(lines):
        m = re.match(r"^(on|\"on\"|'on'):\s*(.*)$", line)
        if not m:
            continue
        inline = m.group(2).strip()
        if inline:
            found += [t.strip() for t in inline.strip("[]").split(",") if t.strip()]
            continue
        for sub in lines[i + 1:]:
            if sub and not sub[0].isspace():
                break
            k = re.match(r"^  ([A-Za-z_]+):", sub)
            if k:
                found.append(k.group(1))
    return found


def clingo():
    """The clingo binary (Nix), or the pip package's module (checks/invariants.requirements.txt)."""
    exe = shutil.which("clingo")
    if exe:
        return [exe]
    if subprocess.run([sys.executable, "-c", "import clingo"], capture_output=True).returncode == 0:
        return [sys.executable, "-m", "clingo"]
    sys.exit("invariants: no clingo (nix develop .#invariants, "
             "or pip install -r checks/invariants.requirements.txt)")


def solve(fact_lines):
    r = subprocess.run([*clingo(), "--outf=2", "-", PROGRAM], input="\n".join(fact_lines),
                       capture_output=True, text=True)
    # The binary exits 10 or 30 on SATISFIABLE; the pip module exits 0. The JSON says which.
    try:
        result = json.loads(r.stdout)
    except json.JSONDecodeError:
        sys.exit(f"invariants: clingo failed ({r.returncode}):\n{r.stderr}{r.stdout}")
    if result.get("Result") != "SATISFIABLE":
        sys.exit(f"invariants: clingo gave {result.get('Result')}:\n{r.stderr}")
    return result["Call"][-1]["Witnesses"][-1]["Value"]


def report(atoms):
    failing = [a for a in atoms if a.startswith("failing(")]
    stale = [a for a in atoms if a.startswith("stale_waiver(")]
    gaps = [a for a in atoms if a.startswith("gap(")]
    for a in sorted(gaps):
        print(f"invariants: gap   {a}")
    for a in sorted(failing + stale):
        print(f"invariants: FAIL  {a}", file=sys.stderr)
    return 1 if failing or stale else 0


BAD = [
    ('just_import("just/gone.just").', "just_import_missing"),
    ('just_file("just/orphan.just").', "just_file_not_imported"),
    ('check_script("checks/loose.sh").', "check_not_strict"),
    ('commit("c1"). commit_pair("c1", "piabrota", "room").', "commit_mentions_repo"),
    ('commit("c2"). commit_url("c2", "someone", "else").', "commit_mentions_repo"),
    ('commit("c3"). commit_issue_ref("c3", "someone", "else").', "commit_mentions_repo"),
    ('commit("c4"). commit_trailer("c4", "co-authored-by").', "commit_attribution"),
    ('branch("claude/x"). branch_part("claude/x", "claude").', "branch_named_by_session"),
    ('lean_package("pkg").', "lean_toolchain_unpinned"),
    ('lean("A.lean"). lean_token("A.lean", 2, sorry).', "lean_hole"),
    ('lean("A.lean"). lean_token("A.lean", 2, axiom).', "lean_hole"),
    ('lean("T.lean"). lean_token("T.lean", 3, native_decide).', "native_decide_outside_examples"),
    ('cabal_dep("x.cabal", "text").', "haskell_dependency"),
    ('workflow_trigger("w.yml", "pull_request").', "workflow_runs_by_itself"),
    ('file("a.pdf"). pdf("a.pdf").', "pdf_committed"),
]
# Facts that every case shares, so that only the case's own rule fires.
GOOD = ['file("flake.nix").', 'file("flake.lock").', 'flake_input_locked("paper").',
        'file("papers/fat-tails/fat-tails.pdf").', 'pdf("papers/fat-tails/fat-tails.pdf").',
        'file("papers/tv-audience/tv-audience.pdf").', 'pdf("papers/tv-audience/tv-audience.pdf").']
CLEAN = GOOD + ['lean("E/Examples.lean"). lean_examples("E/Examples.lean"). '
                'lean_token("E/Examples.lean", 1, native_decide).',
                'commit("ok"). commit_pair("ok", "h0ffmann", "proof"). commit_pair("ok", "z3-scala", "z3.sh").',
                'cabal_package("contextual-bandit"). cabal_dep("x.cabal", "base"). '
                'cabal_dep("x.cabal", "contextual-bandit"). cabal_dep("x.cabal", "liquidhaskell").',
                'workflow_trigger("w.yml", "workflow_dispatch").',
                'branch("add-invariants-lp"). branch_part("add-invariants-lp", "invariants").']
# A file that makes the tree need a toolchain, a nixpkgs attribute that pins it, the toolchain.
NEEDS = [('file("house-pricing/rust/Cargo.toml").', "cargo", "rust"),
         ('file("tools/gleam.toml").', "gleam", "gleam"),
         ('file("vendor/archify/package.json").', "nodejs", "node"),
         ('file("pomodoro/pomodoro.zig").', "zig", "zig"),
         ('file(".claude/skills/roteiro-preview/preview.py").', "ffmpeg-headless", "ffmpeg"),
         ('lean_package("cycle/lean").', "lean4", "lean")]



def self_test():
    for fact, rule in BAD:
        atoms = solve(GOOD + [fact])
        if not any(a.startswith(f"failing({rule},") for a in atoms):
            sys.exit(f"invariants: self-test: {fact} did not give {rule}: {atoms}")
    atoms = solve(CLEAN)
    if any(a.startswith(("failing(", "stale_waiver(")) for a in atoms):
        sys.exit(f"invariants: self-test: clean facts failed: {atoms}")
    # A tool the tree needs is a gap until a Nix shell names its package.
    for need, pkg, tool in NEEDS:
        if "gap(toolchain_not_in_nix," + tool + ")" not in solve(GOOD + [need]):
            sys.exit(f"invariants: self-test: {need} gave no gap for {tool}")
        if "gap(toolchain_not_in_nix," + tool + ")" in solve(GOOD + [need, f'nix_package("{pkg}").']):
            sys.exit(f"invariants: self-test: nix_package({pkg}) did not close the gap of {tool}")
    if not any(a.startswith("stale_waiver(") for a in solve(GOOD[:3])):
        sys.exit("invariants: self-test: a waiver that excuses nothing passed")
    print(f"invariants: self-test passed ({len(BAD)} bad cases, 1 clean, 1 stale waiver, "
          f"{len(NEEDS)} toolchains)")


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "--self-test":
        self_test()
    elif arg == "--facts":
        print("\n".join(facts()))
    elif arg == "":
        code = report(solve(facts()))
        if code == 0:
            print("invariants: ok")
        sys.exit(code)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
