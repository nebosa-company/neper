// The window of lib/wasm/window.js under Node with a canvas shim (C193, D5680):
//   node --no-warnings tests/wasm/window.mjs UI_COUNTER.wasm [UI_COUNTER.threads.wasm]
// UI_COUNTER is tests/wasm/browser/ui_counter built for wasm32-wasi (the second one with --threads, the first thread's
// Worker owning the window). The shim is a canvas that is an EventTarget and keeps the frames the page draws on it
// (frames arrive from the Worker as messages). tests/wasm/browser/ui_counter.html runs the same program on a real
// canvas (ResizeObserver and real events).
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { run } from '../../lib/wasm/neper-host.js'

const [counterPath, threadsPath] = process.argv.slice(2)
const font = new Uint8Array(await readFile(new URL('../../neperos/assets/fonts/jost-regular.ttf', import.meta.url)))

function shim(width, height) {
  const canvas = new EventTarget()
  const frames = []
  Object.assign(canvas, {
    width, height, clientWidth: width, clientHeight: height, tabIndex: -1, style: {},
    focus() {}, getBoundingClientRect: () => ({ left: 0, top: 0, width, height }),
    getContext: () => ({ putImageData: (image) => frames.push({ width: image.width, height: image.height, data: image.data.slice() }) }),
  })
  return { canvas, frames }
}
const pointer = (type, x, y, button = 0) => Object.assign(new Event(type), { clientX: x, clientY: y, button, pointerId: 1 })
const key = (type, k, code) => Object.assign(new Event(type), { key: k, code, repeat: false, shiftKey: false, ctrlKey: false, altKey: false, metaKey: false })
const within = (promise, ms, what) => Promise.race([promise, new Promise((_, reject) => setTimeout(() => reject(new Error(`timed out waiting for ${what}`)), ms))])

async function exercise(path, label) {
  const bytes = new Uint8Array(await readFile(path))
  let out = ''
  const waiters = []
  const stdout = (b) => {
    out += new TextDecoder().decode(b)
    for (const w of waiters.slice()) if (w.test()) { waiters.splice(waiters.indexOf(w), 1); w.done() }
  }
  const until = (pattern) => new Promise((resolve) => {
    const test = () => pattern.test(out)
    if (test()) resolve(); else waiters.push({ test, done: resolve })
  })
  const { canvas, frames } = shim(480, 320)
  const finished = run(bytes, { canvas, files: { 'jost-regular.ttf': font }, stdout, stderr: (b) => process.stderr.write(b) })
  await within(until(/layout 6 \d+ \d+ \d+ \d+\n/), 20000, `${label}: the first layout`)
  const layout = {}
  for (const m of out.matchAll(/layout (\d+) (\d+) (\d+) (\d+) (\d+)/g)) layout[m[1]] = { x: +m[2], y: +m[3], width: +m[4], height: +m[5] }
  const centre = (r) => [r.x + r.width / 2, r.y + r.height / 2]

  // the first frame: drawn at the canvas size, not blank, opaque
  assert.ok(frames.length > 0, `${label}: no frame was presented`)
  const first = frames.at(-1)
  assert.equal(first.width, 480)
  assert.equal(first.height, 320)
  assert.ok(new Set(new Uint32Array(first.data.buffer)).size > 3, `${label}: the first frame is blank`)
  assert.ok(new Uint32Array(first.data.buffer).every((p) => p >>> 24 === 255), `${label}: alpha must be opaque`)

  // a click on the button raises the count and the frame changes
  const [bx, by] = centre(layout[3])
  canvas.dispatchEvent(pointer('pointerdown', bx, by))
  canvas.dispatchEvent(pointer('pointerup', bx, by))
  await within(until(/count 1\n/), 10000, `${label}: the count after a click`)
  await new Promise((resolve) => setTimeout(resolve, 300))
  assert.notDeepEqual(frames.at(-1).data, first.data, `${label}: the frame did not change after the click`)

  // typed text reaches the field
  const [fx, fy] = centre(layout[4])
  canvas.dispatchEvent(pointer('pointerdown', fx, fy))
  canvas.dispatchEvent(pointer('pointerup', fx, fy))
  for (const [k, code] of [['A', 'KeyA'], ['d', 'KeyD'], ['a', 'KeyA']]) {
    canvas.dispatchEvent(key('keydown', k, code))
    canvas.dispatchEvent(key('keyup', k, code))
  }
  await within(until(/name Ada\n/), 10000, `${label}: the text typed into the field`)

  // the button that quits ends the run
  const [qx, qy] = centre(layout[6])
  canvas.dispatchEvent(pointer('pointerdown', qx, qy))
  canvas.dispatchEvent(pointer('pointerup', qx, qy))
  const { exitCode } = await within(finished, 10000, `${label}: the exit`)
  assert.equal(exitCode, 0, label)
  assert.match(out, /bye\n$/, label)
}

await exercise(counterPath, 'plain')
if (threadsPath) await exercise(threadsPath, 'threads')
console.log('neper-host window ok')
