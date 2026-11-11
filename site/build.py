#!/usr/bin/env python3
"""Build the browsable index of proof: one folder that a web server can serve at any path.

    python3 site/build.py --out DIR [--rev COMMIT] [--stamp TEXT] [--no-pdf] [--no-video]
    python3 site/build.py --check

Run it from the repository root. It writes, in DIR:

    index.html            the index: preprints, pages, the video script and its preview, diagrams
    papers/<name>.pdf     every paper of papers/ and the video script, with the justfile's pandoc
                          options, through XeLaTeX twice (like `just paper` and `just script`)
    <dir>/index.html      a page for each Markdown file of PAGES, at the path of its source, so that
                          relative links and images resolve as they do on GitHub
    roteiro/              preview.mp4, preview.srt and shots.md of the video script (the
                          roteiro-preview skill, with no voice)
    docs/diagrams/        the archify diagrams, as committed

A link in a page to a file that is not in DIR goes to the file on GitHub at --rev. `just site`
runs this script inside Nix (site/default.nix), so every tool is pinned by flake.lock.
--check reads every source and writes the index and the pages' link map to a temporary folder,
with no pandoc, XeLaTeX or ffmpeg; `checks/site.sh` runs it.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

REPO = "https://github.com/h0ffmann/proof"

# The Markdown files that become pages, with their section in the index and their title there.
PAGES = [
    ("Contextual bandits", "contextual-bandits/README.md", "The contextual bandit: the idea, the files, what Agda proves, the Haskell port"),
    ("Contextual bandits", "contextual-bandits/README.pt-BR.md", "The same page in Brazilian Portuguese"),
    ("Contextual bandits", "contextual-bandits/script/results.md", "The video's experiments, as the Haskell port writes them"),
    ("Contextual bandits", "docs/decisions/0001-z3-over-lean.md", "Why the specification moved from Lean to Z3"),
    ("Z3 reports", "port-audit/README.md", "Audit of chaceon, the Rust port of WAVEWATCH III: 28 statements and the coverage table"),
    ("Z3 reports", "triangle-grids/README.md", "Triangle grids for WAVEWATCH III: 13 statements on the size rules and the sub-step count"),
    ("Video script", "contextual-bandits/script/README.md", "How the video script is written and built"),
]

# Files and folders copied into the site as they are.
COPY = ["docs/diagrams/index.html", "docs/diagrams/en", "docs/diagrams/pt-BR", "docs/diagrams/img", "docs/logo/logo.svg"]

# An archify page of COPY: the links to it carry ?theme=dark.
DIAGRAM_PAGE = re.compile(r"^docs/diagrams/(en|pt-BR)/[^/]+\.html$")

# The video script: a paper outside papers/ (just/contextual-bandits.just, `script`).
SCRIPT = ("contextual-bandits/script", "prose-pt-BR", "contextual-bandits-script-pt-BR")
EDITIONS = [("prose", "", "English"), ("prose-ste", "-ste", "English, ASD-STE100"), ("prose-pt-BR", "-pt-BR", "Português (BR)")]


@dataclass
class Paper:
    folder: str          # papers/<slug>, or the script's folder
    title: str
    subtitle: str
    version: str
    date: str
    editions: list       # (prose dir, output name, label)


def front_matter(path: Path) -> dict:
    """The flat string keys of a YAML front matter: title, subtitle, version, date."""
    text = path.read_text(encoding="utf-8")
    m = re.match(r"---\n(.*?)\n---", text, re.S)
    out = {}
    for line in (m.group(1) if m else "").splitlines():
        kv = re.match(r'^([a-z]+):\s*"?(.*?)"?\s*$', line)
        if kv and kv.group(2) and kv.group(2) != "|":
            out[kv.group(1)] = kv.group(2)
    return out


def papers(root: Path) -> list[Paper]:
    found = []
    for meta in sorted(root.glob("papers/*/metadata.md")):
        folder = meta.parent
        fm = front_matter(meta)
        eds = [(d, folder.name + suffix, label) for d, suffix, label in EDITIONS if (folder / d).is_dir()]
        found.append(Paper(folder.relative_to(root).as_posix(), fm.get("title", folder.name),
                           fm.get("subtitle", ""), fm.get("version", ""), fm.get("date", ""), eds))
    folder, prose, name = SCRIPT
    fm = front_matter(root / folder / "metadata.md")
    found.append(Paper(folder, fm.get("title", "Video script"), fm.get("subtitle", ""),
                       fm.get("version", ""), fm.get("date", ""), [(prose, name, "Português (BR)")]))
    return found


def pandoc_opts(root: Path) -> list[str]:
    """The pandoc options of the justfile (`pandoc_opts`), so the PDFs are the ones `just paper` makes."""
    m = re.search(r'^pandoc_opts := "(.*)"$', (root / "justfile").read_text(encoding="utf-8"), re.M)
    if not m:
        sys.exit("site: no pandoc_opts in the justfile")
    return m.group(1).split()


def build_pdf(root: Path, paper: Paper, prose: str, name: str, out: Path, stamp: str) -> None:
    """One PDF, as the justfile's `_pdf` builds it: Markdown -> build/tex/<name>.tex -> XeLaTeX twice."""
    build = root / "build"
    (build / "tex").mkdir(parents=True, exist_ok=True)
    (build / ".current-revision").write_text(stamp, encoding="utf-8")
    src = root / paper.folder
    tex = build / "tex" / f"{name}.tex"
    subprocess.run(["pandoc", *pandoc_opts(root), "--bibliography", str(src / "refs.bib"), "-o", str(tex),
                    str(src / "metadata.md"), *map(str, sorted((src / prose).glob("*.md")))],
                   cwd=root, check=True)
    for _ in range(2):
        r = subprocess.run(["xelatex", "-interaction=nonstopmode", "-halt-on-error", f"tex/{name}.tex"],
                           cwd=build, stdout=subprocess.DEVNULL)
        if r.returncode:
            log = (build / f"{name}.log").read_text(errors="replace").splitlines()[-30:]
            sys.exit("site: xelatex failed on %s\n%s" % (name, "\n".join(log)))
    (out / "papers").mkdir(parents=True, exist_ok=True)
    shutil.copyfile(build / f"{name}.pdf", out / "papers" / f"{name}.pdf")


