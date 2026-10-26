// The `neper_host` import module of lib/wasm/run-wasm.mjs (D5675, D5676): sockets, name resolution
// and the poller for a wasm32-wasi module, on node:net, node:dgram and node:dns.
//
// Two halves share this file. `hostImports` runs in the Worker that holds the module: each import
// copies its input into a 64 KiB data SharedArrayBuffer beside a 128-byte mailbox, blocks in
// Atomics.wait and copies the outputs back. `serve` runs on Node's main thread, answers one request
// at a time from the mailbox, and `NetHost` is the state behind it (handles, sockets, pollers).
//
// Mailbox (D5674): Int32 word 0 the state (0 idle, 1 request, 2 reply), word 1 the function number,
// BigInt64 words from byte 8 the arguments (up to twelve), Int32 word 26 the result (a WASI errno).
// Data buffer: bytes 0-31 an address going in, 32-63 an address coming out, 64-127 the u32 output
// slots, 128 and up the bytes in (and, where there are none, the bytes out; a call with both puts
// the bytes out at 1024).
//
// An address record is 32 bytes: u8 family at 0 (0 Ip4, 1 Ip6), u16 port at 2 and u32 scope at 4
// (little-endian), the 16 address bytes at 8, the rest zero.
import dgram from 'node:dgram'
import dns from 'node:dns'
import net from 'node:net'
import { execFile, spawn } from 'node:child_process'
import { constants as osConstants } from 'node:os'
import { join } from 'node:path'
import { isatty } from 'node:tty'

export const BASE = 0x40000000
const MARK = 1048576
const DATA_SIZE = 65536
const PAYLOAD = 128
const PAYLOAD_OUT_AFTER_IN = 1024

const E = { ACCES: 2, ADDRINUSE: 3, ADDRNOTAVAIL: 4, AFNOSUPPORT: 5, AGAIN: 6, ALREADY: 7, BADF: 8, CONNABORTED: 13, CONNREFUSED: 14, CONNRESET: 15, DESTADDRREQ: 17, EXIST: 20, HOSTUNREACH: 23, INPROGRESS: 26, INVAL: 28, IO: 29, ISCONN: 30, MSGSIZE: 35, NETDOWN: 38, NETUNREACH: 40, NOENT: 44, NOSYS: 52, NOTCONN: 53, NOTSUP: 58, PIPE: 64, SRCH: 71, TIMEDOUT: 73 }
const ERRNO = {
  EACCES: E.ACCES, EPERM: E.ACCES, EADDRINUSE: E.ADDRINUSE, EADDRNOTAVAIL: E.ADDRNOTAVAIL, EAFNOSUPPORT: E.AFNOSUPPORT,
  ECONNABORTED: E.CONNABORTED, ECONNREFUSED: E.CONNREFUSED, ECONNRESET: E.CONNRESET, EHOSTUNREACH: E.HOSTUNREACH,
  EINVAL: E.INVAL, EMSGSIZE: E.MSGSIZE, ENETDOWN: E.NETDOWN, ENETUNREACH: E.NETUNREACH, ENOTCONN: E.NOTCONN,
  EPIPE: E.PIPE, ETIMEDOUT: E.TIMEDOUT, ENOENT: E.NOENT, ESRCH: E.SRCH, ENOTFOUND: E.NOENT, ENODATA: E.NOENT,
}
const errnoOf = (error) => ERRNO[error?.code] ?? E.IO

// The functions in the order of their numbers. Per argument: v a value, l an i64 value, i an
// address going in, o an address coming out, c a u32 output slot, p bytes in (a pointer, then n its
// length), q/r/s bytes / 32-byte records / 16-byte records out (a pointer, then n their capacity).
export const FUNCTIONS = [
  ['sock_open', 'vvc'], ['sock_set_nonblocking', 'vv'], ['sock_bind', 'vi'], ['sock_local_address', 'vo'],
  ['sock_listen', 'vv'], ['sock_accept', 'vco'], ['sock_connect', 'vi'], ['sock_send', 'vpnc'],
  ['sock_recv', 'vqnc'], ['sock_send_to', 'vipnc'], ['sock_recv_from', 'vqnco'], ['sock_shutdown', 'vv'],
  ['sock_close', 'v'], ['resolve', 'pnvvrnc'], ['poll_open', 'c'], ['poll_ctl', 'vvvlv'],
  ['poll_wait', 'vsnlc'], ['poll_wake', 'v'], ['poll_close', 'v'],
  ['pipe', 'cc'], ['handle_read', 'vqncv'], ['handle_write', 'vpnc'], ['handle_close', 'v'],
  ['proc_spawn', 'pnvvvvvvvc'], ['proc_wait', 'vc'], ['proc_kill', 'v'], ['proc_group_kill', 'vv'],
]
const SIZE = { q: 1, r: 32, s: 16 }

// What the processes need from the runner (D5677), set by its main thread: the working directory, the
// preopens (guest name -> host directory), the guest's environment and the runner's own path.
export const context = { cwd: '', tmp: '', preopens: {}, env: {}, runner: '' }

// ---- the Worker side -------------------------------------------------------------------------------

