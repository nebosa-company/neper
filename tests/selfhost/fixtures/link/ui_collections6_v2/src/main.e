// The v2 data grid's core (D984, widget plan P5-12, docs/ux/components/DataGrid)
// under the light theme: one active cell ringed in `focus-ring` holding the
// grid's focus, a tap moving it; an invalid cell's 2px `error` outline and the
// status bar's "1 error"; a dirty cell's `primary` start bar; the arrows, Home,
// End, Ctrl+Home, Ctrl+End, Page Up and Page Down moving the active cell;
// Shift+Down extending a `primary-container` range and "2 cells selected";
// Escape dropping it; F2 editing in a `surface-container-highest` editor in a
// 2px `primary` outline over the cell, which takes the focus; typing, Enter
// committing and moving down with the focus back on the grid; Enter editing
// and Escape cancelling.

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
use e.ui.style
use e.ui.testing
use e.ui.widget

const W: usize = 420usize

type Store = struct { state: collection.GridState, draft: []u8, events: usize, last: collection.GridEvent, committed: usize, committed_row: usize, committed_column: usize }

fn cell_text(row: usize, column: usize) -> str {
    if column == 1usize {
        if row == 1usize { ret "22a" }
        ret "22"
    }
    if row == 0usize { ret "alpha" }
    if row == 1usize { ret "beta" }
    if row == 2usize { ret "gamma" }
    if row == 3usize { ret "delta" }
    ret "omega"
}

fn grid_count(ctx: *void) -> usize {
    ret 5usize
}

fn grid_cell(ctx: *void, row: usize, column: usize) -> collection.GridCell {
    var c = collection.GridCell { text: cell_text(row, column), message: "", dirty: false, read_only: false }
    if row == 1usize && column == 1usize { c.message = "Port must be a number" }
    if row == 2usize && column == 0usize { c.dirty = true }
    if row == 3usize && column == 1usize { c.read_only = true }
    ret c
}

fn on_change(ctx: *void, event: collection.GridEvent) -> err {
    let store = mem.cast[*Store](ctx)
    store.events += 1usize
    store.last = event
    store.state = event.next
    if event.kind == .Edit {
        let value = cell_text(event.row, event.column)
        var i = 0usize
        while i < value.len {
            store.draft[i] = value[i]
            i += 1usize
        }
        store.state.len = value.len
    }
    if event.kind == .Commit {
        store.committed = store.state.len
        store.committed_row = event.row
        store.committed_column = event.column
    }
    ret ok
}

