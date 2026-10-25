// Run a wasm32-wasi module the way `neper build --target wasm32-wasi` writes one (D5213):
//   node --no-warnings scripts/run-wasm.mjs FILE.wasm [ARGS...]
// WASI preview 1 over node:wasi and the module's exit status as this process's. A module the engine
// refuses to compile or link exits 125, which scripts/wasm-sweep.sh counts as invalid.
//
// What the module sees (D5620):
//   .       the working directory, which os.wasi.e also mounts as `/`
//   /tmp    a fresh directory, removed when the module ends; TMPDIR, TMP and TEMP name it
//   /home   another, for HOME and USERPROFILE
//   /exe    the module's own directory, only when it is outside the working directory
//   the environment is an allowlist of this process's (D5663): PATH, LANG, LC_*, TZ, TERM,
//     NO_COLOR, SystemRoot and NEPER_*, with TMPDIR, TMP, TEMP, HOME and USERPROFILE pointed at
//     the two directories above. `--env=all` (or NEPER_WASM_ENV=all) hands over the whole
//     environment, as before; the module can read and write the working directory either way.
// A module that imports `neper_host` (sockets, name resolution and the poller, D5675, D5676) gets
// them from scripts/run-wasm-host.mjs: each call blocks the module's worker while this process's
// main thread does it over node:net, node:dgram and node:dns. NEPER_HOST_TRACE=1 prints each call.
// NEPER_WASM_MEMORY=1 and NEPER_WASM_TIME=1 add `wasm memory: N MiB` and `wasm time: N ms`
// (compile, link and run, as scripts/wasm-bench.sh reads it) to standard error at the end.
// The first argument is the module's path inside the preopens (relative to `.`, else under /exe), so
// os.executable_path can stat it.
//
// The module runs in a worker thread with a 256 MB engine stack: the main thread's is about
// a megabyte, which a deeply recursive program (the JSON schema checker, say) exhausts long
// before the 8 MiB shadow stack the module keeps in memory. Running out of the engine's
// stack ("Maximum call stack size exceeded") is reported as the stack overflow it is, with the
// trap's status 134; any other RangeError (the engine could not grow the memory, say) is reported
// with its own text, also as status 134 because the module did not finish. A worker that ends
// without an answer (killed, out of memory) makes the runner exit 1, and an interrupt (SIGINT,
// SIGTERM) stops the worker and removes the scratch directories before the runner exits 130 or
// 143. WASI writes to file descriptors 1 and 2 directly, so output order is the module's.
//
// A module built with `--threads` (D5671) imports its memory as `env.memory` and is run by the
// thread host of D5674 (`hostThreads` below): this main thread owns the shared memory and the one
// node:wasi instance and runs no wasm; every wasm thread, the first one too, is a worker whose WASI
// calls are proxied to it through a mailbox, and `wasi.thread-spawn` hands a thread to an idle
// worker or a new one.
//
// The status is left in `process.exitCode` and the process left to end by itself: on Windows
// `process.exit` while the engine is still finishing a background compile aborts Node
// ("Assertion failed: !(handle->flags & UV_HANDLE_CLOSING)", exit 127).
import { readFile } from 'node:fs/promises'
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path'
import { WASI } from 'node:wasi'
import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads'
import { argv, env as hostEnv, stderr } from 'node:process'
import { NetHost, hostImports, serve } from './run-wasm-host.mjs'