export function hostImports(names, memory, box, data) {
  const state = new Int32Array(box)
  const args = new BigInt64Array(box, 8, 12)
  const bytes = new Uint8Array(data)
  const imports = {}
  for (const name of names) {
    const index = FUNCTIONS.findIndex((entry) => entry[0] === name)
    if (index < 0) {
      imports[name] = () => E.NOSYS
      continue
    }
    const spec = FUNCTIONS[index][1]
    const hasIn = spec.includes('p')
    const hasOut = /[qrs]/.test(spec)
    imports[name] = (...raw) => {
      const mem = new Uint8Array(memory().buffer)
      const slots = []
      let addressOut = 0
      let inPointer = 0
      let outPointer = 0
      let outKind = ''
      let outCap = 0
      for (let k = 0; k < spec.length; k++) {
        const kind = spec[k]
        const value = raw[k]
        args[k] = 0n
        if (kind === 'v') args[k] = BigInt(value >>> 0)
        else if (kind === 'l') args[k] = BigInt.asIntN(64, value)
        else if (kind === 'i') bytes.set(mem.subarray(value >>> 0, (value >>> 0) + 32), 0)
        else if (kind === 'o') addressOut = value >>> 0
        else if (kind === 'c') slots.push(value >>> 0)
        else if (kind === 'p') inPointer = value >>> 0
        else if (kind === 'q' || kind === 'r' || kind === 's') {
          outPointer = value >>> 0
          outKind = kind
        } else if (kind === 'n') {
          if (spec[k - 1] === 'p') {
            const length = Math.min(value >>> 0, (hasOut ? PAYLOAD_OUT_AFTER_IN : DATA_SIZE) - PAYLOAD)
            bytes.set(mem.subarray(inPointer, inPointer + length), PAYLOAD)
            args[k] = BigInt(length)
          } else {
            outCap = Math.min(value >>> 0, Math.floor((DATA_SIZE - (hasIn ? PAYLOAD_OUT_AFTER_IN : PAYLOAD)) / SIZE[outKind]))
            args[k] = BigInt(outCap)
          }
        }
      }
      Atomics.store(state, 1, index)
      Atomics.store(state, 0, 1)
      Atomics.notify(state, 0)
      while (Atomics.load(state, 0) === 1) Atomics.wait(state, 0, 1)
      const status = Atomics.load(state, 26) >>> 0
      Atomics.store(state, 0, 0)
      Atomics.notify(state, 0)
      if (status !== 0) return status
      const out = new Uint8Array(memory().buffer)
      const view = new DataView(data)
      const target = new DataView(memory().buffer)
      slots.forEach((pointer, slot) => target.setUint32(pointer, view.getUint32(64 + 4 * slot, true), true))
      if (addressOut) out.set(bytes.subarray(32, 64), addressOut)
      if (outPointer && slots.length) {
        const count = view.getUint32(64, true)
        const at = hasIn ? PAYLOAD_OUT_AFTER_IN : PAYLOAD
        out.set(bytes.subarray(at, at + count * SIZE[outKind]), outPointer)
      }
      return 0
    }
  }
  return imports
}

// ---- the main thread's side ------------------------------------------------------------------------

// Answers the mailbox until `stop` is called. One request is served at a time; a blocking call is a
// promise that settles when the socket changes, so the event loop keeps running meanwhile. A
// threaded module has a mailbox per thread, all served over one `shared` NetHost (one table of
// handles): each mailbox's calls see that NetHost through a view of their own data buffer.
export function serve(box, data, shared) {
  const bytesView = new Uint8Array(data)
  const state = new Int32Array(box)
  const args = new BigInt64Array(box, 8, 12)
  let host = new NetHost(bytesView)
  if (shared) {
    host = Object.create(shared)
    host.data = bytesView
    host.view = new DataView(data)
  }
  let stopped = false
  const waitWhile = async (value) => {
    while (!stopped && Atomics.load(state, 0) === value) {
      const waiting = Atomics.waitAsync(state, 0, value)
      if (waiting.async) await waiting.value
    }
  }
  ;(async () => {
    while (!stopped) {
      await waitWhile(0)
      if (stopped) break
      const [, spec] = FUNCTIONS[Atomics.load(state, 1)]
      const given = Array.from({ length: spec.length }, (_, k) => (spec[k] === 'l' ? args[k] : Number(args[k])))
      let status
      try {
        status = await host.call(Atomics.load(state, 1), given)
      } catch (error) {
        status = errnoOf(error)
      }
      if (process.env.NEPER_HOST_TRACE) process.stderr.write(`neper_host ${FUNCTIONS[Atomics.load(state, 1)][0]}(${given.join(',')}) = ${status} ${Buffer.from(bytesView.slice(0, 72)).toString('hex')}\n`)
      Atomics.store(state, 26, status)
      Atomics.store(state, 0, 2)
      Atomics.notify(state, 0)
      await waitWhile(2)
    }
  })()
  return {
    stop() {
      stopped = true
      Atomics.notify(state, 0)
      if (!shared) host.closeAll()
    },
  }
}

// Two turns of the loop, so a packet that already arrived at the OS has been read by libuv before a
// call answers "nothing there".
const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))

