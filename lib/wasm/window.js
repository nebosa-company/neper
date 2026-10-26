// The window of a wasm32-wasi module in a page (D5680, C208): `run(source, { canvas })` gives the module one window,
// drawn on a <canvas>, with input from a ring in a SharedArrayBuffer. A Worker running wasm cannot receive a message
// while it runs, so the page writes input into the ring and window_poll reads it with Atomics.wait; frames and
// the title and cursor go the other way as messages, which a running Worker can post. The canvas needs a CSS size
// (the window is that size times devicePixelRatio, and frames are drawn at it); one without falls back to its
// width and height attributes, and its backing size follows the frames.
//
// Ring (Int32 words, then 256 records of 8 words): 0 head (read by window_poll), 1 tail (written by the page),
// 2..6 the window's metrics (width, height, scale percent, focused, visible), records from byte 64. A record is
// the fields of os.WindowEvent: word 0 kind | button << 8 | modifiers << 16 | repeat << 24, then x, y, width,
// height, key, delta, codepoint. The `window` is always 1.
//
// Imports (neper_host, answering a WASI errno): window_open(width, height, out_handle), window_metrics(handle,
// out_5_u32), window_title(handle, ptr, len), window_present(handle, pixels, width, height), window_poll(out_record,
// timeout_ns, out_has), window_cursor(handle, shape), clipboard_text(out, capacity, out_used), set_clipboard_text(ptr, len).
// Text reaches the program as Text events from keydown, beforeinput and compositionend (a virtual keyboard, the
// Browser pane's type action), on a <textarea> the page keeps beside the canvas.

const SLOTS = 256
const WORDS = 8
const RECORDS = 64
const CLIP = RECORDS + SLOTS * WORDS * 4 // the clipboard's copy: word 7 is its length in bytes, the text follows the records
const CLIP_CAP = 65536
export const RING_BYTES = CLIP + CLIP_CAP
const store = (words, ring, text) => {
  // encodeInto rejects a shared buffer; cut on a codepoint boundary
  const encoded = new TextEncoder().encode(text)
  let n = Math.min(encoded.length, CLIP_CAP)
  while (n < encoded.length && n > 0 && (encoded[n] & 0xc0) === 0x80) n--
  new Uint8Array(ring, CLIP, CLIP_CAP).set(encoded.subarray(0, n))
  Atomics.store(words, 7, n)
}
const E = { NOSYS: 52, NOTSUP: 58, INVAL: 28 }
const KIND = { Resize: 1, Focus: 2, Blur: 3, PointerMove: 4, PointerDown: 5, PointerUp: 6, Scroll: 7, KeyDown: 8, KeyUp: 9, Text: 10, Paint: 11 }
const CURSORS = ['default', 'text', 'pointer', 'crosshair', 'ew-resize', 'ns-resize', 'none']

// Windows virtual key codes (what e.ui reads), F keys as X11's 0xffbe range
const BY_CODE = { Space: 32, Minus: 189, Equal: 187, Comma: 188, Period: 190, Slash: 191, Semicolon: 186, Quote: 222, BracketLeft: 219, BracketRight: 221, Backslash: 220, Backquote: 192 }
const BY_KEY = { Backspace: 8, Tab: 9, Enter: 13, Escape: 27, PageUp: 33, PageDown: 34, End: 35, Home: 36, ArrowLeft: 37, ArrowUp: 38, ArrowRight: 39, ArrowDown: 40, Insert: 45, Delete: 46, ContextMenu: 93, Shift: 16, Control: 17, Alt: 18, Meta: 91, CapsLock: 20 }
const BUTTON = [0, 2, 1, 3, 4] // DOM main, auxiliary, secondary, back, forward -> Primary, Secondary, Middle, Back, Forward order of the fence

function keyCode(e) {
  const code = e.code ?? ''
  let m
  if ((m = /^Key([A-Z])$/.exec(code))) return m[1].charCodeAt(0)
  if ((m = /^Digit(\d)$/.exec(code))) return 48 + Number(m[1])
  if ((m = /^Numpad(\d)$/.exec(code))) return 96 + Number(m[1])
  if ((m = /^F(\d+)$/.exec(e.key ?? ''))) return 0xffbe + Number(m[1]) - 1
  // synthetic key events (the Browser pane's) can lack `code`
  if (!code && /^[a-z0-9]$/i.test(e.key ?? '')) return e.key.toUpperCase().charCodeAt(0)
  return BY_KEY[e.key] ?? BY_CODE[code] ?? 0
}

// ---- the page's side ------------------------------------------------------------------------------------------------

