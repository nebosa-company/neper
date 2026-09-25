// `e.ui.navigation`'s document workspace (D852, widget plan P3-03): document tabs
// pick, close, mark the dirty and keep the pinned, move by a drag onto another
// tab and pick their neighbours from the keyboard; a dock panel has a title bar
// with a close; a dock layout sizes its side panels by their handles and reports
// the whole; a workspace's Ctrl+W closes and Ctrl+PageDown picks the next.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.scene
use e.text.shape
use e.ui.accessibility
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.navigation
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { picks: usize, picked: usize, closes: usize, closed: usize, moves: usize, move: navigation.DocumentMove, panel_closes: usize, sizes: usize, size: navigation.DockSizes }

fn on_pick(ctx: *void, value: usize) -> err {
    let log = mem.cast[*Log](ctx)
    log.picks += 1usize
    log.picked = value
    ret ok
}

fn on_close(ctx: *void, value: usize) -> err {
    let log = mem.cast[*Log](ctx)
    log.closes += 1usize
    log.closed = value
    ret ok
}

fn on_move(ctx: *void, value: navigation.DocumentMove) -> err {
    let log = mem.cast[*Log](ctx)
    log.moves += 1usize
    log.move = value
    ret ok
}

fn on_panel_close(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.panel_closes += 1usize
    ret ok
}

fn on_sizes(ctx: *void, value: navigation.DockSizes) -> err {
    let log = mem.cast[*Log](ctx)
    log.sizes += 1usize
    log.size = value
    ret ok
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

fn near(a: f32, b: f32, within: f32) -> bool {
    let d = a - b
    ret d < within && d > 0.0 - within
}

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, documents: []const navigation.Document, current: usize, panel_close: *const widget.Submit, sizes: navigation.DockSizes, which: usize) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 1usize)
    if parts_error != ok { ret (zero, parts_error) }
    if which == 0usize {
        let (view, view_error) = control.text(a, 0u64, "Editor", t, control.text_options())
        if view_error != ok { ret (zero, view_error) }
        let (made, made_error) = navigation.multi_document_workspace(a, 1u64, t, "Documents", documents, current, view, widget.Change[usize] { ctx: ctx, invoke: on_pick }, widget.Change[usize] { ctx: ctx, invoke: on_close }, widget.Change[navigation.DocumentMove] { ctx: ctx, invoke: on_move }, 400.0, 200.0)
        if made_error != ok { ret (zero, made_error) }
        parts[0usize] = made
    } else {
        let (left, left_error) = control.text(a, 0u64, "Files", t, control.text_options())
        if left_error != ok { ret (zero, left_error) }
        let (left_panel, left_panel_error) = navigation.dock_panel(a, 50u64, t, "Explorer", left, panel_close)
        if left_panel_error != ok { ret (zero, left_panel_error) }
        let (centre, centre_error) = control.text(a, 0u64, "Code", t, control.text_options())
        if centre_error != ok { ret (zero, centre_error) }
        let (right, right_error) = control.text(a, 0u64, "Props", t, control.text_options())
        if right_error != ok { ret (zero, right_error) }
        let (bottom, bottom_error) = control.text(a, 0u64, "Output", t, control.text_options())
        if bottom_error != ok { ret (zero, bottom_error) }
        let (made, made_error) = navigation.dock_layout(a, 20u64, t, left_panel, centre, right, bottom, sizes, widget.Change[navigation.DockSizes] { ctx: ctx, invoke: on_sizes }, 800.0, 400.0)
        if made_error != ok { ret (zero, made_error) }
        parts[0usize] = made
    }
    var column = style.defaults()
    column.width = style.Length { Px: 800.0 }
    column.height = style.Length { Px: 400.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column, parts[0usize..1usize]), ok)
}

