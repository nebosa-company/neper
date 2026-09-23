// The v2 list box, multi-select list, combo box, slider and select (D956, widget
// plan P5-05, docs/ux/components) under the light theme at pointer density: a
// list box is 40-tall rows on `surface-container-lowest` in a 1px `outline-variant`
// edge, the selected row `secondary-container`; a multi-select list's rows lead with
// a checkbox; a combo box's 32 chevron button stands inside the field's end; a
// slider's active track and 4-wide handle are `primary`, the rest
// `secondary-container`, 6 clear of the handle; a spin box's arrows stack inside
// its field's end; an open select is a 48-tall field
// in the 2px `primary` outline over a menu of 36-tall rows on `surface-container`,
// the chosen one `secondary-container`.

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

type Store = struct { press: widget.Submit, picks: [3]widget.Submit, words: [3]str, flags: [2]bool, buffer: [16]u8, digits: [8]u8 }

fn on_press(ctx: *void) -> err {
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

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 6usize)
    if items_error != ok { ret (zero, items_error) }
    let (fruit, e1) = control.list_box(a, 20u64, t, "Fruit", s.words[0usize..3usize], 1usize, s.picks[0usize..3usize], 3u32, 200.0)
    let (many, e2) = control.multi_select_list(a, 40u64, t, "Many", s.words[0usize..2usize], s.flags[0usize..2usize], s.picks[0usize..2usize], 2u32, 200.0)
    var options = control.field_options()
    options.width = 200.0
    let (combo, e3) = control.combo_box(a, 60u64, t, "Size", s.buffer[..], 0usize, zero, s.words[0usize..2usize], 0usize, false, s.picks[0usize..2usize], zero, &s.press, options)
    let (level, e4) = control.slider(a, 80u64, t, "Level", 50.0, 0.0, 100.0, 0.0, zero, true)
    let (colour, e5) = control.select(a, 1u64, t, "Colour", s.words[0usize..2usize], 0usize, true, &s.press, s.picks[0usize..2usize])
    let (qty, e6) = control.spin_box(a, 100u64, t, "Qty", s.digits[..], 42i64, 0i64, 99i64, 1i64, zero, zero)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (zero, e1) }
    items[0usize] = fruit
    items[1usize] = many
    items[2usize] = combo
    items[3usize] = level
    items[4usize] = qty
    items[5usize] = colour
    var page = style.defaults()
    page.width = style.Length { Px: 300.0 }
    page.height = style.Length { Px: 680.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 12.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, page, items[0usize..6usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 300usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 240usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 20u16, max_commands: 1024usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 300u32, 680u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let press = widget.Submit { ctx: mem.cast[*void](&stores[0usize]), invoke: on_press }
    stores[0usize].press = press
    stores[0usize].picks[0usize] = press
    stores[0usize].picks[1usize] = press
    stores[0usize].picks[2usize] = press
    stores[0usize].words[0usize] = "Apple"
    stores[0usize].words[1usize] = "Pear"
    stores[0usize].words[2usize] = "Plum"
    stores[0usize].flags[0usize] = true
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme, &stores[0usize])
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let page = style.color(&tokens, .Background)
    let primary = style.color(&tokens, .Primary)
    let secondary = style.color(&tokens, .SecondaryContainer)
    // The list box: 40-tall rows inside the edge, the second selected.
    let (view, has_view) = bounds(&harness, &runtime, 20u64)
    let (apple, has_apple) = bounds(&harness, &runtime, 21u64)
    let (pear, has_pear) = bounds(&harness, &runtime, 22u64)
    if !has_view || !has_apple || !has_pear || !near(apple.height, 40.0) || !near(pear.y - apple.y, 40.0) || !near(apple.width, 198.0) { os.exit(12i32) }
    if !is_color(shot, at(view.x + 0.5, view.y + 20.0), style.color(&tokens, .OutlineVariant)) || !is_color(shot, at(apple.x + 4.0, apple.y + 4.0), style.color(&tokens, .SurfaceContainerLowest)) || !is_color(shot, at(pear.x + 4.0, pear.y + 4.0), secondary) { os.exit(13i32) }
    // The multi-select list: the chosen row on the secondary container with its
    // checkbox filled, the other's checkbox in its outline.
    let (first, has_first) = bounds(&harness, &runtime, 41u64)
    let (second, has_second) = bounds(&harness, &runtime, 42u64)
    if !has_first || !has_second || !near(first.height, 40.0) { os.exit(14i32) }
    if !is_color(shot, at(first.x + 2.0, first.y + 20.0), secondary) || !is_color(shot, at(first.x + 24.0 - 6.5, first.y + 20.0 - 6.5), primary) || !is_color(shot, at(second.x + 24.0 - 8.5, second.y + 20.0), style.color(&tokens, .OnSurfaceVariant)) { os.exit(15i32) }
    // The combo box: a 32 chevron button 4 inside the field's end.
    let (chevron, has_chevron) = bounds(&harness, &runtime, 61u64)
    if !has_chevron || !near(chevron.width, 32.0) || !near(chevron.height, 32.0) { os.exit(16i32) }
    if !is_color(shot, at(chevron.x + 32.0 + 3.5, chevron.y + 16.0), style.color(&tokens, .Outline)) { os.exit(17i32) }
    // The slider at half: the handle at the middle of the 104 track, the active part
    // before it, 6 clear of it, the rest after.
    let (level, has_level) = bounds(&harness, &runtime, 80u64)
    if !has_level || !near(level.height, 44.0) { os.exit(18i32) }
    let mid = level.y + 22.0
    let handle = level.x + 8.0 + 52.0
    if !is_color(shot, at(handle, level.y + 4.0), primary) || !is_color(shot, at(level.x + 30.0, mid), primary) || !is_color(shot, at(handle - 6.5, mid), page) || !is_color(shot, at(level.x + 90.0, mid), secondary) { os.exit(19i32) }
    // The spin box: its 24 x 18 arrows stacked inside the field's end, 8 from it,
    // the value stopping before them.
    let (up, has_up) = bounds(&harness, &runtime, 102u64)
    let (down, has_down) = bounds(&harness, &runtime, 101u64)
    let (digits, has_digits) = bounds(&harness, &runtime, 100u64)
    if !has_up || !has_down || !has_digits || !near(up.width, 24.0) || !near(up.height, 18.0) || !near(down.y - up.y, 18.0) || !near(down.x, up.x) || digits.x + digits.width > up.x + 0.01 { os.exit(23i32) }
    if !is_color(shot, at(up.x + 24.0 + 7.5, up.y + 18.0), style.color(&tokens, .Outline)) { os.exit(24i32) }
    // The open select: 48 tall in the 2px primary outline; its menu 4 below, the
    // chosen row on the secondary container, the other on the container.
    let (head, has_head) = bounds(&harness, &runtime, 1u64)
    let (red, has_red) = bounds(&harness, &runtime, 3u64)
    let (green, has_green) = bounds(&harness, &runtime, 4u64)
    if !has_head || !has_red || !has_green || !near(head.height, 48.0) || !near(red.height, 36.0) || !near(red.y - head.y - head.height, 12.0) { os.exit(20i32) }
    if !is_color(shot, at(head.x + 0.5, head.y + 24.0), primary) || !is_color(shot, at(head.x + 1.5, head.y + 24.0), primary) { os.exit(21i32) }
    if !is_color(shot, at(red.x + 4.0, red.y + 4.0), secondary) || !is_color(shot, at(green.x + 4.0, green.y + 4.0), style.color(&tokens, .SurfaceContainer)) { os.exit(22i32) }
    try io.print("ui selection2 v2 ok\n")
    ret ok
}
