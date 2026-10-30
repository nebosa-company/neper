// A host for wasm32-wasi modules written by `neper build --target wasm32-wasi` (D5678): WASI preview 1
// over an in-memory file system, in one ES module with no dependency, for a page and for Node 22 or later.
//
//   import { run } from './neper-host.js'
//   const { exitCode, files } = await run(source, { args, env, files, stdout, stderr })
//   node lib/wasm/neper-host.js FILE.wasm [ARGS...]      (the file is a command when it is the main module)
//
// `source` is a URL, a Response, bytes or a WebAssembly.Module. The module always runs in a dedicated
// module Worker made from this file's URL, never on the calling thread; a plain module needs no
// SharedArrayBuffer, so a page without special headers runs it.
//
// What the module sees: `.` (fd 3, which os.wasi.e mounts as `/`), `/exe` (fd 4, holding the module as
// /exe/NAME.wasm, which is also args[0]), `/tmp` (fd 5) and `/home` (fd 6). `files` seeds `/` and comes back
// as path -> Uint8Array for every file left under `/` (not /tmp or /home). The environment is TMPDIR, TMP, TEMP
// = /tmp and HOME, USERPROFILE = /home, then `env`. Exactly the 25 WASI functions os.wasi.e imports are
// implemented; any other wasi_snapshot_preview1 or neper_host import answers ENOSYS (52).
//
// Exit status: the module's; 134 for the engine's call stack running out (a Neper trap exits 134 by itself),
// 1 for any other engine error (stack on stderr), 125 for a module that does not compile or link (what
// scripts/wasm-sweep.sh counts as invalid, as with run-wasm.mjs).
//
// A module built with --threads (it imports env.memory, D5671) runs with the calling thread as the host, which
// must therefore be one that can make Workers and may block no longer than a WASI call (a page's main thread, the
// importing thread under Node): it owns the shared memory and the file system, and every wasm thread is a Worker
// whose WASI imports are mailbox calls to it (D5679, D5674's protocol). On a page that is not cross-origin
// isolated, run() rejects with one sentence saying how to serve it. `messages: true` makes the threads ping the
// host instead of the host waiting with Atomics.waitAsync (the default where that is missing).

import * as windowing from './window.js'

const isNode = !!globalThis.process?.versions?.node
const wt = isNode ? await import('node:worker_threads') : null
const inWorker = isNode ? !wt.isMainThread : typeof WorkerGlobalScope !== 'undefined' && globalThis instanceof WorkerGlobalScope

// WASI errno numbers
const E = { ACCES: 2, BADF: 8, BUSY: 10, EXIST: 20, INVAL: 28, ISDIR: 31, LOOP: 32, NOENT: 44, NOSYS: 52, NOTDIR: 54, NOTEMPTY: 55, SPIPE: 70, NOTCAPABLE: 76 }
const DIR = 3, REG = 4, LINK = 7
const RIGHT_READ = 2n, RIGHT_WRITE = 64n
const encoder = new TextEncoder()
const decoder = new TextDecoder()

class Exit { constructor(code) { this.code = code } }
class Errno { constructor(code) { this.code = code } }
const fail = (code) => { throw new Errno(code) }

// ---- the in-memory tree ----------------------------------------------------------------------------------------

const stamp = () => BigInt(Date.now()) * 1000000n
let inodes = 1

function node(type, parent, extra) {
  const t = stamp()
  return { type, parent, ino: inodes++, atim: t, mtim: t, ctim: t, ...extra }
}
const newDir = (parent) => node(DIR, parent, { entries: new Map() })
const newFile = (parent, bytes) => node(REG, parent, { data: bytes ?? new Uint8Array(0), size: bytes?.length ?? 0 })
const touch = (n) => { n.mtim = n.ctim = stamp() }

function addEntry(dir, name, child) {
  child.parent = dir
  dir.entries.set(name, child)
  touch(dir)
}

function writeAt(file, position, bytes) {
  const end = position + bytes.length
  if (end > file.data.length) {
    const grown = new Uint8Array(Math.max(end, file.data.length * 2, 64))
    grown.set(file.data.subarray(0, file.size))
    file.data = grown
  }
  file.data.set(bytes, position)
  if (end > file.size) file.size = end
  touch(file)
}

function truncate(file, size) {
  if (size < file.size) file.data.fill(0, size, file.size)
  else if (size > file.data.length) {
    const grown = new Uint8Array(size)
    grown.set(file.data.subarray(0, file.size))
    file.data = grown
  }
  file.size = size
  touch(file)
}

