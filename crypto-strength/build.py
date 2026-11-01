#!/usr/bin/env python3
"""Check the crypto strength data, rank the assets and draw the heatmap.

Reads data/assets.csv, data/scores.csv and data/sources.csv.
Writes heatmap.svg and results.md next to this file. Python 3 standard library only.
"""

from __future__ import annotations

import csv
import sys
from html import escape
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA = HERE / "data"
YEAR = 2026

# Factor id, column label. Order is the column order of the heatmap.
FACTORS = [
    ("decentralization", "Decentral."),
    ("security", "Security"),
    ("scalability", "Scalability"),
    ("affordability", "Afford."),
    ("adoption", "Adoption"),
    ("maturity", "Maturity"),
    ("fees_solved", "Fees solved"),
    ("privacy", "Privacy"),
    ("crypto_force", "Crypto force"),
]

# Long-term (5-10 year) weights. They favour what is hard to change later:
# who controls the chain, whether it has held up, and whether it can survive new attacks.
LONG_TERM_WEIGHTS = {
    "decentralization": 2.0,
    "security": 2.0,
    "crypto_force": 2.0,
    "maturity": 2.0,
    "adoption": 1.5,
    "scalability": 1.0,
    "fees_solved": 1.0,
    "affordability": 0.5,
    "privacy": 0.5,
}
MIN_AGE_YEARS = 5  # "mature": mainnet at least five years old
TOP_N = 10

# Sequential one-hue ramp (light -> dark blue) for scores 1..5, with the ink that reads on each.
RAMP = {1: "#cde2fb", 2: "#86b6ef", 3: "#3987e5", 4: "#1c5cab", 5: "#0d366b"}
INK = {1: "#0b1f3a", 2: "#0b1f3a", 3: "#ffffff", 4: "#ffffff", 5: "#ffffff"}


