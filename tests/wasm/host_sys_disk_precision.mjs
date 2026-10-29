import assert from 'node:assert/strict'
import { NetHost, context } from '../../lib/wasm/run-wasm-host.mjs'

const savedPreopens = context.preopens
const data = new Uint8Array(65536)
data.set(Buffer.from('.'), 128)
let statfsCall
const host = new NetHost(data, {
  statfs(path, options) {
    statfsCall = { path, options }
    return {
      bsize: 4096n,
      blocks: 9007199254740993n,
      bfree: 2n,
      bavail: 9007199254740991n,
    }
  },
})

try {
  context.preopens = { test: process.cwd() }
  assert.equal(host.sysDisk(3, 1, 128), 0, 'the disk query succeeds')
  assert.deepEqual(statfsCall, {
    path: process.cwd(),
    options: { bigint: true },
  }, 'statfs requests exact integer fields')
  const length = host.view.getUint32(64, true)
  assert.equal(
    Buffer.from(data.subarray(1024, 1024 + length)).toString('utf8'),
    '36893488147419107328 36893488147419099136 36893488147419099136',
    'total, free, and used bytes preserve u64 precision',
  )
} finally {
  context.preopens = savedPreopens
  host.closeAll()
}

console.log('wasm host sys_disk precision ok')
