// The v2 text field and form parts (D951, widget plan P5-04, docs/ux/components)
// under the light theme: an outlined field is 16 taller than the control height
// (48 at pointer density, 56 at touch, 40 dense) with its 1px `outline`, a 2px
// `primary` one while focused and a 2px `error` one when invalid; a filled field
// is the highest container with its indicator along the bottom; a disabled field
// fills at 4%, a read-only one has the `outline-variant` edge; a form puts 20
// between its fields at pointer density; a validation summary is the error
// container.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.text.shape
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

type Store = struct { bufs: [8][32]u8, submit: widget.Submit, jumps: [1]widget.Submit, messages: [1]control.Message, keys: [1]widget.Key }

fn on_submit(ctx: *void) -> err {
    ret ok
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.01 && d > -0.01
}

fn close_to(value: u8, expected: f32) -> bool {
    let e = expected * 255.0
    let v = f32(value)
    ret v - e < 3.0 && e - v < 3.0
}

fn field_at(a: *mem.Arena, t: *const control.Theme, s: *Store, key: widget.Key, slot: usize, options: control.FieldOptions) -> (widget.Node, err) {
    let (node, node_error) = control.text_field(a, key, t, "", s.bufs[slot][..], 0usize, zero, s.submit, options)
    ret (node, node_error)
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 7usize)
    if items_error != ok { ret (zero, items_error) }
    let plain = control.field_options()
    var bad = control.field_options()
    bad.invalid = true
    var filled = control.field_options()
    filled.filled = true
    var off = control.field_options()
    off.enabled = false
    var fixed = control.field_options()
    fixed.read_only = true
    let (f1, e1) = field_at(a, t, s, 1u64, 0usize, plain)
    let (f2, e2) = field_at(a, t, s, 2u64, 1usize, bad)
    let (f3, e3) = field_at(a, t, s, 3u64, 2usize, filled)
    let (f4, e4) = field_at(a, t, s, 4u64, 3usize, off)
    let (f5, e5) = field_at(a, t, s, 5u64, 4usize, fixed)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (zero, e1) }
    let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
    if pair_error != ok { ret (zero, pair_error) }
    let (g1, e6) = field_at(a, t, s, 6u64, 5usize, plain)
    let (g2, e7) = field_at(a, t, s, 7u64, 6usize, plain)
    if e6 != ok || e7 != ok { ret (zero, e6) }
    pair[0usize] = g1
    pair[1usize] = g2
    let (form, form_error) = control.form(a, 20u64, t, "Project", 200.0, pair[0usize..2usize], s.submit, zero)
    if form_error != ok { ret (zero, form_error) }
    let (summary, summary_error) = control.validation_summary(a, 30u64, t, s.messages[0usize..1usize], s.keys[0usize..1usize], s.jumps[0usize..1usize])
    if summary_error != ok { ret (zero, summary_error) }
    items[0usize] = f1
    items[1usize] = f2
    items[2usize] = f3
    items[3usize] = f4
    items[4usize] = f5
    items[5usize] = form
    items[6usize] = summary
    var page = style.defaults()
    page.width = style.Length { Px: 240.0 }
    page.height = style.Length { Px: 640.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 12.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, page, items[0usize..7usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 240usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn over(page: paint.Color, ink: paint.Color, o: f32) -> paint.Color {
    ret paint.rgba(page.red + (ink.red - page.red) * o, page.green + (ink.green - page.green) * o, page.blue + (ink.blue - page.blue) * o, 1.0)
}

// The frame of the field whose editor is keyed `key`: the editor's box grown by
// the frame's sides (16) and its vertical padding.
fn frame_of(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn frame(h: *testing.Harness, a: *mem.Arena, f: *mem.Arena, t: *const control.Theme, s: *Store) -> (image.Image, err) {
    let (root, build_error) = build(f, t, s)
    if build_error != ok { ret (zero, build_error) }
    let pumped = testing.pump(h, root, time.Instant { nanos: 1000000000i64 })
    if pumped != ok { ret (zero, pumped) }
    let (shot, shot_error) = testing.snapshot(h, a)
    ret (shot, shot_error)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    let tokens = style.reference(.Light)
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(4i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 200usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 16u16, max_commands: 1024usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 240u32, 640u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let submit = widget.Submit { ctx: mem.cast[*void](&stores[0usize]), invoke: on_submit }
    stores[0usize].submit = submit
    stores[0usize].jumps[0usize] = submit
    stores[0usize].messages[0usize] = control.Message { validity: .Invalid, text: "Name is required" }
    stores[0usize].keys[0usize] = 1u64
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (shot, shot_error) = frame(&harness, a, &f, &theme, &stores[0usize])
    if shot_error != ok { os.exit(9i32) }
    let page = style.color(&tokens, .Background)
    // The outlined field at rest: its editor stands in a 48-tall box whose left
    // edge is the 1px outline 16 before the editor.
    let (e1, has_e1) = frame_of(&harness, &runtime, 1u64)
    if !has_e1 { os.exit(10i32) }
    let left = e1.x - 16.0
    let mid = e1.y + e1.height * 0.5
    if !is_color(shot, at(left, mid), style.color(&tokens, .Outline)) { os.exit(11i32) }
    // The box is 48 tall: its top edge is 48 above its bottom edge.
    let pad_y = (tokens.metrics.control_height + 16.0 - e1.height) * 0.5
    let top = e1.y - pad_y
    if !is_color(shot, at(left + 10.0, top), style.color(&tokens, .Outline)) || !is_color(shot, at(left + 10.0, top + 47.0), style.color(&tokens, .Outline)) || !is_color(shot, at(left + 10.0, top + 48.0), page) { os.exit(12i32) }
    // Invalid: the 2px error outline.
    let (e2, has_e2) = frame_of(&harness, &runtime, 2u64)
    if !has_e2 || !is_color(shot, at(e2.x - 16.0, e2.y + e2.height * 0.5), style.color(&tokens, .Error)) || !is_color(shot, at(e2.x - 15.0, e2.y + e2.height * 0.5), style.color(&tokens, .Error)) { os.exit(13i32) }
    // Filled: the highest container, its indicator in `on-surface-variant` along
    // the bottom.
    let (e3, has_e3) = frame_of(&harness, &runtime, 3u64)
    if !has_e3 || !is_color(shot, at(e3.x - 8.0, e3.y + e3.height * 0.5), style.color(&tokens, .SurfaceContainerHighest)) { os.exit(14i32) }
    let filled_bottom = e3.y - (tokens.metrics.control_height + 16.0 - e3.height) * 0.5 + tokens.metrics.control_height + 16.0 - 1.0
    if !is_color(shot, at(e3.x + 4.0, filled_bottom), style.color(&tokens, .OnSurfaceVariant)) { os.exit(15i32) }
    // Disabled: `on-surface` at 4% over the page; read-only: the `outline-variant` edge.
    let (e4, has_e4) = frame_of(&harness, &runtime, 4u64)
    if !has_e4 || !is_color(shot, at(e4.x - 8.0, e4.y + e4.height * 0.5), over(page, style.color(&tokens, .OnSurface), 0.04)) { os.exit(16i32) }
    let (e5, has_e5) = frame_of(&harness, &runtime, 5u64)
    if !has_e5 || !is_color(shot, at(e5.x - 16.0, e5.y + e5.height * 0.5), style.color(&tokens, .OutlineVariant)) { os.exit(17i32) }
    // The form: 20 between its fields at pointer density.
    let (g1, has_g1) = frame_of(&harness, &runtime, 6u64)
    let (g2, has_g2) = frame_of(&harness, &runtime, 7u64)
    if !has_g1 || !has_g2 || !near(g2.y - g1.y, tokens.metrics.control_height + 16.0 + 20.0) { os.exit(18i32) }
    // The validation summary: the error container.
    let (sum, has_sum) = widget.bounds_of(&runtime, testing.by_key(&harness, 2u64 + 29u64).element)
    if !has_sum || !is_color(shot, at(sum.x - 8.0, sum.y + 2.0), style.color(&tokens, .ErrorContainer)) { os.exit(19i32) }
    // Focused: a tap on the outlined field turns its outline 2px `primary`.
    if testing.tap(&harness, e1.x + 2.0, mid) != ok { os.exit(20i32) }
    let (focused, focused_error) = frame(&harness, a, &f, &theme, &stores[0usize])
    if focused_error != ok { os.exit(21i32) }
    let primary = style.color(&tokens, .Primary)
    if !is_color(focused, at(left, mid), primary) || !is_color(focused, at(left + 1.0, mid), primary) { os.exit(22i32) }
    // At touch density the box is 56, at dense density 40.
    let touch = style.adapt(&tokens, style.Adaptation { size: .Expanded, capabilities: style.Capabilities { hover: false, fine_pointer: false, keyboard: false, touch: true, pen: false, resizable: false, multi_window: false, insets: zero }, profile: .Touch })
    if !near(touch.metrics.control_height + 16.0, 56.0) { os.exit(23i32) }
    let dense = style.adapt(&tokens, style.Adaptation { size: .Expanded, capabilities: zero, profile: .DesktopDense })
    if !near(dense.metrics.control_height + 16.0, 40.0) { os.exit(24i32) }
    try io.print("ui inputs v2 ok\n")
    ret ok
}
