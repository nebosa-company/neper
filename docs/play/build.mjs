// Rebuilds play/neper.wasm and the library subset the samples need, from the repository root:
//   neper emit-executable src/main.e . wasm32 wasi docs/play/neper.wasm --release   (done here)
//   node docs/play/build.mjs [path-to-neper]
// Each sample is compiled and run with the same code the page uses; the lib files it fetched are copied
// to docs/play/lib, with index.json listing them.
import fs from 'node:fs'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { compile, execute, libraries } from './playground.js'

const here = path.dirname(new URL(import.meta.url).pathname.replace(/^\/(\w:)/, '$1'))
const root = path.resolve(here, '..', '..')
const neper = process.argv[2] || process.env.NEPER || 'neper'
const wasmPath = path.join(here, 'neper.wasm')
const built = spawnSync(neper, ['emit-executable', 'src/main.e', '.', 'wasm32', 'wasi', wasmPath, '--release'], { cwd: root, encoding: 'utf8' })
if (built.status !== 0) { console.error(built.stdout, built.stderr); process.exit(1) }

const everything = []
const walk = (dir) => { for (const e of fs.readdirSync(path.join(root, dir), { withFileTypes: true })) { const p = dir + '/' + e.name; if (e.isDirectory()) walk(p); else if (p.endsWith('.e')) everything.push(p) } }
walk('lib/e')
const fetchLib = libraries(everything, async (p) => new Uint8Array(fs.readFileSync(path.join(root, p))))

const compiler = await WebAssembly.compile(fs.readFileSync(wasmPath))
const used = new Set()
for (const name of fs.readdirSync(path.join(here, 'samples')).filter((n) => n.endsWith('.e'))) {
  const r = await compile(compiler, fs.readFileSync(path.join(here, 'samples', name), 'utf8'), fetchLib)
  if (r.error) { console.error(name, r.error); process.exit(1) }
  let out = ''
  const status = await execute(r.wasm, (s) => (out += s))
  console.log(name, r.wasm.length, 'bytes, exit', status, JSON.stringify(out.slice(0, 80)))
  if (status !== 0) process.exit(1)
  for (const p of r.libraries) used.add(p)
}
fs.rmSync(path.join(here, 'lib'), { recursive: true, force: true })
for (const p of used) { fs.mkdirSync(path.dirname(path.join(here, p)), { recursive: true }); fs.copyFileSync(path.join(root, p), path.join(here, p)) }
fs.writeFileSync(path.join(here, 'lib', 'index.json'), JSON.stringify([...used].sort()))
console.log(used.size, 'library files; neper.wasm', fs.statSync(wasmPath).size, 'bytes')
