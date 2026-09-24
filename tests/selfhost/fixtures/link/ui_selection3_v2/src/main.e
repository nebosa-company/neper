// The v2 slider's states and the multi-select list's count bar (D958, widget plan
// P5-05, docs/ux/components) under the light theme at pointer density: a stepped
// slider shows 4 dots, `on-primary` on the active track and
// `on-secondary-container` beyond, none by the handle; hovered, a `primary` halo
// at the hover opacity rounds the handle; keyboard-focused, its value stands in an
// `inverse-surface` pill 8 above it. A counted multi-select list is one
// `outline-variant` box, a `surface-container-low` bar over a rule over its rows,
// the bar's button "Select all" until every row is chosen, then "Clear".

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

type Store = struct { press: widget.Submit, picks: [3]widget.Submit, words: [3]str, flags: [3]bool }

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
    let (items, items_error) = mem.alloc[widget.Node](a, 2usize)
    if items_error != ok { ret (zero, items_error) }
    let (level, e1) = control.slider(a, 80u64, t, "Level", 50.0, 0.0, 100.0, 25.0, zero, true)
    let (many, e2) = control.multi_select_list_counted(a, 20u64, t, "Hosts", s.words[0usize..3usize], s.flags[0usize..3usize], s.picks[0usize..3usize], 3u32, 220.0, &s.press, &s.press)
    if e1 != ok || e2 != ok { ret (zero, e1) }
    items[0usize] = level
    items[1usize] = many
    var page = style.defaults()
    page.width = style.Length { Px: 260.0 }
    page.height = style.Length { Px: 360.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 12.0 }
    page.padding = style.EdgeLengths { left: pad, top: style.Length { Px: 72.0 }, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 16.0 }, page, items[0usize..2usize]), ok)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 200usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 20u16, max_commands: 1024usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 260u32, 360u32, 1.0)
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
    stores[0usize].words[0usize] = "Linux"
    stores[0usize].words[1usize] = "Mac"
    stores[0usize].words[2usize] = "Windows"
    stores[0usize].flags[0usize] = true
    stores[0usize].flags[2usize] = true
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (shot, shot_error) = frame(&harness, a, &f, &theme, &stores[0usize])
    if shot_error != ok { os.exit(9i32) }
    let page = style.color(&tokens, .Background)
    let primary = style.color(&tokens, .Primary)
    // The ticks every 26 of the 104 track: the one at 26 on the active part, the one
    // at 78 beyond, none at the handle's 52.
    let (level, has_level) = bounds(&harness, &runtime, 80u64)
    if !has_level { os.exit(10i32) }
    let mid = level.y + 22.0
    if !is_color(shot, at(level.x + 8.0 + 26.0, mid), style.color(&tokens, .OnPrimary)) || !is_color(shot, at(level.x + 8.0 + 78.0, mid), style.color(&tokens, .OnSecondaryContainer)) { os.exit(11i32) }
    if !is_color(shot, at(level.x + 8.0 + 52.0 - 6.5, mid), page) { os.exit(12i32) }
    // The counted list: the bar on the low container over the rule, the frame's edge.
    let (row, has_row) = bounds(&harness, &runtime, 21u64)
    if !has_row || !near(row.height, 40.0) { os.exit(13i32) }
    if !is_color(shot, at(row.x + 8.0, row.y - 4.5), style.color(&tokens, .OutlineVariant)) || !is_color(shot, at(row.x + 8.0, row.y - 25.0), style.color(&tokens, .SurfaceContainerLow)) || !is_color(shot, at(row.x - 0.5, row.y + 20.0), style.color(&tokens, .OutlineVariant)) { os.exit(14i32) }
    if testing.by_label(&harness, "Select all").count == 0usize { os.exit(15i32) }
    // Every row chosen: the button clears.
    stores[0usize].flags[1usize] = true
    let (full, full_error) = frame(&harness, a, &f, &theme, &stores[0usize])
    if full_error != ok || full.pixels.len == 0usize { os.exit(16i32) }
    if testing.by_label(&harness, "Clear").count == 0usize || testing.by_label(&harness, "Select all").count != 0usize { os.exit(17i32) }
    // Hovered: the halo round the handle, over the gap beside it.
    if testing.hover(&harness, level.x + 60.0, mid) != ok { os.exit(18i32) }
    let (hovered, hovered_error) = frame(&harness, a, &f, &theme, &stores[0usize])
    if hovered_error != ok { os.exit(19i32) }
    if !is_color(hovered, at(level.x + 60.0 - 4.5, mid), over(page, primary, tokens.states.hover)) { os.exit(20i32) }
    // Keyboard-focused: the value pill 8 above the slider on the inverse surface.
    if testing.hover(&harness, 250.0, 350.0) != ok { os.exit(21i32) }
    let slider_slot = testing.by_key(&harness, 80u64).element.slot
    var tabs = 0usize
    var reached = false
    while !reached && tabs < 10usize {
        if testing.tab(&harness, false) != ok { os.exit(21i32) }
        let (now_focus, has_focus) = testing.focused(&harness)
        reached = has_focus && now_focus.slot == slider_slot
        tabs += 1usize
    }
    if !reached { os.exit(25i32) }
    let (focused, focused_error) = frame(&harness, a, &f, &theme, &stores[0usize])
    if focused_error != ok { os.exit(22i32) }
    let (pill, has_pill) = bounds(&harness, &runtime, 81u64)
    if !has_pill || !near(pill.width, 48.0) || !near(level.y - pill.y - pill.height, 8.0) { os.exit(23i32) }
    if !is_color(focused, at(pill.x + 24.0, pill.y + pill.height * 0.5), style.color(&tokens, .InverseSurface)) { os.exit(24i32) }
    try io.print("ui selection3 v2 ok\n")
    ret ok
}
