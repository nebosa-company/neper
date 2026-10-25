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
// The status is left in `process.exitCode` and the process left to end by itself: on Windows
// `process.exit` while the engine is still finishing a background compile aborts Node
// ("Assertion failed: !(handle->flags & UV_HANDLE_CLOSING)", exit 127).
import { readFile } from 'node:fs/promises'
import { mkdirSync, mkdtempSync, readdirSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path'
import { WASI } from 'node:wasi'
import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads'
import { argv, env as hostEnv, stderr } from 'node:process'
import { hostImports, serve } from './run-wasm-host.mjs'

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

async function run({ args, env, preopens }) {
  const wasi = new WASI({ version: 'preview1', args, env, preopens, returnOnExit: true })
  let instance
  const began = performance.now()
  try {
    const module = await WebAssembly.compile(await readFile(workerData.file))
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
    if (/Maximum call stack size exceeded/.test(error.message)) return { code: 134, note: ': trap[stack]: stack overflow (the engine\'s call stack)\n' }
    return { code: 134, note: `: engine error: ${error}\n` }
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
  const box = new SharedArrayBuffer(128)
  const data = new SharedArrayBuffer(65536)
  const host = serve(box, data)
  const worker = new Worker(new URL(import.meta.url), { workerData: { file: absolute, args: [guest, ...moduleArgs], env, preopens, box, data }, resourceLimits: { stackSizeMb: 256 } })
  const clean = () => {
    host.stop()
    rmSync(scratch, { recursive: true, force: true })
  }
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
    clean()
    if (!answered) process.exitCode = code || 1
  })
  for (const [signal, status] of [['SIGINT', 130], ['SIGTERM', 143]]) {
    process.on(signal, () => {
      clean()
      process.exit(status)
    })
  }
} else {
  parentPort.postMessage(await run(workerData))
}