function addressBytes(text) {
  const out = new Uint8Array(16)
  if (net.isIPv4(text)) {
    text.split('.').forEach((part, at) => (out[at] = Number(part)))
    return out
  }
  let [body] = text.split('%')
  let tail = []
  const dotted = body.lastIndexOf('.')
  if (dotted >= 0) {
    const cut = body.lastIndexOf(':')
    tail = body.slice(cut + 1).split('.').map(Number)
    body = `${body.slice(0, cut + 1)}0:0`
  }
  const [head, rest] = body.split('::')
  const groups = (part) => (part ? part.split(':').map((group) => parseInt(group, 16)) : [])
  const first = groups(head)
  const last = rest === undefined ? [] : groups(rest)
  const all = rest === undefined ? first : [...first, ...Array(8 - first.length - last.length).fill(0), ...last]
  all.forEach((group, at) => {
    out[2 * at] = group >> 8
    out[2 * at + 1] = group & 255
  })
  if (tail.length) tail.forEach((byte, at) => (out[12 + at] = byte))
  return out
}

function textOfAddress(bytes) {
  if (bytes[0] === 0) return `${bytes[8]}.${bytes[9]}.${bytes[10]}.${bytes[11]}`
  const groups = []
  for (let at = 0; at < 8; at++) groups.push(((bytes[8 + 2 * at] << 8) | bytes[9 + 2 * at]).toString(16))
  const scope = bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24)
  return groups.join(':') + (scope ? `%${scope >>> 0}` : '')
}

function writeAddress(view, at, text, port, family) {
  const v6 = family === 6 || family === 'IPv6' || (family === undefined && net.isIPv6(text))
  view.setUint8(at, v6 ? 1 : 0)
  view.setUint16(at + 2, port, true)
  const scope = /%(\d+)$/.exec(text)
  view.setUint32(at + 4, scope ? Number(scope[1]) : 0, true)
  const raw = addressBytes(text)
  for (let k = 0; k < (v6 ? 16 : 4); k++) view.setUint8(at + 8 + k, raw[k])
}

function readAddress(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, 32)
  const family = view.getUint8(0)
  const port = view.getUint16(2, true)
  const record = bytes.slice(0, 32)
  let host = textOfAddress(record)
  // Connecting to "any" means this machine, as it does in the kernel.
  if (host === '0.0.0.0') host = '127.0.0.1'
  else if (host === '0:0:0:0:0:0:0:0') host = '::1'
  return { family, port, host }
}

const wildcard = (family) => (family === 1 ? '::' : '0.0.0.0')

class Sock {
  constructor(family, kind) {
    this.family = family
    this.kind = kind === 1 || kind === 'datagram' ? 'datagram' : 'stream'
    this.nonblocking = false
    this.listeners = new Set()
    this.pollers = new Set()
    this.bound = null
    this.server = null
    this.queue = []
    this.conn = null
    this.state = 'idle'
    this.connectError = 0
    this.rx = []
    this.rxBytes = 0
    this.paused = false
    this.ended = false
    this.readShut = false
    this.writeShut = false
    this.broken = 0
    this.readError = 0
    this.dg = null
    this.dgq = []
    this.dgConnected = false
  }

  changed() {
    for (const listener of [...this.listeners]) listener()
    for (const poller of [...this.pollers]) poller.touch()
  }

  waitUntil(test) {
    return new Promise((resolve) => {
      const check = () => {
        if (!test()) return
        this.listeners.delete(check)
        resolve()
      }
      this.listeners.add(check)
      check()
    })
  }

  // Bits: 1 readable, 2 writable, 4 closed, 8 failed.
  ready() {
    let flags = 0
    if (this.rxBytes > 0 || this.queue.length || this.dgq.length || this.ended || this.readShut || this.readError) flags |= 1
    if (this.kind === 'datagram' ? true : this.state === 'connected' && !this.broken && this.conn.writableLength < MARK) flags |= 2
    if (this.state === 'failed') flags |= 2 | 8
    if (this.ended || this.broken) flags |= 4
    if (this.readError) flags |= 8
    return flags
  }

  attach(conn) {
    this.conn = conn
    conn.on('data', (chunk) => {
      if (this.readShut) return
      this.rx.push(chunk)
      this.rxBytes += chunk.length
      if (this.rxBytes >= MARK && !this.paused) {
        this.paused = true
        conn.pause()
      }
      this.changed()
    })
    conn.on('end', () => {
      this.ended = true
      this.changed()
    })
    conn.on('drain', () => this.changed())
    conn.on('error', (error) => {
      if (this.state === 'connecting') {
        this.state = 'failed'
        this.connectError = errnoOf(error)
      } else {
        this.broken = errnoOf(error)
        this.readError = this.readError || this.broken
      }
      this.changed()
    })
    conn.on('close', () => {
      if (this.state === 'connected') this.ended = true
      this.changed()
    })
  }

