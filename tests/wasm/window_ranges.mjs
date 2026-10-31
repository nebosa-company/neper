// Guest memory ranges passed to the window imports return WASI EINVAL instead of leaking a JavaScript RangeError.
import assert from 'node:assert/strict'
import { imports, RING_BYTES } from '../../lib/wasm/window.js'

const EINVAL = 28
const memory = new WebAssembly.Memory({ initial: 1 })
const host = () => imports({ ring: new SharedArrayBuffer(RING_BYTES) }, () => memory, () => {})

// An invalid open output must not make the host believe the window was opened.
{
  const window = host()
  assert.equal(window.window_open(1, 1, 65535), EINVAL)
  assert.equal(window.window_open(1, 1, 0), 0)
}

{
  const window = host()
  assert.equal(window.window_open(1, 1, 0), 0)
  assert.equal(window.window_metrics(1, 65535), EINVAL)
  assert.equal(window.window_title(1, 65535, 2), EINVAL)
  assert.equal(window.window_present(1, 0, 65536, 65536), EINVAL)
  assert.equal(window.window_present(1, 65535, 1, 1), EINVAL)
  assert.equal(window.clipboard_text(65535, 0, 65535), EINVAL)
  assert.equal(window.clipboard_text(65535, 2, 0), EINVAL)
  assert.equal(window.set_clipboard_text(65535, 2), EINVAL)
  assert.equal(window.window_poll(65535, 0n, 0), EINVAL)
  assert.equal(window.window_poll(0, 0n, 65535), EINVAL)
  assert.equal(window.window_title(1, 0x100000000, 0), EINVAL, 'a direct caller cannot wrap a pointer')
}

console.log('wasm window guest ranges ok')