// Listens on `canvas`, owns the ring. Returns { ring, handle(message), dispose() }: handle() draws a frame the Worker
// posted and applies its title and cursor.
export function attach(canvas) {
  const ring = new SharedArrayBuffer(RING_BYTES)
  const words = new Int32Array(ring)
  const initial = { width: canvas.width, height: canvas.height }
  const stop = []
  const on = (target, type, listener, options) => {
    target.addEventListener(type, listener, options)
    stop.push(() => target.removeEventListener(type, listener, options))
  }
  const metrics = () => {
    const scale = globalThis.devicePixelRatio || 1
    const width = Math.round((canvas.clientWidth || 0) * scale) || initial.width
    const height = Math.round((canvas.clientHeight || 0) * scale) || initial.height
    const changed = words[2] !== width || words[3] !== height || words[4] !== Math.round(scale * 100)
    words[2] = width
    words[3] = height
    words[4] = Math.round(scale * 100)
    words[6] = globalThis.document?.visibilityState === 'hidden' ? 0 : 1
    return changed
  }
  // ponytail: a full ring drops the new event; coalescing pointer moves is the upgrade if a program falls behind.
  const push = (kind, { button = 0, modifiers = 0, repeat = 0, x = 0, y = 0, width = 0, height = 0, key = 0, delta = 0, codepoint = 0 } = {}) => {
    const tail = Atomics.load(words, 1)
    if (tail - Atomics.load(words, 0) >= SLOTS) return
    const at = (RECORDS >> 2) + (tail % SLOTS) * WORDS
    words[at] = kind | (button << 8) | (modifiers << 16) | (repeat << 24)
    words[at + 1] = x
    words[at + 2] = y
    words[at + 3] = width
    words[at + 4] = height
    words[at + 5] = key
    words[at + 6] = delta
    words[at + 7] = codepoint
    Atomics.store(words, 1, tail + 1)
    Atomics.notify(words, 1)
  }
  const modifiers = (e) => (e.shiftKey ? 1 : 0) | (e.ctrlKey ? 2 : 0) | (e.altKey ? 4 : 0) | (e.metaKey ? 8 : 0) | (e.getModifierState?.('CapsLock') ? 16 : 0) | (e.getModifierState?.('NumLock') ? 32 : 0)
  const point = (e) => {
    const rect = canvas.getBoundingClientRect?.() ?? { left: 0, top: 0 }
    // the content box: the border does not count, and the backing size over the CSS size is the scale
    const scaleX = canvas.clientWidth ? words[2] / canvas.clientWidth : (globalThis.devicePixelRatio || 1)
    const scaleY = canvas.clientHeight ? words[3] / canvas.clientHeight : (globalThis.devicePixelRatio || 1)
    return { x: Math.round((e.clientX - rect.left - (canvas.clientLeft || 0)) * scaleX), y: Math.round((e.clientY - rect.top - (canvas.clientTop || 0)) * scaleY), modifiers: modifiers(e) }
  }

  words[5] = 1
  metrics()
  if (canvas.tabIndex < 0) canvas.tabIndex = 0
  on(canvas, 'pointerdown', (e) => {
    try { canvas.setPointerCapture?.(e.pointerId) } catch {}
    canvas.focus?.()
    push(KIND.PointerDown, { ...point(e), button: BUTTON[e.button] ?? 0 })
    e.preventDefault?.()
  })
  on(canvas, 'pointerup', (e) => push(KIND.PointerUp, { ...point(e), button: BUTTON[e.button] ?? 0 }))
  on(canvas, 'pointermove', (e) => push(KIND.PointerMove, point(e)))
  on(canvas, 'contextmenu', (e) => e.preventDefault?.())
  on(canvas, 'wheel', (e) => {
    const notches = Math.max(1, Math.round(Math.abs(e.deltaY) / (e.deltaMode === 0 ? 100 : 1)))
    push(KIND.Scroll, { ...point(e), delta: -Math.sign(e.deltaY) * 120 * notches })
    e.preventDefault?.()
  }, { passive: false })
  // Keyboard focus lives in `sink`: a transparent <textarea> beside the canvas when there is a document, because a
  // canvas is not editable and so shows no virtual keyboard and gets no beforeinput; otherwise the canvas itself.
  let sink = canvas
  if (globalThis.document?.createElement && canvas.parentNode) {
    sink = document.createElement('textarea')
    sink.setAttribute('aria-label', 'keyboard input')
    sink.autocapitalize = 'off'
    sink.autocomplete = 'off'
    sink.spellcheck = false
    Object.assign(sink.style, { position: 'fixed', left: '0', top: '0', width: '1px', height: '1px', opacity: '0', border: '0', padding: '0', resize: 'none', fontSize: '16px' })
    canvas.parentNode.insertBefore(sink, canvas.nextSibling)
    stop.push(() => sink.remove())
    on(canvas, 'focus', () => sink.focus())
  }
  const text = (s) => { for (const c of s ?? '') push(KIND.Text, { codepoint: c.codePointAt(0) }); if (sink !== canvas) sink.value = '' }
  const tap = (key) => { push(KIND.KeyDown, { key }); push(KIND.KeyUp, { key }) }
  // Ctrl or Cmd V waits for the paste event (which carries the text) before the program sees the key and reads the
  // clipboard's copy; 100 ms is the longest it waits when none comes.
  let held
  const release = () => { if (!held) return; clearTimeout(held.timer); const send = held.send; held = undefined; send() }
  on(sink, 'keydown', (e) => {
    if (e.isComposing || e.keyCode === 229) return
    const m = modifiers(e)
    const send = () => {
      push(KIND.KeyDown, { key: keyCode(e), modifiers: m, repeat: e.repeat ? 1 : 0 })
      const [first] = e.key ?? ''
      if (first && [...e.key].length === 1 && !(m & 8) && (!(m & 2) || m & 4)) push(KIND.Text, { codepoint: e.key.codePointAt(0), modifiers: m })
    }
    if (m & 10 && !(m & 4) && (e.key ?? '').toLowerCase() === 'v' && !e.repeat) { held = { send, timer: setTimeout(release, 100) }; return }
    send()
    if (!e.metaKey && !/^F\d/.test(e.key ?? '')) e.preventDefault?.()
  })
  on(sink, 'keyup', (e) => { release(); push(KIND.KeyUp, { key: keyCode(e), modifiers: modifiers(e) }) })
  // A virtual keyboard sends beforeinput (and composition for a language that composes), not keys.
  on(sink, 'beforeinput', (e) => {
    const kind = e.inputType ?? ''
    if (e.isComposing || kind === 'insertCompositionText') return
    if (kind === 'insertText' || kind === 'insertReplacementText') text(e.data)
    else if (kind === 'insertLineBreak' || kind === 'insertParagraph') tap(13)
    else if (kind === 'deleteContentBackward') tap(8)
    else if (kind === 'deleteContentForward') tap(46)
    e.preventDefault?.()
  })
  on(sink, 'compositionend', (e) => text(e.data))
  on(sink, 'paste', (e) => {
    const pasted = e.clipboardData?.getData?.('text/plain')
    if (typeof pasted === 'string') store(words, ring, pasted)
    e.preventDefault?.()
    release()
  })
  on(sink, 'focus', () => {
    words[5] = 1
    push(KIND.Focus)
    // best effort: the browser may ask the person or refuse
    try { navigator.clipboard?.readText?.().then((t) => store(words, ring, t), () => {}) } catch {}
  })
  on(sink, 'blur', () => { words[5] = 0; push(KIND.Blur) })
  const resized = () => { if (metrics()) push(KIND.Resize, { width: words[2], height: words[3] }) }
  if (typeof ResizeObserver === 'function') {
    const observer = new ResizeObserver(resized)
    observer.observe(canvas)
    stop.push(() => observer.disconnect())
  }
  // a change of devicePixelRatio (page zoom, another screen) resizes nothing the observer sees
  const watchScale = () => {
    if (typeof matchMedia !== 'function') return
    const query = matchMedia(`(resolution: ${globalThis.devicePixelRatio}dppx)`)
    const changed = () => { resized(); watchScale() }
    query.addEventListener('change', changed, { once: true })
    stop.push(() => query.removeEventListener('change', changed))
  }
  watchScale()
  if (globalThis.document?.addEventListener) on(document, 'visibilitychange', () => { metrics(); push(KIND.Paint) })

  // Only the newest posted frame is drawn, once per animation frame: a program that presents faster than the page
  // paints would otherwise queue frames the person never sees (without requestAnimationFrame, as in Node, each is drawn).
  let drawing
  let newest
  let waiting = false
  const stats = { posted: 0, drawn: 0 }
  const paint = () => {
    waiting = false
    const { width, height, rgba } = newest
    newest = undefined
    if (canvas.width !== width || canvas.height !== height) { canvas.width = width; canvas.height = height }
    drawing ??= canvas.getContext('2d')
    drawing.putImageData(typeof ImageData === 'function' ? new ImageData(rgba, width, height) : { data: rgba, width, height }, 0, 0)
    stats.drawn++
  }
  return {
    ring,
    stats,
    handle(m) {
      if (m.title !== undefined && globalThis.document) document.title = m.title
      if (m.cursor !== undefined && canvas.style) canvas.style.cursor = m.cursor
      if (m.clipboard !== undefined) { try { navigator.clipboard?.writeText?.(m.clipboard).catch(() => {}) } catch {} }
      if (m.frame) {
        newest = m.frame
        stats.posted++
        if (!waiting) {
          waiting = true
          if (typeof requestAnimationFrame === 'function') requestAnimationFrame(paint)
          else paint()
        }
      }
    },
    dispose() { for (const f of stop) f() },
  }
}