  take(into, max) {
    const count = Math.min(max, this.rxBytes)
    let at = 0
    while (at < count) {
      const chunk = this.rx[0]
      const n = Math.min(chunk.length, count - at)
      into.set(chunk.subarray(0, n), at)
      at += n
      if (n === chunk.length) this.rx.shift()
      else this.rx[0] = chunk.subarray(n)
    }
    this.rxBytes -= count
    if (this.paused && this.rxBytes < MARK) {
      this.paused = false
      this.conn.resume()
    }
    return count
  }

  address() {
    if (this.server) return this.server.address()
    if (this.dg && this.bound) return this.dg.address()
    if (this.conn) return { address: this.conn.localAddress, port: this.conn.localPort, family: this.conn.localFamily }
    return null
  }

  destroy() {
    for (const poller of this.pollers) poller.entries.delete(this.id)
    this.pollers.clear()
    this.queue.splice(0).forEach((conn) => conn.destroy())
    this.server?.close()
    this.dg?.close()
    if (this.conn) {
      if (this.state === 'connected' && !this.conn.destroyed) {
        this.conn.end()
        this.conn.once('finish', () => this.conn.destroy())
      } else this.conn.destroy()
    }
    this.listeners.clear()
  }
}

// A host pipe (D5677 as built by C204): bytes written to the write end wait here for the read end. It
// borrows Sock's queue (`rx`, `take`) and its waiting, so a blocked read is a promise like a socket's.
class Pipe {
  constructor() {
    this.listeners = new Set()
    this.rx = []
    this.rxBytes = 0
    this.paused = false
    this.writers = 1
    this.readers = 1
    this.feeders = new Set()
    this.conn = { pause: () => this.feeders.forEach((s) => s.pause()), resume: () => this.feeders.forEach((s) => s.resume()) }
  }

  changed() {
    for (const listener of [...this.listeners]) listener()
  }
}
Pipe.prototype.waitUntil = Sock.prototype.waitUntil
Pipe.prototype.take = Sock.prototype.take

class Poller {
  constructor() {
    this.entries = new Map()
    this.woken = false
    this.waiter = null
  }

  events(cap) {
    const found = []
    for (const [id, entry] of this.entries) {
      const flags = entry.sock.ready()
      const shown = (flags & 12) | (flags & entry.interest & 3)
      if (shown) found.push([entry.token, shown])
      if (found.length === cap) break
    }
    return found
  }

  touch() {
    if (this.waiter && (this.woken || this.events(1).length)) this.waiter()
  }
}

export class NetHost {
  constructor(data) {
    this.data = data
    this.view = new DataView(data.buffer, data.byteOffset, data.length)
    this.ids = { next: BASE }
    this.socks = new Map()
    this.pollers = new Map()
    this.ends = new Map()
    this.procs = new Map()
  }

  closeAll() {
    for (const sock of this.socks.values()) {
      sock.conn?.destroy()
      sock.destroy()
    }
    this.socks.clear()
    for (const poller of this.pollers.values()) poller.waiter?.()
    this.pollers.clear()
    // The module ended: its children go on (as orphans do), but the runner no longer waits for them or reads their pipes.
    for (const proc of this.procs.values()) {
      proc.child.unref()
      for (const stream of [proc.child.stdin, proc.child.stdout, proc.child.stderr]) stream?.destroy()
    }
  }

  slot(index, value) {
    this.view.setUint32(64 + 4 * index, value, true)
  }

  async call(index, a) {
    const name = FUNCTIONS[index][0]
    switch (name) {
      case 'poll_open': {
        this.pollers.set(this.ids.next, new Poller())
        this.slot(0, this.ids.next++)
        return 0
      }
      case 'poll_ctl': return this.pollCtl(...a)
      case 'poll_wait': return this.pollWait(a[0], a[2], a[3])
      case 'poll_wake': {
        const poller = this.pollers.get(a[0])
        if (!poller) return E.BADF
        poller.woken = true
        poller.touch()
        return 0
      }
      case 'poll_close': {
        const poller = this.pollers.get(a[0])
        if (!poller) return E.BADF
        for (const { sock } of poller.entries.values()) sock.pollers.delete(poller)
        this.pollers.delete(a[0])
        poller.waiter?.()
        return 0
      }
      case 'sock_open': {
        const sock = new Sock(a[0], a[1])
        sock.id = this.ids.next
        this.socks.set(this.ids.next, sock)
        this.slot(0, this.ids.next++)
        return 0
      }
      case 'resolve': return this.resolve(a[1], a[2], a[3], a[5])
      case 'pipe': return this.pipeOpen()
      case 'proc_spawn': return this.procSpawn(a)
    }
    if (name.startsWith('proc_')) {
      const proc = this.procs.get(a[0])
      if (!proc) return E.BADF
      if (name === 'proc_wait') {
        await proc.waitUntil(() => proc.status !== null)
        this.slot(0, proc.status >>> 0)
        return 0
      }
      if (name === 'proc_kill') {
        proc.child.kill('SIGKILL')
        return 0
      }
      return this.procGroupKill(proc, a[1] !== 0)
    }
    if (name.startsWith('handle_')) {
      const end = this.ends.get(a[0])
      if (!end) return E.BADF
      if (name === 'handle_read') return this.pipeRead(end, a[2], a[4] !== 0)
      if (name === 'handle_write') return this.pipeWrite(end, a[2])
      return this.pipeClose(a[0], end)
    }
    const sock = this.socks.get(a[0])
    if (!sock) return E.BADF
    switch (name) {
      case 'sock_set_nonblocking': sock.nonblocking = a[1] !== 0; return 0
      case 'sock_bind': return this.bind(sock)
      case 'sock_local_address': return this.localAddress(sock)
      case 'sock_listen': return this.listen(sock)
      case 'sock_accept': return this.accept(sock)
      case 'sock_connect': return this.connect(sock)
      case 'sock_send': return this.send(sock, a[2])
      case 'sock_recv': return this.recv(sock, a[2], false)
      case 'sock_send_to': return this.sendTo(sock, a[3])
      case 'sock_recv_from': return this.recv(sock, a[2], true)
      case 'sock_shutdown': return this.shutdown(sock, a[1])
      case 'sock_close':
        this.socks.delete(a[0])
        sock.destroy()
        return 0
    }
    return E.NOSYS
  }

