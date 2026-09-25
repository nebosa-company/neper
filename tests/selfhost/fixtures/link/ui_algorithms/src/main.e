// The thirteen `e.ui.*` functions docs/algos.md names (D904): block flow with
// collapsing margins and the automatic table in `e.ui.layout`; hit testing, a
// scroll anchor, keyed reconciliation, lazy loading and the virtual row window in
// `e.ui.widget`; debounce, throttle, a requested frame and idle work in
// `e.ui.app`; the tree and the focus order in `e.ui.accessibility`; damage in
// `e.ui.window`. The layout, widget and accessibility parts run under the
// harness on every host; the app and window parts need a real window and are
// skipped where the host has none.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.scene
use e.text.shape
use e.ui.accessibility
use e.ui.app
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget
use e.ui.window

type Log = struct { presses: usize, idles: usize }

fn on_press(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.presses += 1usize
    ret ok
}

fn on_idle(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.idles += 1usize
    ret ok
}

fn near(x: f32, y: f32) -> bool {
    var d = x - y
    if d < 0.0 { d = 0.0 - d }
    ret d < 0.01
}

fn build(a: *mem.Arena, t: *const control.Theme, press: *const widget.Submit) -> (widget.Node, err) {
    // A column: a button, then a 100-px viewport over ten 50-px rows.
    let (rows, rows_error) = mem.alloc[widget.Node](a, 10usize)
    if rows_error != ok { ret (zero, rows_error) }
    var i = 0usize
    while i < 10usize {
        var row = style.defaults()
        row.width = style.Length { Px: 200.0 }
        row.height = style.Length { Px: 50.0 }
        rows[i] = widget.box(100u64 + u64(i), row, zero)
        i += 1usize
    }
    var viewport = style.defaults()
    viewport.width = style.Length { Px: 200.0 }
    viewport.height = style.Length { Px: 100.0 }
    let (scrolled, scroll_error) = widget.scroll_view(a, 50u64, .Vertical, viewport, rows[0usize..10usize])
    if scroll_error != ok { ret (zero, scroll_error) }
    let (pressed, button_error) = control.button(a, 1u64, t, "Press", press, control.button_options())
    if button_error != ok { ret (zero, button_error) }
    let (regions, regions_error) = mem.alloc[widget.Node](a, 300usize)
    if regions_error != ok { ret (zero, regions_error) }
    let (focusable, focusable_error) = mem.alloc[widget.Node](a, 300usize)
    if focusable_error != ok { ret (zero, focusable_error) }
    var hit_style = style.defaults()
    hit_style.width = style.Length { Px: 4.0 }
    hit_style.height = style.Length { Px: 4.0 }
    i = 0usize
    while i < 300usize {
        regions[i] = widget.region(10000u64 + u64(i), widget.Region { gesture: zero, gestures: 0u8, enabled: true, focusable: true }, hit_style, zero)
        var item_sem: widget.Semantics = zero
        item_sem.role = 11u8
        item_sem.label = "Alpha"
        if i == 299usize { item_sem.label = "Zulu" }
        focusable[i] = widget.semantics(0u64, item_sem, style.defaults(), regions[i..i + 1usize])
        i += 1usize
    }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = pressed
    parts[1usize] = scrolled
    let (list_body, list_body_error) = mem.alloc[widget.Node](a, 1usize)
    if list_body_error != ok { ret (zero, list_body_error) }
    list_body[0usize] = widget.stack(0u64, style.defaults(), focusable[0usize..300usize])
    var list_sem: widget.Semantics = zero
    list_sem.role = 10u8
    list_sem.label = "Large list"
    parts[2usize] = widget.semantics(0u64, list_sem, style.defaults(), list_body[0usize..1usize])
    var column = style.defaults()
    column.width = style.Length { Px: 240.0 }
    column.height = style.Length { Px: 200.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, column, parts[0usize..3usize]), ok)
}