def page_path(src: str) -> str:
    """contextual-bandits/README.md -> contextual-bandits/index.html; x/notes.md -> x/notes.html."""
    p = PurePosixPath(src)
    stem = p.name[:-3]
    stem = "index" + stem[len("README"):] if stem.startswith("README") else stem
    return str(p.parent / f"{stem}.html")


def normal(path: str) -> str:
    """Collapse ../ and ./ of a repository-relative path; '' when it leaves the repository."""
    parts: list[str] = []
    for part in path.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if not parts:
                return ""
            parts.pop()
        else:
            parts.append(part)
    return "/".join(parts)


def relative(target: str, base_dir: str) -> str:
    """target relative to base_dir, both repository-relative."""
    t, b = target.split("/"), [x for x in base_dir.split("/") if x]
    i = 0
    while i < len(b) and i < len(t) - 1 and t[i] == b[i]:
        i += 1
    return "/".join([".."] * (len(b) - i) + t[i:])


class Links:
    """Where a relative link of a page goes: a page or a file of the site, or GitHub at the revision."""

    def __init__(self, root: Path, rev: str, site_files: dict[str, str]):
        self.root, self.rev, self.site = root, rev, site_files
        self.copies: set[str] = set()

    def rewrite(self, url: str, page_src: str, image: bool) -> str:
        if not url or re.match(r"^[a-z][a-z0-9+.-]*:|^#|^/", url, re.I):
            return url
        path, _, frag = url.partition("#")
        frag = "#" + frag if frag else ""
        path, _, query = path.partition("?")
        query = "?" + query if query else ""
        base = str(PurePosixPath(page_src).parent)
        base = "" if base == "." else base
        target = normal(f"{base}/{path}" if base else path)
        if not target:
            return url
        if target in self.site:
            # An archify page opens dark, whatever the reader's setting (AGENTS.md, "Notes").
            if DIAGRAM_PAGE.match(target):
                query = "?theme=dark"
            return relative(self.site[target], base) + query + frag
        if image and (self.root / target).is_file():
            self.copies.add(target)
            return relative(target, base) + frag
        kind = "tree" if (self.root / target).is_dir() else "blob"
        return f"{REPO}/{kind}/{self.rev}/{target}{frag}"