  // A pipe's ends are handles of their own (`ends`: the pipe and which end); a read waits for bytes or
  // for the last writer to close, a write waits below 1 MiB unread and fails with EPIPE once the reader
  // is gone. A nonblocking read answers EAGAIN: the bytes of every earlier write are already here.
  pipeOpen() {
    const pipe = new Pipe()
    this.ends.set(this.ids.next, { pipe, writing: false })
    this.slot(0, this.ids.next++)
    this.ends.set(this.ids.next, { pipe, writing: true })
    this.slot(1, this.ids.next++)
    return 0
  }

  async pipeRead(end, capacity, nonblocking) {
    if (end.writing) return E.BADF
    const { pipe } = end
    while (pipe.rxBytes === 0 && pipe.writers > 0) {
      if (nonblocking) return E.AGAIN
      await pipe.waitUntil(() => pipe.rxBytes > 0 || pipe.writers === 0)
    }
    this.slot(0, pipe.take(this.data.subarray(PAYLOAD), capacity))
    return 0
  }

  async pipeWrite(end, length) {
    if (!end.writing) return E.BADF
    const { pipe } = end
    while (pipe.readers > 0 && pipe.rxBytes >= MARK) await pipe.waitUntil(() => pipe.rxBytes < MARK || pipe.readers === 0)
    if (pipe.readers === 0) return E.PIPE
    pipe.rx.push(Buffer.from(this.data.subarray(PAYLOAD, PAYLOAD + length)))
    pipe.rxBytes += length
    pipe.changed()
    this.slot(0, length)
    return 0
  }

  pipeClose(id, end) {
    this.ends.delete(id)
    if (end.writing) end.pipe.writers--
    else end.pipe.readers--
    end.pipe.changed()
    return 0
  }

  // D5677. The buffer holds the argv strings, then the env strings (each NUL-terminated), then the cwd (a
  // guest path, no terminator). A child whose argv[0] ends in .wasm runs through this runner, since its
  // image is a module; any other is spawned as named. The three stdio words are 0-2 (the runner's own
  // stream) or a pipe end made by `pipe`.
  async procSpawn(a) {
    const buffer = Buffer.from(this.data.subarray(PAYLOAD, PAYLOAD + a[1]))
    const items = []
    let at = 0
    for (let k = 0; k < a[2] + a[3]; k++) {
      const end = buffer.indexOf(0, at)
      if (end < 0) return E.INVAL
      items.push(buffer.toString('utf8', at, end))
      at = end + 1
    }
    const argv = items.slice(0, a[2])
    const guestCwd = buffer.toString('utf8', at, at + a[5])
    if (!argv.length) return E.INVAL
    const wasm = argv[0].endsWith('.wasm')
    const given = []
    for (let k = 0; k < 3; k++) {
      const id = a[6 + k]
      if (id <= 2) {
        given.push(null)
        continue
      }
      const end = this.ends.get(id)
      if (!end) return id >= BASE ? E.BADF : E.NOTSUP
      if (end.writing === (k === 0)) return E.BADF
      given.push(end)
    }
    const win = process.platform === 'win32'
    const key = (name) => (win ? name.toUpperCase() : name)
    const merged = new Map(Object.entries(a[4] & 1 ? (wasm ? context.env : process.env) : {}).map(([n, v]) => [key(n), [n, v]]))
    for (const item of items.slice(a[2])) {
      const cut = item.indexOf('=')
      if (cut > 0) merged.set(key(item.slice(0, cut)), [item.slice(0, cut), item.slice(cut + 1)])
    }
    merged.delete('NEPER_PWD')
    if (wasm && guestCwd !== '' && guestCwd !== '/') merged.set('NEPER_PWD', ['NEPER_PWD', guestCwd])
    let env = Object.fromEntries(merged.values())
    // The child runner is a node process: it gets the module's whole environment as JSON (its own is a real
    // TMPDIR for the scratch directory, which it points the module's at /tmp again, and SystemRoot).
    if (wasm) env = { NEPER_GUEST_ENV: JSON.stringify(env), TMPDIR: context.tmp, TMP: context.tmp, TEMP: context.tmp, ...(win && process.env.SystemRoot ? { SystemRoot: process.env.SystemRoot } : {}) }
    const grouped = (a[4] & 2) !== 0
    const child = spawn(wasm ? process.execPath : argv[0], wasm ? ['--no-warnings', context.runner, this.hostPath(argv[0]), ...argv.slice(1)] : argv.slice(1), {
      cwd: wasm || guestCwd === '' ? context.cwd : this.hostPath(guestCwd),
      env,
      windowsHide: true,
      // libuv puts a Windows child in a job that dies with this process; an orphan must outlive it, unless a console is shared.
      detached: win ? ![0, 1, 2].some((fd) => isatty(fd)) : grouped,
      stdio: given.map((end) => (end ? 'pipe' : 'inherit')),
    })
    const failure = await new Promise((resolve) => {
      child.once('spawn', () => resolve(0))
      child.once('error', (error) => resolve(errnoOf(error)))
    })
    if (failure) return failure
    child.on('error', () => {})
    const proc = { child, status: null, listeners: new Set(), group: grouped }
    proc.waitUntil = Sock.prototype.waitUntil
    child.once('exit', (code, signal) => {
      proc.status = code ?? 128 + (osConstants.signals[signal] ?? 0)
      for (const listener of [...proc.listeners]) listener()
    })
    if (given[0]) this.feedChild(given[0].pipe, child.stdin)
    if (given[1]) this.drainChild(given[1].pipe, child.stdout)
    if (given[2]) this.drainChild(given[2].pipe, child.stderr)
    this.procs.set(this.ids.next, proc)
    this.slot(0, this.ids.next++)
    return 0
  }

