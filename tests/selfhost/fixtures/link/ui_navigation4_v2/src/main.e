// The v2 navigation split, page indicator and pagination (D973, widget plan
// P5-10, docs/ux/components/NavigationSplit, PageIndicator, Pagination) under the
// light theme at pointer density: side by side at expanded width, the list pane
// on `surface-container-low` and the detail on `surface` showing the empty
// statement, the sash named "Resize list"; compact, the detail under a 48 bar
// whose Back is named for the list and pops; one page indicator track 32 tall
// with seven of twelve dots, the edges shrunk, the `primary` pill, taps stepping
// either side of it and the keys stepping and jumping, a slider saying "Page 6 of
// 12"; the on-media pill; seven fixed pagination slots with two ellipses, round
// 32 pages named "Page 10", the current `secondary-container`, Previous and Next
// icon buttons, and the compact form disabled at the start.

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
use e.ui.collection
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.navigation
use e.ui.style
use e.ui.testing
use e.ui.widget

type Counter = struct { count: usize }
type Turned = struct { count: usize, last: usize }

type Store = struct { pops: Counter, pop: widget.Submit, sizes: Counter, dots: Turned, pages: Turned }

fn on_count(ctx: *void) -> err {
    let c = mem.cast[*Counter](ctx)
    c.count += 1usize
    ret ok
}

fn on_size(ctx: *void, value: f32) -> err {
    let c = mem.cast[*Counter](ctx)
    c.count += 1usize
    ret ok
}