fn app_build(model: *Log, ctx: *widget.BuildContext) -> (widget.Node, err) {
    var s = style.defaults()
    s.width = style.Length { Px: 200.0 }
    s.height = style.Length { Px: 120.0 }
    ret (widget.box(1u64, s, zero), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Block flow: 10/20, 30/5 and 0/0 margins around 50, 40 and 10 tall blocks.
    var blocks: [3]ui_layout.Block = zero
    blocks[0usize] = ui_layout.Block { desired: geometry.Size { width: 80.0, height: 50.0 }, margin_top: 10.0, margin_bottom: 20.0 }
    blocks[1usize] = ui_layout.Block { desired: geometry.Size { width: 120.0, height: 40.0 }, margin_top: 30.0, margin_bottom: 5.0 }
    blocks[2usize] = ui_layout.Block { desired: geometry.Size { width: 60.0, height: 10.0 }, margin_top: 0.0, margin_bottom: 0.0 }
    let loose = ui_layout.Constraints { min_width: 0.0, max_width: 1000.0, min_height: 0.0, max_height: 1000.0 }
    let (flowed, flow_error) = ui_layout.flow(a, loose, blocks[..])
    if flow_error != ok || !near(flowed.children[0usize].y, 10.0) || !near(flowed.children[1usize].y, 90.0) || !near(flowed.children[2usize].y, 135.0) || !near(flowed.size.height, 145.0) || !near(flowed.size.width, 120.0) { os.exit(1i32) }
    // The table: two columns of minima 20/30 and maxima 60/80 under a width of 100 with a gap of 10.
    var cells: [4]ui_layout.Cell = zero
    cells[0usize] = ui_layout.Cell { min: geometry.Size { width: 20.0, height: 10.0 }, max: geometry.Size { width: 60.0, height: 20.0 } }
    cells[1usize] = ui_layout.Cell { min: geometry.Size { width: 30.0, height: 10.0 }, max: geometry.Size { width: 80.0, height: 15.0 } }
    cells[2usize] = ui_layout.Cell { min: geometry.Size { width: 10.0, height: 10.0 }, max: geometry.Size { width: 40.0, height: 30.0 } }
    cells[3usize] = ui_layout.Cell { min: geometry.Size { width: 10.0, height: 10.0 }, max: geometry.Size { width: 20.0, height: 10.0 } }
    let narrow = ui_layout.Constraints { min_width: 0.0, max_width: 100.0, min_height: 0.0, max_height: 1000.0 }
    let (tabled, table_error) = ui_layout.table(a, ui_layout.Table { columns: 2usize, column_gap: 10.0, row_gap: 4.0 }, narrow, cells[..])
    if table_error != ok || !near(tabled.children[0usize].width + tabled.children[1usize].width, 90.0) || !near(tabled.children[1usize].x, tabled.children[0usize].width + 10.0) || !near(tabled.children[2usize].y, 24.0) || !near(tabled.children[0usize].height, 20.0) || !near(tabled.size.width, 100.0) { os.exit(2i32) }
    let tight = ui_layout.Constraints { min_width: 0.0, max_width: 40.0, min_height: 0.0, max_height: 1000.0 }
    let (crushed, crushed_error) = ui_layout.table(a, ui_layout.Table { columns: 2usize, column_gap: 10.0, row_gap: 4.0 }, tight, cells[..])
    if crushed_error != ui_layout.Overflow { os.exit(3i32) }
    // Keyed reconciliation and the virtual window, pure.
    var old: [3]widget.Key = zero
    old[0usize] = 7u64
    old[1usize] = 8u64
    old[2usize] = 9u64
    var fresh: [3]widget.Key = zero
    fresh[0usize] = 9u64
    fresh[1usize] = 10u64
    fresh[2usize] = 7u64
    let (matched, match_error) = widget.reconcile_keyed(a, old[..], fresh[..])
    if match_error != ok || matched.len != 3usize || !matched[0usize].found || matched[0usize].old_index != 2usize || matched[1usize].found || !matched[2usize].found || matched[2usize].old_index != 0usize { os.exit(4i32) }
    let window_rows = widget.virtual_list(100.0, 125.0, 50.0, 10usize, 1usize)
    if window_rows.first != 1usize || window_rows.end != 6usize { os.exit(5i32) }
    let no_rows = widget.virtual_list(100.0, 0.0, 50.0, 0usize, 1usize)
    if no_rows.end != 0usize { os.exit(6i32) }
    // Debounce and throttle over an explicit clock.
    var d = app.Debounce { delay: time.millis(100i64), interval: time.millis(50i64), due: zero, last: zero, pending: false, has_last: false }
    if app.debounce(&d, time.Instant { nanos: 0i64 }, true) || app.debounce(&d, time.Instant { nanos: 50000000i64 }, false) || !app.debounce(&d, time.Instant { nanos: 100000000i64 }, false) || app.debounce(&d, time.Instant { nanos: 200000000i64 }, false) { os.exit(7i32) }
    if !app.throttle(&d, time.Instant { nanos: 0i64 }) || app.throttle(&d, time.Instant { nanos: 20000000i64 }) || !app.throttle(&d, time.Instant { nanos: 60000000i64 }) { os.exit(8i32) }
    // The harness: hit testing, the anchor, lazy loading, the tree and the focus order.
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(9i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(10i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(11i32) }
    var renderer = r
    let tokens = style.reference(.Light)
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(12i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 1000usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 16u16, max_commands: 1024usize })
    if runtime_error != ok { os.exit(13i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 240u32, 200u32, 1.0)
    if harness_error != ok { os.exit(14i32) }
    var harness = h
    var log = Log { presses: 0usize, idles: 0usize }
    let press = widget.Submit { ctx: mem.cast[*void](&log), invoke: on_press }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 4194304usize)
    if storage_error != ok { os.exit(15i32) }
    var frame = mem.arena_from(frame_storage)
    let (root, build_error) = build(&frame, &theme, &press)
    if build_error != ok || testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(16i32) }
    let button = testing.by_key(&harness, 1u64)
    let (button_bounds, has_button) = widget.bounds_of(&runtime, button.element)
    if button.count != 1usize || !has_button { os.exit(17i32) }
    let (hit, has_hit) = widget.hit_test(&runtime, geometry.Point { x: button_bounds.x + 2.0, y: button_bounds.y + 2.0 })
    if !has_hit { os.exit(18i32) }
    // The button is a labelled control: the hit is the button or something inside it.
    let (hit_bounds, has_hit_bounds) = widget.bounds_of(&runtime, hit)
    if !has_hit_bounds || hit_bounds.x < button_bounds.x || hit_bounds.y < button_bounds.y || hit_bounds.x + hit_bounds.width > button_bounds.x + button_bounds.width + 0.5 { os.exit(19i32) }
    let (nothing, has_nothing) = widget.hit_test(&runtime, geometry.Point { x: 1000.0, y: 1000.0 })
    if has_nothing { os.exit(20i32) }
    // Lazy loading: the second row is in the viewport, the ninth is not, unless the margin reaches it.
    let viewport = testing.by_key(&harness, 50u64)
    let second = testing.by_key(&harness, 101u64)
    let ninth = testing.by_key(&harness, 108u64)
    if viewport.count != 1usize || second.count != 1usize || ninth.count != 1usize { os.exit(21i32) }
    if !widget.lazy_load(&runtime, second.element, viewport.element, 0.0) || widget.lazy_load(&runtime, ninth.element, viewport.element, 0.0) || !widget.lazy_load(&runtime, ninth.element, viewport.element, 400.0) { os.exit(22i32) }
    // The anchor: the second row sat 20 px higher before, so the viewport scrolls 30 px.
    let (viewport_bounds, has_viewport) = widget.bounds_of(&runtime, viewport.element)
    let (second_bounds, has_second) = widget.bounds_of(&runtime, second.element)
    if !has_viewport || !has_second { os.exit(23i32) }
    let (delta, anchor_error) = widget.scroll_anchor(&runtime, viewport.element, second.element, second_bounds.y - viewport_bounds.y - 30.0)
    let (offset, has_offset) = widget.scroll_offset_of(&runtime, viewport.element)
    if anchor_error != ok || !near(delta, 30.0) || !has_offset || !near(offset, 30.0) { os.exit(24i32) }
    // The tree and the focus order: the button comes first and is focusable.
    let (tree, tree_error) = accessibility.tree(a, &runtime)
    if tree_error != ok || tree.nodes.len == 0usize { os.exit(25i32) }
    let (flat_tree, flat_tree_error) = mem.alloc[os.AccessibleNode](a, tree.nodes.len)
    if flat_tree_error != ok || accessibility.flatten_into(&tree, flat_tree) != ok || tree.nodes.len <= 256usize { os.exit(46i32) }
    let (order, order_error) = accessibility.focus_order(a, &runtime)
    if order_error != ok || order.len <= 256usize {
        try io.printf["focus order: len {} err {} nodes {}\n"](order.len, order_error != ok, tree.nodes.len)
        os.exit(26i32)
    }
    // The button, or the pressable element inside it, comes first in the order.
    let (first_bounds, has_first) = widget.bounds_of(&runtime, order[0usize])
    if !has_first || first_bounds.x < button_bounds.x || first_bounds.y < button_bounds.y || first_bounds.y + first_bounds.height > button_bounds.y + button_bounds.height + 0.5 { os.exit(44i32) }
    let last_focusable = testing.by_key(&harness, 10299u64)
    if last_focusable.count != 1usize || order[order.len - 1usize].slot != last_focusable.element.slot || order[order.len - 1usize].generation != last_focusable.element.generation { os.exit(45i32) }
    let (last_bounds, has_last_bounds) = widget.bounds_of(&runtime, last_focusable.element)
    let (front_hit, has_front_hit) = widget.hit_test(&runtime, geometry.Point { x: last_bounds.x + 1.0, y: last_bounds.y + 1.0 })
    if !has_last_bounds || !has_front_hit || front_hit.slot != last_focusable.element.slot || front_hit.generation != last_focusable.element.generation { os.exit(49i32) }
    let before_limit = testing.by_key(&harness, 10255u64)
    let after_limit = testing.by_key(&harness, 10256u64)
    if widget.focus(&runtime, before_limit.element) != ok || testing.tab(&harness, false) != ok { os.exit(47i32) }
    let (tabbed, has_tabbed) = testing.focused(&harness)
    if !has_tabbed || tabbed.slot != after_limit.element.slot || tabbed.generation != after_limit.element.generation { os.exit(47i32) }
    let first_item = testing.by_key(&harness, 10000u64)
    if widget.focus(&runtime, first_item.element) != ok || testing.press_key(&harness, 90u32, zero) != ok { os.exit(48i32) }
    let (typed, has_typed) = testing.focused(&harness)
    if !has_typed || typed.slot != last_focusable.element.slot || typed.generation != last_focusable.element.generation { os.exit(48i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(27i32) }
    // The app: a requested frame and idle work, where the host has windows.
    var model = Log { presses: 0usize, idles: 0usize }
    let options = app.Options {
        window: window.Options { title: "neper ui_algorithms", width: 200u32, height: 120u32, min_width: 0u32, min_height: 0u32, resizable: true, transparent: false, mode: .Windowed },
        widget_limits: widget.Limits { max_elements: 16usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 32usize },
        frame_arena_bytes: 1048576usize,
        event_capacity: 64usize,
        backend: .Cpu,
    }
    let (application, init_error) = app.init[Log](a, options, app.Builder[Log] { ctx: &model, build: app_build })
    if init_error == app.Failed {
        try io.print("ui algorithms ok\n")
        ret ok
    }
    if init_error != ok { os.exit(28i32) }
    var running = application
    let (first, first_error) = app.step(&running, time.Duration { nanos: 0i64 })
    if first_error != ok || !first || app.frames_of(&running) != 1u64 { os.exit(29i32) }
    if app.request_idle(&running, widget.Submit { ctx: mem.cast[*void](&model), invoke: on_idle }) != ok { os.exit(30i32) }
    var quiet = 0usize
    while quiet < 5usize && model.idles == 0usize {
        let (again, again_error) = app.step(&running, time.Duration { nanos: 0i64 })
        if again_error != ok || !again { os.exit(31i32) }
        quiet += 1usize
    }
    if model.idles != 1usize { os.exit(32i32) }
    let (once_more, once_error) = app.step(&running, time.Duration { nanos: 0i64 })
    if once_error != ok || model.idles != 1usize { os.exit(33i32) }
    let before = app.frames_of(&running)
    if app.request_frame(&running) != ok { os.exit(34i32) }
    let (framed, framed_error) = app.step(&running, time.Duration { nanos: 0i64 })
    if framed_error != ok || app.frames_of(&running) != before + 1u64 { os.exit(35i32) }
    // Damage: two regions unioned, cleared by the frame that presents them.
    let (win, window_error) = app.window_of(&running)
    if window_error != ok { os.exit(36i32) }
    let (none, any_damage) = window.damaged(win)
    if any_damage { os.exit(37i32) }
    if window.damage(win, geometry.Rect { x: 10.0, y: 10.0, width: 20.0, height: 20.0 }) != ok || window.damage(win, geometry.Rect { x: 50.0, y: 5.0, width: 10.0, height: 10.0 }) != ok { os.exit(38i32) }
    if window.damage(win, geometry.Rect { x: 0.0, y: 0.0, width: 0.0, height: 5.0 }) != window.Invalid { os.exit(39i32) }
    let (region, has_region) = window.damaged(win)
    if !has_region || !near(region.x, 10.0) || !near(region.y, 5.0) || !near(region.width, 50.0) || !near(region.height, 25.0) { os.exit(40i32) }
    if app.request_frame(&running) != ok { os.exit(41i32) }
    let (presented, presented_error) = app.step(&running, time.Duration { nanos: 0i64 })
    let (win_again, window_again_error) = app.window_of(&running)
    if window_again_error != ok { os.exit(44i32) }
    let (after, still_damaged) = window.damaged(win_again)
    if presented_error != ok || still_damaged { os.exit(42i32) }
    if app.close(&running) != ok { os.exit(43i32) }
    try io.print("ui algorithms ok\n")
    ret ok
}