  // A guest path as a host path: /tmp, /home and /exe are the runner's directories, any other is under the
  // working directory (the root mount).
  hostPath(guest) {
    for (const [name, directory] of Object.entries(context.preopens)) {
      if (name.startsWith('/') && (guest === name || guest.startsWith(`${name}/`))) return join(directory, guest.slice(name.length))
    }
    return join(context.cwd, guest)
  }

  // The child's stdout or stderr is a write end of a host pipe: its bytes join the pipe's queue, and the
  // pipe has one more writer until the stream closes.
  drainChild(pipe, stream) {
    pipe.writers++
    pipe.feeders.add(stream)
    stream.on('data', (chunk) => {
      if (pipe.readers === 0) return
      pipe.rx.push(chunk)
      pipe.rxBytes += chunk.length
      if (pipe.rxBytes >= MARK && !pipe.paused) {
        pipe.paused = true
        pipe.conn.pause()
      }
      pipe.changed()
    })
    stream.on('close', () => {
      pipe.feeders.delete(stream)
      pipe.writers--
      pipe.changed()
    })
  }

  // The child's stdin is the read end of a host pipe: what is written to the pipe is written on, and the
  // end of the pipe (the last writer closed) ends the child's stdin.
  async feedChild(pipe, stream) {
    pipe.readers++
    stream.on('error', () => {})
    stream.on('close', () => {
      pipe.readers--
      pipe.changed()
    })
    while (!stream.destroyed) {
      await pipe.waitUntil(() => pipe.rxBytes > 0 || pipe.writers === 0 || stream.destroyed)
      if (stream.destroyed) return
      if (pipe.rxBytes === 0) {
        stream.end()
        return
      }
      const chunk = Buffer.alloc(Math.min(pipe.rxBytes, 65536))
      pipe.take(chunk, chunk.length)
      if (!stream.write(chunk)) await new Promise((resolve) => (stream.once('drain', resolve), stream.once('close', resolve)))
    }
  }

  // The group: a negative pid on POSIX (the child leads its own group when spawned with the group flag),
  // the process tree on Windows, where a polite stop does not reach a console program, so it falls back to
  // the forced one.
  async procGroupKill(proc, force) {
    const { pid } = proc.child
    if (process.platform === 'win32') {
      if (proc.status !== null) return 0 // a dead root leaves taskkill nothing to walk
      const run = (flags) => new Promise((resolve) => execFile('taskkill', ['/pid', String(pid), '/T', ...flags], { windowsHide: true }, (error) => resolve(!error)))
      if (!(await run(force ? ['/F'] : [])) && !force) await run(['/F'])
      return 0
    }
    try {
      process.kill(proc.group ? -pid : pid, force ? 'SIGKILL' : 'SIGTERM')
    } catch (error) {
      if (error.code !== 'ESRCH') return errnoOf(error)
    }
    return 0
  }

  ensureDatagram(sock) {
    if (sock.dg) return
    const dg = dgram.createSocket({ type: sock.family === 1 ? 'udp6' : 'udp4' })
    sock.dg = dg
    dg.on('message', (message, info) => {
      sock.dgq.push({ message, info })
      sock.changed()
    })
    dg.on('error', (error) => {
      sock.readError = errnoOf(error)
      sock.changed()
    })
  }

  async bind(sock) {
    const { port, host } = readAddress(this.data)
    if (sock.bound) return E.INVAL
    if (sock.kind === 'datagram') {
      this.ensureDatagram(sock)
      const dg = sock.dg
      const failed = await new Promise((resolve) => {
        const fail = (error) => resolve(errnoOf(error))
        dg.once('error', fail)
        dg.bind({ port, address: host }, () => {
          dg.off('error', fail)
          resolve(0)
        })
      })
      if (failed) {
        dg.close()
        sock.dg = null
        return failed
      }
    }
    sock.bound = { port, host }
    return 0
  }

