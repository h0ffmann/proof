#!/usr/bin/env bash
# The archify diagrams are dark, whatever the reader's setting (AGENTS.md, "Notes"): every PNG in
# docs/diagrams/img/ is a dark capture, and every link of docs/diagrams/index.html to a diagram page
# carries ?theme=dark. Python's standard library only; no browser.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -I - <<'EOF'
import re, struct, sys, zlib
from pathlib import Path

def luminance(path):
    """Mean luma (0 to 1) of an 8-bit RGB or RGBA PNG, one row in eight."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat, head = 8, b"", None
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            head = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + n
    w, h, depth, colour, _, _, interlace = head
    if depth != 8 or colour not in (2, 6) or interlace:
        raise ValueError(f"unsupported PNG (depth {depth}, colour {colour}, interlace {interlace})")
    bpp = 3 if colour == 2 else 4
    raw, stride = zlib.decompress(idat), w * bpp
    prev, total, count = bytearray(stride), 0, 0
    for y in range(h):
        f, row = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = row[i - bpp] if i >= bpp else 0
            b, c = prev[i], prev[i - bpp] if i >= bpp else 0
            if f == 1: row[i] = (row[i] + a) & 255
            elif f == 2: row[i] = (row[i] + b) & 255
            elif f == 3: row[i] = (row[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                row[i] = (row[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        if y % 8 == 0:
            for x in range(0, stride, bpp * 4):
                total += 0.2126 * row[x] + 0.7152 * row[x + 1] + 0.0722 * row[x + 2]
                count += 1
        prev = row
    return total / count / 255

bad = []
pngs = sorted(Path("docs/diagrams/img").rglob("*.png"))
for png in pngs:
    l = luminance(png)
    if l > 0.25:
        bad.append(f"{png}: mean luma {l:.2f}, a light capture (just images takes the dark one)")
index = Path("docs/diagrams/index.html").read_text(encoding="utf-8")
for href in re.findall(r'href="((?:en|pt-BR)/[^"]+)"', index):
    if not href.endswith(".html?theme=dark"):
        bad.append(f"docs/diagrams/index.html: {href} does not open dark (add ?theme=dark)")
if not pngs:
    bad.append("docs/diagrams/img: no PNG")
for b in bad:
    print(b, file=sys.stderr)
if bad:
    sys.exit(1)
print(f"diagrams: OK ({len(pngs)} dark PNGs)")
EOF
