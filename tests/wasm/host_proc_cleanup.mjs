// Direct NetHost boundary checks: invalid sockets allocate nothing, a listener keeps
// the requested backlog, a drained pipe wakes a backpressured writer, long poll waits keep
// their deadline through bounded Node timers, and process/group aliases retain exactly the
// needed host record.
import assert from 'node:assert/strict'
import net from 'node:net'
import { BASE, FUNCTIONS, NetHost, context } from '../../lib/wasm/run-wasm-host.mjs'

const saved = { cwd: context.cwd, tmp: context.tmp, preopens: context.preopens, env: context.env, runner: context.runner }
const data = new Uint8Array(65536)
const host = new NetHost(data)
const wait = FUNCTIONS.findIndex(([name]) => name === 'proc_wait')
const groupClose = FUNCTIONS.findIndex(([name]) => name === 'proc_group_close')
const open = FUNCTIONS.findIndex(([name]) => name === 'sock_open')
const listen = FUNCTIONS.findIndex(([name]) => name === 'sock_listen')
const accept = FUNCTIONS.findIndex(([name]) => name === 'sock_accept')
const close = FUNCTIONS.findIndex(([name]) => name === 'sock_close')
const pollOpen = FUNCTIONS.findIndex(([name]) => name === 'poll_open')
const pollWait = FUNCTIONS.findIndex(([name]) => name === 'poll_wait')
const pollWake = FUNCTIONS.findIndex(([name]) => name === 'poll_wake')
const pipe = FUNCTIONS.findIndex(([name]) => name === 'pipe')
const handleRead = FUNCTIONS.findIndex(([name]) => name === 'handle_read')
const handleWrite = FUNCTIONS.findIndex(([name]) => name === 'handle_write')
const pipeChunk = data.length - 128
const argv = Buffer.from(`${process.execPath}\0-e\0\0`)
const linger = Buffer.from(`${process.execPath}\0-e\0setTimeout(() => {}, 20)\0`)

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
  // A blocking accept must wake if a second caller closes its listener. The
  // direct host seam makes the close deterministic without a second Wasm module.
  assert.equal(await host.call(open, [0, 0, 0]), 0, 'a second listener socket opens')
  const blockedListener = host.view.getUint32(64, true)
  host.socks.get(blockedListener).server = { close() {} }
  let acceptSettled = false
  const pendingAccept = host.call(accept, [blockedListener, 0, 0]).then((status) => {
    acceptSettled = true
    return status
  })
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(acceptSettled, false, 'a listener with no connection blocks accept')
  assert.equal(await host.call(close, [blockedListener]), 0, 'closing the waiting listener succeeds')
  assert.equal(await pendingAccept, 8, 'the pending accept wakes with BADF after close')
  assert.equal(await host.call(pollOpen, []), 0, 'a host poller opens')
  const poller = host.view.getUint32(64, true)
  const originalSetTimeout = globalThis.setTimeout
  const originalClearTimeout = globalThis.clearTimeout
  const timers = []
  let waiting
  let finished = false
  globalThis.setTimeout = (callback, milliseconds) => {
    const timer = { callback, milliseconds }
    timers.push(timer)
    return timer
  }
  globalThis.clearTimeout = (timer) => { timer.cleared = true }
  try {
    // A delay above Node's signed-32-bit timer maximum must be split rather than
    // clamped to one millisecond. Trigger the synthetic first slice, not a real day.
    const longTimeout = (2n * 2147483647n + 1n) * 1000000n
    waiting = host.call(pollWait, [poller, 0, 1, longTimeout, 0]).then((status) => {
      finished = true
      return status
    })
    assert.equal(timers.length, 1, 'the long poll schedules its first timer')
    assert.equal(timers[0].milliseconds, 2147483647, 'the first timer stays within Node\'s limit')
    timers[0].callback()
    await new Promise((resolve) => setImmediate(resolve))
    assert.equal(finished, false, 'one bounded timer does not exhaust the long deadline')
    assert.equal(timers.length, 2, 'the remaining deadline schedules another bounded timer')
    assert.equal(timers[1].milliseconds, 2147483647, 'the recomputed timer stays within Node\'s limit')
    assert.equal(await host.call(pollWake, [poller]), 0, 'a poll wake interrupts the bounded wait')
    assert.equal(await waiting, 0, 'the long poll returns after its wake')
  } finally {
    if (waiting && !finished) {
      await host.call(pollWake, [poller])
      await waiting
    }
    globalThis.setTimeout = originalSetTimeout
    globalThis.clearTimeout = originalClearTimeout
  }
  assert.equal(await host.call(pipe, []), 0, 'a host pipe opens')
  const reader = host.view.getUint32(64, true)
  const writer = host.view.getUint32(68, true)
  data.fill(65, 128)
  // Sixteen mailbox-sized writes stay just below the 1 MiB backpressure mark;
  // the seventeenth crosses it, so the next write must wait for this read.
  for (let turn = 0; turn < 17; turn++) {
    assert.equal(await host.call(handleWrite, [writer, 0, pipeChunk, 0]), 0, `pipe fill ${turn} succeeds`)
  }
  let resumed = false
  const queued = host.call(handleWrite, [writer, 0, 1, 0]).then((status) => {
    resumed = status === 0
    return status
  })
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(resumed, false, 'the full pipe backpressures its next writer')
  assert.equal(await host.call(handleRead, [reader, 0, pipeChunk, 0, 0]), 0, 'the reader drains a mailbox-sized chunk')
  assert.equal(data[128], 65, 'the read copied queued pipe data')
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(resumed, true, 'draining the pipe wakes the queued writer')
  assert.equal(await queued, 0, 'the queued writer completes')
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
  // `proc.run` with contain_tree waits the root and then drops the group. Both aliases name one
  // host record, which disappears only after both lifetimes have ended.
  data.fill(0)
  data.set(argv, 128)
  assert.equal(await host.procSpawn([0, argv.length, 3, 0, 3, 0, 0, 1, 2]), 0)
  const contained = host.view.getUint32(64, true)
  assert.equal(await host.call(wait, [contained, 0]), 0, 'the contained child exits')
  assert.equal(host.procs.size, 1, 'a waited group stays until its group owner closes')
  assert.equal(await host.call(groupClose, [contained]), 0, 'closing the contained group succeeds')
  assert.equal(host.procs.size, 0, 'closing a waited group reclaims its process record')

  // Closing the group first must not invalidate the still-aliased Proc: its wait owns the remaining lifetime.
  data.fill(0)
  data.set(linger, 128)
  assert.equal(await host.procSpawn([0, linger.length, 3, 0, 3, 0, 0, 1, 2]), 0)
  const early = host.view.getUint32(64, true)
  assert.equal(await host.call(groupClose, [early]), 0, 'an early group close succeeds')
  assert.equal(host.procs.size, 1, 'an early group close retains the aliased process')
  assert.equal(await host.call(wait, [early, 0]), 0, 'the aliased process remains waitable')
  assert.equal(host.procs.size, 0, 'waiting after an early group close reclaims the record')
} finally {
  Object.assign(context, saved)
  host.closeAll()
}

console.log('wasm host boundary ok')