  // A bound stream socket is listened by whichever of `listen` and `local_address` comes first,
  // so the port a bind to 0 got is real before the program asks for it.
  async listen(sock) {
    if (sock.kind !== 'stream') return E.INVAL
    if (sock.server) return 0
    if (sock.conn) return E.INVAL
    const { port, host } = sock.bound ?? { port: 0, host: wildcard(sock.family) }
    const server = net.createServer({ pauseOnConnect: true, allowHalfOpen: true })
    server.on('connection', (conn) => {
      sock.queue.push(conn)
      sock.changed()
    })
    const failed = await new Promise((resolve) => {
      server.once('error', (error) => resolve(errnoOf(error)))
      server.listen({ host, port, backlog: 511 }, () => resolve(0))
    })
    if (failed) {
      server.close()
      return failed
    }
    server.on('error', () => {})
    sock.server = server
    if (!sock.bound) sock.bound = { port, host }
    return 0
  }

  async localAddress(sock) {
    if (sock.kind === 'stream' && sock.bound && !sock.server && !sock.conn) {
      const failed = await this.listen(sock)
      if (failed) return failed
    }
    const found = sock.address()
    const view = new DataView(this.data.buffer, this.data.byteOffset + 32, 32)
    for (let k = 0; k < 32; k++) view.setUint8(k, 0)
    if (!found) {
      view.setUint8(0, sock.family)
      return 0
    }
    writeAddress(view, 0, found.address, found.port, found.family)
    return 0
  }

  async accept(sock) {
    if (!sock.server) return E.INVAL
    if (!sock.queue.length) {
      if (sock.nonblocking) {
        await settle()
        if (!sock.queue.length) return E.AGAIN
      } else await sock.waitUntil(() => sock.queue.length)
    }
    const conn = sock.queue.shift()
    const accepted = new Sock(sock.family, 'stream')
    accepted.id = this.ids.next
    accepted.state = 'connected'
    accepted.attach(conn)
    conn.resume()
    this.socks.set(this.ids.next, accepted)
    this.slot(0, this.ids.next++)
    const view = new DataView(this.data.buffer, this.data.byteOffset + 32, 32)
    for (let k = 0; k < 32; k++) view.setUint8(k, 0)
    writeAddress(view, 0, conn.remoteAddress, conn.remotePort, conn.remoteFamily)
    return 0
  }

  async connect(sock) {
    const { family, port, host } = readAddress(this.data)
    if (sock.kind === 'datagram') {
      this.ensureDatagram(sock)
      const failed = await new Promise((resolve) => {
        sock.dg.once('error', (error) => resolve(errnoOf(error)))
        sock.dg.connect(port, host, () => resolve(0))
      })
      if (!failed) sock.dgConnected = true
      return failed
    }
    if (sock.state === 'connected') return E.ISCONN
    if (sock.server) return E.INVAL
    if (sock.state === 'idle') {
      const options = { host, port, family: family === 1 ? 6 : 4, allowHalfOpen: true }
      if (sock.bound) {
        options.localAddress = sock.bound.host
        options.localPort = sock.bound.port
      }
      sock.state = 'connecting'
      const conn = net.createConnection(options)
      sock.attach(conn)
      conn.once('connect', () => {
        sock.state = 'connected'
        sock.changed()
      })
      if (sock.nonblocking) return E.INPROGRESS
    } else if (sock.nonblocking) {
      if (sock.state === 'connecting') return E.ALREADY
    }
    if (sock.state === 'connecting') await sock.waitUntil(() => sock.state !== 'connecting')
    if (sock.state === 'failed') {
      const code = sock.connectError
      sock.state = 'idle'
      sock.connectError = 0
      sock.conn = null
      return code
    }
    return 0
  }

  async send(sock, length) {
    if (sock.kind === 'datagram') {
      if (!sock.dgConnected) return E.DESTADDRREQ
      return this.datagramSend(sock, length, null)
    }
    if (sock.state !== 'connected') return sock.state === 'failed' ? sock.connectError : E.NOTCONN
    if (sock.broken || sock.writeShut || sock.conn.destroyed) return E.PIPE
    while (sock.conn.writableLength >= MARK) {
      if (sock.nonblocking) return E.AGAIN
      await sock.waitUntil(() => sock.conn.writableLength < MARK || sock.broken)
      if (sock.broken) return E.PIPE
    }
    sock.conn.write(Buffer.from(this.data.subarray(PAYLOAD, PAYLOAD + length)), (error) => {
      if (error) {
        sock.broken = errnoOf(error)
        sock.changed()
      }
    })
    this.slot(0, length)
    return 0
  }

  async datagramSend(sock, length, target) {
    this.ensureDatagram(sock)
    const message = Buffer.from(this.data.subarray(PAYLOAD, PAYLOAD + length))
    const failed = await new Promise((resolve) => {
      const done = (error) => resolve(error ? errnoOf(error) : 0)
      if (target) sock.dg.send(message, target.port, target.host, done)
      else sock.dg.send(message, done)
    })
    if (!failed) this.slot(0, length)
    return failed
  }