// Node's WASI answers fd_readdir with ENOSYS on Windows (uvwasi has no directory listing there). Where
// it does, the call is answered here: the directory descriptors the module opens are followed
// (descriptor -> host path) so the listing can be read with fs.readdirSync and written in WASI's
// dirent layout (d_next u64, d_ino u64, d_namlen u32, d_type u8, then the name).
function withReaddir(imports, preopens, memory) {
  const calls = imports.wasi_snapshot_preview1
  const host = new Map(Object.values(preopens).map((path, index) => [3 + index, resolve(path)]))
  const { path_open, fd_close, fd_readdir } = calls
  calls.path_open = (fd, lookup, pathPointer, pathLength, openFlags, rightsBase, rightsInheriting, fdFlags, openedPointer) => {
    const status = path_open(fd, lookup, pathPointer, pathLength, openFlags, rightsBase, rightsInheriting, fdFlags, openedPointer)
    if (status === 0 && (openFlags & 2) !== 0 && host.has(fd)) {
      const name = Buffer.from(memory().buffer, pathPointer >>> 0, pathLength >>> 0).toString()
      host.set(new DataView(memory().buffer).getUint32(openedPointer >>> 0, true), join(host.get(fd), name))
    }
    return status
  }
  // A listing is read when a walk starts (cookie 0) and kept until the next one starts or the
  // descriptor closes, so entries added or removed between two calls of one walk do not shift
  // the cookies the module holds.
  const listings = new Map()
  calls.fd_close = (fd) => {
    const status = fd_close(fd)
    if (fd > 2) {
      host.delete(fd)
      listings.delete(fd)
    }
    return status
  }
  calls.fd_readdir = (fd, buffer, length, cookie, usedPointer) => {
    const status = fd_readdir(fd, buffer, length, cookie, usedPointer)
    if (status !== 52 || !host.has(fd)) return status
    let entries = listings.get(fd)
    if (!entries || Number(cookie) === 0) {
      try {
        const listed = readdirSync(host.get(fd), { withFileTypes: true })
        entries = [{ name: '.', type: 3 }, { name: '..', type: 3 }]
        for (const entry of listed) entries.push({ name: entry.name, type: entry.isDirectory() ? 3 : entry.isFile() ? 4 : entry.isSymbolicLink() ? 7 : 0 })
      } catch {
        return 29
      }
      listings.set(fd, entries)
    }
    const bytes = new Uint8Array(memory().buffer)
    let used = 0
    for (let index = Number(cookie); index < entries.length && used < length; index++) {
      const name = Buffer.from(entries[index].name)
      const record = new Uint8Array(24 + name.length)
      const header = new DataView(record.buffer)
      header.setBigUint64(0, BigInt(index + 1), true)
      header.setUint32(16, name.length, true)
      header.setUint8(20, entries[index].type)
      record.set(name, 24)
      const take = Math.min(record.length, length - used)
      bytes.set(record.subarray(0, take), (buffer >>> 0) + used)
      used += take
    }
    new DataView(memory().buffer).setUint32(usedPointer >>> 0, used, true)
    return 0
  }
  return imports
}

// The limits of the memory a module imports as `env.memory` (D5671), read from its import section
// because the JS API does not report them: {initial, maximum} in pages, or null when it imports none.
function importedMemory(bytes) {
  if (bytes.length < 8 || bytes.readUInt32BE(0) !== 0x0061736d) return null
  let at = 8
  const uleb = () => {
    let value = 0
    let shift = 0
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
    const text = Buffer.from(bytes.subarray(at, at + length)).toString()
    at += length
    return text
  }
  const limits = () => {
    const flag = uleb()
    const initial = uleb()
    return { initial, maximum: flag & 1 ? uleb() : undefined }
  }
  while (at < bytes.length) {
    const id = bytes[at++]
    const size = uleb()
    const end = at + size
    if (id !== 2) {
      at = end
      continue
    }
    for (let count = uleb(); count > 0; count--) {
      const library = name()
      const field = name()
      const kind = bytes[at++]
      if (kind === 0) uleb()
      else if (kind === 1) {
        at++
        limits()
      } else if (kind === 2) {
        const found = limits()
        if (library === 'env' && field === 'memory') return found
      } else if (kind === 3) at += 2
      else if (kind === 4) {
        at++
        uleb()
      }
    }
    return null
  }
  return null
}

async function run({ args, env, preopens }) {
  const wasi = new WASI({ version: 'preview1', args, env, preopens, returnOnExit: true })
  let instance
  const began = performance.now()
  try {
    const bytes = await readFile(workerData.file)
    const module = await WebAssembly.compile(bytes)
    const imports = withReaddir(wasi.getImportObject(), preopens, () => instance.exports.memory)
    const names = WebAssembly.Module.imports(module).filter((item) => item.module === 'neper_host').map((item) => item.name)
    if (names.length) imports.neper_host = hostImports(names, () => instance.exports.memory, workerData.box, workerData.data)
    instance = await WebAssembly.instantiate(module, imports)
  } catch (error) {
    return { code: 125, note: `${error}\n` }
  }
  const memory = () =>
    (env.NEPER_WASM_MEMORY ? `wasm memory: ${instance.exports.memory.buffer.byteLength / 1048576} MiB\n` : '') +
    (env.NEPER_WASM_TIME ? `wasm time: ${Math.round(performance.now() - began)} ms\n` : '')
  try {
    const code = wasi.start(instance)
    return { code, note: memory() }
  } catch (error) {
    if (!(error instanceof RangeError)) throw error
    return rangeError(error)
  }
}

