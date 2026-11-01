# Triad graphs

Sourced graphs of three tech figures at a time: the companies they founded or
fund, the large deals around those companies, and their ties to other tech
figures. [graphify](https://graphify.com) draws each one.

| Triad | Nodes | Edges | Focus capture |
| --- | --- | --- | --- |
| [Musk, Thiel and Karp](musk-thiel-karp/README.md) | 50 | 75 | Palantir |
| [Musk, Altman and Amodei](musk-altman-amodei/README.md) | 39 | 56 | OpenAI |

## Files

Each triad is one folder with the same files:

| File | What it holds |
| --- | --- |
| `<triad>/meta.json` | The PDF title, the node selected in the second capture (`focus`), and the colour groups in order |
| `<triad>/nodes.csv` | One row per person, company, fund or agency: `id`, `label`, `group` (the colour), `kind`, `url` |
| `<triad>/edges.csv` | One row per tie: `source`, `target`, `relation`, `year`, `status`, `url` (the source; two URLs are separated by a space) |
| `<triad>/screenshots/` | The committed captures |
| `<triad>/out/` | `graph.json`, `graph.html`, `<triad>.pdf` and PNG captures. Not committed |

The two scripts serve every triad:

| Script | What it does |
| --- | --- |
| `build.py <triad>` | Checks the CSVs (unknown nodes, missing sources, unquoted commas, nodes with no edge) and writes `out/graph.json` in graphify's format. Standard library only |
| `render.mjs <triad>` | Opens `out/graph.html` in headless Chromium and writes `out/<triad>.pdf` and the PNG captures |

Edit the CSVs, not `out/graph.json`.

## Sources

Every edge has a source URL. `status` is `confirmed` when the source states the
fact, and `reported` when only press reports support it (for example the
Golden Dome bid). graphify marks `reported` edges as `INFERRED`, and draws them
dashed. The figures and dates were checked against the linked pages on
2026-11-01. Wikipedia changes, so a later reader should check the page history.

graphify keeps one edge for each pair of nodes, so `build.py` joins two ties
between the same pair (for example NASA's two SpaceX contracts) into one edge.

## Build

```bash
pip install graphifyy==0.9.100                  # the graphify CLI
just graph                                       # every triad: out/graph.html, out/<triad>.pdf, PNGs
just graph musk-altman-amodei                    # one triad
just render-graph                                # serve musk-thiel-karp at http://localhost:8000/graph.html
just render-graph musk-altman-amodei 8001        # another triad and port
```

`render.mjs` needs Node and Playwright with Chromium. `graph.html` loads
vis-network 9.1.6 from unpkg.com. Where that host is blocked, give a local copy:

```bash
npm pack vis-network@9.1.6 && tar xzf vis-network-9.1.6.tgz
VIS_NETWORK=$PWD/package/standalone/umd/vis-network.min.js just graph
```

The PDF has the graph on page 1, and on the next pages each edge with its
relation, year and source.

## Adding a triad

Copy a triad folder, rename it, and edit `meta.json` and the two CSVs. Then add
a row to the table above. `just graph` picks up every folder that has a
`meta.json`.
