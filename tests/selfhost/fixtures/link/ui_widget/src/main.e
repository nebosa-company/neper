// `e.ui.widget` (D799) over the CPU renderer and an offscreen target: a tree of a
// column with a red box, a button holding text in a square-glyph font, and a green
// box; reconciled, laid out, painted and read back pixel by pixel; typed state kept
// across reconciles by key and retired with its element; a keyed reorder keeping
// state; a pointer press dispatched to the button's action; a duplicate key and a
// tree past the depth limit refused.

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

type Counter = struct { presses: usize, last_x: f32 }

fn on_press(ctx: *void, event: input.Event) -> err {
    let counter = mem.cast[*Counter](ctx)
    switch event {
    case .PointerDown as p:
        counter.presses += 1usize
        counter.last_x = p.position.x
    default:
        counter.presses = counter.presses
    }
    ret ok
}

fn px(v: f32) -> style.Length {
    ret style.Length { Px: v }
}

fn solid(r: f32, g: f32, b: f32) -> paint.Brush {
    ret paint.Brush { Solid: paint.rgba(r, g, b, 1.0) }
}

fn sized(width: f32, height: f32, background: paint.Brush) -> style.Style {
    var s = style.defaults()
    s.width = px(width)
    s.height = px(height)
    s.background = background
    ret s
}