function rangeError(error) {
  if (/Maximum call stack size exceeded/.test(error.message)) return { code: 134, note: ': trap[stack]: stack overflow (the engine\'s call stack)\n' }
  return { code: 134, note: `: engine error: ${error}\n` }
}

// ---- the thread host (D5674) -------------------------------------------------------------------------
// One mailbox per wasm thread, a 128-byte SharedArrayBuffer as Int32 words: 0 the state (0 idle,
// 1 request, 2 reply), 1 the function number (a WASI import's index among the module's WASI imports,
// or one past them for `thread-spawn`), bytes 8-103 up to twelve arguments as BigInt64, 26 the
// result, 27 which arguments are i64 (a bit each), 28 how many. Words 29-31 are the worker's start
// slot: 29 its state (0 idle, 3 claimed by the host, 1 start, 2 running), 30 the tid, 31 the argument.
const MAX_TID = 0x1fffffff
const wasiNames = (module) => WebAssembly.Module.imports(module).filter((item) => item.module === 'wasi_snapshot_preview1').map((item) => item.name)

// Node's main thread: owns the shared memory and the one WASI instance (one descriptor table for every
// thread), answers every thread's mailbox in its event loop and never runs wasm. The run ends when the
// first thread's `_start` returns, a thread calls `proc_exit`, or any thread's engine fails; the other
// workers are then terminated and nothing more is answered.
async function hostThreads({ bytes, limits, args, env, preopens, clean }) {
  const began = performance.now()
  let module
  try {
    module = await WebAssembly.compile(bytes)
  } catch (error) {
    stderr.write(`${error}\n`)
    process.exitCode = 125
    clean()
    return
  }
  const memory = new WebAssembly.Memory({ initial: limits.initial, maximum: limits.maximum ?? 65536, shared: true })
  const wasi = new WASI({ version: 'preview1', args, env, preopens, returnOnExit: true })
  wasi.start({ exports: { memory, _start() {} } })
  const calls = withReaddir(wasi.getImportObject(), preopens, () => memory).wasi_snapshot_preview1
  const names = wasiNames(module)
  const SPAWN = names.length
  const usesNet = WebAssembly.Module.imports(module).some((item) => item.module === 'neper_host')
  const net = new NetHost(new Uint8Array(0))
  const workers = []
  let nextTid = 1
  let ended = false

  const end = (code, note) => {
    if (ended) return
    ended = true
    if (note) stderr.write(note)
    if (hostEnv.NEPER_WASM_MEMORY) stderr.write(`wasm memory: ${memory.buffer.byteLength / 1048576} MiB\n`)
    if (hostEnv.NEPER_WASM_TIME) stderr.write(`wasm time: ${Math.round(performance.now() - began)} ms\nwasm workers: ${workers.length}\n`)
    process.exitCode = code
    for (const record of workers) {
      record.net?.stop()
      Atomics.notify(record.state, 0)
    }
    net.closeAll()
    Promise.allSettled(workers.map((record) => record.worker.terminate())).then(clean)
  }

  // ponytail: an idle worker is found by a scan of all of them; a list of idle ones if a program
  // ever keeps thousands of workers.
  const spawn = (arg) => {
    if (nextTid > MAX_TID) return -6
    const tid = nextTid++
    for (const record of workers) {
      if (record.first || Atomics.compareExchange(record.state, 29, 0, 3) !== 0) continue
      Atomics.store(record.state, 30, tid)
      Atomics.store(record.state, 31, arg)
      Atomics.store(record.state, 29, 1)
      Atomics.notify(record.state, 29)
      return tid
    }
    try {
      start(false, tid, arg)
    } catch {
      return -6
    }
    return tid
  }

  const answer = async (record) => {
    const { state } = record
    const values = new BigInt64Array(state.buffer, 8, 12)
    while (!ended) {
      let seen
      while (!ended && (seen = Atomics.load(state, 0)) !== 1) {
        const waiting = Atomics.waitAsync(state, 0, seen)
        if (waiting.async) await waiting.value
      }
      if (ended) return
      const number = Atomics.load(state, 1)
      const mask = Atomics.load(state, 27)
      const given = []
      for (let k = 0; k < Atomics.load(state, 28); k++) given.push(mask & (1 << k) ? values[k] : Number(BigInt.asIntN(32, values[k])))
      let result
      if (number === SPAWN) result = spawn(given[0])
      else if (names[number] === 'proc_exit') return end(given[0] >>> 0, '')
      else {
        try {
          result = calls[names[number]](...given)
        } catch (error) {
          return end(1, `${error.stack ?? error}\n`)
        }
      }
      Atomics.store(state, 26, result)
      Atomics.store(state, 0, 2)
      Atomics.notify(state, 0)
    }
  }

  const start = (first, tid, arg) => {
    const box = new SharedArrayBuffer(128)
    const state = new Int32Array(box)
    if (!first) {
      state[29] = 1
      state[30] = tid
      state[31] = arg
    }
    const netBox = usesNet ? new SharedArrayBuffer(128) : null
    const netData = usesNet ? new SharedArrayBuffer(65536) : null
    const worker = new Worker(new URL(import.meta.url), {
      workerData: { threaded: true, first, module, memory, box, netBox, netData },
      resourceLimits: { stackSizeMb: first ? 256 : 64 },
    })
    const record = { first, worker, state, net: usesNet ? serve(netBox, netData, net) : null }
    worker.on('message', (result) => end(result.code, result.note))
    worker.on('error', (error) => end(1, `${error.stack ?? error}\n`))
    worker.on('exit', (code) => end(code || 1, first ? '' : `a thread's worker ended (exit ${code})\n`))
    if (!first) worker.unref()
    workers.push(record)
    answer(record)
  }

  start(true)
}

