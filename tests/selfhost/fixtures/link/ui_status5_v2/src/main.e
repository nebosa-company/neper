// The v2 notification list and status bar (D971, widget plan P5-09,
// docs/ux/components/NotificationList, StatusBar) under the light theme: a panel
// on `surface-container-low` with a 56 header, Mark all read and a 1px
// `outline-variant` line, day group headers, 72 tall rows with a severity well,
// an unread `primary` dot and unread/severity in the row's name, the unread
// count in the region's name, the action and Dismiss pressing, the compact empty state;
// a 24 tall status bar on `surface-container` with the message a polite status,
// a 48x4 meter, an end group pressing at the end, and the mode variant on
// `primary-container`.

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

type Store = struct { presses: usize, press: widget.Submit, items: [3]control.NotificationItem, bar: [4]navigation.StatusItem, moded: [1]navigation.StatusItem }

fn on_press(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.presses += 1usize
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
    let (list, e1) = control.notification_list_of(a, 1000u64, t, "Notifications", s.items[0usize..3usize], &s.press, 380.0, 400.0)
    var none: []const control.NotificationItem = zero
    let (calm, e2) = control.notification_list_of(a, 2000u64, t, "Quiet", none, &s.press, 240.0, 240.0)
    let (bar, e3) = navigation.status_bar_of(a, 3000u64, t, s.bar[0usize..4usize], false, 600.0)
    let (debugging, e4) = navigation.status_bar_of(a, 3100u64, t, s.moded[0usize..1usize], true, 600.0)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (zero, e1) }
    let (lists, lists_error) = mem.alloc[widget.Node](a, 2usize)
    if lists_error != ok { ret (zero, lists_error) }
    lists[0usize] = list
    lists[1usize] = calm
    let (items, items_error) = mem.alloc[widget.Node](a, 3usize)
    if items_error != ok { ret (zero, items_error) }
    items[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 12.0 }, style.defaults(), lists[0usize..2usize])
    items[1usize] = bar
    items[2usize] = debugging
    var page = style.defaults()
    page.width = style.Length { Px: 640.0 }
    page.height = style.Length { Px: 520.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 10.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, page, items[0usize..3usize]), ok)
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