def read_csv(name: str) -> list[dict[str, str]]:
    with open(DATA / name, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def load() -> tuple[list[dict], dict[str, dict[str, dict]], set[str]]:
    errors: list[str] = []
    sources = {row["id"] for row in read_csv("sources.csv")}
    assets = read_csv("assets.csv")
    symbols = [a["symbol"] for a in assets]
    if len(set(symbols)) != len(symbols):
        errors.append("duplicate symbol in assets.csv")

    scores: dict[str, dict[str, dict]] = {s: {} for s in symbols}
    factor_ids = {f for f, _ in FACTORS}
    for i, row in enumerate(read_csv("scores.csv"), start=2):
        sym, fac = row["symbol"], row["factor"]
        where = f"scores.csv line {i} ({sym}, {fac})"
        if sym not in scores:
            errors.append(f"{where}: unknown symbol")
            continue
        if fac not in factor_ids:
            errors.append(f"{where}: unknown factor")
            continue
        if fac in scores[sym]:
            errors.append(f"{where}: duplicate")
        try:
            score = int(row["score"])
        except ValueError:
            score = 0
        if not 1 <= score <= 5:
            errors.append(f"{where}: score must be 1..5")
        if not row["evidence"].strip():
            errors.append(f"{where}: no evidence")
        ids = [s for s in row["sources"].split(";") if s]
        if not ids:
            errors.append(f"{where}: no source id (use J for judgment)")
        for sid in ids:
            if sid not in sources:
                errors.append(f"{where}: unknown source {sid}")
        scores[sym][fac] = {"score": score, "evidence": row["evidence"], "sources": ids}

    for a in assets:
        missing = factor_ids - scores[a["symbol"]].keys()
        if missing:
            errors.append(f"{a['symbol']}: missing factors {sorted(missing)}")
        if not a["github"].startswith("https://github.com/"):
            errors.append(f"{a['symbol']}: github link must start with https://github.com/")
        for sid in a["sources"].split(";"):
            if sid and sid not in sources:
                errors.append(f"assets.csv {a['symbol']}: unknown source {sid}")

    if errors:
        print("data errors:", *errors, sep="\n  ", file=sys.stderr)
        sys.exit(1)
    return assets, scores, sources


def rank(assets: list[dict], scores: dict) -> list[dict]:
    total_w = sum(LONG_TERM_WEIGHTS.values())
    rows = []
    for a in assets:
        s = {f: scores[a["symbol"]][f]["score"] for f, _ in FACTORS}
        mean = sum(s.values()) / len(s)
        long_term = sum(LONG_TERM_WEIGHTS[f] * v for f, v in s.items()) / total_w
        judged = sum(1 for f, _ in FACTORS if scores[a["symbol"]][f]["sources"] == ["J"])
        rows.append({
            **a,
            "scores": s,
            "mean": mean,
            "long_term": long_term,
            "age": YEAR - int(a["mainnet_year"]),
            "judged": judged,
        })
    # Ties: higher plain mean first, then symbol, so the order is stable.
    rows.sort(key=lambda r: (-round(r["long_term"], 6), -round(r["mean"], 6), r["symbol"]))
    return rows


def svg_heatmap(rows: list[dict], scores: dict) -> str:
    cell, gap = 46, 2
    left, top = 168, 132
    extra = [("long_term", "Long-term")]
    ncols = len(FACTORS) + len(extra)
    consensus_w = 128
    width = left + consensus_w + ncols * (cell + gap) + 24
    height = top + len(rows) * (cell + gap) + 96
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" font-family="Inter, Helvetica, Arial, sans-serif" '
        'role="img" aria-labelledby="t d">',
        '<title id="t">Crypto strength map, November 2026</title>',
        '<desc id="d">Scores from 1 (weak) to 5 (strong) for 17 networks on nine factors, '
        'sorted by the long-term score. Data in crypto-strength/data/scores.csv.</desc>',
        f'<rect width="{width}" height="{height}" fill="#ffffff"/>',
        '<text x="16" y="28" font-size="18" font-weight="600" fill="#0b1f3a">'
        'Crypto strength map (1 = weak, 5 = strong)</text>',
        '<text x="16" y="48" font-size="12" fill="#55606e">'
        'Sorted by long-term score. Scored 2026-11-01. Educational only, not investment advice.</text>',
    ]
    # Column headers, rotated.
    hx = left
    out.append(f'<text x="{hx + 4}" y="{top - 10}" font-size="12" font-weight="600" fill="#33404f">Consensus</text>')
    for j, (_, label) in enumerate(FACTORS + extra):
        x = left + consensus_w + j * (cell + gap) + cell / 2
        out.append(
            f'<text x="{x - 4}" y="{top - 8}" font-size="12" font-weight="600" fill="#33404f" '
            f'transform="rotate(-50 {x - 4} {top - 8})">{escape(label)}</text>'
        )
    for i, r in enumerate(rows):
        y = top + i * (cell + gap)
        mark = "" if r["age"] >= MIN_AGE_YEARS else " *"
        out.append(
            f'<text x="16" y="{y + cell / 2 + 4}" font-size="13" fill="#0b1f3a">'
            f'<tspan font-weight="600">{escape(r["symbol"])}</tspan> '
            f'<tspan fill="#55606e">{escape(r["name"])}{mark}</tspan></text>'
        )
        out.append(
            f'<rect x="{left}" y="{y}" width="{consensus_w - 6}" height="{cell}" rx="4" fill="#f0efec"/>'
            f'<text x="{left + 8}" y="{y + cell / 2 + 4}" font-size="11" fill="#33404f">'
            f'{escape(r["consensus"])}</text>'
        )
        for j, (fac, label) in enumerate(FACTORS):
            x = left + consensus_w + j * (cell + gap)
            item = scores[r["symbol"]][fac]
            v = item["score"]
            tip = f'{r["symbol"]} {label}: {v}/5. {item["evidence"]} [{", ".join(item["sources"])}]'
            dash = ' stroke="#0b1f3a" stroke-width="1.5" stroke-dasharray="3 3"' if item["sources"] == ["J"] else ""
            out.append(
                f'<g><title>{escape(tip)}</title>'
                f'<rect x="{x}" y="{y}" width="{cell}" height="{cell}" rx="4" fill="{RAMP[v]}"{dash}/>'
                f'<text x="{x + cell / 2}" y="{y + cell / 2 + 5}" font-size="14" text-anchor="middle" '
                f'fill="{INK[v]}">{v}</text></g>'
            )
        x = left + consensus_w + len(FACTORS) * (cell + gap)
        lt = r["long_term"]
        band = max(1, min(5, round(lt)))
        out.append(
            f'<g><title>{escape(r["symbol"])} long-term score {lt:.2f} (weighted mean)</title>'
            f'<rect x="{x}" y="{y}" width="{cell}" height="{cell}" rx="4" fill="{RAMP[band]}" '
            f'stroke="#0b1f3a" stroke-width="2"/>'
            f'<text x="{x + cell / 2}" y="{y + cell / 2 + 5}" font-size="13" font-weight="600" '
            f'text-anchor="middle" fill="{INK[band]}">{lt:.2f}</text></g>'
        )
    # Legend.
    ly = top + len(rows) * (cell + gap) + 22
    out.append(f'<text x="16" y="{ly + 14}" font-size="12" fill="#33404f">Score</text>')
    for k in range(1, 6):
        lx = 64 + (k - 1) * 40
        out.append(
            f'<rect x="{lx}" y="{ly}" width="36" height="20" rx="4" fill="{RAMP[k]}"/>'
            f'<text x="{lx + 18}" y="{ly + 14}" font-size="12" text-anchor="middle" fill="{INK[k]}">{k}</text>'
        )
    out.append(
        f'<rect x="284" y="{ly}" width="20" height="20" rx="4" fill="#ffffff" stroke="#0b1f3a" '
        f'stroke-width="1.5" stroke-dasharray="3 3"/>'
        f'<text x="310" y="{ly + 14}" font-size="12" fill="#33404f">dashed = author judgment, no opened source</text>'
    )
    out.append(
        f'<text x="16" y="{ly + 44}" font-size="12" fill="#55606e">'
        f'* mainnet younger than {MIN_AGE_YEARS} years: excluded from the long-term top {TOP_N}. '
        'Hover a cell for its evidence.</text>'
    )
    out.append("</svg>")
    return "\n".join(out) + "\n"


