# tools: Paper Fabric's paper checks

One Gleam project (Erlang target), run as `tools/fabric <command>` from the repository root inside
`nix develop`. `just fabric-test` runs its tests.

| Command | What it checks |
|---|---|
| `refs-check papers/*/refs.bib` | every `refs.bib` key has a `verified` or `partial` row in the `REFERENCES.md` beside it, no row lacks a key, every entry has a `doi` or `url` |
| `ste-check <slug>` | `papers/<slug>/prose-ste/` (the ASD-STE100 text) keeps the citations, anchors, quotations, numbers and markers of `prose/`; reports sentences over 25 words |
| `ste-check --translation <slug>` | the same for `papers/<slug>/prose-pt-BR/`, with Portuguese number separators and markers |

## Provenance

Copied from [h0ffmann/closed-source](https://github.com/h0ffmann/closed-source) at commit
`6b3aae557f69ab89ec747364311978928dd0ca71` (2026-10-25), `tools/`:
`src/fabric/{sys,re,pystr,refs_check,ste_check}.gleam`, `src/fabric_ffi.erl`, `fabric`, and the
tests `refs_check_test`, `ste_check_test`, `pystr_test`. These files are unchanged.
`src/fabric.gleam`, `test/fabric_test.gleam`, `gleam.toml` and `manifest.toml` are trimmed to these
two commands; the other commands there (site content, citation, Zenodo, timeline, arXiv) are specific
to that repository.

In closed-source, `tools/` is under AGPL-3.0-only and `format/` under MIT (its `REUSE.toml`).