def walk(node, fn):
    """Apply fn to every Link and Image of a pandoc JSON AST, and to the href/src of raw HTML."""
    if isinstance(node, list):
        for x in node:
            walk(x, fn)
    elif isinstance(node, dict):
        t = node.get("t")
        if t in ("Link", "Image"):
            target = node["c"][2]
            target[0] = fn(target[0], t == "Image")
        elif t in ("RawInline", "RawBlock") and node["c"][0] == "html":
            node["c"][1] = re.sub(r'\b(href|src)="([^"]*)"',
                                  lambda m: f'{m.group(1)}="{fn(m.group(2), m.group(1) == "src")}"', node["c"][1])
        for v in node.values():
            walk(v, fn)


STYLE = """
:root { --bg:#fbfbf8; --fg:#1d1d1f; --muted:#5f6368; --line:#d9d9d4; --link:#1b5fa8; --code:#f0efe9; }
@media (prefers-color-scheme: dark) {
  :root { --bg:#141518; --fg:#e8e6e1; --muted:#a0a4ab; --line:#2e3036; --link:#79b2f2; --code:#1f2126; }
}
* { box-sizing: border-box; }
body { margin:0; padding:32px 16px 64px; background:var(--bg); color:var(--fg);
       font:16px/1.6 ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif; }
main { max-width:860px; margin:0 auto; }
a { color:var(--link); }
h1, h2, h3 { line-height:1.25; }
h2 { margin-top:2.2em; padding-bottom:.3em; border-bottom:1px solid var(--line); }
code, pre { font-family:ui-monospace, "JetBrains Mono", Menlo, monospace; font-size:.9em; background:var(--code); }
code { padding:.1em .3em; border-radius:4px; }
pre { padding:12px; overflow-x:auto; border-radius:6px; }
pre code { padding:0; background:none; }
table { border-collapse:collapse; display:block; overflow-x:auto; }
th, td { text-align:left; padding:6px 10px; border-bottom:1px solid var(--line); vertical-align:top; }
img, video { max-width:100%; height:auto; }
.muted, .meta { color:var(--muted); }
.meta { font-size:.9em; }
nav.top { font-size:.9em; margin-bottom:24px; }
header.site { text-align:center; margin-bottom:8px; }
header.site img { width:min(520px, 100%); }
ul.items { list-style:none; padding:0; }
ul.items li { padding:12px 0; border-bottom:1px solid var(--line); }
ul.items .title { font-weight:600; }
footer { margin-top:48px; font-size:.85em; color:var(--muted); }
"""


def page_template(out: Path) -> Path:
    """A pandoc HTML template: the page in <main>, a link back to the index, the site's style."""
    tpl = out.parent / "page.html5"
    tpl.write_text("""<!doctype html>
<html lang="$lang$">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$pagetitle$ · proof</title>
<link rel="stylesheet" href="$css$">
</head>
<body>
<main>
<nav class="top"><a href="$home$">proof</a> · <a href="$source$">source on GitHub</a></nav>
$body$
<footer>Built from <a href="$commit$">$stamp$</a>. MPL-2.0.</footer>
</main>
</body>
</html>
""", encoding="utf-8")
    return tpl


