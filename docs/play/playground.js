// Compiles Neper source to a wasm32-wasi module with neper.wasm, the compiler itself built for WebAssembly,
// and runs the result. The compiler reads lib/e from its file system, so each `use` it cannot find is
// fetched from play/lib and the compile is repeated. Used by play.html and by build.mjs.
import { run } from './neper-host.js'

const enc = new TextEncoder()
const dec = new TextDecoder()
const text = (s) => (typeof s === 'string' ? s : dec.decode(s))
const MISSING = /`use ([A-Za-z0-9_.]+)` names no module/

// load(path) -> Uint8Array; index is every path under lib/. A module e.a.b is lib/e/a/b.e and its
// per-target variants (b.wasi.e, b.windows.e, ...).
export function libraries(index, load) {
  return async (module, files) => {
    const base = 'lib/' + module.replace(/\./g, '/')
    const slash = base.lastIndexOf('/')
    const dir = base.slice(0, slash + 1), stem = base.slice(slash + 1)
    const wanted = index.filter((p) => p.startsWith(dir) && !p.slice(dir.length).includes('/') && (p === base + '.e' || (p.slice(dir.length).startsWith(stem + '.') && p.endsWith('.e'))))
    let added = false
    for (const p of wanted) if (!files[p]) { files[p] = await load(p); added = true }
    return added
  }
}

export async function compile(compiler, source, fetchLib) {
  const files = { 'main.e': enc.encode(source) }
  for (let round = 0; round < 200; round++) {
    let said = ''
    const r = await run(compiler, { args: ['emit-executable', 'main.e', '.', 'wasm32', 'wasi', 'main.wasm', '--release'], files, stdout: (s) => (said += text(s)), stderr: (s) => (said += text(s)) })
    if (r.exitCode === 0) return { wasm: r.files['/main.wasm'], libraries: Object.keys(files).filter((p) => p.startsWith('lib/')) }
    const m = said.match(MISSING)
    if (!m || !(await fetchLib(m[1], files))) return { error: said.trim() || 'the compiler exited with status ' + r.exitCode }
  }
  return { error: 'too many modules to fetch' }
}

export async function execute(wasm, onOutput) {
  const r = await run(wasm, { args: [], stdout: (s) => onOutput(text(s)), stderr: (s) => onOutput(text(s)) })
  return r.exitCode
}