  async sendTo(sock, length) {
    if (sock.kind !== 'datagram') return E.NOTCONN
    return this.datagramSend(sock, length, readAddress(this.data))
  }

  async recv(sock, capacity, withAddress) {
    const at = PAYLOAD
    const out = this.data.subarray(at, at + capacity)
    if (sock.kind === 'datagram') {
      if (!sock.dgq.length) {
        if (sock.readError) {
          const code = sock.readError
          sock.readError = 0
          return code
        }
        if (sock.nonblocking) {
          await settle()
          if (!sock.dgq.length) return E.AGAIN
        } else await sock.waitUntil(() => sock.dgq.length)
      }
      const { message, info } = sock.dgq.shift()
      const count = Math.min(capacity, message.length)
      out.set(message.subarray(0, count))
      this.slot(0, count)
      if (withAddress) this.writeFrom(info.address, info.port, info.family)
      return 0
    }
    if (sock.state !== 'connected' && !sock.ended) return sock.state === 'failed' ? sock.connectError : E.NOTCONN
    for (;;) {
      if (sock.rxBytes > 0) {
        this.slot(0, sock.take(out, capacity))
        break
      }
      if (sock.readError) {
        const code = sock.readError
        sock.readError = 0
        return code
      }
      if (sock.ended || sock.readShut) {
        this.slot(0, 0)
        break
      }
      if (sock.nonblocking) {
        await settle()
        if (sock.rxBytes > 0 || sock.ended || sock.readError) continue
        return E.AGAIN
      }
      await sock.waitUntil(() => sock.rxBytes > 0 || sock.ended || sock.readError || sock.readShut)
    }
    if (withAddress) this.writeFrom(sock.conn.remoteAddress, sock.conn.remotePort, sock.conn.remoteFamily)
    return 0
  }

  writeFrom(address, port, family) {
    const view = new DataView(this.data.buffer, this.data.byteOffset + 32, 32)
    for (let k = 0; k < 32; k++) view.setUint8(k, 0)
    if (address) writeAddress(view, 0, address, port, family)
  }

  shutdown(sock, how) {
    if (sock.kind === 'datagram') return 0
    if (sock.state !== 'connected') return E.NOTCONN
    if (how === 0 || how === 2) {
      sock.readShut = true
      sock.rx = []
      sock.rxBytes = 0
      sock.changed()
    }
    if (how === 1 || how === 2) {
      sock.writeShut = true
      sock.conn.end()
    }
    return 0
  }

  async resolve(length, port, family, cap) {
    const name = Buffer.from(this.data.subarray(PAYLOAD, PAYLOAD + length)).toString('utf8')
    if (!name) return E.NOENT
    let found
    try {
      found = await dns.promises.lookup(name, { all: true, family: family === 1 ? 6 : 4 })
    } catch (error) {
      return errnoOf(error)
    }
    const view = new DataView(this.data.buffer, this.data.byteOffset + PAYLOAD_OUT_AFTER_IN, 32 * cap)
    found = found.slice(0, cap)
    found.forEach((entry, at) => writeAddress(new DataView(view.buffer, view.byteOffset + 32 * at, 32), 0, entry.address, port, entry.family))
    this.slot(0, found.length)
    return 0
  }

  pollCtl(poller, op, handle, token, interest) {
    const owner = this.pollers.get(poller)
    if (!owner) return E.BADF
    const sock = this.socks.get(handle)
    if (op === 2) {
      if (!owner.entries.delete(handle)) return E.NOENT
      sock?.pollers.delete(owner)
      return 0
    }
    if (!sock) return E.BADF
    if (op === 0 && owner.entries.has(handle)) return E.EXIST
    if (op === 1 && !owner.entries.has(handle)) return E.NOENT
    owner.entries.set(handle, { sock, token: BigInt.asUintN(64, token), interest })
    sock.pollers.add(owner)
    owner.touch()
    return 0
  }

  async pollWait(id, cap, timeout) {
    const poller = this.pollers.get(id)
    if (!poller) return E.BADF
    let found = poller.events(cap)
    if (!found.length && !poller.woken && timeout === 0n) {
      await settle()
      found = poller.events(cap)
    }
    if (!found.length && !poller.woken && timeout !== 0n) {
      await new Promise((resolve) => {
        let timer = null
        poller.waiter = () => {
          clearTimeout(timer)
          poller.waiter = null
          resolve()
        }
        if (timeout > 0n) timer = setTimeout(poller.waiter, Math.max(1, Number(timeout / 1000000n)))
      })
      found = poller.events(cap)
    }
    poller.woken = false
    found.forEach(([token, flags], at) => {
      this.view.setBigUint64(PAYLOAD + 16 * at, token, true)
      this.view.setUint32(PAYLOAD + 16 * at + 8, flags, true)
      this.view.setUint32(PAYLOAD + 16 * at + 12, 0, true)
    })
    this.slot(0, found.length)
    return 0
  }
}