// The node `path` names under the directory descriptor `base`, following links the way WASI says: every
// step but the last always, the last when `follow` (or the path ends in '/'). `..` past the descriptor's
// preopened root is ENOTCAPABLE, as is an absolute path or link text. Answers { parent, name, node }: node
// is undefined for a name that is not there, and name is null when the path ends in `.` or `..`.
function lookup(base, path, follow) {
  if (base.kind !== 'dir') fail(E.NOTDIR)
  if (path.length === 0) fail(E.NOENT)
  if (path[0] === '/') fail(E.NOTCAPABLE)
  const trailing = path.endsWith('/')
  const queue = path.split('/').filter(Boolean)
  let cur = base.node
  let links = 0
  for (let i = 0; i < queue.length; ) {
    const part = queue[i]
    const last = i === queue.length - 1
    if (part === '.' || part === '..') {
      if (part === '..') {
        if (cur === base.root) fail(E.NOTCAPABLE)
        cur = cur.parent
      }
      if (last) return { parent: cur.parent, name: null, node: cur }
      i++
      continue
    }
    const child = cur.entries.get(part)
    if (child?.type === LINK && (!last || follow || trailing)) {
      if (++links > 40) fail(E.LOOP)
      if (child.target[0] === '/') fail(E.NOTCAPABLE)
      if (child.target === '') fail(E.NOENT)
      queue.splice(i, 1, ...child.target.split('/').filter(Boolean))
      continue
    }
    if (last) {
      if (trailing && child && child.type !== DIR) fail(E.NOTDIR)
      return { parent: cur, name: part, node: child }
    }
    if (!child) fail(E.NOENT)
    if (child.type !== DIR) fail(E.NOTDIR)
    cur = child
    i++
  }
  return { parent: cur.parent, name: null, node: cur }
}

function isEmptyDir(n) { return n.entries.size === 0 }
function within(n, ancestor) { for (; n; n = n.parent) if (n === ancestor) return true; return false }

// ---- WASI --------------------------------------------------------------------------------------------------------

