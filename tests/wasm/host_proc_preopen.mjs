// `proc_spawn` may name a WASM child or a native working directory only inside
// the selected guest preopen/root.  Each rejected path must fail before a child
// record is allocated or Node starts a process.
import assert from 'node:assert/strict'
import { mkdirSync, mkdtempSync, rmSync, symlinkSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { BASE, NetHost, context } from '../../lib/wasm/run-wasm-host.mjs'

const EACCES = 2
const saved = { cwd: context.cwd, tmp: context.tmp, preopens: context.preopens, env: context.env, runner: context.runner }
const data = new Uint8Array(65536)
const host = new NetHost(data)
const parent = mkdtempSync(join(tmpdir(), 'neper-wasi-proc-parent-'))
const root = join(parent, 'root')
const outside = join(parent, 'outside')

function spawnArguments(argv, cwd) {
  const argumentsBytes = Buffer.from(`${argv.join('\0')}\0${cwd}`)
  data.fill(0)
  data.set(argumentsBytes, 128)
  return [0, argumentsBytes.length, argv.length, 0, 0, Buffer.byteLength(cwd), 0, 1, 2]
}

function denied(argv, cwd, message) {
  return host.procSpawn(spawnArguments(argv, cwd)).then((result) => {
    assert.equal(result, EACCES, message)
    assert.equal(host.procs.size, 0, `${message}: no child is recorded`)
    assert.equal(host.ids.next, BASE, `${message}: no process id is consumed`)
  })
}

try {
  mkdirSync(root)
  mkdirSync(outside)
  let hasJunction = true
  try {
    symlinkSync(outside, join(root, 'escape'), process.platform === 'win32' ? 'junction' : 'dir')
  } catch (error) {
    if (error?.code !== 'EPERM') throw error
    hasJunction = false
  }
  Object.assign(context, { cwd: root, tmp: root, preopens: { '/work': root }, env: {}, runner: process.execPath })

  await denied(['/work/../outside/child.wasm'], '', 'a WASM child path with parent traversal is refused')
  await denied([process.execPath, '-e', 'process.exit(0)'], '/work/../outside', 'a native CWD with preopen parent traversal is refused')
  await denied([process.execPath, '-e', 'process.exit(0)'], '../outside', 'a fallback-root CWD with parent traversal is refused')
  if (hasJunction) await denied([process.execPath, '-e', 'process.exit(0)'], '/work/escape', 'a native CWD through a preopen junction is refused')
} finally {
  Object.assign(context, saved)
  host.closeAll()
  rmSync(parent, { recursive: true, force: true })
}

console.log('wasm host proc preopen boundary ok')
