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
  data.fill(0xa5, 1024, 1056)
  const ipv6 = Buffer.from('::1')
  data.set(ipv6, 128)
  assert.equal(await host.resolve(ipv6.length, 443, 1, 1), 0, 'the IPv6 lookup succeeds')
  const ipv4 = Buffer.from('127.0.0.1')
  data.set(ipv4, 128)
  assert.equal(await host.resolve(ipv4.length, 443, 0, 1), 0, 'the IPv4 lookup succeeds')
  assert.equal(data[1024], 0, 'the reused record is IPv4')
  assert.deepEqual([...data.subarray(1032, 1036)], [127, 0, 0, 1], 'the IPv4 bytes replace the IPv6 address')
  for (let at = 1036; at < 1056; at++) assert.equal(data[at], 0, 'the IPv4 tail and record padding are cleared')
} finally {
  context.preopens = savedPreopens
  host.closeAll()
}

console.log('wasm host sys_disk precision ok')
