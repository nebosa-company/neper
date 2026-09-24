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

type Which = enum u8 { Popup, PopupEmpty, PopupError, PopupFooter, PopupLoading, Flyout, FlyoutCompact, Popover, Below }

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
    let (search_button, e1) = control.button(a, 1u64, t, "Search", &s.subs[1usize], control.button_options())
    let flyout_open = which == .Flyout || which == .FlyoutCompact
    let (filter, e2) = overlay.flyout_button(a, 2u64, t, "Filter", 20u64, flyout_open, &s.subs[1usize])
    let (build_button, e3) = control.button(a, 3u64, t, "Build", &s.subs[1usize], control.button_options())
    let (rows, rows_error) = mem.alloc[widget.Node](a, 2usize)
    if rows_error != ok { ret (zero, rows_error) }
    let (first, e4) = overlay.popup_row_match(a, 11u64, t, "main.e", 0usize, 4usize, "src", &s.subs[0usize])
    let (second, e5) = overlay.popup_row_match(a, 12u64, t, "math.e", 5usize, 99usize, "", &s.subs[0usize])
    rows[0usize] = first
    rows[1usize] = second
    var popup_content = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), rows[0usize..2usize])
    var e11: err = ok
    if which == .PopupEmpty {
        let (empty, empty_error) = overlay.popup_empty(a, 13u64, t, "No files match ovrly")
        popup_content = empty
        e11 = empty_error
    }
    if which == .PopupError {
        let (failed, failed_error) = overlay.popup_error(a, 14u64, t, "Search failed", &s.subs[5usize])
        popup_content = failed
        e11 = failed_error
    }
    if which == .PopupFooter {
        let (footer, footer_error) = overlay.popup_footer(a, 16u64, t, "Search file contents", &s.subs[6usize])
        let (with_footer, with_footer_error) = mem.alloc[widget.Node](a, 2usize)
        if with_footer_error != ok { ret (zero, with_footer_error) }
        with_footer[0usize] = popup_content
        with_footer[1usize] = footer
        popup_content = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), with_footer[0usize..2usize])
        e11 = footer_error
    }
    if which == .PopupLoading {
        let (loading, loading_error) = overlay.popup_loading(a, 18u64, t, "Searching 1,204 files")
        popup_content = loading
        e11 = loading_error
    }
    let popup_open = which == .Popup || which == .PopupEmpty || which == .PopupError || which == .PopupFooter || which == .PopupLoading
    let (popup, e6) = overlay.popup_of(a, 10u64, t, 1u64, .Below, "Suggestions", popup_content, popup_open)
    var active_key = 0u64
    if which == .Popup || which == .PopupFooter { active_key = 11u64 }
    let (search, e10) = overlay.popup_combobox(a, "Search files", 10u64, active_key, popup_open, search_button)
    let (inside, e7) = control.text(a, 0u64, "Only my builds", t, control.text_options())
    var flyout: widget.Node = zero
    var e8: err = ok
    if which == .FlyoutCompact {
        let (made_flyout, made_flyout_error) = overlay.flyout_adaptive(a, 20u64, t, 2u64, .Below, "Filters", inside, flyout_open, &s.subs[2usize], .Compact)
        flyout = made_flyout
        e8 = made_flyout_error
    } else {
        let (made_flyout, made_flyout_error) = overlay.flyout(a, 20u64, t, 2u64, .Below, "Filters", inside, flyout_open, &s.subs[2usize])
        flyout = made_flyout
        e8 = made_flyout_error
    }
    var side: widget.Placement = .Right
    var owner = 3u64
    if which == .Below {
        side = .Below
        owner = 1u64
    }
    let (popover, e9) = overlay.popover_of(a, 30u64, t, owner, side, "Build 4128", inside, s.actions[0usize..2usize], which == .Popover || which == .Below, &s.subs[2usize])
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret (zero, e1) }
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

fn same_element(a: widget.ElementId, b: widget.ElementId) -> bool {
    ret a.slot == b.slot && a.generation == b.generation
}

