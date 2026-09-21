// `e.ui.widget`'s editable text (D807, widget plan P0-04): a single-line editor and
// a multiline one over the square-glyph font; a press places the caret by hit test
// and a drag selects; typed text replaces the selection and reports each change;
// Left/Right/Home/End with Shift extending; Backspace and Delete; copy, cut and
// paste; undo and redo through a coalesced history; Enter submitting a single line
// and breaking a multiline one, with Up and Down between its lines; a composition
// committed by its text; a full buffer refusing more; Tab leaving the editor.

use e.gpu
use e.io
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.text.layout
use e.text.shape
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget
use e.ui.window

fn w16(d: []u8, at: usize, v: u32) {
    d[at] = u8((v >> 8u32) & 255u32)
    d[at + 1usize] = u8(v & 255u32)
}
fn w32(d: []u8, at: usize, v: u32) {
    w16(d, at, v >> 16u32)
    w16(d, at + 2usize, v & 65535u32)
}
fn record(d: []u8, slot: usize, tag: u32, at: usize, len: usize) {
    let r = 12usize + 16usize * slot
    w32(d, r, tag)
    w32(d, r + 8usize, u32(at))
    w32(d, r + 12usize, u32(len))
}

// The square-glyph font of the scene fixture, with a cmap mapping `a` to glyph 1.
fn synthetic_font(a: *mem.Arena) -> ([]u8, err) {
    let (d, d_error) = mem.alloc[u8](a, 512usize)
    if d_error != ok { ret (d, d_error) }
    var i = 0usize
    while i < 512usize {
        d[i] = 0u8
        i += 1usize
    }
    w32(d, 0usize, 65536u32)
    w16(d, 4usize, 7u32)
    record(d, 0usize, 1751474532u32, 128usize, 54usize)
    w16(d, 128usize + 18usize, 1000u32)
    record(d, 1usize, 1751672161u32, 192usize, 36usize)
    w16(d, 192usize + 4usize, 800u32)
    w16(d, 192usize + 34usize, 2u32)
    record(d, 2usize, 1752003704u32, 228usize, 8usize)
    w16(d, 228usize + 4usize, 600u32)
    record(d, 3usize, 1835104368u32, 236usize, 6usize)
    w16(d, 236usize + 4usize, 2u32)
    // cmap at 300: one encoding record (3, 1) to a format 4 subtable with one
    // segment, `a` (0x61) to glyph 1, and the 0xFFFF terminator.
    record(d, 4usize, 1668112752u32, 300usize, 44usize)
    w16(d, 300usize, 0u32)
    w16(d, 302usize, 1u32)
    w16(d, 304usize, 3u32)
    w16(d, 306usize, 1u32)
    w32(d, 308usize, 12u32)
    let sub = 312usize
    w16(d, sub, 4u32)
    w16(d, sub + 2usize, 32u32)
    w16(d, sub + 4usize, 0u32)
    w16(d, sub + 6usize, 4u32)
    w16(d, sub + 8usize, 4u32)
    w16(d, sub + 10usize, 1u32)
    w16(d, sub + 12usize, 0u32)
    w16(d, sub + 14usize, 97u32)
    w16(d, sub + 16usize, 65535u32)
    w16(d, sub + 18usize, 0u32)
    w16(d, sub + 20usize, 97u32)
    w16(d, sub + 22usize, 65535u32)
    w16(d, sub + 24usize, 65440u32)
    w16(d, sub + 26usize, 1u32)
    w16(d, sub + 28usize, 0u32)
    w16(d, sub + 30usize, 0u32)
    record(d, 5usize, 1819239265u32, 252usize, 6usize)
    record(d, 6usize, 1735162214u32, 260usize, 40usize)
    let g = 260usize
    w16(d, g, 1u32)
    w16(d, g + 2usize, 100u32)
    w16(d, g + 4usize, 100u32)
    w16(d, g + 6usize, 900u32)
    w16(d, g + 8usize, 900u32)
    w16(d, g + 10usize, 3u32)
    w16(d, g + 12usize, 0u32)
    var at = g + 14usize
    d[at] = 55u8
    d[at + 1usize] = 33u8
    d[at + 2usize] = 17u8
    d[at + 3usize] = 33u8
    at += 4usize
    d[at] = 100u8
    d[at + 1usize] = 3u8
    d[at + 2usize] = 32u8
    d[at + 3usize] = 252u8
    d[at + 4usize] = 224u8
    at += 5usize
    d[at] = 100u8
    d[at + 1usize] = 3u8
    d[at + 2usize] = 32u8
    at += 3usize
    w16(d, 252usize + 2usize, 0u32)
    w16(d, 252usize + 4usize, u32((at - g) / 2usize))
    ret (d, ok)
}