// A wasm thread in its worker: an instance of the module over the shared memory whose WASI imports
// are mailbox calls to the host. The first thread runs `_start`; every other one runs
// `wasi_thread_start` for each thread the host hands it and then waits, idle, for the next.
function threadWorker({ first, module, memory, box, netBox, netData }) {
  const state = new Int32Array(box)
  const values = new BigInt64Array(box, 8, 12)
  const call = (number, given) => {
    let mask = 0
    for (let k = 0; k < given.length; k++) {
      if (typeof given[k] === 'bigint') {
        values[k] = given[k]
        mask |= 1 << k
      } else values[k] = BigInt(given[k])
    }
    Atomics.store(state, 27, mask)
    Atomics.store(state, 28, given.length)
    Atomics.store(state, 1, number)
    Atomics.store(state, 0, 1)
    Atomics.notify(state, 0)
    while (Atomics.load(state, 0) === 1) Atomics.wait(state, 0, 1)
    const result = Atomics.load(state, 26)
    Atomics.store(state, 0, 0)
    return result
  }
  const names = wasiNames(module)
  const wasi = {}
  names.forEach((name, number) => {
    wasi[name] = (...given) => call(number, given)
  })
  // A sleep (every subscription a relative clock) waits here, so it never holds the host's loop.
  if (wasi.poll_oneoff) {
    const proxied = wasi.poll_oneoff
    const sleeper = new Int32Array(new SharedArrayBuffer(4))
    wasi.poll_oneoff = (subscriptions, events, count, taken) => {
      let view = new DataView(memory.buffer)
      let best = -1
      let least = 0n
      for (let k = 0; k < count; k++) {
        const at = (subscriptions >>> 0) + 48 * k
        if (view.getUint8(at + 8) !== 0 || (view.getUint16(at + 40, true) & 1) !== 0) return proxied(subscriptions, events, count, taken)
        const timeout = view.getBigUint64(at + 24, true)
        if (best < 0 || timeout < least) {
          best = k
          least = timeout
        }
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
  const imports = { env: { memory }, wasi: { 'thread-spawn': (arg) => call(names.length, [arg]) }, wasi_snapshot_preview1: wasi }
  const hostNames = WebAssembly.Module.imports(module).filter((item) => item.module === 'neper_host').map((item) => item.name)
  if (hostNames.length) imports.neper_host = hostImports(hostNames, () => memory, netBox, netData)
  const failed = (error) => (error instanceof RangeError ? rangeError(error) : { code: 1, note: `${error.stack ?? error}\n` })
  let instance
  try {
    instance = new WebAssembly.Instance(module, imports)
  } catch (error) {
    parentPort.postMessage({ code: 125, note: `${error}\n` })
    return
  }
  if (first) {
    try {
      instance.exports._start()
      parentPort.postMessage({ code: 0 })
    } catch (error) {
      parentPort.postMessage(failed(error))
    }
    return
  }
  for (;;) {
    let seen
    while ((seen = Atomics.load(state, 29)) !== 1) Atomics.wait(state, 29, seen)
    Atomics.store(state, 29, 2)
    try {
      instance.exports.wasi_thread_start(Atomics.load(state, 30), Atomics.load(state, 31))
    } catch (error) {
      parentPort.postMessage(failed(error))
      return
    }
    Atomics.store(state, 29, 0)
  }
}

// The environment the module sees: the names a program may reasonably read, not the host's
// secrets (tokens, keys and credentials live in environment variables). A Windows environment is
// case-insensitive, so names are compared upper-cased.
const ALLOWED = /^(PATH|LANG|LC_.*|TZ|TERM|NO_COLOR|SYSTEMROOT|NEPER_.*)$/

if (isMainThread) {
  const rest = argv.slice(2)
  let everything = hostEnv.NEPER_WASM_ENV === 'all'
  while (rest[0]?.startsWith('--env=')) everything = rest.shift() === '--env=all'
  const [file, ...moduleArgs] = rest
  const absolute = resolve(file)
  const inside = relative('.', absolute)
  const preopens = { '.': '.' }
  let guest = inside.replaceAll(sep, '/')
  if (inside.startsWith('..') || isAbsolute(inside)) {
    preopens['/exe'] = dirname(absolute)
    guest = `/exe/${basename(absolute)}`
  }
  const scratch = mkdtempSync(join(tmpdir(), 'neper-wasm-'))
  const tmp = join(scratch, 'tmp')
  const home = join(scratch, 'home')
  mkdirSync(tmp)
  mkdirSync(home)
  preopens['/tmp'] = tmp
  preopens['/home'] = home
  const inherited = everything ? { ...hostEnv } : Object.fromEntries(Object.entries(hostEnv).filter(([name]) => ALLOWED.test(name.toUpperCase())))
  const env = { ...inherited, PATH: hostEnv.PATH, TMPDIR: '/tmp', TMP: '/tmp', TEMP: '/tmp', HOME: '/home', USERPROFILE: '/home' }
  for (const [signal, status] of [['SIGINT', 130], ['SIGTERM', 143]]) {
    process.on(signal, () => {
      rmSync(scratch, { recursive: true, force: true })
      process.exit(status)
    })
  }
  let bytes = null
  try {
    bytes = readFileSync(absolute)
  } catch {}
  const limits = bytes && importedMemory(bytes)
  if (limits) {
    await hostThreads({ bytes, limits, args: [guest, ...moduleArgs], env, preopens, clean: () => rmSync(scratch, { recursive: true, force: true }) })
  } else {
    const box = new SharedArrayBuffer(128)
    const data = new SharedArrayBuffer(65536)
    const host = serve(box, data)
    const worker = new Worker(new URL(import.meta.url), { workerData: { file: absolute, args: [guest, ...moduleArgs], env, preopens, box, data }, resourceLimits: { stackSizeMb: 256 } })
    let answered = false
    worker.on('message', (result) => {
      answered = true
      if (result.note) stderr.write(result.note)
      process.exitCode = result.code
    })
    worker.on('error', (error) => {
      answered = true
      stderr.write(`${error.stack ?? error}\n`)
      process.exitCode = 1
    })
    worker.on('exit', (code) => {
      host.stop()
      rmSync(scratch, { recursive: true, force: true })
      if (!answered) process.exitCode = code || 1
    })
  }
} else if (workerData.threaded) {
  threadWorker(workerData)
} else {
  parentPort.postMessage(await run(workerData))
}