fn tap_key(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> bool {
    let (b, found) = bounds(h, runtime, key)
    if !found { ret false }
    ret testing.tap(h, b.x + b.width * 0.5, b.y + b.height * 0.5) == ok
}

fn focused_is(h: *testing.Harness, key: widget.Key) -> bool {
    let (focused, has_focus) = testing.focused(h)
    let found = testing.by_key(h, key)
    ret has_focus && found.count == 1usize && focused.slot == found.element.slot && focused.generation == found.element.generation
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
    let (h, harness_error) = testing.harness(a, &runtime, 640u32, 520u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    s.press = widget.Submit { ctx: mem.cast[*void](s), invoke: on_press }
    s.items[0usize] = control.NotificationItem { title: "Build 4128 failed", message: "3 tests failed in e.fs", time: "12 min ago", severity: .Error, unread: true, group: "Today", action_label: "View log", action: s.press, dismiss: s.press }
    s.items[1usize] = control.NotificationItem { title: "Ada requested your review", message: "", time: "1 h ago", severity: .Info, unread: false, group: "Today", action_label: "", action: s.press, dismiss: s.press }
    s.items[2usize] = control.NotificationItem { title: "Release 1.2 is out", message: "", time: "", severity: .Success, unread: false, group: "Yesterday", action_label: "", action: s.press, dismiss: s.press }
    s.bar[0usize] = navigation.status_item("Ready")
    s.bar[1usize] = navigation.status_item("2")
    s.bar[1usize].marked = true
    s.bar[1usize].glyph = .Alert
    s.bar[1usize].tone = .Error
    s.bar[1usize].action = s.press
    s.bar[2usize] = navigation.status_item("Indexing")
    s.bar[2usize].progress = 0.5
    s.bar[3usize] = navigation.status_item("Ln 4, Col 2")
    s.bar[3usize].end = true
    s.bar[3usize].action = s.press
    s.moded[0usize] = navigation.status_item("Debugging")
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
    // The panel: `surface-container-low`, the 56 header over a 1px line; the
    // region's name carries the unread count.
    let (panel, has_panel) = bounds(&harness, &runtime, 1000u64)
    let (mark, has_mark) = bounds(&harness, &runtime, 1001u64)
    if !has_panel || !has_mark || !is_color(shot, at(mark.x - 60.0, mark.y + 2.0), style.color(&tokens, .SurfaceContainerLow)) { os.exit(13i32) }
    let (row, has_row) = bounds(&harness, &runtime, 1002u64)
    if !has_row || row.height < 72.0 || !is_color(shot, at(row.x + 100.0, panel.y - 0.5), style.color(&tokens, .OutlineVariant)) { os.exit(14i32) }
    let (region, has_region) = find(tree, .Region, "Notifications, 1 unread")
    if !has_region || region.live != .Polite { os.exit(15i32) }
    // Group headers where the day changes; the unread row named so, with its
    // well in `error-container` and the `primary` dot.
    if testing.by_text(&harness, "Today").count != 1usize || testing.by_text(&harness, "Yesterday").count != 1usize { os.exit(16i32) }
    let (unread, has_unread) = find(tree, .ListItem, "Unread, error, Build 4128 failed")
    let (read, has_read) = find(tree, .ListItem, "info, Ada requested your review")
    if !has_unread || !has_read { os.exit(17i32) }
    if !is_color(shot, at(row.x + 22.0, row.y + 32.0), style.color(&tokens, .ErrorContainer)) { os.exit(18i32) }
    if !is_color(shot, at(row.x + row.width - 56.0, row.y + 16.0), style.color(&tokens, .Primary)) { os.exit(19i32) }
    // The action, Dismiss and Mark all read press.
    if testing.by_label(&harness, "Dismiss").count != 3usize || !tap_key(&harness, &runtime, 1003u64) || !tap_key(&harness, &runtime, 1004u64) || !tap_key(&harness, &runtime, 1001u64) || s.presses != 3usize { os.exit(20i32) }
    // Empty: the compact empty state.
    let (caught, has_caught) = find(tree, .Group, "You're all caught up")
    if !has_caught { os.exit(21i32) }
    // The status bar: 24 tall on `surface-container`, the message a polite status,
    // the meter half filled, the end item pressing at the end.
    let (bar, has_bar) = bounds(&harness, &runtime, 3000u64)
    if !has_bar || !near(bar.height, 24.0) || !is_color(shot, at(bar.x + 1.0, bar.y + 12.0), style.color(&tokens, .SurfaceContainer)) { os.exit(22i32) }
    let (_, has_bar_group) = find(tree, .Group, "Status bar")
    if !has_bar_group { os.exit(28i32) }
    let (ready, has_ready) = find(tree, .Status, "Ready")
    if !has_ready || ready.live != .Polite { os.exit(23i32) }
    if !is_color(shot, at(bar.x + 70.0, bar.y + 12.0), style.color(&tokens, .Primary)) || !is_color(shot, at(bar.x + 100.0, bar.y + 12.0), style.color(&tokens, .SecondaryContainer)) { os.exit(24i32) }
    let (cursor, has_cursor) = bounds(&harness, &runtime, 3004u64)
    if !has_cursor || !near(cursor.x + cursor.width, bar.x + 596.0) || !near(cursor.height, 24.0) || !tap_key(&harness, &runtime, 3004u64) || s.presses != 4usize { os.exit(25i32) }
    // One roving Tab stop; arrows and edge keys follow visual item order.
    if widget.focus(&runtime, testing.by_key(&harness, 3002u64).element) != ok || testing.press_key(&harness, 39u32, zero) != ok || !focused_is(&harness, 3004u64) { os.exit(29i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || !focused_is(&harness, 3002u64) || testing.press_key(&harness, 35u32, zero) != ok || !focused_is(&harness, 3004u64) { os.exit(30i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || !focused_is(&harness, 3002u64) || testing.tab(&harness, false) != ok || focused_is(&harness, 3004u64) { os.exit(31i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 3002u64).element) != ok { os.exit(32i32) }
    f = mem.arena_from(frame_storage)
    let (focused_root, focused_root_error) = build(&f, &theme, s)
    if focused_root_error != ok || testing.pump(&harness, focused_root, time.Instant { nanos: 1100000000i64 }) != ok { os.exit(33i32) }
    let (focused_shot, focused_shot_error) = testing.snapshot(&harness, a)
    let (problem, has_problem) = bounds(&harness, &runtime, 3002u64)
    if focused_shot_error != ok || !has_problem || !is_color(focused_shot, at(problem.x + 4.0, problem.y + 12.0), style.color(&tokens, .FocusRing)) || is_color(focused_shot, at(problem.x + 1.0, problem.y + 12.0), style.color(&tokens, .FocusRing)) { os.exit(34i32) }
    // The mode variant on `primary-container`.
    let (moded, has_moded) = bounds(&harness, &runtime, 3100u64)
    if !has_moded || !is_color(shot, at(moded.x + 300.0, moded.y + 12.0), style.color(&tokens, .PrimaryContainer)) { os.exit(26i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(27i32) }
    try io.print("ui status5 v2 ok\n")
    ret ok
}