type Log = struct { changes: usize, submits: usize, last: [32]u8, last_len: usize }

fn on_change(ctx: *void, value: str) -> err {
    let log = mem.cast[*Log](ctx)
    log.changes += 1usize
    var n = value.len
    if n > 32usize { n = 32usize }
    var i = 0usize
    while i < n {
        log.last[i] = value[i]
        i += 1usize
    }
    log.last_len = n
    ret ok
}

fn on_submit(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.submits += 1usize
    ret ok
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn sized(width: f32, height: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: width }
    s.height = style.Length { Px: height }
    ret s
}

fn pointer(x: f32, y: f32) -> input.Pointer {
    ret input.Pointer { window: window.Id { slot: 0u32, generation: 0u32 }, device: 0u32, pointer: 0u32, kind: .Mouse, position: geometry.Point { x: x, y: y }, buttons: 1u32, changed: .Primary }
}

fn key(code: u32, shift: bool, control: bool) -> input.Event {
    ret input.Event { KeyDown: input.KeyEvent { window: window.Id { slot: 0u32, generation: 0u32 }, key: input.Key { physical: code, logical: code }, modifiers: input.Modifiers { shift: shift, control: control, alt: false, meta: false, caps_lock: false, num_lock: false }, repeat: false } }
}

fn typed(value: str) -> input.Event {
    ret input.Event { Text: input.TextEvent { window: window.Id { slot: 0u32, generation: 0u32 }, text: value } }
}

type Fixture = struct { runtime: widget.Runtime, first: widget.ElementId, second: widget.ElementId }

fn send(f: *Fixture, event: input.Event, code: i32) {
    if widget.dispatch(&f.runtime, event) != ok { os.exit(code) }
}

fn expect_value(f: *Fixture, element: widget.ElementId, value: str, code: i32) {
    let (shown, has_shown) = widget.edit_value(&f.runtime, element)
    if !has_shown || !same(shown, value) { os.exit(code) }
}

