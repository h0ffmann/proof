# Paper Fabric in dogma: how to write a paper

Paper Fabric is the paper pipeline of [h0ffmann/closed-source](https://github.com/h0ffmann/closed-source)
(`docs/4-ways-of-working/paper-fabric.md` there). dogma has its generic parts, so a paper here is
one directory and one command.

## 1. Start a paper

1. Copy `papers/contextual-bandits/` to `papers/<slug>/`.
2. Edit `metadata.md`: title, authors (name, ORCID, affiliation), date, version, abstract, keywords.
   A paper that is shared before peer review is a preprint, and its version says so:
   `version: "Preprint v0 (draft, not peer reviewed)"`. The version prints under the title and in
   the footer of every page.
3. Write one file for each section: `prose/01-introduction.md`, `prose/02-....md`. Keep
   `prose/99-references.md` last: it places the reference list.
4. Put each source in `refs.bib`, and log it in `REFERENCES.md` after you fetched it.
5. In `nix develop`, run `just paper <slug>`. The PDF is `pdf/<slug>.pdf`.

Optional: `prose-ste/` (the ASD-STE100 text) builds `pdf/<slug>-ste.pdf`, and `prose-pt-BR/` (the
Brazilian Portuguese edition) builds `pdf/<slug>-pt-BR.pdf`. A `00-metadata.md` in either directory
overrides keys of `metadata.md`, such as `abstract`, `lang: pt-BR` and `babel: brazilian`.

## 2. Writing

| You write | Pandoc makes |
|---|---|
| `[@li2010contextual]` | a citation from `refs.bib` (citeproc) |
| `# What is proved {#sec:proved}` and `[@sec:proved]` | a numbered section and a link to it (pandoc-crossref) |
| a table followed by `: Caption. {#tbl:x}`, then `[@tbl:x]` | a numbered table and a link to it |
| `![Caption](path.png){#fig:x}`, then `[@fig:x]` | a numbered figure and a link to it |
| `$\varepsilon$` | math |

Start a sentence with `[@Sec:x]` (capital S) to get "Section 2". The build treats every pandoc
warning as an error, so an unknown citation or label fails it.

## 3. Checks

| Command | Fails when |
|---|---|
| `just paper` | pandoc warns (unknown citation or label) or XeLaTeX fails |
| `just paper-check` | the above, or a `refs.bib` key has no `verified`/`partial` row in `REFERENCES.md`, or an entry has no `doi`/`url`, or a `prose-ste/` or `prose-pt-BR/` text loses a citation, quotation or number |
| `just fabric-test` | a test of `tools/` fails |
| `just md-quality` | markdownlint finds a structure fault, Vale finds a prose error, or lychee finds a dead link to a file |

CI is disabled while the repository is private (AGENTS.md). `.github/workflows/pdf.yml` runs
`just fabric-test` and `just paper-check` only when started by hand from the Actions tab, and keeps
the PDFs as an artifact. PDFs are not committed.

## 4. Rules that make the output credible

From Paper Fabric:

- **Fetch before you cite.** Fetch every source before you cite it, and log how in `REFERENCES.md`.
  A source you could not fetch is `unverified` and must not be cited.
- **Allegations stay allegations.** Report a legal case with its court, date, status and source.
- **Personal accounts belong to their authors.** An agent leaves `**[AUTHOR ANECDOTE: ...]**`.
- **Disclose AI use** in each paper's statements.

## 5. Toolchain

Markdown, pandoc with pandoc-crossref and citeproc, the hand-written LaTeX template
`format/tex/template.tex`, XeLaTeX twice, and the Git revision stamped on every page. The template
also compiles with pdfLaTeX. Every tool is pinned by `flake.lock` through the `paper` lab of
[h0ffmann/picasso](https://github.com/h0ffmann/picasso). The template needs pandoc 3.1.8 or later
for its reference list; the pinned lab has it, so use `nix develop`, not a distribution's pandoc.

The Markdown analysers (`.vale/`, `.vale.ini`, `.markdownlint-cli2.jsonc`, `scripts/md-quality.sh`)
come from the same repository. The Vale style `fabric` encodes four rules: short sentences, active
voice, no undefined jargon, numbers over adjectives.