// ---- the Worker's side ------------------------------------------------------------------------------------------------

// The neper_host window imports of a module whose memory is `memory()`. `post` sends a message to the page.
export function imports({ ring }, memory, post) {
  const words = new Int32Array(ring)
  const decoder = new TextDecoder()
  let opened = false
  let frame
  const view = () => new DataView(memory().buffer)
  const known = (handle) => (opened && handle === 1 ? 0 : 8)
  return {
    window_open: (width, height, made) => {
      if (opened) return E.NOTSUP
      opened = true
      view().setUint32(made, 1, true)
      return 0
    },
    window_metrics: (handle, out) => {
      const bad = known(handle)
      if (bad) return bad
      const v = view()
      for (let k = 0; k < 5; k++) v.setUint32(out + 4 * k, Atomics.load(words, 2 + k), true)
      return 0
    },
    window_title: (handle, pointer, length) => {
      const bad = known(handle)
      if (bad) return bad
      post({ window: { title: decoder.decode(new Uint8Array(memory().buffer).slice(pointer, pointer + length)) } })
      return 0
    },
    window_cursor: (handle, shape) => {
      const bad = known(handle)
      if (bad) return bad
      post({ window: { cursor: CURSORS[shape] ?? 'default' } })
      return 0
    },
    window_present: (handle, pixels, width, height) => {
      const bad = known(handle)
      if (bad) return bad
      if (!width || !height) return E.INVAL
      // bytes B G R A (the 0xAARRGGBB the fence presents) become R G B A, and alpha is ignored as SetDIBits ignores it
      const count = width * height
      const source = pixels & 3 ? new Uint32Array(new Uint8Array(memory().buffer).slice(pixels, pixels + count * 4).buffer) : new Uint32Array(memory().buffer, pixels, count)
      if (frame?.length !== count * 4) frame = new Uint8ClampedArray(count * 4)
      const target = new Uint32Array(frame.buffer)
      for (let k = 0; k < count; k++) {
        const v = source[k]
        target[k] = 0xff000000 | (v & 0xff00) | ((v & 0xff) << 16) | ((v >>> 16) & 0xff)
      }
      // The frame goes to the page, which draws it: an OffscreenCanvas transferred to this Worker never shows a frame
      // while the module keeps running, because the canvas is committed when the Worker's task ends (measured, D5790).
      post({ window: { frame: { width, height, rgba: frame } } }, [frame.buffer])
      frame = undefined
      return 0
    },
    // The page's copy of the clipboard (it refreshes it on a paste and a focus); a set writes the copy and asks the
    // page to write navigator.clipboard, which only a page can.
    clipboard_text: (out, capacity, used) => {
      const length = Atomics.load(words, 7)
      if (length > capacity) return E.INVAL
      new Uint8Array(memory().buffer).set(new Uint8Array(ring, CLIP, length), out)
      view().setUint32(used, length, true)
      return 0
    },
    set_clipboard_text: (pointer, length) => {
      const text = decoder.decode(new Uint8Array(memory().buffer).slice(pointer, pointer + length))
      store(words, ring, text)
      post({ window: { clipboard: text } })
      return 0
    },
    window_poll: (out, timeout, has) => {
      const head = Atomics.load(words, 0)
      let tail = Atomics.load(words, 1)
      if (tail === head && timeout > 0n) {
        Atomics.wait(words, 1, tail, Number(timeout) / 1e6)
        tail = Atomics.load(words, 1)
      }
      const v = view()
      if (tail === head) { v.setUint32(has, 0, true); return 0 }
      const at = (RECORDS >> 2) + (head % SLOTS) * WORDS
      for (let k = 0; k < WORDS; k++) v.setUint32(out + 4 * k, words[at + k] >>> 0, true)
      v.setUint32(has, 1, true)
      Atomics.store(words, 0, head + 1)
      return 0
    },
  }
}
