// The API of lib/wasm/neper-host.js under Node (C206, D5678):
//   node --no-warnings tests/wasm/host.mjs FILES.wasm DEBUG.wasm RELEASE.wasm [THREADS.wasm]
// FILES is tests/wasm/browser/host_files, DEBUG and RELEASE are wasm_release built without and with --release.
// THREADS is link/wasm_threads built with --threads (C207, D5679).
// The sweep (scripts/wasm-sweep.sh --host neper-host) covers WASI itself; this covers what a page passes in and gets back.
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { pathToFileURL } from 'node:url'
import { run } from '../../lib/wasm/neper-host.js'

const [filesPath, debugPath, releasePath, threadsPath] = process.argv.slice(2)
const text = (bytes) => new TextDecoder().decode(bytes)
const capture = () => {
  const got = { stdout: '', stderr: '' }
  return { got, stdout: (b) => { got.stdout += text(b) }, stderr: (b) => { got.stderr += text(b) } }
}
const options = { args: ['hello'], env: { HOSTVAR: 'v1' }, files: { '/input.txt': 'abc def' } }

async function checkFiles(source, label) {
  const c = capture()
  const { exitCode, files } = await run(source, { ...options, stdout: c.stdout, stderr: c.stderr })
  assert.equal(exitCode, 7, label)
  assert.equal(c.got.stdout, 'hello\nv1\n', label)
  assert.equal(c.got.stderr, 'to stderr\n', label)
  assert.equal(text(files['/output.txt']), 'ABC DEF', label)
  assert.equal(text(files['/sub/n.txt']), 'nested', label)
  assert.equal(text(files['/input.txt']), 'abc def', label)
}

const bytes = new Uint8Array(await readFile(filesPath))
await checkFiles(pathToFileURL(filesPath), 'file URL')
await checkFiles(bytes, 'bytes')
await checkFiles(await WebAssembly.compile(bytes), 'Module')
await checkFiles(new Response(bytes), 'Response')

// a run starts from a fresh tree, and two at once do not share one
const [alone, other] = await Promise.all([run(bytes, { ...options, stdout() {}, stderr() {} }), run(bytes, { args: ['x'], env: { HOSTVAR: 'y' }, stdout() {}, stderr() {} })])
assert.equal(alone.exitCode, 7)
assert.equal(other.exitCode, 4, 'the second run saw the first one\'s input')
assert.deepEqual(Object.keys(other.files), [])

// traps: the compiler's own trap exits 134 with its message; a module the engine refuses exits 125
const trap = capture()
assert.equal((await run(pathToFileURL(debugPath), { stdout: trap.stdout, stderr: trap.stderr })).exitCode, 134)
assert.match(trap.got.stderr, /main\.e:14:19: trap\[overflow\]: u8 \+ overflows/)
const fine = capture()
assert.equal((await run(pathToFileURL(releasePath), { stdout: fine.stdout, stderr: fine.stderr })).exitCode, 0)
const bounds = capture()
assert.equal((await run(pathToFileURL(releasePath), { args: ['bounds'], stdout: bounds.stdout, stderr: bounds.stderr })).exitCode, 134)
assert.match(bounds.got.stderr, /trap\[bounds\]: index 8 out of bounds for len 8/)
const bad = capture()
assert.equal((await run(new Uint8Array([0, 1, 2, 3]), { stdout: bad.stdout, stderr: bad.stderr })).exitCode, 125)
assert.notEqual(bad.got.stderr, '')

// threads (C207, D5679): the calling thread is the host and every wasm thread a Worker; both ways of answering a
// request (Atomics.waitAsync, and a ping message where it is missing), exit from a thread, two runs at once, and
// the one thing a compiled module cannot do (its memory limits are read from bytes)
if (threadsPath) {
  const expected = 'atomic 8000\nmutex 8000\nids distinct\nmain id 1\na thread started a thread\ndetached\nwait timeout\ndetails per thread\n200 cycles\nmain returns\n'
  const threaded = new Uint8Array(await readFile(threadsPath))
  for (const [source, label, extra] of [[pathToFileURL(threadsPath), 'URL', {}], [threaded, 'bytes', {}], [threaded, 'bytes, ping messages', { messages: true }]]) {
    const c = capture()
    const { exitCode } = await run(source, { ...extra, stdout: c.stdout, stderr: c.stderr })
    assert.equal(exitCode, 0, `threads ${label}: ${c.got.stderr}`)
    assert.equal(c.got.stdout, expected, `threads ${label}`)
  }
  for (const extra of [{}, { messages: true }]) {
    const c = capture()
    assert.equal((await run(threaded, { args: ['exit'], ...extra, stdout: c.stdout, stderr: c.stderr })).exitCode, 7, 'a thread\'s os.exit')
  }
  const [one, two] = await Promise.all([0, 1].map(() => { const c = capture(); return run(threaded, { stdout: c.stdout, stderr: c.stderr }).then((r) => ({ ...r, ...c.got })) }))
  assert.equal(one.stdout, expected)
  assert.equal(two.stdout, expected)
  await assert.rejects(run(await WebAssembly.compile(threaded), { stdout() {}, stderr() {} }), /URL, a Response or bytes/)
}

console.log('neper-host api ok')