fn has_action(node: accessibility.Node, wanted: accessibility.Action) -> bool {
    var i = 0usize
    while i < node.actions.len {
        if node.actions[i] == wanted { ret true }
        i += 1usize
    }
    ret false
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
    if !has_search || !has_popup { os.exit(12i32) }
    if !near(popup.x, search.x) {
        try io.print("popup anchor x\n")
        os.exit(12i32)
    }
    if !near(popup.y, search.y + search.height + 4.0) {
        try io.print("popup anchor y\n")
        os.exit(12i32)
    }
    if !near(popup.width, 200.0) {
        try io.print("popup anchor width\n")
        os.exit(28i32)
    }
    if !is_color(shot, at(popup.x + 100.0, popup.y + 2.0), style.color(&tokens, .SurfaceContainer)) || !is_color(shot, at(popup.x + 100.0, popup.y + popup.height - 2.0), style.color(&tokens, .SurfaceContainer)) { os.exit(13i32) }
    let (row, has_row) = bounds(&harness, &runtime, 11u64)
    if !has_row || !near(row.x, popup.x) || !near(row.y, popup.y + 4.0) || !near(row.height, 40.0) || !near(popup.height, 88.0) { os.exit(14i32) }
    let (group, has_group) = find(tree, .Group, "Suggestions")
    let (search_combo, has_search_combo) = find(tree, .Combobox, "Search files")
    let (closed_filter, has_closed_filter) = find(tree, .Button, "Filter")
    let (plain_math, has_plain_math) = find(tree, .ListItem, "math.e")
    if !has_group || testing.by_role(&harness, .ListItem).count != 2usize || testing.by_text(&harness, "main").count != 1usize || testing.by_text(&harness, ".e").count != 1usize || !has_plain_math || !has_search_combo || !search_combo.state.expanded || !same_element(search_combo.relations.controls, testing.by_key(&harness, 10u64).element) || !same_element(search_combo.relations.active, testing.by_key(&harness, 11u64).element) || !has_closed_filter || closed_filter.state.selected || closed_filter.state.expanded || !has_action(closed_filter, .ShowMenu) { os.exit(15i32) }
    if !tap_key(&harness, &runtime, 2u64) || s.counters[1usize].count != 1usize { os.exit(16i32) }
    if !tap_key(&harness, &runtime, 12u64) || s.counters[0usize].count != 1usize { os.exit(17i32) }
    // Empty results are a padded polite status row, never a blank popup.
    let (root_empty, empty_error) = build(&f, &theme, s, .PopupEmpty)
    if empty_error != ok || testing.pump(&harness, root_empty, time.Instant { nanos: 1050000000i64 }) != ok { os.exit(43i32) }
    let (empty_bounds, has_empty_bounds) = bounds(&harness, &runtime, 13u64)
    let (empty_popup, has_empty_popup) = lifted(&harness, 10u64)
    let (empty_tree, empty_tree_error) = testing.semantics(&harness)
    if empty_tree_error != ok { os.exit(44i32) }
    let (empty_status, has_empty_status) = find(empty_tree, .Status, "No files match ovrly")
    if !has_empty_bounds { os.exit(45i32) }
    if !has_empty_popup { os.exit(46i32) }
    if !has_empty_status { os.exit(47i32) }
    if empty_status.live != .Polite { os.exit(48i32) }
    // Errors are assertive alerts with one ordinary Retry button.
    let (root_error, popup_error) = build(&f, &theme, s, .PopupError)
    if popup_error != ok || testing.pump(&harness, root_error, time.Instant { nanos: 1075000000i64 }) != ok { os.exit(49i32) }
    let (error_tree, error_tree_error) = testing.semantics(&harness)
    if error_tree_error != ok { os.exit(50i32) }
    let (error_status, has_error_status) = find(error_tree, .Alert, "Search failed")
    let (retry_node, has_retry) = find(error_tree, .Button, "Retry")
    if !has_error_status { os.exit(51i32) }
    if !error_status.state.invalid { os.exit(53i32) }
    if error_status.live != .Assertive { os.exit(54i32) }
    if !has_retry { os.exit(55i32) }
    if !tap_key(&harness, &runtime, 15u64) || s.counters[5usize].count != 1usize { os.exit(52i32) }
    // A footer follows the result rows behind a divider and is one full-width
    // 40px primary action.
    let (root_footer, footer_error) = build(&f, &theme, s, .PopupFooter)
    if footer_error != ok || testing.pump(&harness, root_footer, time.Instant { nanos: 1085000000i64 }) != ok { os.exit(56i32) }
    let (footer_bounds, has_footer_bounds) = bounds(&harness, &runtime, 16u64)
    let (footer_tree, footer_tree_error) = testing.semantics(&harness)
    if footer_tree_error != ok { os.exit(57i32) }
    let (footer_button, has_footer_button) = find(footer_tree, .Button, "Search file contents")
    if !has_footer_bounds || !near(footer_bounds.height, 40.0) || !has_footer_button { os.exit(58i32) }
    if !tap_key(&harness, &runtime, 16u64) || s.counters[6usize].count != 1usize { os.exit(59i32) }
    // Loading keeps the final popup open under a flush indeterminate bar and
    // announces one polite busy status line.
    let (root_loading, loading_error) = build(&f, &theme, s, .PopupLoading)
    if loading_error != ok || testing.pump(&harness, root_loading, time.Instant { nanos: 1090000000i64 }) != ok { os.exit(60i32) }
    let (loading_tree, loading_tree_error) = testing.semantics(&harness)
    if loading_tree_error != ok { os.exit(61i32) }
    let (loading_status, has_loading_status) = find(loading_tree, .Status, "Searching 1,204 files")
    if !has_loading_status || !loading_status.state.busy || loading_status.live != .Polite { os.exit(62i32) }
    let (loading_shot, loading_shot_error) = testing.snapshot(&harness, a)
    let (loading_popup, has_loading_popup) = lifted(&harness, 10u64)
    if loading_shot_error != ok || !has_loading_popup || !is_color(loading_shot, at(loading_popup.x + 100.0, loading_popup.y + 1.0), style.color(&tokens, .Primary)) || !is_color(loading_shot, at(loading_popup.x + 10.0, loading_popup.y + 1.0), style.color(&tokens, .SecondaryContainer)) { os.exit(63i32) }
    // The flyout with a pointer: 4 below Filter, 200 wide at least on
    // `surface-container`, 12 above and 8 below its content; a modal dialog named
    // Filters; its anchor stays selected tonal and reports Expanded/Controls;
    // a press outside dismisses without reaching Search.
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
    let (filter_node, has_filter_node) = find(tree_2, .Button, "Filter")
    if !has_filters || !filters.state.modal || !has_filter_node || !filter_node.state.selected || !filter_node.state.expanded || !has_action(filter_node, .ShowMenu) || !same_element(filter_node.relations.controls, testing.by_key(&harness, 20u64).element) { os.exit(23i32) }
    if !is_color(shot_2, at(filter.x + 3.0, filter.y + filter.height * 0.5), style.color(&tokens, .SecondaryContainer)) { os.exit(42i32) }
    if testing.tap(&harness, search.x + 4.0, search.y + 4.0) != ok || s.counters[2usize].count != 1usize || s.counters[1usize].count != 1usize { os.exit(24i32) }
    // On touch: 16 all round, 240 wide at least.
    let (root_3, build_3_error) = build(&f, &touch_theme, s, .Flyout)
    if build_3_error != ok || testing.pump(&harness, root_3, time.Instant { nanos: 1200000000i64 }) != ok { os.exit(25i32) }
    let (touch_fly, has_touch_fly) = lifted(&harness, 20u64)
    if !has_touch_fly || !near(touch_fly.height, 32.0) || touch_fly.width < 240.0 { os.exit(26i32) }
    // A compact touch flyout becomes the existing half-height modal bottom sheet.
    let (root_compact, compact_error) = build(&f, &touch_theme, s, .FlyoutCompact)
    if compact_error != ok || testing.pump(&harness, root_compact, time.Instant { nanos: 1250000000i64 }) != ok { os.exit(64i32) }
    let (compact_sheet, has_compact_sheet) = lifted(&harness, 20u64)
    let (compact_tree, compact_tree_error) = testing.semantics(&harness)
    if compact_tree_error != ok { os.exit(65i32) }
    let (compact_dialog, has_compact_dialog) = find(compact_tree, .Dialog, "Filters")
    if !has_compact_sheet || !near(compact_sheet.x, 0.0) || !near(compact_sheet.y, 240.0) || !near(compact_sheet.width, 640.0) || !near(compact_sheet.height, 240.0) || !has_compact_dialog || !compact_dialog.state.modal { os.exit(66i32) }
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
