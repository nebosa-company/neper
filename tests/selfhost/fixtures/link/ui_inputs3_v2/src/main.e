// The v2 rating, dial and shortcut recorder (D953, widget plan P5-04,
// docs/ux/components) under the light theme at pointer density: a rating's stars
// stand in 32px cells, the rated ones filled `primary`, an unrated one hollow, and
// under the pointer the stars up to it preview at 60%; a dial draws its track in
// `secondary-container`, its active arc and handle in `primary`; a recorder is a
// 220 x 40 outlined box, its outline 2px `primary` while recording.

use e.gpu
use e.io
use e.math
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

type Store = struct { start: widget.Submit }

fn on_start(ctx: *void) -> err {
    ret ok
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.01 && d > -0.01
}

fn close_to(value: u8, expected: f32) -> bool {
    let e = expected * 255.0
    let v = f32(value)
    ret v - e < 4.0 && e - v < 4.0
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store, recording: bool) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 3usize)
    if items_error != ok { ret (zero, items_error) }
    let (stars, e1) = control.rating(a, 1u64, t, "Quality", 2u32, 5u32, zero)
    let (knob, e2) = control.dial(a, 20u64, t, "Level", 50.0, 0.0, 100.0, zero, 120.0)
    let (keys, e3) = control.shortcut_recorder(a, 40u64, t, "Shortcut", control.Chord { key: 83u32, modifiers: zero }, recording, &s.start, zero)
    if e1 != ok || e2 != ok || e3 != ok { ret (zero, e1) }
    items[0usize] = stars
    items[1usize] = knob
    items[2usize] = keys
    var page = style.defaults()
    page.width = style.Length { Px: 260.0 }
    page.height = style.Length { Px: 320.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 12.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 16.0 }, page, items[0usize..3usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 260usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn over(ground: paint.Color, ink: paint.Color, o: f32) -> paint.Color {
    ret paint.rgba(ground.red + (ink.red - ground.red) * o, ground.green + (ink.green - ground.green) * o, ground.blue + (ink.blue - ground.blue) * o, 1.0)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn frame(h: *testing.Harness, a: *mem.Arena, f: *mem.Arena, t: *const control.Theme, s: *Store, recording: bool) -> (image.Image, err) {
    let (root, build_error) = build(f, t, s, recording)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 160usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 16u16, max_commands: 1024usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 260u32, 320u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    stores[0usize] = Store { start: widget.Submit { ctx: mem.cast[*void](&stores[0usize]), invoke: on_start } }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (shot, shot_error) = frame(&harness, a, &f, &theme, &stores[0usize], false)
    if shot_error != ok { os.exit(9i32) }
    let page = style.color(&tokens, .Background)
    let primary = style.color(&tokens, .Primary)
    // The rating: 32px cells; the second star filled, the fourth hollow.
    let (second, has_second) = bounds(&harness, &runtime, 3u64)
    let (fourth, has_fourth) = bounds(&harness, &runtime, 5u64)
    if !has_second || !has_fourth || !near(second.width, 32.0) || !near(second.height, 32.0) { os.exit(10i32) }
    if !is_color(shot, at(second.x + 16.0, second.y + 16.0), primary) || !is_color(shot, at(fourth.x + 16.0, fourth.y + 16.0), page) { os.exit(11i32) }
    // The dial at half: its handle at the top in `primary`, the arc past it (lower
    // right) the track, the arc before it (upper left) active.
    let (face, has_face) = bounds(&harness, &runtime, 20u64)
    if !has_face || !near(face.width, 120.0) { os.exit(12i32) }
    let cx = face.x + 60.0
    let cy = face.y + 60.0
    let radius: f32 = 48.0
    if !is_color(shot, at(cx, cy - radius), primary) { os.exit(13i32) }
    let late: f32 = 1.9
    if !is_color(shot, at(cx + math.sin[f32](late) * radius, cy - math.cos[f32](late) * radius), style.color(&tokens, .SecondaryContainer)) { os.exit(14i32) }
    let early: f32 = 0.0 - 1.4
    if !is_color(shot, at(cx + math.sin[f32](early) * radius, cy - math.cos[f32](early) * radius), primary) { os.exit(15i32) }
    // The recorder: 220 x 40 in the 1px outline.
    let (box, has_box) = bounds(&harness, &runtime, 40u64)
    if !has_box || !near(box.width, 220.0) || !near(box.height, 40.0) { os.exit(16i32) }
    if !is_color(shot, at(box.x, box.y + 20.0), style.color(&tokens, .Outline)) { os.exit(17i32) }
    // Hovering the fourth star previews the third and fourth at 60%.
    if testing.hover(&harness, fourth.x + 16.0, fourth.y + 16.0) != ok { os.exit(18i32) }
    let (hovered, hovered_error) = frame(&harness, a, &f, &theme, &stores[0usize], false)
    if hovered_error != ok { os.exit(19i32) }
    let cell = over(page, style.color(&tokens, .OnSurface), tokens.states.hover)
    if !is_color(hovered, at(fourth.x + 16.0, fourth.y + 16.0), over(cell, primary, 0.6)) { os.exit(20i32) }
    // Keyboard focus rings the rating group and layers the current star.
    if testing.hover(&harness, 250.0, 310.0) != ok || testing.tab(&harness, false) != ok { os.exit(22i32) }
    let (focused, focused_error) = frame(&harness, a, &f, &theme, &stores[0usize], false)
    if focused_error != ok { os.exit(23i32) }
    if !is_color(focused, at(second.x + 4.0, second.y + 16.0), over(page, style.color(&tokens, .OnSurface), tokens.states.focus)) { os.exit(24i32) }
    // Recording: the outline 2px `primary`.
    let (live, live_error) = frame(&harness, a, &f, &theme, &stores[0usize], true)
    if live_error != ok { os.exit(21i32) }
    if !is_color(live, at(box.x, box.y + 20.0), primary) || !is_color(live, at(box.x + 1.0, box.y + 20.0), primary) { os.exit(22i32) }
    try io.print("ui inputs3 v2 ok\n")
    ret ok
}
