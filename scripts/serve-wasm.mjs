// Serve lib/wasm, tests/wasm/browser and build/wasm-sweep read-only on 127.0.0.1 for the browser host (D5678):
//   node scripts/serve-wasm.mjs [--isolated] [--port N]
// URLs are repository paths (/tests/wasm/browser/index.html?module=/build/wasm-sweep/NAME.wasm). --isolated adds
// Cross-Origin-Opener-Policy: same-origin and Cross-Origin-Embedder-Policy: require-corp, which makes the page
// cross-origin isolated (SharedArrayBuffer, needed by threads and by e.ui input).
import { createServer } from 'node:http'
import { readFile } from 'node:fs/promises'
import { dirname, extname, join, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const roots = ['lib/wasm', 'tests/wasm/browser', 'build/wasm-sweep'].map((r) => resolve(repo, r))
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png' }
const args = process.argv.slice(2)
const isolated = args.includes('--isolated')
const port = args.includes('--port') ? Number(args[args.indexOf('--port') + 1]) : 8765

createServer(async (request, response) => {
  const path = decodeURIComponent(new URL(request.url, 'http://x').pathname)
  const headers = { 'Cache-Control': 'no-store' }
  if (isolated) Object.assign(headers, { 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' })
  if (path === '/') {
    response.writeHead(302, { ...headers, Location: '/tests/wasm/browser/index.html' }).end()
    return
  }
  const file = resolve(repo, '.' + path)
  if (request.method !== 'GET' || !roots.some((r) => file.startsWith(r + sep))) {
    response.writeHead(404, headers).end('not served')
    return
  }
  try {
    response.writeHead(200, { ...headers, 'Content-Type': types[extname(file)] ?? 'application/octet-stream' }).end(await readFile(file))
  } catch {
    response.writeHead(404, headers).end('not found')
  }
}).listen(port, '127.0.0.1', () => console.log(`serving http://127.0.0.1:${port}/${isolated ? ' (cross-origin isolated)' : ''}`))
