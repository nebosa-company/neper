// Direct NetHost boundary checks: invalid sockets allocate nothing, a listener keeps
// the requested backlog, and a waited ordinary child does not accumulate in procs.
import assert from 'node:assert/strict'
import net from 'node:net'
import { BASE, FUNCTIONS, NetHost, context } from '../../lib/wasm/run-wasm-host.mjs'

const saved = { cwd: context.cwd, tmp: context.tmp, preopens: context.preopens, env: context.env, runner: context.runner }
const data = new Uint8Array(65536)
const host = new NetHost(data)
const wait = FUNCTIONS.findIndex(([name]) => name === 'proc_wait')
const open = FUNCTIONS.findIndex(([name]) => name === 'sock_open')
const listen = FUNCTIONS.findIndex(([name]) => name === 'sock_listen')
const argv = Buffer.from(`${process.execPath}\0-e\0\0`)

try {
  context.cwd = process.cwd()
  assert.equal(await host.call(open, [7, 0, 0]), 5, 'an unknown socket family is AFNOSUPPORT')
  assert.equal(await host.call(open, [0, 2, 0]), 28, 'an unknown socket kind is INVAL')
  assert.equal(host.socks.size, 0, 'invalid sockets are not allocated')
  assert.equal(host.ids.next, BASE, 'invalid sockets do not consume handles')
  assert.equal(await host.call(open, [0, 0, 0]), 0, 'a valid stream socket opens')
  const socket = host.view.getUint32(64, true)
  const originalCreateServer = net.createServer
  let options
  net.createServer = () => ({
    on() {},
    once() {},
    listen(given, ready) { options = given; ready() },
    close() {},
  })
  try {
    assert.equal(await host.call(listen, [socket, 1]), 0, 'the listener starts')
    assert.equal(options.backlog, 1, 'the listener receives the guest backlog')
  } finally {
    net.createServer = originalCreateServer
  }
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

console.log('wasm host boundary ok')
