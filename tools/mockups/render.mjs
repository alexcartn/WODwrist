// Render the watch mockups (screens drawn with the same layout fractions as
// the Monkey C views) to docs/mockups/. Needs Playwright + Chromium:
//   node tools/mockups/render.mjs
import { chromium } from "playwright";
import path from "node:path";

const here = path.dirname(new URL(import.meta.url).pathname);
const out = path.join(here, "../../docs/mockups");
const sheets = {
  "wodwrist-ecrans.png": (i) => i < 13,
  "wodwrist-stats.png": (i) => i >= 13 && i < 18,
  "wodwrist-coach.png": (i) => i >= 18 && i < 24,
  "wodwrist-perf.png": (i) => i === 9 || i >= 24,
};
const b = await chromium.launch();
for (const [file, keep] of Object.entries(sheets)) {
  const p = await b.newPage({ viewport: { width: 1900, height: 900 } });
  await p.goto("file://" + path.join(here, "index.html"));
  await p.evaluate((src) => {
    const keep = eval(src);
    document.querySelectorAll(".item").forEach((it, i) => { if (!keep(i)) it.remove(); });
  }, keep.toString());
  await p.screenshot({ path: path.join(out, file), fullPage: true });
  await p.close();
}
await b.close();
console.log("wrote", Object.keys(sheets).join(", "));