function makeWasi({ args, env, files, exe, memory, out }) {
  const fds = new Map()
  const preopen = (fd, name, dir) => fds.set(fd, { kind: 'dir', node: dir, root: dir, rights: -1n, pre: name })
  const rootDir = newDir(null)
  const exeDir = newDir(null)
  addEntry(exeDir, exe.name, newFile(exeDir, exe.bytes))
  fds.set(0, { kind: 'stdio', rights: RIGHT_READ })
  fds.set(1, { kind: 'stdio', rights: RIGHT_WRITE })
  fds.set(2, { kind: 'stdio', rights: RIGHT_WRITE })
  preopen(3, '.', rootDir)
  preopen(4, '/exe', exeDir)
  preopen(5, '/tmp', newDir(null))
  preopen(6, '/home', newDir(null))

  for (const [path, content] of Object.entries(files ?? {})) {
    let dir = rootDir
    const parts = path.split('/').filter(Boolean)
    const leaf = parts.pop()
    for (const part of parts) {
      let next = dir.entries.get(part)
      if (!next) addEntry(dir, part, (next = newDir(dir)))
      dir = next
    }
    addEntry(dir, leaf, newFile(dir, typeof content === 'string' ? encoder.encode(content) : Uint8Array.from(content)))
  }

  const argv = [`/exe/${exe.name}`, ...args].map((a) => encoder.encode(a + '\0'))
  const environ = Object.entries({ TMPDIR: '/tmp', TMP: '/tmp', TEMP: '/tmp', HOME: '/home', USERPROFILE: '/home', ...env }).map(([k, v]) => encoder.encode(`${k}=${v}\0`))

  const view = () => new DataView(memory().buffer)
  const bytes = () => new Uint8Array(memory().buffer)
  // slice copies: a TextDecoder and getRandomValues refuse a view over a shared memory
  const text = (pointer, length) => decoder.decode(bytes().slice(pointer, pointer + length))
  const fd = (n) => fds.get(n) ?? fail(E.BADF)
  const dirFd = (n) => { const f = fd(n); if (f.kind !== 'dir') fail(E.NOTDIR); return f }
  const call = (body) => (...a) => {
    try { body(...a); return 0 } catch (e) { if (e instanceof Errno) return e.code; throw e }
  }

  const sizesGet = (items) => call((countPointer, sizePointer) => {
    const v = view()
    v.setUint32(countPointer, items.length, true)
    v.setUint32(sizePointer, items.reduce((n, s) => n + s.length, 0), true)
  })
  const itemsGet = (items) => call((pointers, buffer) => {
    const v = view(), b = bytes()
    for (const s of items) {
      v.setUint32(pointers, buffer, true)
      pointers += 4
      b.set(s, buffer)
      buffer += s.length
    }
  })

  const filestat = (pointer, n) => {
    const v = view()
    v.setBigUint64(pointer, 0n, true)
    v.setBigUint64(pointer + 8, BigInt(n.ino), true)
    v.setUint8(pointer + 16, n.type)
    v.setBigUint64(pointer + 24, 1n, true)
    v.setBigUint64(pointer + 32, BigInt(n.type === REG ? n.size : n.type === LINK ? encoder.encode(n.target).length : 0), true)
    v.setBigUint64(pointer + 40, n.atim, true)
    v.setBigUint64(pointer + 48, n.mtim, true)
    v.setBigUint64(pointer + 56, n.ctim, true)
  }

  const open = (n, parentFd, rights, fdflags) => {
    let number = 7
    while (fds.has(number)) number++
    fds.set(number, { kind: n.type === DIR ? 'dir' : 'file', node: n, root: parentFd.root, rights, append: (fdflags & 1) !== 0, position: 0 })
    return number
  }

  const named = (r) => { if (r.name === null) fail(E.INVAL); return r }

  return {
    args_sizes_get: sizesGet(argv),
    args_get: itemsGet(argv),
    environ_sizes_get: sizesGet(environ),
    environ_get: itemsGet(environ),

    clock_time_get: call((id, precision, pointer) => {
      let ns
      if (id === 0) ns = stamp()
      else if (id === 1) {
        const ms = performance.timeOrigin + performance.now()
        ns = BigInt(Math.floor(ms)) * 1000000n + BigInt(Math.round((ms % 1) * 1e6))
      } else if (id === 2 || id === 3) ns = BigInt(Math.round(performance.now() * 1e6))
      else fail(E.INVAL)
      view().setBigUint64(pointer, ns, true)
    }),

    random_get: call((pointer, length) => {
      const piece = new Uint8Array(Math.min(length, 65536))
      for (let done = 0; done < length; done += 65536) {
        const part = piece.subarray(0, Math.min(length - done, 65536))
        crypto.getRandomValues(part)
        bytes().set(part, pointer + done)
      }
    }),

    // A sleep: every subscription a relative clock. The first to expire is the one reported; anything else is ENOSYS.
    poll_oneoff: call((subscriptions, events, count, taken) => {
      const v = view()
      let best = -1, least = 0n
      for (let k = 0; k < count; k++) {
        const at = subscriptions + 48 * k
        if (v.getUint8(at + 8) !== 0 || (v.getUint16(at + 40, true) & 1) !== 0) fail(E.NOSYS)
        const timeout = v.getBigUint64(at + 24, true)
        if (best < 0 || timeout < least) { best = k; least = timeout }
      }
      if (best < 0) fail(E.INVAL)
      const ms = Number(least) / 1e6
      if (ms > 0) {
        let slept = false
        if (typeof SharedArrayBuffer === 'function') { try { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); slept = true } catch { /* a page's main thread cannot block */ } }
        if (!slept) { const end = performance.now() + ms; while (performance.now() < end); }
      }
      const out = events
      for (let k = 0; k < 32; k++) v.setUint8(out + k, 0)
      v.setBigUint64(out, v.getBigUint64(subscriptions + 48 * best, true), true)
      v.setUint32(taken, 1, true)
    }),

    proc_exit: (code) => { throw new Exit(code) },

    fd_write: call((n, iovs, count, writtenPointer) => {
      const f = fd(n)
      if (!(f.rights & RIGHT_WRITE) || f.kind === 'dir') fail(E.BADF)
      let total = 0
      const v = view(), b = bytes()
      const pieces = []
      for (let i = 0; i < count; i++) {
        const start = v.getUint32(iovs + i * 8, true), length = v.getUint32(iovs + i * 8 + 4, true)
        pieces.push(b.subarray(start, start + length))
        total += length
      }
      const joined = new Uint8Array(total)
      let at = 0
      for (const p of pieces) { joined.set(p, at); at += p.length }
      if (f.kind === 'stdio') out(n, joined)
      else {
        if (f.append) f.position = f.node.size
        writeAt(f.node, f.position, joined)
        f.position += total
      }
      view().setUint32(writtenPointer, total, true)
    }),

    fd_read: call((n, iovs, count, readPointer) => {
      const f = fd(n)
      if (f.kind === 'dir') fail(E.ISDIR)
      if (!(f.rights & RIGHT_READ)) fail(E.BADF)
      let total = 0
      if (f.kind === 'file') {
        const v = view(), b = bytes()
        for (let i = 0; i < count && f.position < f.node.size; i++) {
          const start = v.getUint32(iovs + i * 8, true), length = v.getUint32(iovs + i * 8 + 4, true)
          const take = Math.min(length, f.node.size - f.position)
          b.set(f.node.data.subarray(f.position, f.position + take), start)
          f.position += take
          total += take
          if (take < length) break
        }
        f.node.atim = stamp()
      }
      view().setUint32(readPointer, total, true)
    }),

    fd_close: call((n) => { fd(n); fds.delete(n) }),

    fd_seek: call((n, offset, whence, pointer) => {
      const f = fd(n)
      if (f.kind === 'stdio') fail(E.SPIPE)
      if (f.kind === 'dir') fail(E.ISDIR)
      const at = (whence === 0 ? 0 : whence === 1 ? f.position : whence === 2 ? f.node.size : fail(E.INVAL)) + Number(offset)
      if (at < 0) fail(E.INVAL)
      f.position = at
      view().setBigUint64(pointer, BigInt(at), true)
    }),

    fd_sync: call((n) => { fd(n) }),

    fd_prestat_get: call((n, pointer) => {
      const f = fd(n)
      if (f.pre === undefined) fail(E.BADF)
      view().setUint32(pointer, 0, true)
      view().setUint32(pointer + 4, encoder.encode(f.pre).length, true)
    }),

    fd_prestat_dir_name: call((n, pointer, length) => {
      const f = fd(n)
      if (f.pre === undefined) fail(E.BADF)
      bytes().set(encoder.encode(f.pre).subarray(0, length), pointer)
    }),

    fd_readdir: call((n, buffer, length, cookie, usedPointer) => {
      const f = dirFd(n)
      const d = f.node
      const list = [['.', d], ['..', d.parent ?? d], ...d.entries]
      const b = bytes()
      let used = 0
      for (let i = Number(cookie); i < list.length && used < length; i++) {
        const name = encoder.encode(list[i][0])
        const record = new Uint8Array(24 + name.length)
        const h = new DataView(record.buffer)
        h.setBigUint64(0, BigInt(i + 1), true)
        h.setBigUint64(8, BigInt(list[i][1].ino), true)
        h.setUint32(16, name.length, true)
        h.setUint8(20, list[i][1].type)
        record.set(name, 24)
        const take = Math.min(record.length, length - used)
        b.set(record.subarray(0, take), buffer + used)
        used += take
      }
      view().setUint32(usedPointer, used, true)
    }),

    path_open: call((n, lookupFlags, pointer, length, oflags, rightsBase, rightsInheriting, fdflags, openedPointer) => {
      const base = dirFd(n)
      const creat = (oflags & 1) !== 0, wantDir = (oflags & 2) !== 0, excl = (oflags & 4) !== 0, trunc = (oflags & 8) !== 0
      const r = lookup(base, text(pointer, length), (lookupFlags & 1) !== 0 && !(creat && excl))
      let target = r.node
      if (target?.type === LINK) fail(wantDir ? E.NOTDIR : E.LOOP)
      if (!target) {
        if (!creat) fail(E.NOENT)
        named(r)
        target = newFile(r.parent)
        addEntry(r.parent, r.name, target)
      } else if (creat && excl) fail(E.EXIST)
      else if (wantDir && target.type !== DIR) fail(E.NOTDIR)
      if (target.type === DIR && (trunc || (rightsBase & RIGHT_WRITE) !== 0n)) fail(E.ISDIR)
      if (target.type === REG && trunc) truncate(target, 0)
      view().setUint32(openedPointer, open(target, base, rightsBase, fdflags), true)
    }),

    path_filestat_get: call((n, lookupFlags, pointer, length, buffer) => {
      filestat(buffer, lookup(dirFd(n), text(pointer, length), (lookupFlags & 1) !== 0).node ?? fail(E.NOENT))
    }),

    path_filestat_set_times: call((n, lookupFlags, pointer, length, accessed, modified, flags) => {
      if (((flags & 1) && (flags & 2)) || ((flags & 4) && (flags & 8))) fail(E.INVAL)
      const target = lookup(dirFd(n), text(pointer, length), (lookupFlags & 1) !== 0).node ?? fail(E.NOENT)
      if (flags & 1) target.atim = accessed
      if (flags & 2) target.atim = stamp()
      if (flags & 4) target.mtim = modified
      if (flags & 8) target.mtim = stamp()
      target.ctim = stamp()
    }),

    path_create_directory: call((n, pointer, length) => {
      const r = lookup(dirFd(n), text(pointer, length), false)
      if (r.node) fail(E.EXIST)
      addEntry(r.parent, r.name, newDir(r.parent))
    }),

    path_remove_directory: call((n, pointer, length) => {
      const r = named(lookup(dirFd(n), text(pointer, length), false))
      if (!r.node) fail(E.NOENT)
      if (r.node.type !== DIR) fail(E.NOTDIR)
      if (!isEmptyDir(r.node)) fail(E.NOTEMPTY)
      r.parent.entries.delete(r.name)
      touch(r.parent)
    }),

    path_unlink_file: call((n, pointer, length) => {
      const r = named(lookup(dirFd(n), text(pointer, length), false))
      if (!r.node) fail(E.NOENT)
      if (r.node.type === DIR) fail(E.ISDIR)
      r.parent.entries.delete(r.name)
      touch(r.parent)
    }),

    path_rename: call((n, pointer, length, newN, newPointer, newLength) => {
      const from = named(lookup(dirFd(n), text(pointer, length), false))
      const to = named(lookup(dirFd(newN), text(newPointer, newLength), false))
      if (!from.node) fail(E.NOENT)
      if (from.node === to.node) return
      if (from.node.type === DIR && within(to.parent, from.node)) fail(E.INVAL)
      if (to.node) {
        if (to.node.type === DIR) {
          if (from.node.type !== DIR) fail(E.ISDIR)
          if (!isEmptyDir(to.node)) fail(E.NOTEMPTY)
        } else if (from.node.type === DIR) fail(E.NOTDIR)
      }
      from.parent.entries.delete(from.name)
      touch(from.parent)
      addEntry(to.parent, to.name, from.node)
      from.node.ctim = stamp()
    }),

    path_readlink: call((n, pointer, length, buffer, bufferLength, usedPointer) => {
      const r = lookup(dirFd(n), text(pointer, length), false)
      if (!r.node) fail(E.NOENT)
      if (r.node.type !== LINK) fail(E.INVAL)
      const target = encoder.encode(r.node.target).subarray(0, bufferLength)
      bytes().set(target, buffer)
      view().setUint32(usedPointer, target.length, true)
    }),

    path_symlink: call((oldPointer, oldLength, n, pointer, length) => {
      const r = named(lookup(dirFd(n), text(pointer, length), false))
      if (r.node) fail(E.EXIST)
      addEntry(r.parent, r.name, node(LINK, r.parent, { target: text(oldPointer, oldLength) }))
    }),

    root: rootDir,
  }
}

