// Renders the static reference catalogues from the two source markdown files:
//   docs/reference/modules.html     from docs/module-apis.md  (module name, summary, anchor)
//   docs/reference/algorithms.html  from docs/algos.md        (catalog id, name, summary, verdict)
// Run from the repository root:  node scripts/render_reference.mjs
import fs from 'node:fs'

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
const clean = (s) => s.replace(/\*\*|`/g, '').replace(/\s+/g, ' ').trim()

function page({ title, description, canonical, h1, lede, body }) {
  if (title.length > 60) throw new Error(`title ${title.length} > 60: ${title}`)
  if (description.length > 160) throw new Error(`description ${description.length} > 160: ${description}`)
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${esc(title)}</title>
  <meta name="description" content="${esc(description)}">
  <link rel="canonical" href="${canonical}">
  <meta name="theme-color" content="#145db2">
  <link rel="icon" href="/favicon.ico" sizes="any">
  <link rel="icon" type="image/svg+xml" href="/gtm/logo/neper-icon.svg">
  <link rel="apple-touch-icon" href="/apple-touch-icon.png">
  <link rel="manifest" href="/site.webmanifest">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Neper">
  <meta property="og:title" content="${esc(h1)}">
  <meta property="og:description" content="${esc(description)}">
  <meta property="og:url" content="${canonical}">
  <meta property="og:image" content="https://neper.dev/gtm/blog-og.png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="stylesheet" href="/ux/components/bundle.css">
  <style>
    :root { color-scheme: light dark; --primary: #145db2; --on-primary: #fff; --surface: #f8f9ff; --on-surface: #1a1b20;
      --on-surface-variant: #434653; --outline-variant: #c3c6d5;
      --font-sans: "Segoe UI Variable Text", "Segoe UI", -apple-system, BlinkMacSystemFont, "SF Pro Text", Roboto, "Noto Sans", system-ui, sans-serif;
      --font-display: "Segoe UI Variable Display", "Segoe UI", -apple-system, "SF Pro Display", Roboto, "Noto Sans", system-ui, sans-serif;
      --font-mono: "Cascadia Code", ui-monospace, Menlo, "JetBrains Mono", Consolas, monospace; }
    @media (prefers-color-scheme: dark) { :root { --primary: #b3c5ff; --surface: #10131a; --on-surface: #e3e2e9; --on-surface-variant: #c3c6d5; --outline-variant: #434653; } }
    * { box-sizing: border-box; }
    body { margin: 0; background: var(--surface); color: var(--on-surface); font: 400 16px/26px var(--font-sans); }
    .wrap { width: min(100% - 48px, 960px); margin: 0 auto; padding: 24px 0 32px; }
    nav { display: flex; align-items: center; justify-content: space-between; gap: 20px; padding: 12px 0 24px; }
    .brand { display: flex; align-items: center; gap: 11px; color: inherit; text-decoration: none; }
    .brand img { width: 40px; height: 40px; } .brand span { font: 600 16px/24px var(--font-sans); }
    .nav-links { display: flex; flex-wrap: wrap; gap: 16px; }
    .nav-links a { color: var(--on-surface-variant); text-decoration: none; font-size: 14px; }
    .nav-links a:hover, a { color: var(--primary); }
    h1 { font: 600 clamp(30px, 5vw, 44px)/1.15 var(--font-display); margin: 24px 0 16px; }
    h2 { font: 600 24px/32px var(--font-display); margin: 40px 0 12px; padding-top: 8px; border-top: 1px solid var(--outline-variant); }
    h3 { font: 600 17px/24px var(--font-mono); margin: 18px 0 4px; }
    h3 a, .src a { text-decoration: none; }
    .eyebrow { color: var(--on-surface-variant); font: 500 13px/18px var(--font-sans); letter-spacing: .02em; text-transform: uppercase; }
    p { max-width: 72ch; margin: 0 0 8px; } .lede { font-size: 18px; line-height: 28px; }
    .summary { color: var(--on-surface-variant); }
    dl { margin: 0; } dt { margin: 14px 0 2px; font-weight: 600; }
    dd { margin: 0 0 4px 0; color: var(--on-surface-variant); }
    .id { display: inline-block; min-width: 52px; color: var(--on-surface-variant); font: 400 14px/22px var(--font-mono); }
    code { font-family: var(--font-mono); }
    footer { display: flex; justify-content: space-between; gap: 20px; padding: 24px 0 0; margin-top: 40px; border-top: 1px solid var(--outline-variant); color: var(--on-surface-variant); font-size: 14px; }
    @media (max-width: 640px) { footer { flex-direction: column; } }
  </style>
</head>
<body>
  <div class="wrap">
    <nav aria-label="Primary navigation">
      <a class="brand" href="/" aria-label="Neper home"><img src="/gtm/logo/neper-icon.svg" alt="" width="40" height="40"><span>Neper</span></a>
      <div class="nav-links">
        <a href="/get-started.html">get started</a>
        <a href="/blog/">blog</a>
        <a href="/charts.html">charts</a>
        <a href="/reference/modules.html">modules</a>
        <a href="/reference/algorithms.html">algorithms</a>
      </div>
    </nav>
    <main>
      <div class="eyebrow">&gt; reference_</div>
      <h1>${esc(h1)}</h1>
      <p class="lede">${lede}</p>
${body}
    </main>
    <footer>
      <span>Generated from the repository documentation; the source is authoritative.</span>
      <a href="/">← home</a>
    </footer>
  </div>
</body>
</html>
`
}

