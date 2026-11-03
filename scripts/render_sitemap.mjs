// Writes docs/sitemap.xml: the pages worth indexing, each with the date of its last commit.
//   node scripts/render_sitemap.mjs
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'

const SITE = 'https://neper.dev/'
const PAGES = [
  ['index.html', '', 1.0],
  ['get-started.html', 'get-started.html', 0.9],
  ['play.html', 'play.html', 0.9],
  ['blog/index.html', 'blog/', 0.8],
  ['charts.html', 'charts.html', 0.6],
  ['ux/showcase.html', 'ux/showcase.html', 0.6],
  ['progress.html', 'progress.html', 0.4],
]
const SKIP = new Set(['index.html', 'e-db-three-drivers.html', 'e-db-four-drivers.html']) // blog index, redirect stubs
for (const f of fs.readdirSync('docs/blog').sort()) {
  if (f.endsWith('.html') && !SKIP.has(f)) PAGES.push(['blog/' + f, 'blog/' + f, 0.7])
}

const rows = PAGES.map(([file, url, priority]) => {
  const date = execFileSync('git', ['log', '-1', '--format=%cs', '--', 'docs/' + file], { encoding: 'utf8' }).trim()
  return `  <url>\n    <loc>${SITE}${url}</loc>\n${date ? `    <lastmod>${date}</lastmod>\n` : ''}    <priority>${priority.toFixed(1)}</priority>\n  </url>`
})
fs.writeFileSync('docs/sitemap.xml', `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${rows.join('\n')}\n</urlset>\n`)
console.log(PAGES.length, 'pages')
