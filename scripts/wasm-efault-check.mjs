// Minimal raw-wasm regression for neper-host's checked iovec traversal: a module
// imports fd_write/proc_exit, calls fd_write with iovs = 65535 on a one-page memory
// (out of bounds), and exits with the returned errno. The host must answer EFAULT (21).
import { run } from '../lib/wasm/neper-host.js'

const u = (...xs) => Uint8Array.from(xs)
const vec = (xs) => Uint8Array.from(xs.flat())
const uleb = (n) => { const out = []; do { let b = n & 0x7f; n >>>= 7; if (n) b |= 0x80; out.push(b) } while (n); return out }
const section = (id, body) => vec([id, ...uleb(body.length), ...body])
const str = (s) => [...uleb(s.length), ...new TextEncoder().encode(s)]

const types = section(1, [...uleb(3), 0x60, ...uleb(4), 0x7f, 0x7f, 0x7f, 0x7f, ...uleb(1), 0x7f, 0x60, ...uleb(0), ...uleb(0), 0x60, ...uleb(1), 0x7f, ...uleb(0)])
const imports = section(2, [...uleb(2), ...str('wasi_snapshot_preview1'), ...str('fd_write'), 0x00, 0x00, ...str('wasi_snapshot_preview1'), ...str('proc_exit'), 0x00, 0x02])
const funcs = section(3, [...uleb(1), 0x01])
const mem = section(5, [...uleb(1), 0x00, ...uleb(1)])
const exports = section(7, [...uleb(2), ...str('memory'), 0x02, 0x00, ...str('_start'), 0x00, 0x02])
const body = [0x00, 0x41, 0x01, 0x41, 0xff, 0xff, 0x03, 0x41, 0x01, 0x41, 0x00, 0x10, 0x00, 0x10, 0x01, 0x0b]
const code = section(10, [...uleb(1), ...uleb(body.length), ...body])
const module = vec([0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, ...types, ...imports, ...funcs, ...mem, ...exports, ...code])

let failed = true
try {
  const result = await run(module, { stdout: () => {}, stderr: () => {} })
  if (result.exitCode === 21) { console.log('neper-host EFAULT ok (exit 21)'); failed = false }
  else console.log('unexpected exit', result.exitCode)
} catch (error) {
  console.log('host threw:', error.message)
}
if (failed) process.exitCode = 1
