// Renders scripts/material/gallery.html (Material Web components) headlessly and writes
// docs/ui/looks/ref/material/{light,dark}/<cell>@{1x,2x}.png (manifest.csv: scripts/material/manifest.py).
//   MATWEB=D:/Temp/matweb PLAYWRIGHT_BROWSERS_PATH=D:/tools/ms-playwright node scripts/material/capture.mjs [substring ...]
// MATWEB is a scratch folder where `npm i playwright-core @material/web esbuild` was run. Each PNG is the cell's box plus
// MARGIN px on every side on the scheme's surface colour (shadows and state layers fit inside the margin).
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const web = process.env.MATWEB || "D:/Temp/matweb";
const require = createRequire(path.join(web, "x.js"));
const { chromium } = require("playwright-core");
const esbuild = require("esbuild");
const MARGIN = 16; // per cell: gallery.html may ask for more (the elevation cells)

// bundle Material Web once, next to the gallery (not committed)
const bundle = path.join(here, "bundle.js");
if (!process.env.SHARD || process.env.SHARD.startsWith("0/")) await esbuild.build({ stdin: { contents: 'import "@material/web/all.js";', resolveDir: web }, bundle: true, minify: true, outfile: bundle, format: "iife" });

const only = process.argv.slice(2);
const out = path.join(root, "docs/ui/looks/ref/material");
const CONTROL = [
  ["icon-button", "button_icon"], ["button", "button"], ["fab", "fab"], ["checkbox", "checkbox"], ["radio", "radio"], ["switch", "switch"],
  ["text-field", "text_field"], ["select", "combo_box"], ["chip", "chips"], ["slider", "slider"], ["progress", "progress_bar"], ["tabs", "tabs"],
  ["menu", "menu"], ["list-item", "list"], ["dialog", "dialog"], ["snackbar", "snackbar"], ["tooltip", "hint"], ["navigation-bar", "navigation_bar"],
  ["app-bar", "app_bar"], ["search-bar", "search_bar"], ["badge", "badge"], ["date-picker", "date_picker"],
];
const STATES = ["rest", "hover", "pressed", "focus", "disabled", "error"];
const rows = [];
const browser = await chromium.launch({ args: ["--disable-lcd-text", "--font-render-hinting=none"], executablePath: process.env.CHROMIUM || "D:/tools/ms-playwright/chromium_headless_shell-1228/chrome-headless-shell-win64/chrome-headless-shell.exe" });
const pages = {};
for (const scale of [1, 2]) {
  const ctx = await browser.newContext({ deviceScaleFactor: scale, viewport: { width: 900, height: 900 } });
  const page = await ctx.newPage();
  await page.goto("file:///" + path.join(here, "gallery.html").replace(/\\/g, "/"));
  pages[scale] = page;
}
let names = await pages[1].evaluate(() => window.cellNames());
// SHARD=i/n runs every n-th cell (several processes in parallel; shard 0 builds bundle.js first, so start it alone for a moment);
// scripts/material/manifest.py writes manifest.csv from the PNGs afterwards
const [shard, shards] = (process.env.SHARD || "0/1").split("/").map(Number);
const allNames = names;
names = names.filter((_, i) => i % shards === shard);
for (const scheme of ["light", "dark"]) {
  fs.mkdirSync(path.join(out, scheme), { recursive: true });
  for (const name of names) {
    if (only.length && !only.some((o) => name.includes(o))) continue;
    const suffix = name.split("-").pop();
    const state = STATES.includes(suffix) ? suffix : "rest";
    let w = 0, h = 0;
    for (const scale of [1, 2]) {
      const page = pages[scale];
      await page.mouse.up();
      await page.mouse.move(0, 0);
      const r = await page.evaluate(([n, s]) => window.mount(n, s), [name, scheme]);
      const cx = r.x + r.w / 2, cy = r.y + r.h / 2;
      if (state === "hover") { await page.mouse.move(cx, cy); await page.waitForTimeout(150); }
      if (state === "pressed") { await page.mouse.move(cx, cy); await page.mouse.down(); await page.evaluate(() => window.pressedOnly()); await page.waitForTimeout(520); if (name.startsWith("list-item")) { await page.evaluate(() => document.getAnimations().forEach((a) => { try { a.finish(); } catch (e) {} })); await page.waitForTimeout(100); } }
      if (state === "focus") { await page.keyboard.press("Tab"); await page.evaluate(() => window.focusLayer()); await page.waitForTimeout(120); }
      w = Math.round(r.w); h = Math.round(r.h);
      const MARGIN = r.margin;
      const x0 = Math.floor(r.x) - MARGIN, y0 = Math.floor(r.y) - MARGIN;
      await page.screenshot({ path: path.join(out, scheme, `${name}@${scale}x.png`), clip: { x: x0, y: y0, width: Math.ceil(r.x + r.w) - Math.floor(r.x) + 2 * MARGIN, height: Math.ceil(r.y + r.h) - Math.floor(r.y) + 2 * MARGIN } });
      if (scale === 1) {
        // the same cell with its text and icon glyphs made invisible: the comparer reads the glyph mask from the difference
        await page.evaluate(() => document.documentElement.classList.add("notext"));
        await page.waitForTimeout(60);
        await page.screenshot({ path: path.join(out, scheme, `${name}@1x-notext.png`), clip: { x: x0, y: y0, width: Math.ceil(r.x + r.w) - Math.floor(r.x) + 2 * MARGIN, height: Math.ceil(r.y + r.h) - Math.floor(r.y) + 2 * MARGIN } });
        await page.evaluate(() => document.documentElement.classList.remove("notext"));
      }
      await page.mouse.up();
    }
    const ctl = (CONTROL.find(([p]) => name.startsWith(p)) || ["", name])[1];
    rows.push([scheme, ctl, name, `${scheme}/${name}@1x.png`, `${scheme}/${name}@2x.png`, w, h, `margin=${MARGIN}`]);
  }
}
await browser.close();
console.log("cells", rows.length);