// every file under `dir`, as path -> Uint8Array
function collect(dir, prefix, into) {
  for (const [name, child] of dir.entries) {
    if (child.type === DIR) collect(child, `${prefix}${name}/`, into)
    else if (child.type === REG) into[prefix + name] = child.data.slice(0, child.size)
  }
  return into
}

// ---- the Worker: instantiate, run, report ----------------------------------------------------------------------------

async function execute({ module, bytes, name, mapUrl, args, env, files, window }, post) {
  let instance
  const wasi = makeWasi({ args, env, files, exe: { name, bytes: bytes ?? new Uint8Array(0) }, memory: () => instance.exports.memory, out: (fd, data) => post({ out: fd, bytes: data }, [data.buffer]) })
  const finish = (exitCode, note) => {
    if (note) post({ out: 2, bytes: encoder.encode(note) })
    post({ done: { exitCode, files: collect(wasi.root, '/', {}) } })
  }
  const { root, ...table } = wasi
  try {
    module ??= await WebAssembly.compile(bytes)
    const imports = {}
    const screen = window && windowing.imports(window, () => instance.exports.memory, post)
    for (const { module: m, name: n, kind } of WebAssembly.Module.imports(module)) {
      if (kind === 'function' && (m === 'wasi_snapshot_preview1' || m === 'neper_host')) (imports[m] ??= {})[n] = (m === 'wasi_snapshot_preview1' ? table[n] : screen?.[n]) || (() => E.NOSYS)
    }
    instance = await WebAssembly.instantiate(module, imports)
  } catch (error) {
    return finish(125, `${error}\n`)
  }
  try {
    instance.exports._start()
    finish(0)
  } catch (error) {
    if (error instanceof Exit) finish(error.code)
    else if (error instanceof RangeError) finish(134, ": trap[stack]: stack overflow (the engine's call stack)\n")
    else finish(1, await withLines(`${error.stack ?? error}\n`, mapUrl))
  }
}

