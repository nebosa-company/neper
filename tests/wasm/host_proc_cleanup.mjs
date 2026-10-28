// A waited ordinary child must not accumulate in NetHost.procs. This bypasses the
// compiler deliberately, so the host table is tested at its JavaScript boundary.
import assert from 'node:assert/strict'
import { FUNCTIONS, NetHost, context } from '../../lib/wasm/run-wasm-host.mjs'

const saved = { cwd: context.cwd, tmp: context.tmp, preopens: context.preopens, env: context.env, runner: context.runner }
const data = new Uint8Array(65536)
const host = new NetHost(data)
const wait = FUNCTIONS.findIndex(([name]) => name === 'proc_wait')
const argv = Buffer.from(`${process.execPath}\0-e\0\0`)

try {
  context.cwd = process.cwd()
  for (let turn = 0; turn < 16; turn++) {
    data.fill(0)
    data.set(argv, 128)
    assert.equal(await host.procSpawn([0, argv.length, 3, 0, 1, 0, 0, 1, 2]), 0)
    const id = host.view.getUint32(64, true)
    assert.equal(host.procs.size, 1, `spawn ${turn} is retained until waited`)
    assert.equal(await host.call(wait, [id, 0]), 0)
    assert.equal(host.view.getUint32(64, true), 0, `child ${turn} exited cleanly`)
    assert.equal(host.procs.size, 0, `wait ${turn} reclaimed its process entry`)
    assert.equal(await host.call(wait, [id, 0]), 8, `wait ${turn} cannot reuse a reclaimed handle`)
  }
} finally {
  Object.assign(context, saved)
  host.closeAll()
}

console.log('wasm host proc cleanup ok')
