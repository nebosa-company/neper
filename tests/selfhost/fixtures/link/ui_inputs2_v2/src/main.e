// The v2 compound inputs (D952, widget plan P5-04, docs/ux/components) under the
// light theme at pointer density: the search bar is a 40-tall pill on the high
// container; an open autocomplete lists its rows 36 tall on the container, 4 below
// the field, the active row under the focus layer; the token field is one outlined
// box at least 40 tall; the stepper is a pill the control height tall in the
// outline; an empty formatted field is not invalid yet.

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

type Store = struct { bufs: [4][32]u8, submit: widget.Submit, picks: [2]widget.Submit, words: [2]str, removes: [1]widget.Submit, tokens: [1]str }

fn on_submit(ctx: *void) -> err {
    ret ok
}

fn never(ctx: *void, value: str) -> bool {
    ret false
}

fn copy(ctx: *void, out: []u8, value: str) -> usize {
    ret 0usize
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

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 5usize)
    if items_error != ok { ret (zero, items_error) }
    var options = control.field_options()
    options.width = 200.0
    let (search, e1) = control.search_field(a, 1u64, t, s.bufs[0usize][..], 0usize, zero, s.submit, &s.submit, options)
    let (auto, e2) = control.autocomplete(a, 10u64, t, "City", s.bufs[1usize][..], 0usize, zero, s.words[0usize..2usize], 1usize, true, s.picks[0usize..2usize], zero, &s.submit, options)
    let (tokens, e3) = control.token_field(a, 30u64, t, "To", s.tokens[0usize..0usize], s.removes[0usize..0usize], s.bufs[2usize][..], 0usize, zero, s.submit, s.words[0usize..0usize], 0usize, false, s.picks[0usize..0usize], zero, &s.submit, 200.0)
    let (step, e4) = control.stepper(a, 100u64, t, "Copies", 3i64, 1i64, 9i64, 1i64, zero)
    let (formatted, e5) = control.formatted_field(a, 120u64, t, "Port", s.bufs[3usize][..], 0usize, control.Format { ctx: mem.cast[*void](s), accept: never, format: copy }, zero, zero, options)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (zero, e1) }
    items[0usize] = search
    items[1usize] = auto
    items[2usize] = tokens
    items[3usize] = step
    items[4usize] = formatted
    var page = style.defaults()
    page.width = style.Length { Px: 240.0 }
    page.height = style.Length { Px: 720.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 12.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 96.0 }, page, items[0usize..5usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 240usize + usize(x)) * 4usize
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
    let (h, harness_error) = testing.harness(a, &runtime, 240u32, 720u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let submit = widget.Submit { ctx: mem.cast[*void](&stores[0usize]), invoke: on_submit }
    stores[0usize].submit = submit
    stores[0usize].picks[0usize] = submit
    stores[0usize].picks[1usize] = submit
    stores[0usize].words[0usize] = "Oslo"
    stores[0usize].words[1usize] = "Osaka"
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme, &stores[0usize])
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let page = style.color(&tokens, .Background)
    // The search bar: 40 tall on the high container, fully rounded.
    let (query, has_query) = bounds(&harness, &runtime, 1u64)
    if !has_query { os.exit(12i32) }
    // Scan from the query's middle 60 in: the fill runs 40 rows.
    let fillc = style.color(&tokens, .SurfaceContainerHigh)
    let column = query.x + 48.0
    var y = query.y + query.height * 0.5
    if !is_color(shot, at(column, y), fillc) { os.exit(13i32) }
    while y > 1.0 && is_color(shot, at(column, y - 1.0), fillc) { y = y - 1.0 }
    var bottom = query.y + query.height * 0.5
    while bottom < 719.0 && is_color(shot, at(column, bottom + 1.0), fillc) { bottom = bottom + 1.0 }
    if !(bottom - y + 1.0 > 38.0) || !(bottom - y + 1.0 < 42.0) { os.exit(14i32) }
    // Fully rounded: the bar's corner pixel is the page.
    if !is_color(shot, at(query.x - 12.0 + 1.0, y + 1.0), page) { os.exit(40i32) }
    // The open autocomplete: rows 36 tall, the active (second) one under the focus
    // layer of `on-surface` over the container, the first on the container itself.
    let (first, has_first) = bounds(&harness, &runtime, 12u64)
    let (second, has_second) = bounds(&harness, &runtime, 13u64)
    if !has_first || !has_second || !near(first.height, 36.0) || !near(second.y - first.y, 36.0) { os.exit(15i32) }
    let list = style.color(&tokens, .SurfaceContainer)
    if !is_color(shot, at(first.x + 4.0, first.y + 4.0), list) { os.exit(16i32) }
    if !is_color(shot, at(second.x + 4.0, second.y + 4.0), over(list, style.color(&tokens, .OnSurface), tokens.states.focus)) { os.exit(17i32) }
    // The token field: one outlined box at least 40 tall around its input.
    let (input, has_input) = bounds(&harness, &runtime, 30u64)
    if !has_input || input.width < 96.0 { os.exit(18i32) }
    if !is_color(shot, at(input.x - 12.0, input.y + input.height * 0.5), style.color(&tokens, .Outline)) { os.exit(19i32) }
    // The stepper: a pill the control height tall in the outline, 28px buttons.
    let (less, has_less) = bounds(&harness, &runtime, 101u64)
    if !has_less || !near(less.width, 28.0) || !near(less.height, 28.0) { os.exit(20i32) }
    if !is_color(shot, at(less.x + 14.0, less.y - 2.0), style.color(&tokens, .Outline)) { os.exit(21i32) }
    // The empty formatted field is not invalid yet: its outline is not the error one.
    let (port, has_port) = bounds(&harness, &runtime, 120u64)
    if !has_port || is_color(shot, at(port.x - 16.0, port.y + port.height * 0.5), style.color(&tokens, .Error)) { os.exit(22i32) }
    try io.print("ui inputs2 v2 ok\n")
    ret ok
}