def build_page(root: Path, out: Path, src: str, links: Links, tpl: Path, rev: str, stamp: str) -> None:
    ast = json.loads(subprocess.run(["pandoc", "-f", "gfm+tex_math_dollars", "-t", "json", str(root / src)],
                                    check=True, capture_output=True, text=True).stdout)
    walk(ast["blocks"], lambda url, image: links.rewrite(url, src, image))
    dest = out / page_path(src)
    dest.parent.mkdir(parents=True, exist_ok=True)
    base = str(PurePosixPath(src).parent)
    base = "" if base == "." else base
    title = next((s for s in (root / src).read_text(encoding="utf-8").splitlines() if s.startswith("# ")), "# " + src)[2:]
    subprocess.run(["pandoc", "-f", "json", "-t", "html5", "-s", "--mathml", "--template", str(tpl),
                    "-M", f"pagetitle={title}", "-V", f"lang={'pt-BR' if 'pt-BR' in src else 'en'}",
                    "-V", f"css={relative('style.css', base)}", "-V", f"home={relative('index.html', base)}",
                    "-V", f"source={REPO}/blob/{rev}/{src}", "-V", f"commit={REPO}/tree/{rev}",
                    "-V", f"stamp={stamp}", "-o", str(dest)],
                   input=json.dumps(ast), check=True, text=True)