// The stack with `[path:line]` after each frame, when OUT.map lies beside the module (C211, D5683).
async function withLines(stack, mapUrl) {
  if (!mapUrl) return stack
  try {
    const { addLines } = await import('./source-map.js')
    const map = mapUrl.startsWith('file:') ? await (await import('node:fs/promises')).readFile(new URL(mapUrl), 'utf8') : await (await fetch(mapUrl)).text()
    return addLines(stack, map)
  } catch {
    return stack
  }
}

// ---- threads (D5679, on D5674's protocol) ------------------------------------------------------------------------------
// A module importing env.memory (a `--threads` build, D5671) runs with the calling thread as the host: it owns the
// shared memory, the in-memory tree and WASI, runs no wasm, and answers; every wasm thread, the first too, is a Worker
// with its own instance over the memory whose WASI imports are mailbox calls. One mailbox per thread, a 128-byte
// SharedArrayBuffer as Int32 words: 0 the state (0 idle, 1 request, 2 reply), 1 the function number (an import's
// index among the module's wasi_snapshot_preview1 imports, one past them for `thread-spawn`), bytes 8-103 up to
// twelve arguments as BigInt64, 26 the result, 27 which arguments are i64 (a bit each), 28 how many; words 29-31
// the Worker's start slot (29: 0 idle, 3 claimed by the host, 1 start, 2 running; 30 the tid; 31 the argument).
// The host waits with Atomics.waitAsync; where that is missing the thread posts a ping after each request.
// Every Worker is made by the host, which is never blocked: a Worker made by a blocked Worker never starts (D5670).
const MAX_TID = 0x1fffffff
const ISOLATION = 'a threaded module needs a cross-origin isolated page: serve it with Cross-Origin-Opener-Policy: same-origin and Cross-Origin-Embedder-Policy: require-corp'
const CANVAS = 'a window on a canvas needs a cross-origin isolated page: serve it with Cross-Origin-Opener-Policy: same-origin and Cross-Origin-Embedder-Policy: require-corp'
const wasiNames = (module) => WebAssembly.Module.imports(module).filter((i) => i.module === 'wasi_snapshot_preview1' && i.kind === 'function').map((i) => i.name)

