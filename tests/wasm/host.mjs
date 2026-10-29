// The API of lib/wasm/neper-host.js under Node (C206, D5678):
//   node --no-warnings tests/wasm/host.mjs FILES.wasm DEBUG.wasm RELEASE.wasm [THREADS.wasm THREAD_OPS.wasm]
// FILES is tests/wasm/browser/host_files, DEBUG and RELEASE are wasm_release built without and with --release.
// THREADS is link/wasm_threads and THREAD_OPS is wasm_thread_ops, both built with --threads (C207, D5679).
// The sweep (scripts/wasm-sweep.sh --host neper-host) covers WASI itself; this covers what a page passes in and gets back.
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { readFile } from 'node:fs/promises'
import { pathToFileURL } from 'node:url'
import { run } from '../../lib/wasm/neper-host.js'
import { addLines } from '../../lib/wasm/source-map.js'

const [filesPath, debugPath, releasePath, threadsPath, threadOpsPath] = process.argv.slice(2)
const text = (bytes) => new TextDecoder().decode(bytes)
const capture = () => {
  const got = { stdout: '', stderr: '' }
  return { got, stdout: (b) => { got.stdout += text(b) }, stderr: (b) => { got.stderr += text(b) } }
}
const options = { args: ['hello'], env: { HOSTVAR: 'v1' }, files: { '/input.txt': 'abc def' } }

// Source-map VLQ decoding accepts the compiler's ordinary mapping and rejects malformed
// sidecars promptly, so a trap report cannot leave a runner spinning in its decoder.
const mapText = (mappings) => JSON.stringify({ version: 3, sources: ['source.e'], names: [], mappings })
assert.equal(addLines('RuntimeError: wasm-function[3]:0x4)', mapText('IAAA')), 'RuntimeError: wasm-function[3]:0x4) [source.e:1]')
const sourceMapUrl = new URL('../../lib/wasm/source-map.js', import.meta.url).href
for (const [label, mappings] of [
  ['invalid digit', '?AAAA'],
  ['unterminated continuation', 'g'],
  ['overflow', `${'+'.repeat(11)}AAAA`],
]) {
  const probe = [
    `import { addLines } from ${JSON.stringify(sourceMapUrl)}`,
    `try { addLines('wasm-function[0]:0x0)', ${JSON.stringify(mapText(mappings))}) } catch { process.exit(0) }`,
    'process.exit(1)',
  ].join('\n')
  const result = spawnSync(process.execPath, ['--input-type=module', '--eval', probe], { encoding: 'utf8', timeout: 2000 })
  assert.equal(result.error, undefined, `${label} source-map decoder exceeded its 2-second bound`)
  assert.equal(result.status, 0, `${label} source-map decoder accepted malformed mappings: ${result.stderr ?? ''}`)
}

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
  if (threadOpsPath) {
    const expectedOps = 'threads 1\nthread.id 0\nspawn null -6\nspawn unaligned -6\nspawn past end -6\npoll valid 0\npoll subscription 21\npoll event 21\npoll taken 21\npoll count 21\nload 7\ncas hit 7\nload 4000000000\ncas miss 4000000000\nload 4000000000\nnotify 0\nwait different 1\nwait timeout 2\n'
    const threadOps = new Uint8Array(await readFile(threadOpsPath))
    for (const extra of [{}, { messages: true }]) {
      const c = capture()
      const { exitCode } = await run(threadOps, { ...extra, stdout: c.stdout, stderr: c.stderr })
      assert.equal(exitCode, 0, `threaded poll ranges: ${c.got.stderr}`)
      assert.equal(c.got.stdout, expectedOps, 'threaded poll ranges')
    }
  }
}

console.log('neper-host api ok')