def results_md(rows: list[dict]) -> str:
    head = "| # | Asset | " + " | ".join(label for _, label in FACTORS) + " | Mean | Long-term | J cells |"
    sep = "|" + "---|" * (len(FACTORS) + 5)
    lines = [
        "# Results",
        "",
        "Generated by `build.py` from `data/`. Do not edit by hand.",
        "",
        "## All assets, by long-term score",
        "",
        head,
        sep,
    ]
    for i, r in enumerate(rows, start=1):
        cells = " | ".join(str(r["scores"][f]) for f, _ in FACTORS)
        young = "" if r["age"] >= MIN_AGE_YEARS else " \\*"
        lines.append(
            f"| {i} | {r['symbol']} ({r['name']}){young} | {cells} | {r['mean']:.2f} | "
            f"**{r['long_term']:.2f}** | {r['judged']} |"
        )
    lines += [
        "",
        f"\\* Mainnet younger than {MIN_AGE_YEARS} years, so not eligible for the long-term top {TOP_N}.",
        "\"J cells\" counts the factors scored by judgment only, with no opened source.",
        "",
        f"## Long-term top {TOP_N} (mainnet at least {MIN_AGE_YEARS} years old)",
        "",
        "| # | Project | Long-term | Consensus | Mainnet | Code |",
        "|---|---|---|---|---|---|",
    ]
    eligible = [r for r in rows if r["age"] >= MIN_AGE_YEARS][:TOP_N]
    for i, r in enumerate(eligible, start=1):
        repo = r["github"].removeprefix("https://github.com/")
        lines.append(
            f"| {i} | {r['name']} ({r['symbol']}) | {r['long_term']:.2f} | {r['consensus']} | "
            f"{r['mainnet_year']} | [{repo}]({r['github']}) |"
        )
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    assets, scores, _ = load()
    rows = rank(assets, scores)
    (HERE / "heatmap.svg").write_text(svg_heatmap(rows, scores), encoding="utf-8")
    (HERE / "results.md").write_text(results_md(rows), encoding="utf-8")
    eligible = [r for r in rows if r["age"] >= MIN_AGE_YEARS][:TOP_N]
    print(f"{len(rows)} assets x {len(FACTORS)} factors OK")
    print("long-term top", TOP_N, ":", ", ".join(f"{r['symbol']} {r['long_term']:.2f}" for r in eligible))


if __name__ == "__main__":
    main()