// The limits of the memory a module imports as env.memory, read from its import section because the JS API does
// not report them: {initial, maximum} in pages, or null when it imports none (or is not a module).
function importedMemory(bytes) {
  if (bytes.length < 8 || new DataView(bytes.buffer, bytes.byteOffset).getUint32(0) !== 0x0061736d) return null
  let at = 8
  const uleb = () => {
    let value = 0, shift = 0
    for (;;) {
      const byte = bytes[at++]
      if (byte === undefined) return value
      value += (byte & 127) * 2 ** shift
      if (byte < 128) return value
      shift += 7
    }
  }
  const name = () => {
    const length = uleb()
    const found = decoder.decode(bytes.subarray(at, at + length))
    at += length
    return found
  }
  const limits = () => {
    const flag = uleb()
    const initial = uleb()
    return { initial, maximum: flag & 1 ? uleb() : undefined }
  }
  while (at < bytes.length) {
    const id = bytes[at++]
    const end = uleb() + at
    if (id !== 2) { at = end; continue }
    for (let count = uleb(); count > 0 && at < end; count--) {
      const library = name(), field = name(), kind = bytes[at++]
      if (kind === 0) uleb()
      else if (kind === 1) { at++; limits() }
      else if (kind === 2) { const found = limits(); if (library === 'env' && field === 'memory') return found }
      else if (kind === 3) at += 2
      else if (kind === 4) { at++; uleb() }
    }
    return null
  }
  return null
}

// A wasm thread in its Worker. The first runs `_start`; every other runs `wasi_thread_start` for each thread the host
// hands it and then waits, idle, for the next.
function threadWorker({ first, module, memory, box, messages, window }, post) {
  const state = new Int32Array(box)
  const values = new BigInt64Array(box, 8, 12)
  const call = (number, given) => {
    let mask = 0
    for (let k = 0; k < given.length; k++) {
      if (typeof given[k] === 'bigint') { values[k] = given[k]; mask |= 1 << k } else values[k] = BigInt(given[k])
    }
    Atomics.store(state, 27, mask)
    Atomics.store(state, 28, given.length)
    Atomics.store(state, 1, number)
    Atomics.store(state, 0, 1)
    Atomics.notify(state, 0)
    if (messages) post({ ping: true })
    while (Atomics.load(state, 0) === 1) Atomics.wait(state, 0, 1)
    const result = Atomics.load(state, 26)
    Atomics.store(state, 0, 0)
    return result
  }
  const names = wasiNames(module)
  const wasi = {}
  names.forEach((name, number) => { wasi[name] = (...given) => call(number, given) })
  // A sleep (every subscription a relative clock) waits here, so it never holds the host's loop.
  if (wasi.poll_oneoff) {
    const proxied = wasi.poll_oneoff
    const sleeper = new Int32Array(new SharedArrayBuffer(4))
    wasi.poll_oneoff = (subscriptions, events, count, taken) => {
      let view = new DataView(memory.buffer)
      let best = -1, least = 0n
      for (let k = 0; k < count; k++) {
        const at = (subscriptions >>> 0) + 48 * k
        if (view.getUint8(at + 8) !== 0 || (view.getUint16(at + 40, true) & 1) !== 0) return proxied(subscriptions, events, count, taken)
        const timeout = view.getBigUint64(at + 24, true)
        if (best < 0 || timeout < least) { best = k; least = timeout }
      }
      if (best < 0) return proxied(subscriptions, events, count, taken)
      if (least > 0n) Atomics.wait(sleeper, 0, 0, Number(least) / 1e6)
      view = new DataView(memory.buffer)
      const out = events >>> 0
      for (let k = 0; k < 32; k++) view.setUint8(out + k, 0)
      view.setBigUint64(out, view.getBigUint64((subscriptions >>> 0) + 48 * best, true), true)
      view.setUint32(taken >>> 0, 1, true)
      return 0
    }
  }
  const screen = window && windowing.imports(window, () => memory, post)
  const imports = { env: { memory }, wasi: { 'thread-spawn': (arg) => call(names.length, [arg]) }, wasi_snapshot_preview1: wasi }
  for (const { module: m, name: n, kind } of WebAssembly.Module.imports(module)) {
    if (m === 'neper_host' && kind === 'function') (imports.neper_host ??= {})[n] = (first && screen?.[n]) || (() => E.NOSYS)
  }
  const failed = (error) => (error instanceof RangeError
    ? { code: 134, note: /Maximum call stack size exceeded/.test(error.message) ? ": trap[stack]: stack overflow (the engine's call stack)\n" : `: engine error: ${error}\n` }
    : { code: 1, note: `${error.stack ?? error}\n` })
  let instance
  try {
    instance = new WebAssembly.Instance(module, imports)
  } catch (error) {
    return post({ code: 125, note: `${error}\n` })
  }
  if (first) {
    try { instance.exports._start(); post({ code: 0 }) } catch (error) { post(failed(error)) }
    return
  }
  for (;;) {
    let seen
    while ((seen = Atomics.load(state, 29)) !== 1) Atomics.wait(state, 29, seen)
    Atomics.store(state, 29, 2)
    try {
      instance.exports.wasi_thread_start(Atomics.load(state, 30), Atomics.load(state, 31))
    } catch (error) {
      return post(failed(error))
    }
    Atomics.store(state, 29, 0)
  }
}

