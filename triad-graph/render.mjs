// Open graphify's graph.html in headless Chromium, wait for the layout to settle,
// then write a PDF and PNG screenshots. Usage: node triad-graph/render.mjs triad-graph/<triad>
// Reads <triad>/meta.json (title, focus node) and <triad>/out/graph.html; writes into <triad>/out/.
import { createRequire } from "node:module";
import path from "node:path";
import fs from "node:fs";
import { pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
if (!process.argv[2]) { console.error("usage: render.mjs <triad folder>"); process.exit(1); }
const here = path.resolve(process.argv[2]);
const outDir = path.join(here, "out");
const meta = JSON.parse(fs.readFileSync(path.join(here, "meta.json"), "utf-8"));
const html = pathToFileURL(path.join(here, "out", "graph.html")).href;

const browser = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {});
const page = await browser.newPage({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 2 });
// graph.html loads vis-network from unpkg. Where unpkg is blocked, point VIS_NETWORK at a local
// copy of vis-network@9.1.6/standalone/umd/vis-network.min.js (for example from `npm pack`).
if (process.env.VIS_NETWORK) {
  await page.route("https://unpkg.com/vis-network@9.1.6/**", (route) =>
    route.fulfill({ path: process.env.VIS_NETWORK, contentType: "application/javascript" }));
}
await page.goto(html, { waitUntil: "networkidle" });
await page.waitForFunction(() => typeof network !== "undefined");
// Show every label, not only the high-degree ones, and fit the settled layout.
await page.evaluate(() => new Promise((done) => {
  const all = nodesDS.get().map((n) => ({ id: n.id, font: Object.assign({}, n.font, { size: 14 }) }));
  nodesDS.update(all);
  network.once("stabilized", () => { network.fit(); done(); });
  network.stabilize(400);
  setTimeout(() => { network.fit(); done(); }, 8000);
}));
await page.waitForTimeout(800);
await page.screenshot({ path: path.join(outDir, "graph.png") });

// A second screenshot with the focus node selected, so the side panel lists its ties.
const pos = await page.evaluate((id) => network.canvasToDOM(network.getPositions([id])[id]), meta.focus);
await page.mouse.click(pos.x, pos.y);
await page.waitForTimeout(500);
await page.screenshot({ path: path.join(outDir, `graph-${meta.focus}.png`) });

// The PDF: the graph on page 1, then every edge with its source (deal sizes live in the edge text).
const graph = JSON.parse(fs.readFileSync(path.join(here, "out", "graph.json"), "utf-8"));
const label = Object.fromEntries(graph.nodes.map((n) => [n.id, n.label]));
const esc = (t) => String(t).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const rows = graph.links.map((l) => `<tr><td>${esc(label[l.source])}</td><td>${esc(label[l.target])}</td>
  <td>${esc(l.relation)}${l.confidence === "INFERRED" ? " <b>[reported]</b>" : ""}</td>
  <td>${l.source_file.split(" ").map((u) => `<a href="${esc(u)}">${esc(new URL(u).hostname.replace(/^www\./, ""))}</a>`).join(" ")}</td></tr>`).join("\n");
const png = fs.readFileSync(path.join(outDir, "graph.png")).toString("base64");
const report = `<!doctype html><meta charset="utf-8"><style>
  @page { size: A4 landscape; margin: 10mm; }
  body { font: 9pt -apple-system, "Segoe UI", sans-serif; color: #111; }
  h1 { font-size: 15pt; margin: 0 0 4px; } p { margin: 0 0 6px; color: #444; }
  .fig { page-break-after: always; } .fig img { width: 100%; }
  table { border-collapse: collapse; width: 100%; } td, th { border-bottom: 1px solid #ddd; padding: 2px 4px; text-align: left; vertical-align: top; }
  th { background: #eee; } a { color: #1a4e8a; text-decoration: none; }
</style>
<div class="fig"><h1>${esc(meta.title)}</h1>
<p>${graph.nodes.length} nodes, ${graph.links.length} edges. Drawn by graphify from triad-graph/${path.basename(here)}/nodes.csv and edges.csv. Dashed edges are press reports, not confirmed deals.</p>
<img src="data:image/png;base64,${png}"></div>
<h1>Edges and sources</h1><table><tr><th>From</th><th>To</th><th>Relation (year)</th><th>Source</th></tr>${rows}</table>`;
const doc = await browser.newPage();
await doc.setContent(report, { waitUntil: "load" });
await doc.pdf({ path: path.join(outDir, `${path.basename(here)}.pdf`), printBackground: true, preferCSSPageSize: true });
await browser.close();
console.log(`wrote graph.png, graph-${meta.focus}.png and ${path.basename(here)}.pdf in ${outDir}`);
