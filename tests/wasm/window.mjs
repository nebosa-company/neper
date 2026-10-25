// The window of lib/wasm/window.js under Node with a canvas shim (C208, D5680):
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

  // a paste: the page's copy is refreshed by the paste event, then the key reaches the program, which reads it
  const clip = (type, data, extra = {}) => Object.assign(new Event(type), { data, inputType: 'insertText', clipboardData: { getData: () => data }, ...extra })
  canvas.dispatchEvent(clip('paste', 'Bo'))
  canvas.dispatchEvent(Object.assign(key('keydown', 'v', 'KeyV'), { ctrlKey: true }))
  canvas.dispatchEvent(Object.assign(key('keyup', 'v', 'KeyV'), { ctrlKey: true }))
  await within(until(/name AdaBo\n/), 10000, `${label}: the text pasted into the field`)
  // text from a virtual keyboard (beforeinput) and from a composition
  canvas.dispatchEvent(clip('beforeinput', 'é'))
  canvas.dispatchEvent(clip('compositionend', '漢'))
  await within(until(/name AdaBoé漢\n/), 10000, `${label}: the text from beforeinput and compositionend`)

  // the button that quits ends the run
  const [qx, qy] = centre(layout[6])
  canvas.dispatchEvent(pointer('pointerdown', qx, qy))
  canvas.dispatchEvent(pointer('pointerup', qx, qy))
  const { exitCode } = await within(finished, 10000, `${label}: the exit`)
  assert.equal(exitCode, 0, label)
  assert.match(out, /bye\n$/, label)
}


// The page and the Worker's imports without a program: only the newest frame is drawn per animation frame, the
// clipboard's copy crosses the ring both ways, and the virtual keyboard's events become the right records.
{
  const { attach, imports } = await import('../../lib/wasm/window.js')
  const { canvas, frames } = shim(64, 48)
  const queue = []
  globalThis.requestAnimationFrame = (f) => queue.push(f)
  const screen = attach(canvas)
  const frame = (v) => ({ frame: { width: 2, height: 2, rgba: new Uint8ClampedArray(16).fill(v) } })
  for (const v of [1, 2, 3]) screen.handle(frame(v))
  assert.equal(frames.length, 0, 'nothing is drawn before the animation frame')
  queue.shift()()
  assert.equal(frames.length, 1, 'one draw per animation frame')
  assert.equal(frames[0].data[0], 3, 'the newest frame is the one drawn')
  assert.equal(queue.length, 0)
  screen.handle(frame(4))
  assert.equal(queue.length, 1, 'a later frame asks for the next animation frame')
  queue.shift()()
  assert.deepEqual(screen.stats, { posted: 4, drawn: 2 })
  delete globalThis.requestAnimationFrame

  const memory = new WebAssembly.Memory({ initial: 1 })
  const posted = []
  const host = imports(screen, () => memory, (m) => posted.push(m))
  const bytes = new Uint8Array(memory.buffer)
  const view = new DataView(memory.buffer)
  assert.equal(host.clipboard_text(100, 1000, 0), 0)
  assert.equal(view.getUint32(0, true), 0, 'the copy starts empty')
  canvas.dispatchEvent(Object.assign(new Event('paste'), { clipboardData: { getData: () => 'héllo' } }))
  assert.equal(host.clipboard_text(100, 1000, 0), 0)
  assert.equal(new TextDecoder().decode(bytes.slice(100, 100 + view.getUint32(0, true))), 'héllo')
  bytes.set(new TextEncoder().encode('written'), 200)
  assert.equal(host.set_clipboard_text(200, 7), 0)
  assert.deepEqual(posted, [{ window: { clipboard: 'written' } }])
  assert.equal(host.clipboard_text(100, 1000, 0), 0)
  assert.equal(new TextDecoder().decode(bytes.slice(100, 100 + view.getUint32(0, true))), 'written')

  const poll = () => { host.window_poll(300, 0n, 400); return view.getUint32(400, true) ? [...new Uint32Array(memory.buffer, 300, 8)] : null }
  while (poll()); // the records the page pushed at attach
  const input = (type, data, inputType = 'insertText') => canvas.dispatchEvent(Object.assign(new Event(type), { data, inputType }))
  input('beforeinput', '😀')
  const [head, , , , , , , codepoint] = poll()
  assert.equal(head & 255, 10, 'a Text event')
  assert.equal(codepoint, 0x1f600)
  input('beforeinput', null, 'deleteContentBackward')
  assert.deepEqual([poll()[5], poll()[5]], [8, 8], 'Backspace down and up')
  input('compositionend', 'ab')
  assert.deepEqual([poll()[7], poll()[7]], [97, 98])
  const composing = Object.assign(new Event('beforeinput'), { data: 'x', inputType: 'insertCompositionText', isComposing: true })
  canvas.dispatchEvent(composing)
  assert.equal(poll(), null, 'composition text waits for compositionend')
  screen.dispose()
}
await exercise(counterPath, 'plain')
if (threadsPath) await exercise(threadsPath, 'threads')
console.log('neper-host window ok')