// The host side: the calling thread. Resolves { exitCode, files } when the first thread's `_start` returns, any
// thread calls proc_exit, or any thread's engine fails; the other Workers are then terminated and nothing more is
// answered, so no thread writes after the exit.
async function runThreads({ bytes, name, mapUrl }, limits, { args, env, files }, sinks, messages, window) {
  if (!isNode && !globalThis.crossOriginIsolated) throw new Error(ISOLATION)
  let module
  try {
    module = await WebAssembly.compile(bytes)
  } catch (error) {
    sinks[2](encoder.encode(`${error}\n`))
    return { exitCode: 125, files: {} }
  }
  const memory = new WebAssembly.Memory({ initial: limits.initial, maximum: limits.maximum ?? 65536, shared: true })
  const { root, ...calls } = makeWasi({ args, env, files, exe: { name, bytes }, memory: () => memory, out: (fd, data) => sinks[fd](data) })
  const names = wasiNames(module)
  const SPAWN = names.length
  const workers = []
  let nextTid = 1
  let ended = false
  let finish

  const end = async (code, note) => {
    if (ended) return
    ended = true
    const result = { exitCode: code, files: collect(root, '/', {}) }
    for (const record of workers) { Atomics.notify(record.state, 0); record.worker.terminate() }
    if (note) sinks[2](encoder.encode(await withLines(note, mapUrl)))
    finish(result)
  }

  // ponytail: an idle Worker is found by a scan of all of them; a list of idle ones if a program keeps thousands.
  // A Worker's engine stack follows the stack its thread asked for (the size D5673 puts at +40 of the block), twice
  // that for the engine's bigger frames, between 8 and 64 MB (run-wasm.mjs gives the reason). A browser sizes its own.
  const engineStack = (arg) => Math.min(64, Math.max(8, 2 * Math.ceil(Number(new BigUint64Array(memory.buffer, (arg >>> 0) + 40, 1)[0]) / 1048576)))

  const spawn = (arg) => {
    if (nextTid > MAX_TID) return -6
    const tid = nextTid++
    const stackMb = engineStack(arg)
    for (const record of workers) {
      if (record.first || record.stackMb < stackMb || Atomics.compareExchange(record.state, 29, 0, 3) !== 0) continue
      Atomics.store(record.state, 30, tid)
      Atomics.store(record.state, 31, arg)
      Atomics.store(record.state, 29, 1)
      Atomics.notify(record.state, 29)
      return tid
    }
    try { start(false, tid, arg, stackMb) } catch { return -6 }
    return tid
  }

  // Answer the request in a mailbox, if it holds one.
  const serve = ({ state, values }) => {
    if (ended || Atomics.load(state, 0) !== 1) return
    const number = Atomics.load(state, 1), mask = Atomics.load(state, 27)
    const given = []
    for (let k = 0; k < Atomics.load(state, 28); k++) given.push(mask & (1 << k) ? values[k] : Number(BigInt.asIntN(32, values[k])))
    let result
    if (number === SPAWN) result = spawn(given[0])
    else if (names[number] === 'proc_exit') return end(given[0] >>> 0, '')
    else if (!calls[names[number]]) result = E.NOSYS
    else {
      try { result = calls[names[number]](...given) } catch (error) { return end(1, `${error.stack ?? error}\n`) }
    }
    Atomics.store(state, 26, result)
    Atomics.store(state, 0, 2)
    Atomics.notify(state, 0)
  }

  const listen = async (record) => {
    while (!ended) {
      const seen = Atomics.load(record.state, 0)
      if (seen === 1) { serve(record); continue }
      const waiting = Atomics.waitAsync(record.state, 0, seen)
      if (waiting.async) await waiting.value
    }
  }

  const start = (first, tid, arg, stackMb = 256) => {
    const box = new SharedArrayBuffer(128)
    const state = new Int32Array(box)
    if (!first) { state[29] = 1; state[30] = tid; state[31] = arg }
    const worker = isNode
      ? new wt.Worker(new URL(import.meta.url), { resourceLimits: { stackSizeMb: stackMb } })
      : new Worker(import.meta.url, { type: 'module' })
    const record = { first, worker, state, stackMb, values: new BigInt64Array(box, 8, 12) }
    const message = (m) => (m.ping ? serve(record) : m.window ? window.handle(m.window) : end(m.code, m.note))
    if (isNode) {
      worker.on('message', message)
      worker.on('error', (error) => end(1, `${error.stack ?? error}\n`))
      worker.on('exit', (code) => end(code || 1, first ? '' : `a thread's worker ended (exit ${code})\n`))
      if (!first) worker.unref()
    } else {
      worker.onmessage = (event) => message(event.data)
      worker.onerror = (event) => end(1, `${event.message}\n`)
    }
    worker.postMessage({ threaded: true, first, module, memory, box, messages, window: first && window ? { ring: window.ring } : undefined })
    workers.push(record)
    if (!messages) listen(record)
  }

  return new Promise((resolve) => {
    finish = resolve
    start(true)
  })
}