def index_html(root: Path, found: list[Paper], rev: str, stamp: str, pdf: bool, video: bool) -> str:
    e = html.escape
    parts = [f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>proof</title>
<meta name="description" content="Specifications checked by a prover, implementations that follow them, and papers.">
<link rel="stylesheet" href="style.css">
</head>
<body>
<main>
<header class="site">
<img src="docs/logo/logo.svg" alt="A neural network flowing into the universal quantifier, drawn from Desmos equations">
<h1>proof</h1>
<p class="muted">∀ · specifications checked by a prover, implementations that follow them name for name,
and data experiments with papers. <a href="{REPO}">The repository</a>.</p>
</header>
"""]
    parts.append('<h2 id="preprints">Preprints</h2>\n<ul class="items">\n')
    for p in found:
        if p.folder == SCRIPT[0]:
            continue
        parts.append(paper_item(p, rev, pdf))
    parts.append("</ul>\n")
    sections: dict[str, list] = {}
    for section, src, blurb in PAGES:
        sections.setdefault(section, []).append((src, blurb))
    for section in ("Contextual bandits", "Z3 reports"):
        parts.append(f'<h2 id="{section.lower().replace(" ", "-")}">{e(section)}</h2>\n<ul class="items">\n')
        for src, blurb in sections[section]:
            parts.append(page_item(root, src, blurb))
        if section == "Contextual bandits":
            parts.append('<li><a class="title" href="docs/diagrams/index.html">Diagrams</a>'
                         '<div class="meta">The archify diagrams of the bandit, in English and Brazilian Portuguese.</div></li>\n')
        parts.append("</ul>\n")
    parts.append('<h2 id="video-script">Video script</h2>\n')
    if video:
        parts.append('<video controls preload="metadata" src="roteiro/preview.mp4">'
                     '<track kind="subtitles" srclang="pt-BR" label="Português (BR)" src="roteiro/preview.vtt" default>'
                     '</video>\n<p class="meta">The first 1:30 of the script, with its subtitles and no voice '
                     '(the roteiro-preview skill). <a href="roteiro/preview.srt">Subtitles</a> · '
                     '<a href="roteiro/shots.md">shot list</a>.</p>\n')
    parts.append('<ul class="items">\n')
    parts.append(paper_item(next(p for p in found if p.folder == SCRIPT[0]), rev, pdf))
    for src, blurb in sections["Video script"]:
        parts.append(page_item(root, src, blurb))
    parts.append("</ul>\n")
    parts.append(f'<footer>Built from <a href="{REPO}/tree/{e(rev)}">{e(stamp)}</a> by <code>just site</code>. '
                 'MPL-2.0.</footer>\n</main>\n</body>\n</html>\n')
    return "".join(parts)


def paper_item(p: Paper, rev: str, pdf: bool) -> str:
    e = html.escape
    eds = " · ".join(f'<a href="papers/{name}.pdf">PDF, {e(label)}</a>' if pdf else e(label)
                     for _, name, label in p.editions)
    meta = " · ".join(x for x in (e(p.version), e(p.date)) if x)
    sub = f'<div>{e(p.subtitle)}</div>' if p.subtitle else ""
    return (f'<li><span class="title">{e(p.title)}</span>{sub}<div class="meta">{meta}</div>'
            f'<div>{eds} · <a href="{REPO}/tree/{e(rev)}/{e(p.folder)}">source</a></div></li>\n')


def page_item(root: Path, src: str, blurb: str) -> str:
    e = html.escape
    title = next((s[2:] for s in (root / src).read_text(encoding="utf-8").splitlines() if s.startswith("# ")), src)
    return (f'<li><a class="title" href="{e(page_path(src))}">{e(title)}</a>'
            f'<div class="meta">{e(blurb)}</div></li>\n')


def srt_to_vtt(srt: Path, vtt: Path) -> None:
    text = srt.read_text(encoding="utf-8")
    text = re.sub(r"(\d\d:\d\d:\d\d),(\d\d\d)", r"\1.\2", text)
    vtt.write_text("WEBVTT\n\n" + text, encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", type=Path)
    ap.add_argument("--rev", default="main", help="the commit the links to GitHub point at")
    ap.add_argument("--stamp", default="", help="the revision printed on the pages and the PDFs (default: --rev, short)")
    ap.add_argument("--no-pdf", action="store_true")
    ap.add_argument("--no-video", action="store_true")
    ap.add_argument("--check", action="store_true", help="read every source and write the index, with no tool")
    a = ap.parse_args()
    root = Path.cwd()
    if not (root / "justfile").is_file():
        sys.exit("site: run from the repository root")
    stamp = a.stamp or a.rev[:7]
    pdf, video = not (a.no_pdf or a.check), not (a.no_video or a.check)

    for src in [s for _, s, _ in PAGES] + COPY:
        if not (root / src).exists():
            sys.exit(f"site: {src} is missing")
    found = papers(root)

    tmp = None
    if a.check:
        tmp = tempfile.TemporaryDirectory()
        out = Path(tmp.name) / "site"
    elif a.out:
        out = a.out
    else:
        sys.exit("site: --out DIR or --check")
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    work = Path(tempfile.mkdtemp())
    (work / "out").mkdir()

    for c in COPY:
        s, d = root / c, out / c
        d.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(s, d) if s.is_dir() else shutil.copyfile(s, d)
    (out / "style.css").write_text(STYLE.lstrip(), encoding="utf-8")

    site_files = {src: page_path(src) for _, src, _ in PAGES}
    site_files.update({c: c for c in COPY if (root / c).is_file()})
    for c in COPY:
        if (root / c).is_dir():
            site_files.update({f.relative_to(root).as_posix(): f.relative_to(root).as_posix()
                               for f in (root / c).rglob("*") if f.is_file()})
    if pdf:
        # A link to a paper's metadata.md is a link to the paper: its first edition's PDF.
        for p in found:
            site_files[f"{p.folder}/metadata.md"] = f"papers/{p.editions[0][1]}.pdf"
    links = Links(root, a.rev, site_files)

    if pdf:
        for p in found:
            for prose, name, _ in p.editions:
                print(f"site: papers/{name}.pdf", flush=True)
                build_pdf(root, p, prose, name, out, stamp)
    if not a.check:
        tpl = page_template(work / "out")
        for _, src, _ in PAGES:
            print(f"site: {page_path(src)}", flush=True)
            build_page(root, out, src, links, tpl, a.rev, stamp)
        for c in sorted(links.copies):
            (out / c).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(root / c, out / c)
    if video:
        print("site: roteiro/preview.mp4", flush=True)
        subprocess.run([sys.executable, ".claude/skills/roteiro-preview/preview.py", SCRIPT[0] + "/" + SCRIPT[1],
                        "--tts", "none", "--out", str(out / "roteiro")], check=True, stdout=subprocess.DEVNULL)
        srt_to_vtt(out / "roteiro" / "preview.srt", out / "roteiro" / "preview.vtt")

    (out / "index.html").write_text(index_html(root, found, a.rev, stamp, pdf, video), encoding="utf-8")
    shutil.rmtree(work)
    if a.check:
        print(f"site: OK ({len(found)} papers, {len(PAGES)} pages, {len(site_files)} files in the site)")
        tmp.cleanup()
    else:
        print(f"site: {out}/index.html")
    return 0


if __name__ == "__main__":
    sys.exit(main())
