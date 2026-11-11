# Publishing a paper to aiXiv from GitHub

The workflow `.github/workflows/aixiv.yml` builds one paper of `papers/` with the pinned toolchain
and sends it to [aiXiv](https://aixiv.online) through aiXiv's REST API. It runs only by hand, from
the Actions tab. The code is `scripts/aixiv.sh`.

aiXiv has no GitHub App or Action of its own. Its documented routes for an agent or a script are
the `aixiv` command line, a bearer token on the REST API, and an MCP endpoint
([skill.md](https://aixiv.online/skill.md), [llms.txt](https://aixiv.online/llms.txt), read
2026-11-11). The workflow uses the REST API with a token, because a runner has no browser for
`aixiv login`.

## Set up once

1. Make a token at <https://aixiv.online/settings>.
2. In this repository on GitHub: Settings, Environments, New environment, name it `aixiv`.
3. In that environment, add the secret `AIXIV_TOKEN` with the token as its value.
4. Optional: in the same environment, add yourself as a required reviewer. Then every run waits
   for your approval before it can read the token.

## Describe the paper

`papers/<slug>/aixiv.json` holds the fields of the submission. The names are the API's, and the
`aixiv` command line 0.4.1 reads the same names from an `aixiv.json`, so `npx aixiv publish` works
on the same file. A long field can be `file:NAME.md`, relative to the paper's folder.

| Field | Need | Meaning |
|---|---|---|
| `primary_category` | required | a category open on aiXiv, such as `math.ST` ([the list](https://aixiv.online/api/v1/categories)) |
| `ai_contribution` | required | one of `ai-proofread`, `ai-consulted`, `ai-assisted`, `ai-derived`, `ai-discovered`, `ai-authored` |
| `ai_models` | required | a short list of names, such as `Claude Code, Agda 2.8.0` |
| `id` | after the first publication | the aiXiv id; with it, a publication is a new version |
| `categories`, `license`, `msc_class`, `comments` | optional | the record's other fields |
| `process_summary`, `verification_notes`, `negative_results`, `prompts_harness` | optional | the AI process notes |

Title, authors and abstract come from `metadata.md`, so the record matches the PDF. The repository
URL is the repository the workflow runs in, unless `repo_url` is set. `scripts/aixiv.sh check`
(`just aixiv-check`, and `checks/aixiv.sh` in `just check`) refuses a manifest with an unknown
field, a wrong AI-use level or a missing file.

`papers/bandit-decision-layer/aixiv.json` is aiXiv:2611.01105. Its notes in `aixiv/` are the text
of that record (`GET /api/v1/papers/2611.01105`, read 2026-11-11).

## Run it

Actions, aixiv, Run workflow:

- **paper**: the folder under `papers/`.
- **publish** off: a dry run. aiXiv checks every field and stores nothing. This is the default.
- **publish** on: also type the folder again in **confirm**, and run from `main`. A paper with an
  `id` gets a new version and needs a **changelog**. A paper with no `id` becomes a new paper; add
  the id that the run prints to its `aixiv.json` in a pull request.

The run uploads the PDF, the LaTeX, the metadata and aiXiv's answers as an artifact, and writes
the log to the run's summary. A publication cannot be undone: aiXiv keeps every version with its
time and SHA-256 hash.

The workflow sends both the LaTeX and the PDF, because the papers build with XeLaTeX and aiXiv
compiles with pdfLaTeX. With both, aiXiv publishes the PDF and hashes the source (skill.md,
"Field notes").

From a terminal, with `AIXIV_TOKEN` set:

```bash
just aixiv-dry-run bandit-decision-layer
scripts/aixiv.sh submit bandit-decision-layer --publish --changelog "what changed"
```

## What it does not do

- It attaches no agent sessions. aiXiv asks for the raw session files of the work, and a runner has
  none. Attach them later from the machine where the work was done:
  `npx aixiv@latest attach` ([attach.md](https://aixiv.online/attach.md)).
- It does not publish to arXiv. arXiv takes automated submissions only through its SWORD deposit
  API, which arXiv meant for conference and journal editors. It needs a registered author and an
  authorization asked from arXiv's administrators by email
  ([SWORD/APP Deposit API User's Manual](https://info.arxiv.org/help/submit_sword.html), read
  2026-11-11).
