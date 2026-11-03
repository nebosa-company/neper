// Renders the 1200x630 share images: node docs/gtm/og/build.mjs  (Playwright via PLAYWRIGHT_MODULE)
import { createRequire } from 'node:module'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
const { chromium } = createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE || 'playwright')
const here = path.dirname(fileURLToPath(import.meta.url))
const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 1200, height: 630 } })
for (const card of ['get-started', 'play', 'blog']) {
  await page.goto(pathToFileURL(path.join(here, 'card.html')).href + '?card=' + card)
  await page.evaluate(() => document.fonts.ready)
  await page.screenshot({ path: path.join(here, '..', card + '-og.png') })
}
await browser.close()
