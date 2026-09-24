// The v2 dock panel's other variants (D967, widget plan P5-08,
// docs/ux/components/DockPanel) under the light theme at pointer density: a tab
// group's tabs are 32 tall, the current one over a 2px `primary` line as wide as
// its label and count badge (`secondary-container`), Right picking the next; a
// Maximise button stands in the header; a floating panel is
// `surface-container` with 12 corners under a 40 header holding Dock, Restore
// and Close, a 2px `primary` busy bar under it and its empty sentence as the
// body; a stacked slot's 32 headers share the height left between the open
// bodies, 1px apart, and fire their toggles.

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
use e.ui.accessibility
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.navigation
use e.ui.style
use e.ui.testing
use e.ui.widget

type Hit = struct { store: *Store, index: usize }
type Store = struct { hits: [8]u32, targets: [8]Hit, actions: [8]widget.Submit, tabs: [3]str, counts: [3]str, titles: [3]str, open: [3]bool }

fn on_hit(ctx: *void) -> err {
    let h = mem.cast[*Hit](ctx)
    h.store.hits[h.index] += 1u32
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

fn blank(w: f32, h: f32) -> widget.Node {
    ret widget.box(0u64, control.sized_style(w, h), zero)
}

fn sized_row(a: *mem.Arena, w: f32, h: f32, child: widget.Node) -> (widget.Node, err) {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = child
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Stretch, gap: 0.0 }, control.sized_style(w, h), held[0usize..1usize]), ok)
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 3usize)
    if items_error != ok { ret (zero, items_error) }
    var grouped = navigation.dock_panel_options()
    grouped.tabs = s.tabs[0usize..3usize]
    grouped.counts = s.counts[0usize..3usize]
    grouped.current = 0usize
    grouped.picks = s.actions[0usize..3usize]
    grouped.maximise = &s.actions[3usize]
    let (tabbed, e1) = navigation.dock_panel_of(a, 10u64, t, "Output", blank(10.0, 10.0), &s.actions[4usize], grouped)
    if e1 != ok { ret (zero, e1) }
    let (one, e1b) = sized_row(a, 300.0, 150.0, tabbed)
    var afloat = navigation.dock_panel_options()
    afloat.floating = true
    afloat.maximised = true
    afloat.busy = true
    afloat.empty = "Nothing here"
    afloat.dock = &s.actions[5usize]
    afloat.maximise = &s.actions[3usize]
    let (floated, e2) = navigation.dock_panel_of(a, 30u64, t, "Inspector", blank(10.0, 10.0), &s.actions[4usize], afloat)
    if e2 != ok { ret (zero, e2) }
    let (two, e2b) = sized_row(a, 300.0, 200.0, floated)
    let (bodies, bodies_error) = mem.alloc[widget.Node](a, 3usize)
    if bodies_error != ok { ret (zero, bodies_error) }
    bodies[0usize] = blank(10.0, 10.0)
    bodies[1usize] = blank(10.0, 10.0)
    bodies[2usize] = blank(10.0, 10.0)
    let (stacked, e3) = navigation.dock_stack(a, 50u64, t, "Side", s.titles[0usize..3usize], bodies[0usize..3usize], s.open[0usize..3usize], s.actions[5usize..8usize])
    if e3 != ok { ret (zero, e3) }
    let (three, e3b) = sized_row(a, 200.0, 200.0, stacked)
    if e1b != ok || e2b != ok || e3b != ok { ret (zero, e1b) }
    items[0usize] = one
    items[1usize] = two
    items[2usize] = three
    var page = style.defaults()
    page.width = style.Length { Px: 320.0 }
    page.height = style.Length { Px: 620.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 10.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, page, items[0usize..3usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 320usize + usize(x)) * 4usize
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 400usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 24u16, max_commands: 1024usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 320u32, 620u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    var i = 0usize
    while i < 8usize {
        stores[0usize].targets[i] = Hit { store: &stores[0usize], index: i }
        stores[0usize].actions[i] = widget.Submit { ctx: mem.cast[*void](&stores[0usize].targets[i]), invoke: on_hit }
        i += 1usize
    }
    stores[0usize].tabs[0usize] = "Problems"
    stores[0usize].tabs[1usize] = "Output"
    stores[0usize].tabs[2usize] = "Terminal"
    stores[0usize].counts[0usize] = "3"
    stores[0usize].counts[1usize] = ""
    stores[0usize].counts[2usize] = ""
    stores[0usize].titles[0usize] = "Outline"
    stores[0usize].titles[1usize] = "Timeline"
    stores[0usize].titles[2usize] = "Breakpoints"
    stores[0usize].open[0usize] = true
    stores[0usize].open[2usize] = true
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme, &stores[0usize])
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let primary = style.color(&tokens, .Primary)
    // The tab group: 32 tall tabs, the current one's 2px primary line under its
    // label and badge, the badge secondary-container; Maximise and Close.
    let (first, has_first) = bounds(&harness, &runtime, 14u64)
    let (second, has_second) = bounds(&harness, &runtime, 15u64)
    if !has_first || !has_second || !near(first.height, 32.0) || testing.by_role(&harness, .Tab).count != 3usize { os.exit(12i32) }
    if !is_color(shot, at(first.x + 12.0 + 10.0, first.y + 31.0), primary) || !is_color(shot, at(first.x + 12.0 + 4.0 + 8.0, first.y + 15.0), style.color(&tokens, .SecondaryContainer)) { os.exit(13i32) }
    if testing.by_label(&harness, "Maximise panel").count != 1usize || testing.by_label(&harness, "Close Output panel").count != 1usize { os.exit(14i32) }
    if testing.tap(&harness, first.x + 20.0, first.y + 16.0) != ok || stores[0usize].hits[0usize] != 1u32 { os.exit(15i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || stores[0usize].hits[1usize] != 1u32 { os.exit(16i32) }
    // The floating panel: surface-container with rounded corners under a 40
    // header, Dock and Restore before Close, the busy bar and the empty sentence.
    let (floated, has_floated) = bounds(&harness, &runtime, 30u64)
    let (closer, has_closer) = bounds(&harness, &runtime, 31u64)
    if !has_floated || !has_closer || !near(closer.y - floated.y, 4.0) || !near(floated.width, 300.0) { os.exit(17i32) }
    if !is_color(shot, at(floated.x + 150.0, floated.y + 100.0), style.color(&tokens, .SurfaceContainer)) || !is_color(shot, at(floated.x + 0.5, floated.y + 0.5), style.color(&tokens, .Background)) { os.exit(18i32) }
    if !is_color(shot, at(floated.x + 20.0, floated.y + 41.0), primary) || !is_color(shot, at(floated.x + 200.0, floated.y + 41.0), style.color(&tokens, .SurfaceContainer)) { os.exit(19i32) }
    if testing.by_label(&harness, "Dock panel").count != 1usize || testing.by_label(&harness, "Restore panel").count != 1usize || testing.by_text(&harness, "Nothing here").count != 1usize { os.exit(20i32) }
    // The stacked slot: 32 headers, the two open bodies sharing what is left.
    let (top, has_top) = bounds(&harness, &runtime, 51u64)
    let (middle, has_middle) = bounds(&harness, &runtime, 53u64)
    let (last_body, has_last) = bounds(&harness, &runtime, 56u64)
    if !has_top || !has_middle || !has_last || !near(top.width, 200.0) || !near(top.height, 32.0) || !near(last_body.height, 51.0) || !near(middle.y - top.y, 32.0 + 51.0 + 1.0) { os.exit(21i32) }
    if !is_color(shot, at(top.x + 150.0, top.y + 60.0), style.color(&tokens, .SurfaceContainerLow)) || !is_color(shot, at(top.x + 150.0, middle.y - 0.5), style.color(&tokens, .OutlineVariant)) { os.exit(22i32) }
    if testing.tap(&harness, top.x + 190.0, top.y + 16.0) != ok || stores[0usize].hits[5usize] != 1u32 { os.exit(25i32) }
    if testing.tap(&harness, middle.x + 10.0, middle.y + 16.0) != ok || stores[0usize].hits[6usize] != 1u32 { os.exit(23i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(24i32) }
    try io.print("ui containers3 v2 ok\n")
    ret ok
}