fn build_tree(a: *mem.Arena, font: shape.Font, counter: *Counter, swapped: bool) -> (widget.Node, err) {
    let (fonts, fonts_error) = mem.alloc[layout.FontChoice](a, 1usize)
    if fonts_error != ok { ret (zero, fonts_error) }
    fonts[0usize] = layout.FontChoice { font: font, size: 16.0 }
    let (children, children_error) = mem.alloc[widget.Node](a, 3usize)
    if children_error != ok { ret (zero, children_error) }
    let (label, label_error) = mem.alloc[widget.Node](a, 1usize)
    if label_error != ok { ret (zero, label_error) }
    label[0usize] = widget.text(0u64, widget.Text { value: "aa", style: layout.Style { fonts: fonts, language: "", line_height: 16.0 }, color: paint.rgba(1.0, 1.0, 1.0, 1.0) }, style.defaults())
    let red = widget.box(1u64, sized(20.0, 12.0, solid(1.0, 0.0, 0.0)), zero)
    let press = widget.button(2u64, widget.Button { action: widget.Action { ctx: mem.cast[*void](counter), invoke: on_press }, enabled: true }, sized(40.0, 20.0, solid(0.0, 0.0, 1.0)), label[0usize..1usize])
    let green = widget.box(3u64, sized(20.0, 12.0, solid(0.0, 1.0, 0.0)), zero)
    if swapped {
        children[0usize] = green
        children[1usize] = press
        children[2usize] = red
    } else {
        children[0usize] = red
        children[1usize] = press
        children[2usize] = green
    }
    var column = style.defaults()
    column.width = px(64.0)
    column.height = px(64.0)
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, column, children[0usize..3usize]), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (t, target_error) = gpu.open_target(q, gpu.Surface { kind: .Offscreen, handle: zero, context: zero }, 64u32, 64u32, .Rgba8)
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
    let limits = widget.Limits { max_elements: 32usize, max_states: 16usize, state_bytes: 1024usize, state_classes: 4u16, max_depth: 8u16, max_commands: 64usize }
    let (rt, runtime_error) = widget.runtime(a, &renderer, limits)
    if runtime_error != ok { os.exit(8i32) }
    var runtime = rt
    var counter = Counter { presses: 0usize, last_x: 0.0 }
    let (frame_storage, frame_storage_error) = mem.alloc[u8](a, 1048576usize)
    if frame_storage_error != ok { os.exit(8i32) }
    var frame = mem.arena_from(frame_storage)
    let limits_64 = ui_layout.Constraints { min_width: 0.0, max_width: 64.0, min_height: 0.0, max_height: 64.0 }

    // Frame 1: red at (0,0)-(20,12), button at y 16..36, green at y 40..52.
    let (root, tree_error) = build_tree(&frame, font, &counter, false)
    if tree_error != ok { os.exit(9i32) }
    let (first_scene, first_error) = widget.reconcile(&runtime, &frame, root, limits_64)
    if first_error != ok { os.exit(10i32) }
    if scene.render(&renderer, first_scene, canvas, geometry.Size { width: 64.0, height: 64.0 }) != ok { os.exit(11i32) }
    let (shown, shown_error) = gpu.presented(t)
    if shown_error != ok { os.exit(12i32) }
    var pixels: [4096]u32 = zero
    if gpu.read_image(q, shown, pixels[0..]) != ok { os.exit(13i32) }
    if pixels[6usize * 64usize + 10usize] != 4278190335u32 { os.exit(14i32) }
    if pixels[14usize * 64usize + 10usize] != 0u32 { os.exit(15i32) }
    if pixels[18usize * 64usize + 38usize] != 4294901760u32 { os.exit(16i32) }
    // The label: two 16 px squares of `a` at the button's origin, glyph boxes at
    // 1.6..14.4 px from each pen; the first square's centre is white.
    if pixels[26usize * 64usize + 8usize] != 4294967295u32 { os.exit(17i32) }
    if pixels[26usize * 64usize + 17usize] != 4294967295u32 { os.exit(18i32) }
    if pixels[46usize * 64usize + 10usize] != 4278255360u32 { os.exit(19i32) }
    if pixels[60usize * 64usize + 10usize] != 0u32 { os.exit(20i32) }

    // State: a counter kept on the button by key, across frames.
    let (button_element, button_count) = widget.find_by_key(mem.cast[*widget.State](runtime.state), 2u64)
    if button_count != 1usize { os.exit(21i32) }
    var ctx = widget.BuildContext { runtime: &runtime, element: button_element, frame: 1u64 }
    let (cell, cell_id, cell_error) = widget.state[usize](&ctx, 9u64, 5usize)
    if cell_error != ok || *cell != 5usize { os.exit(22i32) }
    *cell = 6usize
    let (same_cell, same_id, same_error) = widget.state[usize](&ctx, 9u64, 0usize)
    if same_error != ok || *same_cell != 6usize || same_id.slot != cell_id.slot { os.exit(23i32) }
    let (_, _, type_error) = widget.state[u8](&ctx, 9u64, 0u8)
    if type_error != widget.StateType { os.exit(24i32) }

    // A press on the button reaches its action; one beside it reaches nothing.
    let down = input.Event { PointerDown: input.Pointer { window: window.Id { slot: 0u32, generation: 0u32 }, device: 0u32, pointer: 0u32, kind: .Mouse, position: geometry.Point { x: 30.0, y: 25.0 }, buttons: 1u32, changed: .Primary } }
    if widget.dispatch(&runtime, down) != ok || counter.presses != 1usize || counter.last_x != 30.0 { os.exit(25i32) }
    let outside = input.Event { PointerDown: input.Pointer { window: window.Id { slot: 0u32, generation: 0u32 }, device: 0u32, pointer: 0u32, kind: .Mouse, position: geometry.Point { x: 10.0, y: 5.0 }, buttons: 1u32, changed: .Primary } }
    if widget.dispatch(&runtime, outside) != ok || counter.presses != 1usize { os.exit(26i32) }

    // Frame 2, the children reordered by key: the button keeps its element and
    // state, and the green box is now on top.
    mem.reset(&frame, 0usize)
    let (swapped_root, swapped_error) = build_tree(&frame, font, &counter, true)
    if swapped_error != ok { os.exit(27i32) }
    let (second_scene, second_error) = widget.reconcile(&runtime, &frame, swapped_root, limits_64)
    if second_error != ok { os.exit(28i32) }
    let (button_again, again_count) = widget.find_by_key(mem.cast[*widget.State](runtime.state), 2u64)
    if again_count != 1usize || button_again.slot != button_element.slot || button_again.generation != button_element.generation { os.exit(29i32) }
    let (kept, kept_id, kept_error) = widget.state[usize](&ctx, 9u64, 0usize)
    if kept_error != ok || *kept != 6usize { os.exit(30i32) }
    if scene.render(&renderer, second_scene, canvas, geometry.Size { width: 64.0, height: 64.0 }) != ok { os.exit(31i32) }
    let (shown_again, shown_again_error) = gpu.presented(t)
    if shown_again_error != ok || gpu.read_image(q, shown_again, pixels[0..]) != ok { os.exit(32i32) }
    if pixels[6usize * 64usize + 10usize] != 4278255360u32 || pixels[46usize * 64usize + 10usize] != 4278190335u32 { os.exit(33i32) }
    let (bounds, has_bounds) = widget.bounds_of(&runtime, button_again)
    if !has_bounds || bounds.y != 16.0 || bounds.height != 20.0 { os.exit(34i32) }

    // Frame 3, the button gone: its element and state are retired.
    mem.reset(&frame, 0usize)
    let (only, only_error) = mem.alloc[widget.Node](&frame, 1usize)
    if only_error != ok { os.exit(35i32) }
    only[0usize] = widget.box(3u64, sized(20.0, 12.0, solid(0.0, 1.0, 0.0)), zero)
    var column = style.defaults()
    column.width = px(64.0)
    column.height = px(64.0)
    let (third_scene, third_error) = widget.reconcile(&runtime, &frame, widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, column, only[0usize..1usize]), limits_64)
    if third_error != ok { os.exit(36i32) }
    let (_, gone_count) = widget.find_by_key(mem.cast[*widget.State](runtime.state), 2u64)
    if gone_count != 0usize { os.exit(37i32) }
    let (_, _, gone_error) = widget.state[usize](&ctx, 9u64, 0usize)
    if gone_error != widget.InvalidTree { os.exit(38i32) }
    if widget.dispatch(&runtime, down) != ok || counter.presses != 1usize { os.exit(39i32) }

    // Refusals: a duplicate key among siblings; a tree deeper than the limit.
    mem.reset(&frame, 0usize)
    let (twins, twins_error) = mem.alloc[widget.Node](&frame, 2usize)
    if twins_error != ok { os.exit(40i32) }
    twins[0usize] = widget.box(5u64, style.defaults(), zero)
    twins[1usize] = widget.box(5u64, style.defaults(), zero)
    let (_, duplicate_error) = widget.reconcile(&runtime, &frame, widget.box(0u64, style.defaults(), twins[0usize..2usize]), limits_64)
    if duplicate_error != widget.DuplicateKey { os.exit(41i32) }
    mem.reset(&frame, 0usize)
    let (deep, deep_error) = mem.alloc[widget.Node](&frame, 10usize)
    if deep_error != ok { os.exit(42i32) }
    deep[9usize] = widget.box(0u64, style.defaults(), zero)
    var level = 9usize
    while level > 0usize {
        level = level - 1usize
        deep[level] = widget.box(0u64, style.defaults(), deep[level + 1usize..level + 2usize])
    }
    let (_, depth_error) = widget.reconcile(&runtime, &frame, deep[0usize], limits_64)
    if depth_error != widget.TooDeep { os.exit(43i32) }
    if widget.close(&runtime) != ok || widget.close(&runtime) != widget.InvalidTree { os.exit(44i32) }
    if scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(45i32) }
    try io.print("ui widget ok\n")
    ret ok
}
