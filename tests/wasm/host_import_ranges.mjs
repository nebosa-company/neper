// The worker-side generic neper_host adapter must reject invalid guest ranges
// before it wakes NetHost, and address zero remains a valid output destination.
import assert from 'node:assert/strict'
import { isMainThread, parentPort, Worker, workerData } from 'node:worker_threads'
import { BASE, hostImports, serve } from '../../lib/wasm/run-wasm-host.mjs'

const EINVAL = 28

if (isMainThread) {
  const box = new SharedArrayBuffer(128)
  const data = new SharedArrayBuffer(65536)
  const service = serve(box, data)
  const worker = new Worker(new URL(import.meta.url), { workerData: { box, data } })
  let answered = false
  try {
    const result = await new Promise((resolve, reject) => {
      worker.once('message', (message) => {
        answered = true
        resolve(message)
      })
      worker.once('error', reject)
      worker.once('exit', (code) => {
        if (!answered) reject(new Error(`host-import worker ended with ${code}`))
      })
    })
    if (!result.ok) throw new Error(result.error)
  } finally {
    service.stop()
    await worker.terminate()
  }
  console.log('wasm host-import guest ranges ok')
} else {
  try {
    const memory = new WebAssembly.Memory({ initial: 1 })
    const bytes = new Uint8Array(memory.buffer)
    const state = new Int32Array(workerData.box)
    const imports = hostImports(['sock_open', 'sock_bind', 'sock_local_address', 'sock_send', 'sock_recv', 'resolve', 'poll_wait'], () => memory, workerData.box, workerData.data)

    // Each letter in the import description that names guest storage is
    // validated before the mailbox is touched: c, i, o, p, q, r and s.
    assert.equal(imports.sock_open(0, 0, 65535), EINVAL)
    assert.equal(imports.sock_open(0, 0, 0x100000000), EINVAL, 'a direct caller cannot wrap an output pointer')
    assert.equal(imports.sock_bind(BASE, 65535), EINVAL)
    assert.equal(imports.sock_local_address(BASE, 65535), EINVAL)
    assert.equal(imports.sock_send(BASE, 65535, 2, 0), EINVAL)
    assert.equal(imports.sock_recv(BASE, 65535, 2, 0), EINVAL)
    assert.equal(imports.resolve(0, 0, 0, 0, 65535, 1, 0), EINVAL)
    assert.equal(imports.poll_wait(0, 65535, 1, 0n, 0), EINVAL)
    assert.equal(Atomics.load(state, 0), 0, 'invalid calls did not dispatch a host operation')

    // The rejected open did not consume an ID, and a u32 result can be stored at
    // address zero.  This also proves that the test has a live main-thread host.
    assert.equal(imports.sock_open(0, 0, 0), 0)
    const socket = new DataView(memory.buffer).getUint32(0, true)
    assert.equal(socket, BASE, 'invalid output did not create a socket')

    // `o` is a 32-byte output.  Fill address zero first to prove the reply is
    // copied there instead of treating zero as an omitted optional pointer.
    bytes.fill(0xa5, 0, 32)
    assert.equal(imports.sock_local_address(socket, 0), 0)
    assert.deepEqual([...bytes.subarray(0, 32)], Array(32).fill(0))
    parentPort.postMessage({ ok: true })
  } catch (error) {
    parentPort.postMessage({ ok: false, error: error.stack ?? String(error) })
  }
}
