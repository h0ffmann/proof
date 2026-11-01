"""Turn one triad's nodes.csv and edges.csv into a graphify graph.json (node-link format).

Run: python3 triad-graph/build.py triad-graph/<triad>
  -> triad-graph/<triad>/out/graph.json and .graphify_labels.json
Then `graphify export html --graph triad-graph/<triad>/out/graph.json` draws graph.html.
The colour groups come from <triad>/meta.json. Only the standard library is used.
"""
import csv
import json
import sys
from pathlib import Path

if len(sys.argv) != 2:
    sys.exit("usage: build.py <triad folder>")
HERE = Path(sys.argv[1]).resolve()
OUT = HERE / "out"
# graphify colours nodes by community; one community per group, in meta.json order.
GROUPS = json.loads((HERE / "meta.json").read_text(encoding="utf-8"))["groups"]
# graphify confidence tags: EXTRACTED = stated by the source, INFERRED = press reports only.
CONFIDENCE = {"confirmed": "EXTRACTED", "reported": "INFERRED"}


def read(name):
    with open(HERE / name, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    bad = [r for r in rows if None in r]
    if bad:
        sys.exit(f"build.py: {name}: extra columns (unquoted comma?) in {bad[0]}")
    return rows


def main():
    nodes, edges = read("nodes.csv"), read("edges.csv")
    community = {g: i for i, g in enumerate(GROUPS)}
    ids = set()
    errors = []
    out_nodes = []
    for n in nodes:
        if n["id"] in ids:
            errors.append(f"duplicate node {n['id']}")
        if n["group"] not in community:
            errors.append(f"unknown group {n['group']} on {n['id']}")
            continue
        ids.add(n["id"])
        out_nodes.append({
            "id": n["id"],
            "label": n["label"],
            "file_type": "concept",
            "source_file": n["url"],
            "kind": n["kind"],
            "community": community[n["group"]],
        })
    links = []
    for e in edges:
        for end in ("source", "target"):
            if e[end] not in ids:
                errors.append(f"edge {e['source']} -> {e['target']}: unknown node {e[end]}")
        if not e["url"].startswith("https://"):
            errors.append(f"edge {e['source']} -> {e['target']}: no https source")
        if e["status"] not in CONFIDENCE:
            errors.append(f"edge {e['source']} -> {e['target']}: bad status {e['status']}")
            continue
        relation = f"{e['relation']} ({e['year']})" if e["year"] else e["relation"]
        links.append({
            "source": e["source"],
            "target": e["target"],
            "relation": relation,
            "confidence": CONFIDENCE[e["status"]],
            "source_file": e["url"],
        })
    # graphify keeps one edge per node pair, so parallel edges are merged into one.
    merged = {}
    for l in links:
        key = frozenset((l["source"], l["target"]))
        if key in merged:
            m = merged[key]
            m["relation"] += "; " + l["relation"]
            m["source_file"] += " " + l["source_file"]
            if l["confidence"] == "INFERRED":
                m["confidence"] = "INFERRED"
        else:
            merged[key] = dict(l)
    links = list(merged.values())
    linked = {l[k] for l in links for k in ("source", "target")}
    errors += [f"node {i} has no edge" for i in sorted(ids - linked)]
    if errors:
        sys.exit("build.py: " + "\n".join(errors))
    OUT.mkdir(exist_ok=True)
    graph = {"directed": False, "multigraph": False, "graph": {}, "nodes": out_nodes, "links": links}
    (OUT / "graph.json").write_text(json.dumps(graph, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    labels = {str(i): label for i, label in enumerate(GROUPS.values())}
    (OUT / ".graphify_labels.json").write_text(json.dumps(labels, indent=1) + "\n", encoding="utf-8")
    print(f"graph.json: {len(out_nodes)} nodes, {len(links)} edges")


if __name__ == "__main__":
    main()