fn expect_selection(f: *Fixture, element: widget.ElementId, lo: usize, hi: usize, code: i32) {
    let (start, end, has_selection) = widget.edit_selection(&f.runtime, element)
    if !has_selection || start != lo || end != hi { os.exit(code) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (t, target_error) = gpu.open_target(q, gpu.Surface { kind: .Offscreen, handle: zero, context: zero }, 64u32, 100u32, .Rgba8)
    if target_error != ok { os.exit(3i32) }
    let (canvas, canvas_error) = scene.target_of(a, t)
    if canvas_error != ok { os.exit(4i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(5i32) }
    var renderer = r
    let (font_bytes, font_error) = synthetic_font(a)
    if font_error != ok { os.exit(6i32) }
    let font = shape.Font { id: 7u32, data: font_bytes, face_index: 0u32 }
    if scene.register_font(&renderer, font) != ok { os.exit(7i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 32usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 128usize })
    if runtime_error != ok { os.exit(8i32) }
    var f: Fixture = zero
    f.runtime = rt
    var log: Log = zero
    let ctx = mem.cast[*void](&log)
    let (fonts, fonts_error) = mem.alloc[layout.FontChoice](a, 1usize)
    if fonts_error != ok { os.exit(9i32) }
    fonts[0usize] = layout.FontChoice { font: font, size: 16.0 }
    let text_style = layout.Style { fonts: fonts, language: "", line_height: 16.0 }
    // The first editor's buffer holds sixteen bytes, the second's thirty-two.
    let (first_buffer, first_buffer_error) = mem.alloc[u8](a, 16usize)
    if first_buffer_error != ok { os.exit(10i32) }
    let (second_buffer, second_buffer_error) = mem.alloc[u8](a, 32usize)
    if second_buffer_error != ok { os.exit(11i32) }
    let (children, children_error) = mem.alloc[widget.Node](a, 2usize)
    if children_error != ok { os.exit(12i32) }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let blue = paint.rgba(0.0, 0.0, 1.0, 1.0)
    children[0usize] = widget.edit(1u64, widget.Edit { buffer: first_buffer, len: 0usize, style: text_style, color: white, selection: blue, change: widget.Change[str] { ctx: ctx, invoke: on_change }, submit: widget.Submit { ctx: ctx, invoke: on_submit }, enabled: true, read_only: false, multiline: false }, sized(64.0, 20.0))
    children[1usize] = widget.edit(2u64, widget.Edit { buffer: second_buffer, len: 0usize, style: text_style, color: white, selection: blue, change: zero, submit: widget.Submit { ctx: ctx, invoke: on_submit }, enabled: true, read_only: false, multiline: true }, sized(64.0, 60.0))
    var column = style.defaults()
    column.width = style.Length { Px: 64.0 }
    column.height = style.Length { Px: 100.0 }
    let root = widget.flex(3u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, column, children[0usize..2usize])
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(13i32) }
    var frame = mem.arena_from(frame_storage)
    let limits = ui_layout.Constraints { min_width: 0.0, max_width: 64.0, min_height: 0.0, max_height: 100.0 }
    let (compiled, reconcile_error) = widget.reconcile(&f.runtime, &frame, root, limits)
    if reconcile_error != ok { os.exit(14i32) }
    let (first, first_count) = widget.find_by_key(mem.cast[*widget.State](f.runtime.state), 1u64)
    let (second, second_count) = widget.find_by_key(mem.cast[*widget.State](f.runtime.state), 2u64)
    if first_count != 1usize || second_count != 1usize { os.exit(15i32) }
    f.first = first
    f.second = second
    // A press focuses the first editor with the caret at the start of its empty value.
    send(&f, input.Event { PointerDown: pointer(5.0, 10.0) }, 16i32)
    send(&f, input.Event { PointerUp: pointer(5.0, 10.0) }, 17i32)
    let (focus_now, has_focus) = widget.focused(&f.runtime)
    if !has_focus || focus_now.slot != first.slot { os.exit(18i32) }
    expect_selection(&f, first, 0usize, 0usize, 19i32)
    // Four typed `a`s, each reported.
    send(&f, typed("a"), 20i32)
    send(&f, typed("a"), 21i32)
    send(&f, typed("a"), 22i32)
    send(&f, typed("a"), 23i32)
    expect_value(&f, first, "aaaa", 24i32)
    if log.changes != 4usize || !same(log.last[0usize..log.last_len], "aaaa") { os.exit(25i32) }
    // The caret by hit test: each `a` advances 9.6 px from the editor's origin.
    send(&f, input.Event { PointerDown: pointer(15.0, 10.0) }, 26i32)
    send(&f, input.Event { PointerUp: pointer(15.0, 10.0) }, 27i32)
    expect_selection(&f, first, 2usize, 2usize, 28i32)
    send(&f, input.Event { PointerDown: pointer(37.0, 10.0) }, 29i32)
    send(&f, input.Event { PointerUp: pointer(37.0, 10.0) }, 30i32)
    expect_selection(&f, first, 4usize, 4usize, 31i32)
    // Left, Shift+Left selecting, Backspace erasing the selection, Home, End, Shift+Home.
    send(&f, key(37u32, false, false), 32i32)
    expect_selection(&f, first, 3usize, 3usize, 33i32)
    send(&f, key(37u32, true, false), 34i32)
    expect_selection(&f, first, 2usize, 3usize, 35i32)
    send(&f, key(8u32, false, false), 36i32)
    expect_value(&f, first, "aaa", 37i32)
    expect_selection(&f, first, 2usize, 2usize, 38i32)
    send(&f, key(36u32, false, false), 39i32)
    expect_selection(&f, first, 0usize, 0usize, 40i32)
    send(&f, key(35u32, false, false), 41i32)
    expect_selection(&f, first, 3usize, 3usize, 42i32)
    send(&f, key(36u32, true, false), 43i32)
    expect_selection(&f, first, 0usize, 3usize, 44i32)
    // Copy, Right collapsing to the end, paste, select all, cut, paste.
    send(&f, key(67u32, false, true), 45i32)
    send(&f, key(39u32, false, false), 46i32)
    expect_selection(&f, first, 3usize, 3usize, 47i32)
    send(&f, key(86u32, false, true), 48i32)
    expect_value(&f, first, "aaaaaa", 49i32)
    send(&f, key(65u32, false, true), 50i32)
    expect_selection(&f, first, 0usize, 6usize, 51i32)
    send(&f, key(88u32, false, true), 52i32)
    expect_value(&f, first, "", 53i32)
    send(&f, key(86u32, false, true), 54i32)
    expect_value(&f, first, "aaaaaa", 55i32)
    // Undo through the history -- the typed run is one entry -- and redo.
    send(&f, key(90u32, false, true), 56i32)
    expect_value(&f, first, "", 57i32)
    send(&f, key(90u32, false, true), 58i32)
    expect_value(&f, first, "aaaaaa", 59i32)
    send(&f, key(90u32, false, true), 60i32)
    expect_value(&f, first, "aaa", 61i32)
    send(&f, key(90u32, false, true), 62i32)
    expect_value(&f, first, "aaaa", 63i32)
    send(&f, key(90u32, false, true), 64i32)
    expect_value(&f, first, "", 65i32)
    send(&f, key(90u32, false, true), 66i32)
    expect_value(&f, first, "", 67i32)
    send(&f, key(89u32, false, true), 68i32)
    expect_value(&f, first, "aaaa", 69i32)
    send(&f, key(90u32, true, true), 70i32)
    expect_value(&f, first, "aaa", 71i32)
    // Enter submits a single line and leaves it as it is.
    send(&f, key(13u32, false, false), 72i32)
    if log.submits != 1usize { os.exit(73i32) }
    expect_value(&f, first, "aaa", 74i32)
    // A composition is shown, then committed by its text.
    send(&f, key(35u32, false, false), 75i32)
    send(&f, input.Event { Composition: input.Composition { window: window.Id { slot: 0u32, generation: 0u32 }, text: "a", selection_start: 0usize, selection_end: 1usize } }, 76i32)
    let (composed, composed_error) = widget.reconcile(&f.runtime, &frame, root, limits)
    if composed_error != ok { os.exit(77i32) }
    if scene.render(&renderer, composed, canvas, geometry.Size { width: 64.0, height: 100.0 }) != ok { os.exit(78i32) }
    expect_value(&f, first, "aaa", 79i32)
    send(&f, typed("a"), 80i32)
    expect_value(&f, first, "aaaa", 81i32)
    // A drag selects from the press (in the first glyph's leading half) to the
    // pointer; Delete erases it.
    send(&f, input.Event { PointerDown: pointer(3.0, 10.0) }, 82i32)
    send(&f, input.Event { PointerMove: pointer(37.0, 10.0) }, 83i32)
    send(&f, input.Event { PointerUp: pointer(37.0, 10.0) }, 84i32)
    expect_selection(&f, first, 0usize, 4usize, 85i32)
    send(&f, key(46u32, false, false), 86i32)
    expect_value(&f, first, "", 87i32)
    // The buffer holds sixteen bytes; the seventeenth is refused and not reported.
    var n = 0usize
    while n < 16usize {
        send(&f, typed("a"), 88i32)
        n += 1usize
    }
    let before = log.changes
    send(&f, typed("a"), 89i32)
    expect_value(&f, first, "aaaaaaaaaaaaaaaa", 90i32)
    if log.changes != before { os.exit(91i32) }
    // The multiline editor: Enter breaks the line, Up and Down move between lines,
    // Home goes to the line's start, Shift+Up selects the first line and the break,
    // Delete erases them.
    send(&f, input.Event { PointerDown: pointer(5.0, 34.0) }, 92i32)
    send(&f, input.Event { PointerUp: pointer(5.0, 34.0) }, 93i32)
    let (focus_second, has_second) = widget.focused(&f.runtime)
    if !has_second || focus_second.slot != second.slot { os.exit(94i32) }
    send(&f, typed("a"), 95i32)
    send(&f, key(13u32, false, false), 96i32)
    send(&f, typed("a"), 97i32)
    expect_value(&f, second, "a\na", 98i32)
    if log.submits != 1usize { os.exit(99i32) }
    expect_selection(&f, second, 3usize, 3usize, 100i32)
    send(&f, key(38u32, false, false), 101i32)
    expect_selection(&f, second, 1usize, 1usize, 102i32)
    send(&f, key(40u32, false, false), 103i32)
    expect_selection(&f, second, 3usize, 3usize, 104i32)
    send(&f, key(36u32, false, false), 105i32)
    expect_selection(&f, second, 2usize, 2usize, 106i32)
    send(&f, key(38u32, true, false), 107i32)
    expect_selection(&f, second, 0usize, 2usize, 108i32)
    send(&f, key(46u32, false, false), 109i32)
    expect_value(&f, second, "a", 110i32)
    // Tab leaves the editor for the next focusable element, wrapping to the first.
    send(&f, key(9u32, false, false), 111i32)
    let (after_tab, has_tab) = widget.focused(&f.runtime)
    if !has_tab || after_tab.slot != first.slot { os.exit(112i32) }
    // The frame paints: the first editor's text is white at its first glyph's centre.
    let (painted, painted_error) = widget.reconcile(&f.runtime, &frame, root, limits)
    if painted_error != ok { os.exit(113i32) }
    if scene.render(&renderer, painted, canvas, geometry.Size { width: 64.0, height: 100.0 }) != ok { os.exit(114i32) }
    let (shown, shown_error) = gpu.presented(t)
    if shown_error != ok { os.exit(115i32) }
    var pixels: [6400]u32 = zero
    if gpu.read_image(q, shown, pixels[0..]) != ok { os.exit(116i32) }
    if pixels[8usize * 64usize + 8usize] != 4294967295u32 { os.exit(117i32) }
    if widget.close(&f.runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(118i32) }
    try io.print("ui edit ok\n")
    ret ok
}
