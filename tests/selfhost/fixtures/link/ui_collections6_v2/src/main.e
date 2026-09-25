// The v2 data grid's core (D984, widget plan P5-12, docs/ux/components/DataGrid)
// under the light theme: one active cell ringed in `focus-ring` holding the
// grid's focus, a tap moving it; an invalid cell's 2px `error` outline and the
// status bar's "1 error"; a dirty cell's `primary` start bar; the arrows, Home,
// End, Ctrl+Home, Ctrl+End, Page Up and Page Down moving the active cell; Tab
// wrapping, Ctrl+A selecting all cells, Shift+Space selecting a row,
// Ctrl+Space selecting a column, F8 finding the next invalid cell, TSV Copy,
// typing to replace, and caller-owned Paste, Clear, Undo and Fill Down commands;
// Shift+Down extending a `primary-container` range and "2 cells selected";
// Escape dropping it; F2 editing in a `surface-container-highest` editor in a
// 2px `primary` outline over the cell, which takes the focus; typing, Enter or
// Tab committing and moving with the focus back on the grid; Enter editing and
// Escape cancelling. X keysyms and Windows virtual keys share those paths.

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

type Store = struct { state: collection.GridState, draft: []u8, events: usize, last: collection.GridEvent, committed: usize, committed_row: usize, committed_column: usize, saving: bool }

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
    let store = mem.cast[*Store](ctx)
    var c = collection.GridCell { text: cell_text(row, column), message: "", dirty: false, read_only: false, saving: store.saving && row == 2usize && column == 0usize }
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
    if event.kind == .Replace {
        var i = 0usize
        while i < event.text.len && i < store.draft.len {
            store.draft[i] = event.text[i]
            i += 1usize
        }
        store.state.len = i
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

fn same_text(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn shift_key(down: bool) -> input.Event {
    var held: input.Modifiers = zero
    held.shift = down
    let key = input.KeyEvent { window: zero, key: input.Key { physical: 65505u32, logical: 65505u32 }, modifiers: held, repeat: false }
    if down { ret input.Event { KeyDown: key } }
    ret input.Event { KeyUp: key }
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
    let (storage, storage_error) = mem.alloc[u8](a, 33554432usize)
    if storage_error != ok { os.exit(9i32) }
    var f = mem.arena_from(storage)
    var now = time.Instant { nanos: 1000000000i64 }
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
    // The invalid cell takes the hover state layer immediately and shows its
    // standard tooltip after the shared 500 ms delay.
    let invalid_y = grid.y + 72.0 + 15.0
    if testing.hover(&harness, port_x + 50.0, invalid_y) != ok || testing.begin(&harness, now) != ok { os.exit(95i32) }
    let (hover_wait, hover_wait_error) = build(&f, &theme, ctx, store)
    if hover_wait_error != ok || testing.pump(&harness, hover_wait, now) != ok || !widget.interaction(&runtime, 1028u64).hovered || testing.by_key(&harness, 1001028u64).count != 0usize { os.exit(96i32) }
    let hover_due = time.Instant { nanos: 1500000000i64 }
    if testing.begin(&harness, hover_due) != ok { os.exit(97i32) }
    let (hover_shown, hover_shown_error) = build(&f, &theme, ctx, store)
    if hover_shown_error != ok || testing.pump(&harness, hover_shown, hover_due) != ok { os.exit(98i32) }
    if testing.by_key(&harness, 1001028u64).count != 1usize { os.exit(103i32) }
    if testing.by_text(&harness, "Port must be a number").count == 0usize { os.exit(104i32) }
    let (hover_shot, hover_shot_error) = testing.snapshot(&harness, a)
    let hover_fill = style.layer(style.color(&tokens, .Surface), style.color(&tokens, .OnSurface), tokens.states.hover)
    if hover_shot_error != ok || !is_color(hover_shot, at(port_x + 50.0, invalid_y), hover_fill) { os.exit(99i32) }
    if testing.hover(&harness, 410.0, 390.0) != ok { os.exit(100i32) }
    let hover_done = time.Instant { nanos: 1600000000i64 }
    if testing.begin(&harness, hover_done) != ok { os.exit(101i32) }
    let (hover_clear, hover_clear_error) = build(&f, &theme, ctx, store)
    if hover_clear_error != ok || testing.pump(&harness, hover_clear, hover_done) != ok || testing.by_key(&harness, 1001028u64).count != 0usize { os.exit(102i32) }
    now = hover_done
    // Host of gamma is dirty: the 2 wide primary bar at its start.
    if !is_color(shot, at(grid.x + 41.0, grid.y + 104.0 + 15.0), style.color(&tokens, .Primary)) || is_color(shot, at(grid.x + 41.0, grid.y + 72.0 + 15.0), style.color(&tokens, .Primary)) { os.exit(15i32) }
    var plain: input.Modifiers = zero
    var shift: input.Modifiers = zero
    shift.shift = true
    var ctrl: input.Modifiers = zero
    ctrl.control = true
    // A tap on Port of alpha moves the active cell there and takes the focus.
    if testing.tap(&harness, port_x + 50.0, grid.y + 55.0) != ok || !at_cell(store, 0usize, 1usize) { os.exit(16i32) }
    let (root_2, build_2_error) = build(&f, &theme, ctx, store)
    if build_2_error != ok || testing.pump(&harness, root_2, now) != ok { os.exit(17i32) }
    let (moved, has_moved) = bounds(&harness, &runtime, 2u64)
    if !has_moved || !near(moved.x, port_x) || !near(moved.width, 99.0) || !focus_on(&harness, 2u64) { os.exit(18i32) }
    // A held host Shift key makes a pointer tap extend from the existing anchor.
    if widget.dispatch(&runtime, shift_key(true)) != ok || !widget.modifiers(&runtime).shift || testing.tap(&harness, grid.x + 100.0, grid.y + 120.0) != ok || widget.dispatch(&runtime, shift_key(false)) != ok || widget.modifiers(&runtime).shift || store.last.kind != .Extend || store.state.row != 2usize || store.state.column != 0usize || store.state.anchor_row != 0usize || store.state.anchor_column != 1usize { os.exit(111i32) }
    let (root_2s, build_2s_error) = build(&f, &theme, ctx, store)
    if build_2s_error != ok || testing.pump(&harness, root_2s, now) != ok || testing.by_text(&harness, "6 cells selected").count != 1usize { os.exit(112i32) }
    // A second tap within 500 ms keeps both ordinary tap notifications and adds
    // edit mode for an editable cell.
    let double_at = time.Instant { nanos: 2200000000i64 }
    if testing.begin(&harness, double_at) != ok || testing.tap(&harness, port_x + 50.0, grid.y + 55.0) != ok || testing.tap(&harness, port_x + 50.0, grid.y + 55.0) != ok || store.last.kind != .Edit || !store.state.editing || store.state.row != 0usize || store.state.column != 1usize { os.exit(107i32) }
    let (root_2a, build_2a_error) = build(&f, &theme, ctx, store)
    if build_2a_error != ok || testing.pump(&harness, root_2a, double_at) != ok || !focus_on(&harness, 3u64) { os.exit(108i32) }
    if testing.press_key(&harness, 27u32, plain) != ok || store.last.kind != .Cancel || store.state.editing { os.exit(109i32) }
    let (root_2b, build_2b_error) = build(&f, &theme, ctx, store)
    if build_2b_error != ok || testing.pump(&harness, root_2b, double_at) != ok || !focus_on(&harness, 2u64) { os.exit(110i32) }
    now = double_at
    // Down, then Shift+Down: a range of two, filled, and counted.
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
    // Tab wraps by cell, F8 visits the invalid Port of beta, and Ctrl+A selects
    // the whole grid. Linux keysyms normalize to the same public key codes.
    if widget.key_code(65471u32) != 113u32 || widget.key_code(65477u32) != 119u32 || widget.key_code(65365u32) != 33u32 || widget.key_code(65366u32) != 34u32 { os.exit(55i32) }
    if testing.press_key(&harness, 9u32, plain) != ok || !at_cell(store, 0usize, 1usize) { os.exit(56i32) }
    let (root_11a, build_11a_error) = build(&f, &theme, ctx, store)
    if build_11a_error != ok || testing.pump(&harness, root_11a, now) != ok { os.exit(57i32) }
    if testing.press_key(&harness, 9u32, plain) != ok || !at_cell(store, 1usize, 0usize) { os.exit(58i32) }
    let (root_11b, build_11b_error) = build(&f, &theme, ctx, store)
    if build_11b_error != ok || testing.pump(&harness, root_11b, now) != ok { os.exit(59i32) }
    if testing.press_key(&harness, 9u32, shift) != ok || !at_cell(store, 0usize, 1usize) { os.exit(60i32) }
    let (root_11c, build_11c_error) = build(&f, &theme, ctx, store)
    if build_11c_error != ok || testing.pump(&harness, root_11c, now) != ok { os.exit(61i32) }
    if testing.press_key(&harness, 65477u32, plain) != ok || !at_cell(store, 1usize, 1usize) { os.exit(62i32) }
    let (root_11d, build_11d_error) = build(&f, &theme, ctx, store)
    if build_11d_error != ok || testing.pump(&harness, root_11d, now) != ok || testing.by_key(&harness, 1001028u64).count != 1usize { os.exit(63i32) }
    if testing.press_key(&harness, 65u32, ctrl) != ok || store.last.kind != .Extend || store.state.row != 4usize || store.state.column != 1usize || store.state.anchor_row != 0usize || store.state.anchor_column != 0usize { os.exit(64i32) }
    let (root_11e, build_11e_error) = build(&f, &theme, ctx, store)
    if build_11e_error != ok || testing.pump(&harness, root_11e, now) != ok || testing.by_text(&harness, "10 cells selected").count != 1usize { os.exit(65i32) }
    if testing.press_key(&harness, 27u32, plain) != ok || store.state.anchor_row != 4usize || store.state.anchor_column != 1usize { os.exit(66i32) }
    let (root_11f, build_11f_error) = build(&f, &theme, ctx, store)
    if build_11f_error != ok || testing.pump(&harness, root_11f, now) != ok { os.exit(67i32) }
    if testing.press_key(&harness, 36u32, ctrl) != ok || !at_cell(store, 0usize, 0usize) { os.exit(68i32) }
    let (root_11g, build_11g_error) = build(&f, &theme, ctx, store)
    if build_11g_error != ok || testing.pump(&harness, root_11g, now) != ok { os.exit(69i32) }
    // Linux F2 edits alpha: the editor over the cell, its fill and outline, focused.
    if testing.press_key(&harness, 65471u32, plain) != ok || store.last.kind != .Edit || !store.state.editing || store.state.len != 5usize { os.exit(39i32) }
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
    // Tab commits an edit to the next cell; Shift+Enter commits upward.
    let (root_16, build_16_error) = build(&f, &theme, ctx, store)
    if build_16_error != ok || testing.pump(&harness, root_16, now) != ok { os.exit(70i32) }
    if !focus_on(&harness, 2u64) { os.exit(90i32) }
    if testing.press_key(&harness, 13u32, plain) != ok { os.exit(71i32) }
    if !store.state.editing { os.exit(89i32) }
    let (root_17, build_17_error) = build(&f, &theme, ctx, store)
    if build_17_error != ok || testing.pump(&harness, root_17, now) != ok { os.exit(72i32) }
    if testing.press_key(&harness, 9u32, plain) != ok || store.last.kind != .Commit || !at_cell(store, 1usize, 1usize) { os.exit(73i32) }
    let (root_18, build_18_error) = build(&f, &theme, ctx, store)
    if build_18_error != ok || testing.pump(&harness, root_18, now) != ok || testing.press_key(&harness, 13u32, plain) != ok || !store.state.editing { os.exit(74i32) }
    let (root_19, build_19_error) = build(&f, &theme, ctx, store)
    if build_19_error != ok || testing.pump(&harness, root_19, now) != ok { os.exit(75i32) }
    if testing.press_key(&harness, 13u32, shift) != ok || store.last.kind != .Commit || !at_cell(store, 0usize, 1usize) { os.exit(76i32) }
    // Selection commands expose row/column ranges; clipboard and mutation
    // commands keep the values caller-owned.
    let (root_20, build_20_error) = build(&f, &theme, ctx, store)
    if build_20_error != ok || testing.pump(&harness, root_20, now) != ok { os.exit(77i32) }
    if testing.press_key(&harness, 32u32, shift) != ok || store.last.kind != .Extend || store.state.row != 0usize || store.state.column != 1usize || store.state.anchor_row != 0usize || store.state.anchor_column != 0usize { os.exit(78i32) }
    let (root_21, build_21_error) = build(&f, &theme, ctx, store)
    if build_21_error != ok || testing.pump(&harness, root_21, now) != ok || testing.by_text(&harness, "2 cells selected").count != 1usize { os.exit(79i32) }
    if testing.press_key(&harness, 32u32, ctrl) != ok || store.last.kind != .Extend || store.state.row != 4usize || store.state.column != 1usize || store.state.anchor_row != 0usize || store.state.anchor_column != 1usize { os.exit(80i32) }
    let (root_22, build_22_error) = build(&f, &theme, ctx, store)
    if build_22_error != ok || testing.pump(&harness, root_22, now) != ok || testing.by_text(&harness, "5 cells selected").count != 1usize { os.exit(81i32) }
    if testing.press_key(&harness, 67u32, ctrl) != ok { os.exit(82i32) }
    let (copied, copied_error) = widget.clipboard_get(&runtime, &f)
    if copied_error != ok || !same_text(copied, "22\n22a\n22\n22\n22") { os.exit(83i32) }
    if widget.clipboard_set(&runtime, "7\t8") != ok || testing.press_key(&harness, 86u32, ctrl) != ok || store.last.kind != .Paste || !same_text(store.last.text, "7\t8") { os.exit(84i32) }
    if testing.press_key(&harness, 46u32, plain) != ok || store.last.kind != .Clear { os.exit(85i32) }
    if testing.press_key(&harness, 90u32, ctrl) != ok || store.last.kind != .Undo { os.exit(86i32) }
    if testing.press_key(&harness, 68u32, ctrl) != ok || store.last.kind != .FillDown { os.exit(87i32) }
    if testing.press_key(&harness, 13u32, ctrl) != ok || store.last.kind != .FillDown { os.exit(88i32) }
    // Text input in navigation mode replaces the active value and opens its editor.
    if testing.type_text(&harness, "z") != ok || store.last.kind != .Replace || !store.state.editing || store.state.len != 1usize || store.draft[0usize] != 122u8 { os.exit(91i32) }
    let (root_23, build_23_error) = build(&f, &theme, ctx, store)
    if build_23_error != ok || testing.pump(&harness, root_23, now) != ok || !focus_on(&harness, 3u64) { os.exit(92i32) }
    if testing.press_key(&harness, 27u32, plain) != ok || store.last.kind != .Cancel || store.state.editing { os.exit(93i32) }
    let (root_24, build_24_error) = build(&f, &theme, ctx, store)
    if build_24_error != ok || testing.pump(&harness, root_24, now) != ok || !focus_on(&harness, 2u64) { os.exit(94i32) }
    // Bulk saving disables every edit path, reports the count, and gives each
    // saving cell the shared 16px indeterminate ring.
    store.saving = true
    store.state.disabled = true
    store.state.saving = 3usize
    let events_before_save = store.events
    let row_before_save = store.state.row
    let (root_25, build_25_error) = build(&f, &theme, ctx, store)
    if build_25_error != ok || testing.pump(&harness, root_25, now) != ok || testing.by_text(&harness, "Saving 3 changes").count != 1usize || testing.by_key(&harness, 2001029u64).count != 1usize || !widget.animation_frame_requested(&runtime) { os.exit(105i32) }
    if testing.press_key(&harness, 40u32, plain) != ok || testing.type_text(&harness, "x") != ok || testing.tap(&harness, port_x + 50.0, grid.y + 55.0) != ok || store.events != events_before_save || store.state.row != row_before_save { os.exit(106i32) }
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