fn on_scroll(ctx: *void, value: f32) -> err {
    ret ok
}

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, store: *Store) -> (widget.Node, err) {
    let (columns, columns_error) = mem.alloc[collection.Column](a, 2usize)
    if columns_error != ok { ret (zero, columns_error) }
    columns[0usize] = collection.Column { title: "Host", width: 120.0 }
    columns[1usize] = collection.Column { title: "Port", width: 100.0 }
    let source = collection.GridSource { ctx: ctx, count: grid_count, cell: grid_cell }
    let (grid, grid_error) = collection.data_grid_of(a, 1u64, t, "Build hosts", columns[0usize..2usize], source, store.state, store.draft, widget.Change[collection.GridEvent] { ctx: ctx, invoke: on_change }, 0.0, 0.0, widget.Change[f32] { ctx: ctx, invoke: on_scroll }, 280.0)
    if grid_error != ok { ret (zero, grid_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 1usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = grid
    var page = style.defaults()
    page.width = style.Length { Px: 420.0 }
    page.height = style.Length { Px: 400.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 10.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, page, parts[0usize..1usize]), ok)
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

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * W + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn focus_on(h: *testing.Harness, key: widget.Key) -> bool {
    let (element, has) = testing.focused(h)
    let m = testing.by_key(h, key)
    ret has && m.count == 1usize && element.slot == m.element.slot
}

fn at_cell(store: *const Store, row: usize, column: usize) -> bool {
    ret store.state.row == row && store.state.column == column && !store.state.editing
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 800usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 40u16, max_commands: 4096usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 420u32, 400u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (draft, draft_error) = mem.alloc[u8](a, 64usize)
    if draft_error != ok { os.exit(7i32) }
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(8i32) }
    var blank: Store = zero
    stores[0usize] = blank
    stores[0usize].draft = draft
    let store = &stores[0usize]
    let ctx = mem.cast[*void](store)
    let (storage, storage_error) = mem.alloc[u8](a, 16777216usize)
    if storage_error != ok { os.exit(9i32) }
    var f = mem.arena_from(storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&f, &theme, ctx, store)
    if build_error != ok || testing.pump(&harness, root, now) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    // The frame: the grid 40 + 220 wide; the active cell 40 in and under the
    // 40 header, 119 by 31 (its column less the grid line), ringed.
    let (grid, has_grid) = bounds(&harness, &runtime, 1u64)
    let (holder, has_holder) = bounds(&harness, &runtime, 2u64)
    if !has_grid || !has_holder || !near(grid.width, 260.0) || !near(holder.x, grid.x + 40.0) || !near(holder.y, grid.y + 40.0) || !near(holder.width, 119.0) || !near(holder.height, 31.0) { os.exit(12i32) }
    if !is_color(shot, at(holder.x + 1.5, holder.y + 15.0), style.color(&tokens, .FocusRing)) || !is_color(shot, at(holder.x + 60.0, holder.y + 15.0), style.color(&tokens, .Background)) { os.exit(13i32) }
    // Port of beta is invalid: its 2px error outline, and the status bar's count.
    let port_x = grid.x + 160.0
    if !is_color(shot, at(port_x + 1.0, grid.y + 72.0 + 15.0), style.color(&tokens, .Error)) || testing.by_text(&harness, "1 error").count != 1usize { os.exit(14i32) }
    // Host of gamma is dirty: the 2 wide primary bar at its start.
    if !is_color(shot, at(grid.x + 41.0, grid.y + 104.0 + 15.0), style.color(&tokens, .Primary)) || is_color(shot, at(grid.x + 41.0, grid.y + 72.0 + 15.0), style.color(&tokens, .Primary)) { os.exit(15i32) }
    // A tap on Port of alpha moves the active cell there and takes the focus.
    if testing.tap(&harness, port_x + 50.0, grid.y + 55.0) != ok || !at_cell(store, 0usize, 1usize) { os.exit(16i32) }
    let (root_2, build_2_error) = build(&f, &theme, ctx, store)
    if build_2_error != ok || testing.pump(&harness, root_2, now) != ok { os.exit(17i32) }
    let (moved, has_moved) = bounds(&harness, &runtime, 2u64)
    if !has_moved || !near(moved.x, port_x) || !near(moved.width, 99.0) || !focus_on(&harness, 2u64) { os.exit(18i32) }
    // Down, then Shift+Down: a range of two, filled, and counted.
    var plain: input.Modifiers = zero
    var shift: input.Modifiers = zero
    shift.shift = true
    var ctrl: input.Modifiers = zero
    ctrl.control = true
    if testing.press_key(&harness, 40u32, plain) != ok || !at_cell(store, 1usize, 1usize) { os.exit(19i32) }
    let (root_3, build_3_error) = build(&f, &theme, ctx, store)
    if build_3_error != ok || testing.pump(&harness, root_3, now) != ok { os.exit(20i32) }
    if testing.press_key(&harness, 40u32, shift) != ok || store.last.kind != .Extend || store.state.row != 2usize || store.state.anchor_row != 1usize { os.exit(21i32) }
    let (root_4, build_4_error) = build(&f, &theme, ctx, store)
    if build_4_error != ok || testing.pump(&harness, root_4, now) != ok { os.exit(22i32) }
    let (shot_4, shot_4_error) = testing.snapshot(&harness, a)
    if shot_4_error != ok { os.exit(23i32) }
    if !is_color(shot_4, at(port_x + 50.0, grid.y + 104.0 + 20.0), style.color(&tokens, .PrimaryContainer)) || is_color(shot_4, at(port_x + 50.0, grid.y + 136.0 + 20.0), style.color(&tokens, .PrimaryContainer)) || testing.by_text(&harness, "2 cells selected").count != 1usize { os.exit(24i32) }
    // Escape drops the range; Home, End, Ctrl+End, Ctrl+Home, Page Down, Page Up.
    if testing.press_key(&harness, 27u32, plain) != ok || !at_cell(store, 2usize, 1usize) || store.state.anchor_row != 2usize { os.exit(25i32) }
    let (root_5, build_5_error) = build(&f, &theme, ctx, store)
    if build_5_error != ok || testing.pump(&harness, root_5, now) != ok || testing.by_text(&harness, "2 cells selected").count != 0usize { os.exit(26i32) }
    if testing.press_key(&harness, 36u32, plain) != ok || !at_cell(store, 2usize, 0usize) { os.exit(27i32) }
    let (root_6, build_6_error) = build(&f, &theme, ctx, store)
    if build_6_error != ok || testing.pump(&harness, root_6, now) != ok { os.exit(28i32) }
    if testing.press_key(&harness, 35u32, plain) != ok || !at_cell(store, 2usize, 1usize) { os.exit(29i32) }
    let (root_7, build_7_error) = build(&f, &theme, ctx, store)
    if build_7_error != ok || testing.pump(&harness, root_7, now) != ok { os.exit(30i32) }
    if testing.press_key(&harness, 35u32, ctrl) != ok || !at_cell(store, 4usize, 1usize) { os.exit(31i32) }
    let (root_8, build_8_error) = build(&f, &theme, ctx, store)
    if build_8_error != ok || testing.pump(&harness, root_8, now) != ok { os.exit(32i32) }
    if testing.press_key(&harness, 36u32, ctrl) != ok || !at_cell(store, 0usize, 0usize) { os.exit(33i32) }
    let (root_9, build_9_error) = build(&f, &theme, ctx, store)
    if build_9_error != ok || testing.pump(&harness, root_9, now) != ok { os.exit(34i32) }
    if testing.press_key(&harness, 34u32, plain) != ok || !at_cell(store, 4usize, 0usize) { os.exit(35i32) }
    let (root_10, build_10_error) = build(&f, &theme, ctx, store)
    if build_10_error != ok || testing.pump(&harness, root_10, now) != ok { os.exit(36i32) }
    if testing.press_key(&harness, 33u32, plain) != ok || !at_cell(store, 0usize, 0usize) || !focus_on(&harness, 2u64) { os.exit(37i32) }
    let (root_11, build_11_error) = build(&f, &theme, ctx, store)
    if build_11_error != ok || testing.pump(&harness, root_11, now) != ok { os.exit(38i32) }
    // F2 edits alpha: the editor over the cell, its fill and outline, focused.
    if testing.press_key(&harness, 113u32, plain) != ok || store.last.kind != .Edit || !store.state.editing || store.state.len != 5usize { os.exit(39i32) }
    let (root_12, build_12_error) = build(&f, &theme, ctx, store)
    if build_12_error != ok || testing.pump(&harness, root_12, now) != ok { os.exit(40i32) }
    let (shot_12, shot_12_error) = testing.snapshot(&harness, a)
    if shot_12_error != ok { os.exit(41i32) }
    let (editor, has_editor) = bounds(&harness, &runtime, 3u64)
    if !has_editor || !near(editor.x, grid.x + 40.0) || !near(editor.y, grid.y + 40.0) || !near(editor.width, 119.0) || !near(editor.height, 31.0) || !focus_on(&harness, 3u64) { os.exit(42i32) }
    if !is_color(shot_12, at(editor.x + 60.0, editor.y + 15.0), style.color(&tokens, .SurfaceContainerHighest)) || !is_color(shot_12, at(editor.x + 0.5, editor.y + 15.0), style.color(&tokens, .Primary)) { os.exit(43i32) }
    // Typing reaches the draft; Enter commits alpha and moves down, the focus
    // back on the grid.
    if testing.type_text(&harness, "x") != ok || store.last.kind != .Type || store.state.len != 6usize { os.exit(44i32) }
    let (root_13, build_13_error) = build(&f, &theme, ctx, store)
    if build_13_error != ok || testing.pump(&harness, root_13, now) != ok { os.exit(45i32) }
    if testing.press_key(&harness, 13u32, plain) != ok || store.last.kind != .Commit || store.committed != 6usize || store.committed_row != 0usize || !at_cell(store, 1usize, 0usize) { os.exit(46i32) }
    let (root_14, build_14_error) = build(&f, &theme, ctx, store)
    if build_14_error != ok || testing.pump(&harness, root_14, now) != ok { os.exit(47i32) }
    if testing.by_key(&harness, 3u64).count != 0usize || !focus_on(&harness, 2u64) { os.exit(48i32) }
    // Enter edits beta; Escape cancels and stays.
    if testing.press_key(&harness, 13u32, plain) != ok || store.last.kind != .Edit || !store.state.editing { os.exit(49i32) }
    let (root_15, build_15_error) = build(&f, &theme, ctx, store)
    if build_15_error != ok || testing.pump(&harness, root_15, now) != ok { os.exit(50i32) }
    if testing.press_key(&harness, 27u32, plain) != ok || store.last.kind != .Cancel || !at_cell(store, 1usize, 0usize) { os.exit(51i32) }
    // The grid in the tree, named, 5 by 2.
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(52i32) }
    var found = false
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == .Grid && tree.nodes[i].position.row_count == 5u32 && tree.nodes[i].position.column_count == 2u32 { found = true }
        i += 1usize
    }
    if !found { os.exit(53i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(54i32) }
    try io.print("ui collections6 v2 ok\n")
    ret ok
}
