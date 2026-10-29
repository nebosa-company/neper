// A preopen path through a link must not let fs_chmod change a file outside it.
import assert from 'node:assert/strict'
import { chmodSync, mkdtempSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { FUNCTIONS, NetHost, context } from '../../lib/wasm/run-wasm-host.mjs'

const saved = { cwd: context.cwd, tmp: context.tmp, preopens: context.preopens, env: context.env, runner: context.runner }
const data = new Uint8Array(65536)
const host = new NetHost(data)
const chmod = FUNCTIONS.findIndex(([name]) => name === 'fs_chmod')
const root = mkdtempSync(join(tmpdir(), 'neper-wasi-preopen-'))
const outside = mkdtempSync(join(tmpdir(), 'neper-wasi-outside-'))
const link = join(root, 'escape')
const outsideFile = join(outside, 'sentinel')

function pathLength(value) {
  data.fill(0)
  const bytes = Buffer.from(value)
  data.set(bytes, 128)
  return bytes.length
}

try {
  assert.notEqual(chmod, -1, 'fs_chmod is registered')
  context.preopens = { '/work': root }
  const insideFile = join(root, 'inside')
  writeFileSync(insideFile, 'inside')
  writeFileSync(outsideFile, 'outside')
  chmodSync(outsideFile, 0o444)
  symlinkSync(outside, link, process.platform === 'win32' ? 'junction' : 'dir')

  assert.equal(await host.call(chmod, [3, 0, pathLength('inside'), 0o444]), 0, 'a path inside the preopen can be chmodded')
  assert.equal(statSync(insideFile).mode & 0o222, 0, 'the inside file received its mode change')
  assert.equal(statSync(outsideFile).mode & 0o222, 0, 'the outside sentinel starts read-only')

  const escaped = await host.call(chmod, [3, 0, pathLength('escape/sentinel'), 0o666])
  assert.equal(escaped, 2, 'a symlink target outside the preopen is refused')
  assert.equal(statSync(outsideFile).mode & 0o222, 0, 'the outside sentinel was not made writable')
} finally {
  Object.assign(context, saved)
  host.closeAll()
  rmSync(root, { recursive: true, force: true })
  rmSync(outside, { recursive: true, force: true })
}

console.log('wasm host preopen symlink boundary ok')