// ---- modules: `### `e.x`` sections, grouped by the `## ` headings above them.
const api = fs.readFileSync('docs/module-apis.md', 'utf8').split('\n')
const modules = []
let group = ''
for (let i = 0; i < api.length; i += 1) {
  const line = api[i]
  if (line.startsWith('## ')) { group = line.replace(/^##\s+/, '').trim(); continue }
  const m = line.match(/^### `([^`]+)`\s*$/)
  if (!m) continue
  const name = m[1]
  const decl = []
  for (let j = i + 1; j < api.length && !api[j].startsWith('### ') && !api[j].startsWith('## '); j += 1) {
    if (/^```neper/.test(api[j])) {
      for (let k = j + 1; k < api.length && !api[k].startsWith('```'); k += 1) decl.push(api[k])
      break
    }
  }
  const fns = decl.filter((l) => /^fn /.test(l)).map((l) => l.slice(3).split('[')[0].split('(')[0].trim())
  const types = decl.filter((l) => /^type /.test(l)).length
  const errors = decl.filter((l) => /^error /.test(l)).length
  const consts = decl.filter((l) => /^(const|var|global) /.test(l)).length
  const parts = []
  if (fns.length) parts.push(`${fns.length} function${fns.length === 1 ? '' : 's'}`)
  if (types) parts.push(`${types} type${types === 1 ? '' : 's'}`)
  if (consts) parts.push(`${consts} constant${consts === 1 ? '' : 's'}`)
  if (errors) parts.push(`${errors} error name${errors === 1 ? '' : 's'}`)
  const names = fns.slice(0, 3).join(', ')
  const summary = `${parts.length ? parts.join(', ') : 'no public declarations'}: ${names}${fns.length > 3 ? ', …' : ''}`
  modules.push({ name, group, summary })
}

const moduleGroups = []
for (const mod of modules) {
  const last = moduleGroups[moduleGroups.length - 1]
  if (last && last.title === mod.group) last.items.push(mod)
  else moduleGroups.push({ title: mod.group, items: [mod] })
}
const moduleBody = moduleGroups.map((g) => `      <h2>${esc(g.title)}</h2>\n` + g.items.map((mod) =>
  `      <h3 id="${esc(mod.name)}"><a href="#${esc(mod.name)}"><code>${esc(mod.name)}</code></a></h3>\n      <p class="summary">${esc(mod.summary)}</p>`
).join('\n')).join('\n')

// ---- algorithms: `N. **Name** – summary → verdict`, grouped by `## ` headings.
const algoLines = fs.readFileSync('docs/algos.md', 'utf8').split('\n')
const moduleNames = new Set(modules.map((m) => m.name))
const algoGroups = []
let algoGroup = { title: 'Entries', items: [] }
for (const line of algoLines) {
  const h = line.match(/^##\s+(\d+\..*)$/)
  if (h) { if (algoGroup.items.length) algoGroups.push(algoGroup); algoGroup = { title: h[1].trim(), items: [] }; continue }
  const e = line.match(/^(\d+)\. \*\*(.+?)\*\* – (.+?) → (.+)$/)
  if (!e) continue
  const id = e[1]
  const name = clean(e[2])
  const summary = clean(e[3])
  const raw = e[4].trim()
  const verdict = /^`([^`]+)`/.exec(raw)
  let verdictHtml
  if (verdict) {
    const ref = verdict[1]
    verdictHtml = moduleNames.has(ref)
      ? `<a href="/reference/modules.html#${esc(ref)}"><code>${esc(ref)}</code></a>`
      : `<code>${esc(ref)}</code>`
  } else {
    verdictHtml = esc(clean(raw))
  }
  algoGroup.items.push({ id, name, summary, verdictHtml })
}
if (algoGroup.items.length) algoGroups.push(algoGroup)
const algoBody = algoGroups.map((g) => `      <h2>${esc(g.title)}</h2>\n      <dl>\n` + g.items.map((e) =>
  `        <dt id="a-${e.id}"><span class="id">#${e.id}</span>${esc(e.name)}</dt>\n        <dd>${esc(e.summary)} — ${e.verdictHtml}</dd>`
).join('\n') + '\n      </dl>').join('\n')

fs.mkdirSync('docs/reference', { recursive: true })
fs.writeFileSync('docs/reference/modules.html', page({
  title: 'Standard library modules — Neper',
  description: "Every public module of Neper's standard library with its declaration summary, grouped by dependency layer from docs/module-apis.md.",
  canonical: 'https://neper.dev/reference/modules.html',
  h1: 'Standard library module catalogue',
  lede: `${modules.length} public modules from <a href="https://github.com/nebosa-company/neper/blob/master/docs/module-apis.md"><code>docs/module-apis.md</code></a>, in dependency-layer order; each name is an anchor and the summary counts the public declarations in that module.`,
  body: moduleBody,
}))
fs.writeFileSync('docs/reference/algorithms.html', page({
  title: 'Algorithm catalogue — Neper',
  description: '1,000 programming functions and algorithms mapped to Neper modules, with catalog ids, one-line descriptions and each entry’s verdict from docs/algos.md.',
  canonical: 'https://neper.dev/reference/algorithms.html',
  h1: 'Algorithm catalogue',
  lede: `${algoGroups.reduce((n, g) => n + g.items.length, 0)} catalog entries from <a href="https://github.com/nebosa-company/neper/blob/master/docs/algos.md"><code>docs/algos.md</code></a>: each id is an anchor, and a mapped entry links to its module in the standard library catalogue.`,
  body: algoBody,
}))
console.log(`docs/reference/modules.html (${modules.length} modules), docs/reference/algorithms.html (${algoGroups.reduce((n, g) => n + g.items.length, 0)} entries)`)