fn find(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

fn centre_of(h: *testing.Harness, runtime: *const widget.Runtime, key: widget.Key) -> (geometry.Point, bool) {
    let found = testing.by_key(h, key)
    if found.count != 1usize { ret (zero, false) }
    let (area, has_area) = widget.bounds_of(runtime, found.element)
    if !has_area { ret (zero, false) }
    ret (geometry.Point { x: area.x + area.width * 0.5, y: area.y + area.height * 0.5 }, true)
}

// A point near the leading edge of a keyed element, clear of a close button.
fn start_of(h: *testing.Harness, runtime: *const widget.Runtime, key: widget.Key) -> (geometry.Point, bool) {
    let found = testing.by_key(h, key)
    if found.count != 1usize { ret (zero, false) }
    let (area, has_area) = widget.bounds_of(runtime, found.element)
    if !has_area { ret (zero, false) }
    ret (geometry.Point { x: area.x + 6.0, y: area.y + area.height * 0.5 }, true)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 200usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 16u16, max_commands: 512usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 800u32, 400u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (documents, documents_error) = mem.alloc[navigation.Document](a, 3usize)
    if documents_error != ok { os.exit(8i32) }
    documents[0usize] = navigation.Document { key: 1001u64, title: "main.e", dirty: false, pinned: true }
    documents[1usize] = navigation.Document { key: 1002u64, title: "notes", dirty: true, pinned: false }
    documents[2usize] = navigation.Document { key: 1003u64, title: "todo", dirty: false, pinned: false }
    let (closers, closers_error) = mem.alloc[widget.Submit](a, 1usize)
    if closers_error != ok { os.exit(9i32) }
    closers[0usize] = widget.Submit { ctx: ctx, invoke: on_panel_close }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(10i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let sizes = navigation.DockSizes { left: 200.0, right: 200.0, bottom: 100.0 }
    let (root, build_error) = build(&frame, &theme, ctx, documents[0usize..3usize], 1usize, &closers[0usize], sizes, 0usize)
    if build_error != ok || testing.pump(&harness, root, now) != ok { os.exit(11i32) }
    // The tabs: three tabs under a tab list named Documents, the second selected
    // and named unsaved (D974: its dot in the close slot), the pinned first without
    // a close button; the view shows.
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(12i32) }
    let (list, has_list) = find(tree, .TabList, "Documents")
    if !has_list || testing.by_role(&harness, .Tab).count != 3usize || testing.by_text(&harness, "Editor").count != 1usize { os.exit(13i32) }
    let (notes, has_notes) = find(tree, .Tab, "notes, unsaved changes")
    if !has_notes || !notes.state.selected || !same(notes.hint, "unsaved") || testing.by_text(&harness, "notes").count == 0usize { os.exit(14i32) }
    // The tabs are keyed from the strip's key: main.e is 2 + 1, notes 2 + 3, todo
    // 2 + 5; a pinned tab has no close (2 + 2), the others do.
    if testing.by_key(&harness, 4u64).count != 0usize || testing.by_key(&harness, 6u64).count != 1usize { os.exit(15i32) }
    // A tap on todo picks 2; its close reports 2; dragging todo onto notes moves
    // 2 to 1; dragging main.e (pinned) moves nothing; Right from the focused
    // notes picks 2, Left picks 0.
    let (todo_at, has_todo) = start_of(&harness, &runtime, 7u64)
    if !has_todo || testing.tap(&harness, todo_at.x, todo_at.y) != ok || logs[0usize].picks != 1usize || logs[0usize].picked != 2usize { os.exit(16i32) }
    let (close_at, has_close) = centre_of(&harness, &runtime, 8u64)
    if !has_close || testing.tap(&harness, close_at.x, close_at.y) != ok || logs[0usize].closes != 1usize || logs[0usize].closed != 2usize { os.exit(17i32) }
    let (notes_at, has_notes_at) = start_of(&harness, &runtime, 5u64)
    if !has_notes_at || testing.drag(&harness, todo_at, notes_at, 5usize) != ok || logs[0usize].moves != 1usize || logs[0usize].move.from != 2usize || logs[0usize].move.to != 1usize { os.exit(18i32) }
    let (main_at, has_main) = start_of(&harness, &runtime, 3u64)
    if !has_main || testing.drag(&harness, main_at, notes_at, 5usize) != ok || logs[0usize].moves != 1usize { os.exit(19i32) }
    if testing.tap(&harness, notes_at.x, notes_at.y) != ok || logs[0usize].picked != 1usize { os.exit(20i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || logs[0usize].picked != 2usize { os.exit(21i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || logs[0usize].picked != 0usize { os.exit(22i32) }
    // The workspace's chords: Ctrl+W closes the current (1); Ctrl+PageDown picks 2;
    // Ctrl+PageUp picks 0.
    var held: input.Modifiers = zero
    held.control = true
    if testing.press_key(&harness, 87u32, held) != ok || logs[0usize].closes != 2usize || logs[0usize].closed != 1usize { os.exit(23i32) }
    if testing.press_key(&harness, 34u32, held) != ok || logs[0usize].picked != 2usize { os.exit(24i32) }
    if testing.press_key(&harness, 33u32, held) != ok || logs[0usize].picked != 0usize { os.exit(25i32) }
    // The dock layout, 800 by 400 so v2's minimums hold (D966): the left panel
    // 200 wide with a titled dock panel whose close fires; the bottom a hundred
    // tall; the left sash dragged twenty right reports left 220 with the rest
    // kept; the middle's sash dragged twenty left reports right 220; the bottom's
    // sash dragged twenty up (a drag reports from the move after the one that
    // crosses the slop) reports bottom 120.
    let (root_2, build_2_error) = build(&frame, &theme, ctx, documents[0usize..3usize], 1usize, &closers[0usize], sizes, 1usize)
    if build_2_error != ok || testing.pump(&harness, root_2, now) != ok { os.exit(26i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(27i32) }
    let (explorer, has_explorer) = find(tree_2, .Region, "Explorer")
    if !has_explorer || !near(explorer.bounds.width, 200.0, 0.5) { os.exit(28i32) }
    let (panel_close_at, has_panel_close) = centre_of(&harness, &runtime, 51u64)
    if !has_panel_close || testing.tap(&harness, panel_close_at.x, panel_close_at.y) != ok || logs[0usize].panel_closes != 1usize { os.exit(29i32) }
    let (left_grip, has_left_grip) = centre_of(&harness, &runtime, 23u64)
    if !has_left_grip || testing.drag(&harness, left_grip, geometry.Point { x: left_grip.x + 20.0, y: left_grip.y }, 4usize) != ok { os.exit(30i32) }
    if logs[0usize].sizes == 0usize || !near(logs[0usize].size.left, 220.0, 0.5) || !near(logs[0usize].size.right, 200.0, 0.5) || !near(logs[0usize].size.bottom, 100.0, 0.5) { os.exit(31i32) }
    let (middle_grip, has_middle_grip) = centre_of(&harness, &runtime, 26u64)
    if !has_middle_grip || testing.drag(&harness, middle_grip, geometry.Point { x: middle_grip.x - 20.0, y: middle_grip.y }, 4usize) != ok { os.exit(32i32) }
    if !near(logs[0usize].size.right, 220.0, 0.5) || !near(logs[0usize].size.left, 200.0, 0.5) { os.exit(33i32) }
    let (bottom_grip, has_bottom_grip) = centre_of(&harness, &runtime, 29u64)
    if !has_bottom_grip || testing.drag(&harness, bottom_grip, geometry.Point { x: bottom_grip.x, y: bottom_grip.y - 20.0 }, 4usize) != ok { os.exit(34i32) }
    if !near(logs[0usize].size.bottom, 120.0, 0.5) { os.exit(35i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(36i32) }
    try io.print("ui workspace ok\n")
    ret ok
}
