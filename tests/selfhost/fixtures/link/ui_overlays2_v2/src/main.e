// The v2 popups, flyouts and popovers (D976, widget plan P5-11,
// docs/ux/components/Popup, Flyout, Popover) under the light theme: a popup 4
// below its field on `surface-container`, a 4 rim above its 40 suggestion rows,
// a group named for its list that presses pass by; a flyout 4 below its button
// on `surface-container`, 12 above and 8 below its content with a pointer and 16
// on touch, 200 and 240 wide at least; a popover 320 wide on
// `surface-container-high` whose beak stands 4 off its anchor and the card 10,
// its level-2 title naming the dialog, a 32 Close and two actions with the tonal
// main one last; below its anchor the beak is on top.

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
use e.ui.overlay
use e.ui.style
use e.ui.testing
use e.ui.widget

type Counter = struct { count: usize }

// The counters: 0 rows, 1 anchors, 2 dismiss, 3 main action, 4 other action.
type Store = struct { counters: [8]Counter, subs: [8]widget.Submit, actions: [2]overlay.MenuItem }

type Which = enum u8 { Popup, Flyout, Popover, Below }

fn on_count(ctx: *void) -> err {
    let c = mem.cast[*Counter](ctx)
    c.count += 1usize
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

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store, which: Which) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 4usize)
    if items_error != ok { ret (zero, items_error) }
    let (search, e1) = control.button(a, 1u64, t, "Search", &s.subs[1usize], control.button_options())
    let (filter, e2) = control.button(a, 2u64, t, "Filter", &s.subs[1usize], control.button_options())
    let (build_button, e3) = control.button(a, 3u64, t, "Build", &s.subs[1usize], control.button_options())
    let (rows, rows_error) = mem.alloc[widget.Node](a, 2usize)
    if rows_error != ok { ret (zero, rows_error) }
    let (first, e4) = overlay.popup_row(a, 11u64, t, "main.e", "src", &s.subs[0usize])
    let (second, e5) = overlay.popup_row(a, 12u64, t, "math.e", "", &s.subs[0usize])
    rows[0usize] = first
    rows[1usize] = second
    let list = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), rows[0usize..2usize])
    let (popup, e6) = overlay.popup_of(a, 10u64, t, 1u64, .Below, "Suggestions", list, which == .Popup)
    let (inside, e7) = control.text(a, 0u64, "Only my builds", t, control.text_options())
    let (flyout, e8) = overlay.flyout(a, 20u64, t, 2u64, .Below, "Filters", inside, which == .Flyout, &s.subs[2usize])
    var side: widget.Placement = .Right
    var owner = 3u64
    if which == .Below {
        side = .Below
        owner = 1u64
    }
    let (popover, e9) = overlay.popover_of(a, 30u64, t, owner, side, "Build 4128", inside, s.actions[0usize..2usize], which == .Popover || which == .Below, &s.subs[2usize])
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (zero, e1) }
    let (anchors, anchors_error) = mem.alloc[widget.Node](a, 3usize)
    if anchors_error != ok { ret (zero, anchors_error) }
    anchors[0usize] = search
    anchors[1usize] = filter
    anchors[2usize] = build_button
    var column = style.defaults()
    column.width = style.Length { Px: 200.0 }
    items[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 120.0 }, column, anchors[0usize..3usize])
    items[1usize] = popup
    items[2usize] = flyout
    items[3usize] = popover
    var page_style = style.defaults()
    page_style.width = style.Length { Px: 640.0 }
    page_style.height = style.Length { Px: 480.0 }
    page_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 10.0 }
    page_style.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, page_style, items[0usize..4usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 640usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn lifted(h: *testing.Harness, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = testing.overlay_of(h, testing.by_key(h, key).element)
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
    let touch_tokens = style.adapt(&tokens, style.Adaptation { size: .Expanded, capabilities: style.Capabilities { hover: false, fine_pointer: false, keyboard: false, touch: true, pen: false, resizable: false, multi_window: false, insets: zero }, profile: .Touch })
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(4i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 800usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 40u16, max_commands: 8192usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let touch_theme = control.Theme { tokens: &touch_tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 640u32, 480u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    var i = 0usize
    while i < 8usize {
        s.subs[i] = widget.Submit { ctx: mem.cast[*void](&s.counters[i]), invoke: on_count }
        i += 1usize
    }
    s.actions[0usize] = overlay.MenuItem { label: "Rerun", action: s.subs[3usize], enabled: true }
    s.actions[1usize] = overlay.MenuItem { label: "Open log", action: s.subs[4usize], enabled: true }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    // The popup: 4 below Search, 200 wide at least, `surface-container` with a 4
    // rim, its first 40 row at its start; a group named Suggestions of two list
    // items; a press on Filter passes by it, a row presses.
    let (root, build_error) = build(&f, &theme, s, .Popup)
    if build_error != ok || testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(9i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(10i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(11i32) }
    let (search, has_search) = bounds(&harness, &runtime, 1u64)
    let (popup, has_popup) = lifted(&harness, 10u64)
    if !has_search || !has_popup || !near(popup.x, search.x) || !near(popup.y, search.y + search.height + 4.0) || popup.width < 200.0 { os.exit(12i32) }
    if !is_color(shot, at(popup.x + 100.0, popup.y + 2.0), style.color(&tokens, .SurfaceContainer)) || !is_color(shot, at(popup.x + 100.0, popup.y + popup.height - 2.0), style.color(&tokens, .SurfaceContainer)) { os.exit(13i32) }
    let (row, has_row) = bounds(&harness, &runtime, 11u64)
    if !has_row || !near(row.x, popup.x) || !near(row.y, popup.y + 4.0) || !near(row.height, 40.0) || !near(popup.height, 88.0) { os.exit(14i32) }
    let (group, has_group) = find(tree, .Group, "Suggestions")
    if !has_group || testing.by_role(&harness, .ListItem).count != 2usize { os.exit(15i32) }
    if !tap_key(&harness, &runtime, 2u64) || s.counters[1usize].count != 1usize { os.exit(16i32) }
    if !tap_key(&harness, &runtime, 12u64) || s.counters[0usize].count != 1usize { os.exit(17i32) }
    // The flyout with a pointer: 4 below Filter, 200 wide at least on
    // `surface-container`, 12 above and 8 below its content; a modal dialog named
    // Filters; a press outside dismisses without reaching Search.
    let (root_2, build_2_error) = build(&f, &theme, s, .Flyout)
    if build_2_error != ok || testing.pump(&harness, root_2, time.Instant { nanos: 1100000000i64 }) != ok { os.exit(18i32) }
    let (shot_2, shot_2_error) = testing.snapshot(&harness, a)
    if shot_2_error != ok { os.exit(19i32) }
    let (filter, has_filter) = bounds(&harness, &runtime, 2u64)
    let (fly, has_fly) = lifted(&harness, 20u64)
    if !has_filter || !has_fly || !near(fly.y, filter.y + filter.height + 4.0) || fly.width < 200.0 || !near(fly.height, 20.0) { os.exit(20i32) }
    if !is_color(shot_2, at(fly.x + 100.0, fly.y + 10.0), style.color(&tokens, .SurfaceContainer)) { os.exit(21i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(22i32) }
    let (filters, has_filters) = find(tree_2, .Dialog, "Filters")
    if !has_filters || !filters.state.modal { os.exit(23i32) }
    if testing.tap(&harness, search.x + 4.0, search.y + 4.0) != ok || s.counters[2usize].count != 1usize || s.counters[1usize].count != 1usize { os.exit(24i32) }
    // On touch: 16 all round, 240 wide at least.
    let (root_3, build_3_error) = build(&f, &touch_theme, s, .Flyout)
    if build_3_error != ok || testing.pump(&harness, root_3, time.Instant { nanos: 1200000000i64 }) != ok { os.exit(25i32) }
    let (touch_fly, has_touch_fly) = lifted(&harness, 20u64)
    if !has_touch_fly || !near(touch_fly.height, 32.0) || touch_fly.width < 240.0 { os.exit(26i32) }
    // The popover to Build's right: the beak's tip 4 off it, the 320 card 10 off
    // it on `surface-container-high`, the beak in the card's colour 16 down.
    let (root_4, build_4_error) = build(&f, &theme, s, .Popover)
    if build_4_error != ok || testing.pump(&harness, root_4, time.Instant { nanos: 1300000000i64 }) != ok { os.exit(27i32) }
    let (shot_4, shot_4_error) = testing.snapshot(&harness, a)
    if shot_4_error != ok { os.exit(28i32) }
    let (anchor, has_anchor) = bounds(&harness, &runtime, 3u64)
    let (pop, has_pop) = lifted(&harness, 30u64)
    if !has_anchor || !has_pop || !near(pop.x, anchor.x + anchor.width + 4.0) || !near(pop.width, 326.0) { os.exit(29i32) }
    let high = style.color(&tokens, .SurfaceContainerHigh)
    if !is_color(shot_4, at(pop.x + 166.0, pop.y + 8.0), high) || !is_color(shot_4, at(pop.x + 4.0, pop.y + 22.0), high) || !is_color(shot_4, at(pop.x + 3.0, pop.y + 8.0), style.color(&tokens, .Background)) { os.exit(30i32) }
    // Its title names the dialog as a level-2 heading; Close is 32 across and
    // dismisses; Rerun, the tonal main action, stands last and runs.
    let (tree_4, tree_4_error) = testing.semantics(&harness)
    if tree_4_error != ok { os.exit(31i32) }
    let (dialog, has_dialog) = find(tree_4, .Dialog, "Build 4128")
    let (heading, has_heading) = find(tree_4, .Heading, "Build 4128")
    let (close, has_close) = find(tree_4, .Button, "Close")
    if !has_dialog || dialog.relations.labelled_by.generation == 0u32 || !has_heading || heading.level != 2u8 || !has_close { os.exit(32i32) }
    let (closer, has_closer) = bounds(&harness, &runtime, 32u64)
    let (main_action, has_main) = bounds(&harness, &runtime, 33u64)
    let (other, has_other) = bounds(&harness, &runtime, 34u64)
    if !has_closer || !near(closer.width, 32.0) || !has_main || !has_other || main_action.x < other.x + other.width { os.exit(33i32) }
    if !is_color(shot_4, at(main_action.x + main_action.width * 0.5, main_action.y + 3.0), style.color(&tokens, .SecondaryContainer)) { os.exit(34i32) }
    if !tap_key(&harness, &runtime, 33u64) || s.counters[3usize].count != 1usize { os.exit(35i32) }
    if !tap_key(&harness, &runtime, 32u64) || s.counters[2usize].count != 2usize { os.exit(36i32) }
    // Below Search: the beak on top, its tip 4 below the anchor.
    let (root_5, build_5_error) = build(&f, &theme, s, .Below)
    if build_5_error != ok || testing.pump(&harness, root_5, time.Instant { nanos: 1400000000i64 }) != ok { os.exit(37i32) }
    let (shot_5, shot_5_error) = testing.snapshot(&harness, a)
    if shot_5_error != ok { os.exit(38i32) }
    let (under, has_under) = lifted(&harness, 30u64)
    if !has_under || !near(under.y, search.y + search.height + 4.0) || !near(under.width, 320.0) { os.exit(39i32) }
    if !is_color(shot_5, at(under.x + 22.0, under.y + 4.0), high) || !is_color(shot_5, at(under.x + 8.0, under.y + 3.0), style.color(&tokens, .Background)) { os.exit(40i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(41i32) }
    try io.print("ui overlays2 v2 ok\n")
    ret ok
}
