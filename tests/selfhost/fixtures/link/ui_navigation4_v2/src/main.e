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
// icon buttons mirrored in RTL, and the compact text-button form disabled at
// the start.

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

// (D1409) A split size, kept.
fn on_split_size(ctx: *void, value: f32) -> err {
    let kept = mem.cast[*f32](ctx)
    *kept = value
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
    if testing.drag(&harness, geometry.Point { x: track.x + 66.0, y: track.y + 16.0 }, geometry.Point { x: track.x + 122.0, y: track.y + 16.0 }, 4usize) != ok || s.dots.count != 8usize || s.dots.last != 8usize { os.exit(36i32) }
    var rtl_tokens = style.reference(.Light)
    rtl_tokens.direction = .RightToLeft
    let rtl_theme = control.Theme { tokens: &rtl_tokens, fonts: fonts, language: "", runtime: &runtime }
    let (rtl, rtl_error) = build(&f, &rtl_theme, s)
    if rtl_error != ok || testing.pump(&harness, rtl, time.Instant { nanos: 1100000000i64 }) != ok || testing.press_key(&harness, 39u32, zero) != ok || s.dots.last != 4usize || testing.press_key(&harness, 37u32, zero) != ok || s.dots.last != 6usize { os.exit(34i32) }
    let (rtl_shot, rtl_shot_error) = testing.snapshot(&harness, a)
    let (rtl_media, has_rtl_media) = bounds(&harness, &runtime, 4401u64)
    let (rtl_previous, has_rtl_previous) = bounds(&harness, &runtime, 4501u64)
    let (rtl_next, has_rtl_next) = bounds(&harness, &runtime, 4502u64)
    let rtl_muted = style.color(&rtl_tokens, .OnSurfaceVariant)
    if rtl_shot_error != ok || !has_rtl_media || !has_rtl_previous || !has_rtl_next || !is_color(rtl_shot, at(rtl_media.x + 76.0, rtl_media.y + 16.0), style.color(&rtl_tokens, .Primary)) || !is_color(rtl_shot, at(rtl_previous.x + 14.0, rtl_previous.y + 13.0), rtl_muted) || is_color(rtl_shot, at(rtl_previous.x + 17.0, rtl_previous.y + 13.0), rtl_muted) || !is_color(rtl_shot, at(rtl_next.x + 17.0, rtl_next.y + 13.0), rtl_muted) || is_color(rtl_shot, at(rtl_next.x + 14.0, rtl_next.y + 13.0), rtl_muted) || testing.tap(&harness, track.x + 20.0, track.y + 16.0) != ok || s.dots.last != 6usize || testing.tap(&harness, track.x + 110.0, track.y + 16.0) != ok || s.dots.last != 4usize || testing.drag(&harness, geometry.Point { x: track.x + 66.0, y: track.y + 16.0 }, geometry.Point { x: track.x + 20.0, y: track.y + 16.0 }, 4usize) != ok || s.dots.count != 15usize || s.dots.last != 8usize { os.exit(35i32) }
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
    // Compact at the first page: "Page 1 of 5" between the Previous and Next
    // text buttons, with Previous disabled.
    let (compact_node, has_compact) = find(tree, .Group, "Pages")
    let (compact_previous, has_compact_previous) = find(tree, .Button, "Previous")
    let (compact_next, has_compact_next) = find(tree, .Button, "Next")
    if !has_compact || !has_compact_previous || !compact_previous.state.disabled || !has_compact_next || compact_next.state.disabled || testing.by_text(&harness, "Previous").count == 0usize || testing.by_text(&harness, "Page 1 of 5").count != 1usize || testing.by_text(&harness, "Next").count == 0usize { os.exit(29i32) }
    let (first_back, has_first_back) = bounds(&harness, &runtime, 4601u64)
    if !has_first_back || !tap_key(&harness, &runtime, 4602u64) || s.pages.count != 3usize || s.pages.last != 1usize { os.exit(30i32) }
    // (D1239) The table footer: rows 21-40 of 1,284 at 20 a page; Next turns to
    // record 40 and Previous to 0; at the first page Previous is disabled; and a
    // page size of 50 keeps record 20 in view from record 0.
    var page_sizes: [3]usize = zero
    page_sizes[0usize] = 10usize
    page_sizes[1usize] = 20usize
    page_sizes[2usize] = 50usize
    var size_picks: [3]widget.Submit = zero
    let footer_turn = widget.Change[usize] { ctx: mem.cast[*void](&s.dots), invoke: on_turn }
    var footer_step = 0usize
    while footer_step < 2usize {
        var footer_first = 20usize
        if footer_step == 1usize { footer_first = 0usize }
        f = mem.arena_from(frame_storage)
        let (footer, footer_error) = collection.pagination_footer(&f, 9500u64, &theme, "Builds pages", 1284usize, footer_first, 20usize, page_sizes[..], false, &size_picks[0usize], size_picks[..], footer_turn, 44u8, 600.0)
        if footer_error != ok { os.exit(56i32) }
        let (footer_page, footer_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if footer_page_error != ok { os.exit(56i32) }
        footer_page[0usize] = footer
        if testing.pump(&harness, widget.box(0u64, control.sized_style(600.0, 200.0), footer_page[0usize..1usize]), time.Instant { nanos: 3000000000i64 + i64(footer_step) }) != ok { os.exit(57i32) }
        let (footer_box, has_footer_box) = bounds(&harness, &runtime, 9500u64)
        if !has_footer_box || !near(footer_box.height, 48.0) { os.exit(58i32) }
        let (footer_tree, footer_tree_error) = testing.semantics(&harness)
        if footer_tree_error != ok { os.exit(59i32) }
        let (previous_button, has_previous_button) = find(footer_tree, .Button, "Previous")
        let (next_button, has_next_button) = find(footer_tree, .Button, "Next")
        if !has_previous_button || !has_next_button { os.exit(60i32) }
        if footer_step == 0usize {
            if testing.by_text(&harness, "21–40 of 1,284").count == 0usize || previous_button.state.disabled { os.exit(61i32) }
            if !tap_key(&harness, &runtime, 9503u64) || s.dots.last != 40usize { os.exit(62i32) }
            if !tap_key(&harness, &runtime, 9502u64) || s.dots.last != 0usize { os.exit(63i32) }
        }
        if footer_step == 1usize && (!previous_button.state.disabled || next_button.state.disabled || testing.by_text(&harness, "1–20 of 1,284").count == 0usize) { os.exit(64i32) }
        footer_step += 1usize
    }
    if collection.page_first_after_resize(20usize, 50usize) != 0usize || collection.page_first_after_resize(45usize, 20usize) != 40usize { os.exit(65i32) }
    // (D1409) On touch the list's divider dragged from 300 toward 350 snaps to 360.
    let split_touch_tokens = style.adapt(&tokens, style.Adaptation { size: .Expanded, capabilities: style.Capabilities { hover: false, fine_pointer: false, keyboard: false, touch: true, pen: false, resizable: false, multi_window: false, insets: zero }, profile: .Touch })
    let split_touch = control.Theme { tokens: &split_touch_tokens, fonts: theme.fonts, language: "", runtime: &runtime }
    var split_size: f32 = 0.0
    var snap_step = 0usize
    while snap_step < 2usize {
        f = mem.arena_from(frame_storage)
        let (snap_list, snap_list_error) = control.text(&f, 0u64, "Build list", &split_touch, control.text_options())
        let (snap_log, snap_log_error) = control.text(&f, 0u64, "Log", &split_touch, control.text_options())
        var snap_options = navigation.navigation_split_options()
        snap_options.list_label = "Builds"
        snap_options.detail_label = "Build 4127"
        let (snap_split, snap_split_error) = navigation.navigation_split_of(&f, 4500u64, &split_touch, snap_list, snap_log, false, 300.0, widget.Change[f32] { ctx: mem.cast[*void](&split_size), invoke: on_split_size }, 880.0, 300.0, snap_options)
        let (snap_page, snap_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if snap_list_error != ok || snap_log_error != ok || snap_split_error != ok || snap_page_error != ok { os.exit(136i32) }
        snap_page[0usize] = snap_split
        if testing.pump(&harness, widget.box(0u64, control.sized_style(900.0, 560.0), snap_page[0usize..1usize]), time.Instant { nanos: 40000000000i64 + i64(snap_step) }) != ok { os.exit(137i32) }
        snap_step += 1usize
    }
    let (snap_sash, has_snap_sash) = bounds(&harness, &runtime, 4503u64)
    if !has_snap_sash { os.exit(138i32) }
    let snap_from = geometry.Point { x: snap_sash.x + snap_sash.width * 0.5, y: snap_sash.y + snap_sash.height * 0.5 }
    if testing.drag(&harness, snap_from, geometry.Point { x: snap_from.x + 50.0, y: snap_from.y }, 3usize) != ok || split_size != 360.0 { os.exit(139i32) }
    // (D1410) Side by side, F6 moves the focus from the list to the detail and back.
    var cycle_step = 0usize
    while cycle_step < 2usize {
        f = mem.arena_from(frame_storage)
        let cycle_list = widget.region(4611u64, widget.Region { gesture: zero, gestures: 0u8, enabled: true, focusable: true }, control.sized_style(60.0, 20.0), zero)
        let cycle_detail = widget.region(4612u64, widget.Region { gesture: zero, gestures: 0u8, enabled: true, focusable: true }, control.sized_style(60.0, 20.0), zero)
        var cycle_options = navigation.navigation_split_options()
        cycle_options.list_label = "Builds"
        cycle_options.detail_label = "Build 4127"
        cycle_options.list_focus = 4611u64
        cycle_options.detail_focus = 4612u64
        let (cycle_split, cycle_split_error) = navigation.navigation_split_of(&f, 4600u64, &theme, cycle_list, cycle_detail, true, 300.0, zero, 880.0, 300.0, cycle_options)
        let (cycle_page, cycle_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if cycle_split_error != ok || cycle_page_error != ok { os.exit(140i32) }
        cycle_page[0usize] = cycle_split
        if testing.pump(&harness, widget.box(0u64, control.sized_style(900.0, 560.0), cycle_page[0usize..1usize]), time.Instant { nanos: 41000000000i64 + i64(cycle_step) }) != ok { os.exit(141i32) }
        cycle_step += 1usize
    }
    if widget.focus(&runtime, testing.by_key(&harness, 4611u64).element) != ok || testing.press_key(&harness, 65475u32, zero) != ok { os.exit(142i32) }
    let (cycled_key, _) = widget.focused_key(&runtime)
    if cycled_key != 4612u64 { os.exit(143i32) }
    // (D1411) Escape in the detail returns the focus to the list.
    if testing.press_key(&harness, 27u32, zero) != ok { os.exit(144i32) }
    let (escaped_key, _) = widget.focused_key(&runtime)
    if escaped_key != 4611u64 { os.exit(145i32) }
    // (D1412) In a single pane, showing the detail pushes it in: 50 ms in the
    // page's start is not yet what it settles to.
    var push_step = 0usize
    var push_mid: u32 = 0u32
    var push_end: u32 = 0u32
    while push_step < 5usize {
        var push_at = 42000000000i64 + i64(push_step) * 16000000i64
        if push_step == 3usize { push_at = 42082000000i64 }
        if push_step == 4usize { push_at = 43000000000i64 }
        if testing.begin(&harness, time.Instant { nanos: push_at }) != ok { os.exit(146i32) }
        f = mem.arena_from(frame_storage)
        let (push_list, push_list_error) = control.text(&f, 0u64, "Build list", &theme, control.text_options())
        let (push_log, push_log_error) = control.text(&f, 0u64, "Log", &theme, control.text_options())
        var push_options = navigation.navigation_split_options()
        push_options.list_label = "Builds"
        let (push_split, push_split_error) = navigation.navigation_split_of(&f, 4700u64, &theme, push_list, push_log, push_step >= 2usize, 280.0, zero, 400.0, 200.0, push_options)
        let (push_page, push_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if push_list_error != ok || push_log_error != ok || push_split_error != ok || push_page_error != ok { os.exit(147i32) }
        push_page[0usize] = push_split
        if testing.pump(&harness, widget.box(0u64, control.sized_style(900.0, 560.0), push_page[0usize..1usize]), time.Instant { nanos: push_at }) != ok { os.exit(148i32) }
        if push_step >= 3usize {
            let (push_box, has_push_box) = bounds(&harness, &runtime, 4700u64)
            let (push_shot, push_shot_error) = testing.snapshot(&harness, a)
            if !has_push_box || push_shot_error != ok { os.exit(149i32) }
            let push_spot = (usize(push_box.y + 100.0) * 900usize + usize(push_box.x + 20.0)) * 4usize
            let push_rgb = u32(push_shot.pixels[push_spot]) * 65536u32 + u32(push_shot.pixels[push_spot + 1usize]) * 256u32 + u32(push_shot.pixels[push_spot + 2usize])
            if push_step == 3usize { push_mid = push_rgb }
            if push_step == 4usize { push_end = push_rgb }
        }
        push_step += 1usize
    }
    if push_mid == push_end { os.exit(150i32) }
    // (D1546) 1300 wide (a harness of its own), the supporting pane stands 320
    // wide at the end, flush after a 1px line; 1000 wide it is not built.
    let (wide_rt, wide_runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 600usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 32u16, max_commands: 2048usize })
    if wide_runtime_error != ok { os.exit(151i32) }
    var wide_runtime = wide_rt
    let wide_theme = control.Theme { tokens: &tokens, fonts: theme.fonts, language: "", runtime: &wide_runtime }
    let (wide_h, wide_harness_error) = testing.harness(a, &wide_runtime, 1320u32, 560u32, 1.0)
    if wide_harness_error != ok { os.exit(151i32) }
    var wide_harness = wide_h
    var support_step = 0usize
    while support_step < 2usize {
        var support_width: f32 = 1300.0
        if support_step == 1usize { support_width = 1000.0 }
        f = mem.arena_from(frame_storage)
        let support_list = widget.region(4711u64, widget.Region { gesture: zero, gestures: 0u8, enabled: true, focusable: true }, control.sized_style(60.0, 20.0), zero)
        let support_detail = widget.region(4712u64, widget.Region { gesture: zero, gestures: 0u8, enabled: true, focusable: true }, control.sized_style(60.0, 20.0), zero)
        var support_options = navigation.navigation_split_options()
        support_options.supporting = widget.region(4713u64, widget.Region { gesture: zero, gestures: 0u8, enabled: true, focusable: true }, control.sized_style(60.0, 20.0), zero)
        support_options.has_supporting = true
        support_options.supporting_label = "Inspector"
        let (support_split, support_split_error) = navigation.navigation_split_of(&f, 4700u64, &wide_theme, support_list, support_detail, true, 300.0, zero, support_width, 300.0, support_options)
        let (support_page, support_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if support_split_error != ok || support_page_error != ok { os.exit(151i32) }
        support_page[0usize] = support_split
        if testing.pump(&wide_harness, widget.box(0u64, control.sized_style(1320.0, 560.0), support_page[0usize..1usize]), time.Instant { nanos: 43000000000i64 + i64(support_step) }) != ok { os.exit(151i32) }
        let (support_box, has_support_box) = bounds(&wide_harness, &wide_runtime, 4713u64)
        let (support_detail_box, has_support_detail_box) = bounds(&wide_harness, &wide_runtime, 4712u64)
        if support_step == 0usize && (!has_support_box || !has_support_detail_box || !(support_box.x > 1300.0 - 321.5) || !(support_box.x < 1300.0 - 318.5) || !(support_detail_box.x < support_box.x - 100.0)) { os.exit(152i32) }
        if support_step == 1usize && testing.by_key(&wide_harness, 4713u64).count != 0usize { os.exit(153i32) }
        support_step += 1usize
    }
    if testing.close(&wide_harness) != ok || widget.close(&wide_runtime) != ok { os.exit(151i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(31i32) }
    try io.print("ui navigation4 v2 ok\n")
    ret ok
}