if (inWorker) {
  const port =isNode ? wt.parentPort : globalThis
  const post = (message, transfer) => port.postMessage(message, transfer)
  const start = async (data) => {
    try {
      await (data.threaded ? threadWorker(data, post) : execute(data, post))
    } catch (error) {
      post(data.threaded ? { code: 1, note: `${error.stack ?? error}\n` } : { error: `${error.stack ?? error}` })
    }
  }
  if (isNode) port.once('message', start)
  else globalThis.onmessage = (event) => start(event.data)
}

// ---- the caller's side -------------------------------------------------------------------------------------------------

async function load(source) {
  if (source instanceof WebAssembly.Module) return { module: source, name: 'main.wasm' }
  if (source instanceof Uint8Array || source instanceof ArrayBuffer) return { bytes: new Uint8Array(source), name: 'main.wasm' }
  let name = 'main.wasm'
  let mapUrl
  let response = source
  if (typeof source === 'string' || source instanceof URL) {
    const url = new URL(source, globalThis.location?.href ?? 'file:///')
    name = url.pathname.split('/').pop() || name
    mapUrl = `${url.href}.map`
    response = url.protocol === 'file:' ? new Response(await (await import('node:fs/promises')).readFile(url)) : await fetch(url)
  }
  if (!response.ok) throw new Error(`cannot load the module: ${response.status} ${response.statusText}`)
  return { bytes: new Uint8Array(await response.arrayBuffer()), name, mapUrl }
}

// The default sink: bytes decoded and logged a line at a time; null ends the stream and flushes the rest.
function lines(sink) {
  const stream = new TextDecoder()
  let pending = ''
  return (data) => {
    if (data) {
      pending += stream.decode(data, { stream: true })
      const parts = pending.split('\n')
      pending = parts.pop()
      parts.forEach(sink)
    } else {
      pending += stream.decode()
      if (pending) sink(pending)
      pending = ''
    }
  }
}

export async function run(source, { args = [], env = {}, files = {}, stdout, stderr, canvas, debug, messages = typeof Atomics.waitAsync !== 'function' } = {}) {
  if (canvas && !isNode && !globalThis.crossOriginIsolated) throw new Error(CANVAS)
  const loaded = await load(source)
  const sinks = { 1: stdout ?? lines((l) => console.log(l)), 2: stderr ?? lines((l) => console.error(l)) }
  const screen = canvas ? windowing.attach(canvas) : undefined
  if (debug && screen) debug.stats = screen.stats
  try {
    const threaded = loaded.bytes ? importedMemory(loaded.bytes) : null
    if (loaded.module && WebAssembly.Module.imports(loaded.module).some((i) => i.module === 'env' && i.name === 'memory')) {
      throw new Error('a threaded module is given as a URL, a Response or bytes, not a compiled module: its memory limits are read from the bytes')
    }
    if (threaded) return await runThreads(loaded, threaded, { args, env, files }, sinks, messages, screen)
    return await runPlain(loaded, { args, env, files }, sinks, screen)
  } finally {
    screen?.dispose()
    if (!stdout) sinks[1](null)
    if (!stderr) sinks[2](null)
  }
}

async function runPlain(loaded, { args, env, files }, sinks, screen) {
  const worker = isNode
    ? new wt.Worker(new URL(import.meta.url), { resourceLimits: { stackSizeMb: 256 } })
    : new Worker(import.meta.url, { type: 'module' })
  const listen = (handler, failed) => {
    if (isNode) { worker.on('message', handler); worker.on('error', failed); worker.on('exit', () => failed(new Error('the worker ended without a result'))) }
    else { worker.onmessage = (event) => handler(event.data); worker.onerror = (event) => failed(new Error(event.message)) }
  }
  try {
    return await new Promise((resolve, reject) => {
      listen((message) => {
        if (message.out) sinks[message.out](message.bytes)
        else if (message.window) screen.handle(message.window)
        else if (message.done) resolve(message.done)
        else if (message.error) reject(new Error(message.error))
      }, reject)
      worker.postMessage({ ...loaded, args, env, files, window: screen && { ring: screen.ring } })
    })
  } finally {
    if (!isNode) worker.terminate()
  }
}

// ---- the command ----------------------------------------------------------------------------------------------------------

const url = isNode && !inWorker ? await import('node:url') : null
if (url && process.argv[1] && import.meta.url === url.pathToFileURL(process.argv[1]).href) {
  const [file, ...rest] = process.argv.slice(2)
  const { PATH } = process.env
  const result = await run(url.pathToFileURL(file), {
    args: rest,
    env: { ...process.env, PATH, TMPDIR: '/tmp', TMP: '/tmp', TEMP: '/tmp', HOME: '/home', USERPROFILE: '/home' },
    stdout: (data) => process.stdout.write(data),
    stderr: (data) => process.stderr.write(data),
  })
  process.exitCode = result.exitCode
}
