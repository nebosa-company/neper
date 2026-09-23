// The v2 choice, switch, chip and segmented control (D955, widget plan P5-05,
// docs/ux/components) under the light theme at pointer density: a checkbox is an
// 18 box in a 2px `on-surface-variant` outline, filled `primary` when checked with
// an `on-primary` dash when mixed, in a 40 circle that takes the hover layer; a
// radio is a 20 `primary` ring round a 10 dot; a switch is a 52 x 32 track, its
// thumb 16 `outline` off and 24 `on-primary` on; a chip is 32 tall in a 1px
// outline, a selected filter chip `secondary-container`; a segmented control's
// selected segment is `secondary-container`, a 1px `outline` divider after it.

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

type Store = struct { press: widget.Submit, picks: [2]widget.Submit, views: [2]str }

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
    let (items, items_error) = mem.alloc[widget.Node](a, 10usize)
    if items_error != ok { ret (zero, items_error) }
    let (off, e1) = control.checkbox(a, 1u64, t, "Off", false, false, &s.press, true)
    let (on, e2) = control.checkbox(a, 2u64, t, "On", true, false, &s.press, true)
    let (some, e3) = control.checkbox(a, 3u64, t, "Some", false, true, &s.press, true)
    let (pick, e4) = control.radio(a, 4u64, t, "Pick", true, &s.press, true)
    let (dark, e5) = control.switch_control(a, 10u64, t, "Dark", false, &s.press, true)
    let (light, e6) = control.switch_control(a, 11u64, t, "Light", true, &s.press, true)
    let (filter, e7) = control.chip(a, 50u64, t, "Open", .Filter, true, &s.press, &s.press)
    let (assist, e8) = control.chip(a, 52u64, t, "Help", .Assist, false, &s.press, &s.press)
    let (input, e9) = control.chip(a, 54u64, t, "Ada", .Input, false, &s.press, &s.press)
    let (views, e10) = control.segmented_control(a, 60u64, t, "View", s.views[0usize..2usize], 0usize, s.picks[0usize..2usize], true)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret (zero, e1) }
    items[0usize] = off
    items[1usize] = on
    items[2usize] = some
    items[3usize] = pick
    items[4usize] = dark
    items[5usize] = light
    items[6usize] = filter
    items[7usize] = assist
    items[8usize] = input
    items[9usize] = views
    var page = style.defaults()
    page.width = style.Length { Px: 260.0 }
    page.height = style.Length { Px: 520.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 12.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, page, items[0usize..10usize]), ok)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 240usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 16u16, max_commands: 1024usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 260u32, 520u32, 1.0)
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
    stores[0usize].views[0usize] = "List"
    stores[0usize].views[1usize] = "Grid"
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (shot, shot_error) = frame(&harness, a, &f, &theme, &stores[0usize])
    if shot_error != ok { os.exit(9i32) }
    let page = style.color(&tokens, .Background)
    let primary = style.color(&tokens, .Primary)
    // The checkboxes: rows 40 tall, the box 18 in the 40 circle at the row's start.
    let (off, has_off) = bounds(&harness, &runtime, 1u64)
    if !has_off || !near(off.height, 40.0) { os.exit(10i32) }
    let cx = off.x + 20.0
    let cy = off.y + 20.0
    if !is_color(shot, at(cx - 8.5, cy), style.color(&tokens, .OnSurfaceVariant)) || !is_color(shot, at(cx, cy), page) { os.exit(11i32) }
    let (on, has_on) = bounds(&harness, &runtime, 2u64)
    if !has_on || !is_color(shot, at(on.x + 20.0 - 6.5, on.y + 20.0 - 6.5), primary) { os.exit(12i32) }
    let (some, has_some) = bounds(&harness, &runtime, 3u64)
    if !has_some || !is_color(shot, at(some.x + 20.0, some.y + 20.0), style.color(&tokens, .OnPrimary)) || !is_color(shot, at(some.x + 20.0, some.y + 20.0 - 5.5), primary) { os.exit(13i32) }
    // The radio: a 20 ring round a 10 dot, the page between them.
    let (pick, has_pick) = bounds(&harness, &runtime, 4u64)
    if !has_pick { os.exit(14i32) }
    let rx = pick.x + 20.0
    let ry = pick.y + 20.0
    if !is_color(shot, at(rx - 8.5, ry), primary) || !is_color(shot, at(rx - 6.5, ry), page) || !is_color(shot, at(rx, ry), primary) { os.exit(15i32) }
    // The switches: a 52 x 32 track 4 in from a 60 x 40 box.
    let (dark, has_dark) = bounds(&harness, &runtime, 10u64)
    let (light, has_light) = bounds(&harness, &runtime, 11u64)
    if !has_dark || !has_light || !near(dark.height, 40.0) { os.exit(16i32) }
    if !is_color(shot, at(dark.x + 16.0, dark.y + 8.5), style.color(&tokens, .SurfaceContainerHighest)) || !is_color(shot, at(dark.x + 20.0, dark.y + 20.0), style.color(&tokens, .Outline)) || !is_color(shot, at(dark.x + 5.0, dark.y + 20.0), style.color(&tokens, .Outline)) { os.exit(17i32) }
    if !is_color(shot, at(light.x + 16.0, light.y + 8.5), primary) || !is_color(shot, at(light.x + 40.0, light.y + 20.0), style.color(&tokens, .OnPrimary)) { os.exit(18i32) }
    // The chips: 32 tall; the selected filter chip on the secondary container, the
    // assist chip in its outline, the input chip's remove circle 24 across.
    let (filter, has_filter) = bounds(&harness, &runtime, 50u64)
    let (assist, has_assist) = bounds(&harness, &runtime, 52u64)
    let (remove, has_remove) = bounds(&harness, &runtime, 55u64)
    if !has_filter || !has_assist || !has_remove || !near(filter.height, 32.0) || !near(assist.height, 32.0) || !near(remove.width, 24.0) { os.exit(19i32) }
    if !is_color(shot, at(filter.x + 3.5, filter.y + 16.0), style.color(&tokens, .SecondaryContainer)) { os.exit(20i32) }
    if !is_color(shot, at(assist.x + 0.5, assist.y + 16.0), style.color(&tokens, .Outline)) || !is_color(shot, at(assist.x + 3.5, assist.y + 16.0), page) { os.exit(21i32) }
    // The segmented control: 30 inside its 1px edge, the selected segment on the
    // secondary container, the divider after it, the other on the page.
    let (list, has_list) = bounds(&harness, &runtime, 61u64)
    let (grid, has_grid) = bounds(&harness, &runtime, 62u64)
    if !has_list || !has_grid || !near(list.height, 30.0) || list.width < 72.0 || !near(grid.x - list.x - list.width, 1.0) { os.exit(22i32) }
    if !is_color(shot, at(list.x + 3.5, list.y + 15.0), style.color(&tokens, .SecondaryContainer)) || !is_color(shot, at(grid.x - 0.5, grid.y + 15.0), style.color(&tokens, .Outline)) || !is_color(shot, at(grid.x + 3.5, grid.y + 15.0), page) { os.exit(23i32) }
    // Hovering the first checkbox lays `on-surface` at the hover opacity on its
    // circle, outside the box.
    if testing.hover(&harness, cx, cy) != ok { os.exit(24i32) }
    let (hovered, hovered_error) = frame(&harness, a, &f, &theme, &stores[0usize])
    if hovered_error != ok { os.exit(25i32) }
    if !is_color(hovered, at(cx - 15.0, cy), over(page, style.color(&tokens, .OnSurface), tokens.states.hover)) { os.exit(26i32) }
    try io.print("ui selection v2 ok\n")
    ret ok
}