fn on_turn(ctx: *void, value: usize) -> err {
    let c = mem.cast[*Turned](ctx)
    c.count += 1usize
    c.last = value
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

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    let (list, e1) = control.text(a, 0u64, "Build list", t, control.text_options())
    let (log, e2) = control.text(a, 0u64, "Log", t, control.text_options())
    let resize = widget.Change[f32] { ctx: mem.cast[*void](&s.sizes), invoke: on_size }
    var wide = navigation.navigation_split_options()
    wide.list_label = "Builds"
    wide.detail_label = "Build 4127"
    wide.empty = "Select a build to see its log"
    let (split, e3) = navigation.navigation_split_of(a, 4000u64, t, list, log, false, 280.0, resize, 880.0, 160.0, wide)
    var narrow = navigation.navigation_split_options()
    narrow.list_label = "Builds"
    narrow.detail_title = "Build 4127"
    narrow.pop = s.pop
    let (single, e4) = navigation.navigation_split_of(a, 4200u64, t, list, log, true, 280.0, resize, 400.0, 100.0, narrow)
    let dots = widget.Change[usize] { ctx: mem.cast[*void](&s.dots), invoke: on_turn }
    let (indicator, e5) = collection.page_indicator_of(a, 4300u64, t, 12usize, 5usize, dots, collection.indicator_options())
    var media = collection.indicator_options()
    media.on_media = true
    let (lifted, e6) = collection.page_indicator_of(a, 4400u64, t, 3usize, 0usize, dots, media)
    let pages = widget.Change[usize] { ctx: mem.cast[*void](&s.pages), invoke: on_turn }
    let (numbered, e7) = collection.pagination_of(a, 4500u64, t, "Results pages", 20usize, 9usize, pages, collection.pagination_options())
    var small = collection.pagination_options()
    small.compact = true
    let (compact, e8) = collection.pagination_of(a, 4600u64, t, "Pages", 5usize, 0usize, pages, small)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (zero, e1) }
    let (items, items_error) = mem.alloc[widget.Node](a, 6usize)
    if items_error != ok { ret (zero, items_error) }
    items[0usize] = split
    items[1usize] = single
    items[2usize] = indicator
    items[3usize] = lifted
    items[4usize] = numbered
    items[5usize] = compact
    var page_style = style.defaults()
    page_style.width = style.Length { Px: 900.0 }
    page_style.height = style.Length { Px: 560.0 }
    page_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHighest) }
    let pad = style.Length { Px: 10.0 }
    page_style.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, page_style, items[0usize..6usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 900usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn tap_key(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> bool {
    let (b, found) = bounds(h, runtime, key)
    if !found { ret false }
    ret testing.tap(h, b.x + b.width * 0.5, b.y + b.height * 0.5) == ok
}

fn find(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 600usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 32u16, max_commands: 2048usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 900u32, 560u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    s.pop = widget.Submit { ctx: mem.cast[*void](&s.pops), invoke: on_count }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme, s)
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(12i32) }
    // Side by side at 880 (the compact split below shows its "Log" alone): the list pane 280 on `surface-container-low`, the
    // detail on `surface` showing the empty statement; the panes named; the sash
    // named "Resize list".
    let (split, has_split) = bounds(&harness, &runtime, 4000u64)
    let (pane, has_pane) = bounds(&harness, &runtime, 4002u64)
    if !has_split || !has_pane || !near(pane.width, 280.0) || !is_color(shot, at(pane.x + 10.0, pane.y + 80.0), style.color(&tokens, .SurfaceContainerLow)) || !is_color(shot, at(split.x + 600.0, split.y + 20.0), style.color(&tokens, .Background)) { os.exit(13i32) }
    let (builds, has_builds) = find(tree, .Group, "Builds")
    let (detail, has_detail) = find(tree, .Group, "Build 4127")
    let (sash, has_sash) = find(tree, .Separator, "Resize list")
    if !has_builds || !has_detail || !has_sash { os.exit(14i32) }
    if testing.by_text(&harness, "Select a build to see its log").count != 1usize || testing.by_text(&harness, "Log").count != 1usize { os.exit(15i32) }
    // Compact: the detail under a 48 bar, Back named for the list, popping.
    let (bar, has_bar) = bounds(&harness, &runtime, 4204u64)
    let (back, has_back) = find(tree, .Button, "Back to Builds")
    if !has_bar || !near(bar.height, 48.0) || !has_back || testing.by_text(&harness, "Build list").count != 1usize { os.exit(16i32) }
    if !tap_key(&harness, &runtime, 4205u64) || s.pops.count != 1usize { os.exit(17i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || s.pops.count != 2usize { os.exit(32i32) }
    var alt: input.Modifiers = zero
    alt.alt = true
    if testing.press_key(&harness, 37u32, alt) != ok || s.pops.count != 3usize { os.exit(33i32) }
    // The indicator: a 32 tall track, seven dots 4, 6, 8, the 24 pill, 8, 6, 4,
    // 8 apart and 12 in; the pill `primary`, a dot `outline`.
    let (track, has_track) = bounds(&harness, &runtime, 4301u64)
    if !has_track || !near(track.height, 32.0) || !near(track.width, 132.0) { os.exit(18i32) }
    if !is_color(shot, at(track.x + 66.0, track.y + 16.0), style.color(&tokens, .Primary)) || !is_color(shot, at(track.x + 42.0, track.y + 16.0), style.color(&tokens, .Outline)) || !is_color(shot, at(track.x + 51.0, track.y + 16.0), style.color(&tokens, .SurfaceContainerHighest)) { os.exit(19i32) }
    let (slider, has_slider) = find(tree, .Slider, "Page")
    if !has_slider || !same(slider.value, "Page 6 of 12") || slider.live != .Polite { os.exit(20i32) }
    // A tap before the pill steps back, after it forward; the keys step and jump.
    if testing.tap(&harness, track.x + 20.0, track.y + 16.0) != ok || s.dots.count != 1usize || s.dots.last != 4usize { os.exit(21i32) }
    if testing.tap(&harness, track.x + 110.0, track.y + 16.0) != ok || s.dots.count != 2usize || s.dots.last != 6usize { os.exit(22i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || s.dots.last != 4usize || testing.press_key(&harness, 35u32, zero) != ok || s.dots.last != 11usize || testing.press_key(&harness, 36u32, zero) != ok || s.dots.last != 0usize { os.exit(23i32) }
    // On media: the dots on a 32 tall `surface-container-high` pill 12 in.
    let (media, has_media) = bounds(&harness, &runtime, 4401u64)
    if !has_media || !is_color(shot, at(media.x + 16.0, media.y + 16.0), style.color(&tokens, .SurfaceContainerHigh)) || !is_color(shot, at(media.x + 36.0, media.y + 16.0), style.color(&tokens, .Primary)) { os.exit(24i32) }
    // Pagination at page ten of twenty: 1, the ellipsis, 9, 10, 11, the
    // ellipsis, 20; 32 round pages, the current `secondary-container`, Selected
    // and Current; Next page turns forward, 11 to it.
    if testing.by_label(&harness, "Page 1").count != 1usize || testing.by_label(&harness, "Page 9").count != 1usize || testing.by_label(&harness, "Page 20").count != 1usize || testing.by_label(&harness, "Page 8").count != 0usize || testing.by_text(&harness, "…").count != 2usize { os.exit(25i32) }
    let (ten, has_ten) = bounds(&harness, &runtime, 4512u64)
    let (ten_node, has_ten_node) = find(tree, .Button, "Page 10")
    if !has_ten || !near(ten.width, 32.0) || !near(ten.height, 32.0) || !is_color(shot, at(ten.x + 16.0, ten.y + 16.0), style.color(&tokens, .SecondaryContainer)) || !has_ten_node || !ten_node.state.selected || !ten_node.state.current { os.exit(26i32) }
    let (previous, has_previous) = find(tree, .Button, "Previous page")
    if !has_previous || previous.state.disabled || !tap_key(&harness, &runtime, 4502u64) || s.pages.last != 10usize || !tap_key(&harness, &runtime, 4513u64) || s.pages.last != 10usize || s.pages.count != 2usize { os.exit(27i32) }
    if !tap_key(&harness, &runtime, 4512u64) || s.pages.count != 2usize { os.exit(28i32) }
    // Compact at the first page: "Page 1 of 5" between the buttons, Previous
    // disabled.
    let (compact_node, has_compact) = find(tree, .Group, "Pages")
    if !has_compact || testing.by_text(&harness, "Page 1 of 5").count != 1usize { os.exit(29i32) }
    let (first_back, has_first_back) = bounds(&harness, &runtime, 4601u64)
    var disabled_back = false
    var i = 0usize
    while i < tree.nodes.len {
        if same(tree.nodes[i].label, "Previous page") && tree.nodes[i].state.disabled { disabled_back = true }
        i += 1usize
    }
    if !has_first_back || !disabled_back { os.exit(30i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(31i32) }
    try io.print("ui navigation4 v2 ok\n")
    ret ok
}
