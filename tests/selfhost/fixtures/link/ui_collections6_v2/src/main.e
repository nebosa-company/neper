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

type Store = struct { state: collection.GridState, draft: []u8, events: usize, last: collection.GridEvent, committed: usize, committed_row: usize, committed_column: usize, saving: bool, checked: bool, opened: usize, offset: f32, scrolls: usize }

fn cell_text(row: usize, column: usize) -> str {
    if column == 1usize {
        if row == 1usize { ret "22a" }
        if row == 4usize { ret "2026-09-25" }
        ret "22"
    }
    if row == 0usize { ret "alpha" }
    if row == 1usize { ret "beta" }
    if row == 2usize { ret "gamma" }
    if row == 3usize { ret "staging" }
    ret "Enabled"
}

// (D1505) A two-row grid whose first cell's value the test changes.
type FadeModel = struct { value: str }

fn fade_count(ctx: *void) -> usize {
    ret 2usize
}

fn fade_cell(ctx: *void, row: usize, column: usize) -> collection.GridCell {
    let model = mem.cast[*FadeModel](ctx)
    var text = "x"
    if row == 0usize && column == 0usize { text = model.value }
    ret collection.GridCell { text: text, message: "", kind: .Text, checked: false, dirty: false, read_only: false, saving: false }
}

fn grid_count(ctx: *void) -> usize {
    ret 5usize
}

fn grid_cell(ctx: *void, row: usize, column: usize) -> collection.GridCell {
    let store = mem.cast[*Store](ctx)
    var c = collection.GridCell { text: cell_text(row, column), message: "", kind: .Text, checked: false, dirty: false, read_only: false, saving: store.saving && row == 2usize && column == 0usize }
    if row == 1usize && column == 1usize { c.message = "Port must be a number" }
    if row == 2usize && column == 0usize { c.dirty = true }
    if row == 3usize && column == 0usize { c.kind = .Select }
    if row == 4usize && column == 0usize {
        c.kind = .Checkbox
        c.checked = store.checked
    }
    if row == 4usize && column == 1usize { c.kind = .Date }
    if row == 3usize && column == 1usize { c.read_only = true }
    ret c
}

// (D1402) A sheet Save, counted.
fn on_save(ctx: *void) -> err {
    let count = mem.cast[*u32](ctx)
    *count += 1u32
    ret ok
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
    if event.kind == .Toggle { store.checked = !store.checked }
    if event.kind == .Open { store.opened += 1usize }
    ret ok
}

fn on_scroll(ctx: *void, value: f32) -> err {
    let store = mem.cast[*Store](ctx)
    store.offset = value
    store.scrolls += 1usize
    ret ok
}

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, store: *Store) -> (widget.Node, err) {
    let (columns, columns_error) = mem.alloc[collection.Column](a, 2usize)
    if columns_error != ok { ret (zero, columns_error) }
    columns[0usize] = collection.Column { title: "Host", width: 120.0 }
    columns[1usize] = collection.Column { title: "Port", width: 100.0 }
    let source = collection.GridSource { ctx: ctx, count: grid_count, cell: grid_cell }
    let (grid, grid_error) = collection.data_grid_of(a, 1u64, t, "Build hosts", columns[0usize..2usize], source, store.state, store.draft, widget.Change[collection.GridEvent] { ctx: ctx, invoke: on_change }, 0.0, store.offset, widget.Change[f32] { ctx: ctx, invoke: on_scroll }, 280.0)
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

// (D1540) A virtual grid's asks: pages, zooms and the last level.
type GridLog = struct { pages: usize, zooms: usize, level: usize }

fn wall_count(ctx: *void) -> usize {
    ret 10usize
}

fn wall_key(ctx: *void, index: usize) -> widget.Key {
    ret 8100u64 + u64(index)
}

fn wall_tile(ctx: *void, index: usize) -> collection.Tile {
    ret collection.tile_of_name("Photo")
}

fn on_grid_page(ctx: *void) -> err {
    let log = mem.cast[*GridLog](ctx)
    log.pages += 1usize
    ret ok
}

fn on_grid_zoom(ctx: *void, value: usize) -> err {
    let log = mem.cast[*GridLog](ctx)
    log.zooms += 1usize
    log.level = value
    ret ok
}

// (D1539) The toolbar's filter removals: how many, and the last index.
type UnfilterLog = struct { count: usize, index: usize }

fn on_unfilter(ctx: *void, value: usize) -> err {
    let log = mem.cast[*UnfilterLog](ctx)
    log.count += 1usize
    log.index = value
    ret ok
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
    var alt: input.Modifiers = zero
    alt.alt = true
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
    // (D1382) A range of numbers sums: Port of gamma and staging is 22 + 22; a
    // range with a name in it does not; the sum is written with thousands commas.
    let number_source = collection.GridSource { ctx: ctx, count: grid_count, cell: grid_cell }
    var number_state: collection.GridState = zero
    number_state.row = 2usize
    number_state.anchor_row = 3usize
    number_state.column = 1usize
    number_state.anchor_column = 1usize
    let (port_sum, port_numbers, port_whole) = collection.grid_sum(number_source, number_state)
    number_state.column = 0usize
    let (_, mixed_numbers, _) = collection.grid_sum(number_source, number_state)
    if !port_numbers || !port_whole || port_sum != 44.0 || mixed_numbers { os.exit(160i32) }
    var grouped: [24]u8 = zero
    let grouped_len = collection.write_sum(grouped[..], 1234567.0, true)
    let halves_len = collection.write_sum(grouped[12usize..24usize], 11244.5, false)
    let (read_back, read_whole, read_ok) = collection.read_number("1,234.5")
    if !testing.same_text(grouped[0usize..grouped_len], "1,234,567") || !testing.same_text(grouped[12usize..12usize + halves_len], "11,244.50") || !read_ok || read_whole || read_back != 1234.5 { os.exit(161i32) }
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
    if copied_error != ok || !same_text(copied, "22\n22a\n22\n22\n2026-09-25") { os.exit(83i32) }
    if widget.clipboard_set(&runtime, "7\t8") != ok || testing.press_key(&harness, 86u32, ctrl) != ok || store.last.kind != .Paste || !same_text(store.last.text, "7\t8") { os.exit(84i32) }
    if testing.press_key(&harness, 46u32, plain) != ok || store.last.kind != .Clear { os.exit(85i32) }
    if testing.press_key(&harness, 90u32, ctrl) != ok || store.last.kind != .Undo { os.exit(86i32) }
    if testing.press_key(&harness, 68u32, ctrl) != ok || store.last.kind != .FillDown { os.exit(87i32) }
    if testing.press_key(&harness, 13u32, ctrl) != ok || store.last.kind != .FillDown { os.exit(88i32) }
    // Non-text cells keep their values caller-owned: date/select open through
    // Alt+Down, while click and Space toggle a checkbox.
    if testing.press_key(&harness, 40u32, alt) != ok || store.last.kind != .Open || store.opened != 1usize { os.exit(115i32) }
    if testing.tap(&harness, grid.x + 100.0, grid.y + 184.0) != ok || store.last.kind != .Toggle || !store.checked || !at_cell(store, 4usize, 0usize) { os.exit(116i32) }
    let (root_22a, build_22a_error) = build(&f, &theme, ctx, store)
    if build_22a_error != ok || testing.pump(&harness, root_22a, now) != ok || testing.press_key(&harness, 32u32, plain) != ok || store.last.kind != .Toggle || store.checked { os.exit(117i32) }
    if testing.tap(&harness, grid.x + 100.0, grid.y + 152.0) != ok || !at_cell(store, 3usize, 0usize) { os.exit(118i32) }
    let (root_22b, build_22b_error) = build(&f, &theme, ctx, store)
    if build_22b_error != ok || testing.pump(&harness, root_22b, now) != ok || testing.press_key(&harness, 40u32, alt) != ok || store.last.kind != .Open || store.opened != 2usize { os.exit(119i32) }
    if testing.press_key(&harness, 36u32, ctrl) != ok || !at_cell(store, 0usize, 0usize) { os.exit(120i32) }
    let (root_22c, build_22c_error) = build(&f, &theme, ctx, store)
    if build_22c_error != ok || testing.pump(&harness, root_22c, now) != ok { os.exit(121i32) }
    // Text input in navigation mode replaces the active value and opens its editor.
    if testing.type_text(&harness, "z") != ok || store.last.kind != .Replace || !store.state.editing || store.state.len != 1usize || store.draft[0usize] != 122u8 { os.exit(91i32) }
    let (root_23, build_23_error) = build(&f, &theme, ctx, store)
    if build_23_error != ok || testing.pump(&harness, root_23, now) != ok || !focus_on(&harness, 3u64) { os.exit(92i32) }
    if testing.press_key(&harness, 27u32, plain) != ok || store.last.kind != .Cancel || store.state.editing { os.exit(93i32) }
    let (root_24, build_24_error) = build(&f, &theme, ctx, store)
    if build_24_error != ok || testing.pump(&harness, root_24, now) != ok || !focus_on(&harness, 2u64) { os.exit(94i32) }
    // A header press opens its menu; the command selects the complete column.
    if testing.tap(&harness, port_x + 50.0, grid.y + 20.0) != ok || store.last.kind != .Menu || !store.state.menu_open || store.state.menu_column != 1usize { os.exit(122i32) }
    let (root_24m, build_24m_error) = build(&f, &theme, ctx, store)
    if build_24m_error != ok { os.exit(123i32) }
    if testing.pump(&harness, root_24m, now) != ok { os.exit(126i32) }
    let select_match = testing.by_role(&harness, .MenuItem)
    if select_match.count != 1usize { os.exit(127i32) }
    let (select_column, has_select_column) = widget.bounds_of(&runtime, select_match.element)
    if !has_select_column { os.exit(124i32) }
    if testing.tap(&harness, select_column.x + 12.0, select_column.y + 12.0) != ok { os.exit(128i32) }
    if store.last.kind != .Extend || store.state.menu_open || store.state.row != 4usize || store.state.column != 1usize || store.state.anchor_row != 0usize || store.state.anchor_column != 1usize { os.exit(129i32) }
    let (root_24c, build_24c_error) = build(&f, &theme, ctx, store)
    if build_24c_error != ok || testing.pump(&harness, root_24c, now) != ok || testing.by_text(&harness, "5 cells selected").count != 1usize || !focus_on(&harness, 2u64) { os.exit(125i32) }
    if testing.tap(&harness, port_x + 50.0, grid.y + 20.0) != ok || !store.state.menu_open { os.exit(130i32) }
    let (root_24d, build_24d_error) = build(&f, &theme, ctx, store)
    if build_24d_error != ok || testing.pump(&harness, root_24d, now) != ok || testing.press_key(&harness, 27u32, plain) != ok || store.last.kind != .Menu || store.state.menu_open { os.exit(131i32) }
    let (root_24e, build_24e_error) = build(&f, &theme, ctx, store)
    if build_24e_error != ok || testing.pump(&harness, root_24e, now) != ok || store.state.row != 4usize || store.state.anchor_row != 0usize || store.state.column != 1usize || store.state.anchor_column != 1usize { os.exit(132i32) }
    // A row-number click selects every column in that row and keeps grid focus.
    if testing.tap(&harness, grid.x + 20.0, grid.y + 152.0) != ok || store.last.kind != .Extend || store.state.row != 3usize || store.state.column != 1usize || store.state.anchor_row != 3usize || store.state.anchor_column != 0usize { os.exit(113i32) }
    let (root_24r, build_24r_error) = build(&f, &theme, ctx, store)
    if build_24r_error != ok || testing.pump(&harness, root_24r, now) != ok || testing.by_text(&harness, "2 cells selected").count != 1usize || !focus_on(&harness, 2u64) { os.exit(114i32) }
    // Keyboard navigation asks the caller for the minimum scroll that reveals
    // the new active row.
    store.offset = 64.0
    let (root_24s, build_24s_error) = build(&f, &theme, ctx, store)
    if build_24s_error != ok || testing.pump(&harness, root_24s, now) != ok || testing.press_key(&harness, 36u32, ctrl) != ok || !at_cell(store, 0usize, 0usize) || store.scrolls != 1usize || !near(store.offset, 0.0) { os.exit(133i32) }
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
    // (D1284) Pasted text: two rows of three and two cells (CRLF, a trailing LF),
    // a quoted cell holding a tab and a doubled quote, and an empty cell.
    let pasted = "a\tb\tc\r\n\"x\ty \"\"q\"\"\"\t\n"
    let (paste_rows, paste_columns) = collection.grid_paste_size(pasted)
    if paste_rows != 2usize || paste_columns != 3usize { os.exit(134i32) }
    let (paste_room, paste_room_error) = mem.alloc[u8](a, 32usize)
    if paste_room_error != ok { os.exit(135i32) }
    let (first_cell, has_first_cell) = collection.grid_paste_cell(pasted, 0usize, 1usize, paste_room)
    if !has_first_cell || !mem.eq[u8](first_cell, "b") { os.exit(136i32) }
    let (quoted_cell, has_quoted_cell) = collection.grid_paste_cell(pasted, 1usize, 0usize, paste_room)
    if !has_quoted_cell || !mem.eq[u8](quoted_cell, "x\ty \"q\"") { os.exit(137i32) }
    let (empty_cell, has_empty_cell) = collection.grid_paste_cell(pasted, 1usize, 1usize, paste_room)
    let (_, has_missing_cell) = collection.grid_paste_cell(pasted, 2usize, 0usize, paste_room)
    if !has_empty_cell || empty_cell.len != 0usize || has_missing_cell { os.exit(138i32) }
    // (D1402) On touch a tapped row asks to be edited in a sheet; the sheet lays
    // out a field per column and Save.
    let sheet_tokens = style.adapt(&tokens, style.Adaptation { size: .Expanded, capabilities: style.Capabilities { hover: false, fine_pointer: false, keyboard: false, touch: true, pen: false, resizable: false, multi_window: false, insets: zero }, profile: .Touch })
    let sheet_theme = control.Theme { tokens: &sheet_tokens, fonts: theme.fonts, language: "", runtime: &runtime }
    store.state.editing = false
    store.state.menu_open = false
    store.state.disabled = false
    var sheet_step = 0usize
    while sheet_step < 2usize {
        f = mem.arena_from(storage)
        let (touch_grid, touch_grid_error) = build(&f, &sheet_theme, ctx, store)
        if touch_grid_error != ok || testing.pump(&harness, touch_grid, time.Instant { nanos: 90000000000i64 + i64(sheet_step) }) != ok { os.exit(162i32) }
        sheet_step += 1usize
    }
    let (touch_cell, has_touch_cell) = bounds(&harness, &runtime, 2u64)
    if !has_touch_cell { os.exit(163i32) }
    let (whole_grid, has_whole_grid) = bounds(&harness, &runtime, 1u64)
    let events_before_tap = store.events
    if !has_whole_grid || testing.tap(&harness, whole_grid.x + 150.0, whole_grid.y + 70.0) != ok { os.exit(164i32) }
    if store.events == events_before_tap { os.exit(169i32) }
    if store.last.kind != .EditRow { os.exit(170i32) }
    var sheet_columns: [2]collection.Column = zero
    sheet_columns[0usize] = collection.Column { title: "Host", width: 120.0 }
    sheet_columns[1usize] = collection.Column { title: "Port", width: 100.0 }
    let (sheet_bytes, sheet_bytes_error) = mem.alloc[u8](a, 64usize)
    if sheet_bytes_error != ok { os.exit(165i32) }
    var drafts: [2]collection.RowDraft = zero
    drafts[0usize] = collection.RowDraft { buffer: sheet_bytes[0usize..32usize], len: 0usize }
    drafts[1usize] = collection.RowDraft { buffer: sheet_bytes[32usize..64usize], len: 0usize }
    var saves = 0u32
    let sheet_cancel = widget.Submit { ctx: mem.cast[*void](&saves), invoke: on_save }
    f = mem.arena_from(storage)
    let (row_sheet, row_sheet_error) = collection.grid_row_sheet(&f, 900u64, &sheet_theme, "Edit host", sheet_columns[..], drafts[..], zero, widget.Submit { ctx: mem.cast[*void](&saves), invoke: on_save }, &sheet_cancel, true, 300.0)
    let (sheet_page, sheet_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if row_sheet_error != ok || sheet_page_error != ok { os.exit(166i32) }
    sheet_page[0usize] = row_sheet
    if testing.pump(&harness, widget.box(0u64, control.sized_style(640.0, 600.0), sheet_page[0usize..1usize]), time.Instant { nanos: 91000000000i64 }) != ok { os.exit(167i32) }
    if testing.by_key(&harness, 916u64).count != 1usize || testing.by_key(&harness, 917u64).count != 1usize || testing.by_text(&harness, "Save").count == 0usize { os.exit(168i32) }
    // (D1505) An edit that ends with a new value fades it in: 30 ms on the new
    // value's ink is not yet opaque, a second on it is.
    var fade_model = FadeModel { value: "old" }
    var fade_state: collection.GridState = zero
    var fade_columns: [2]collection.Column = zero
    fade_columns[0usize] = collection.Column { title: "Name", width: 120.0 }
    fade_columns[1usize] = collection.Column { title: "Port", width: 80.0 }
    let (fade_draft, fade_draft_error) = mem.alloc[u8](a, 16usize)
    if fade_draft_error != ok { os.exit(171i32) }
    var fade_step = 0usize
    while fade_step < 5usize {
        var fade_at = 80000000000i64 + i64(fade_step)
        fade_state.editing = fade_step < 2usize
        if fade_step >= 2usize { fade_model.value = "new" }
        if fade_step == 2usize { fade_at = 80100000000i64 }
        if fade_step == 3usize { fade_at = 80130000000i64 }
        if fade_step == 4usize { fade_at = 81100000000i64 }
        if testing.begin(&harness, time.Instant { nanos: fade_at }) != ok { os.exit(172i32) }
        f = mem.arena_from(storage)
        let fade_source = collection.GridSource { ctx: mem.cast[*void](&fade_model), count: fade_count, cell: fade_cell }
        let (fade_grid, fade_grid_error) = collection.data_grid_of(&f, 7000u64, &theme, "Fading", fade_columns[..], fade_source, fade_state, fade_draft, zero, 0.0, 0.0, zero, 200.0)
        let (fade_page, fade_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if fade_grid_error != ok || fade_page_error != ok { os.exit(173i32) }
        fade_page[0usize] = fade_grid
        if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 300.0), fade_page[0usize..1usize]), time.Instant { nanos: fade_at }) != ok { os.exit(174i32) }
        if fade_step >= 3usize {
            let (new_ink, has_new_ink) = testing.text_color(&harness, "new")
            if !has_new_ink { os.exit(175i32) }
            if fade_step == 3usize && !(new_ink.alpha < 0.99) { os.exit(176i32) }
            if fade_step == 4usize && !(new_ink.alpha > 0.99) { os.exit(177i32) }
        }
        fade_step += 1usize
    }
    // (D1537) A refresh's outcome: failed with Retry, new rows above counted, up
    // to date only past 2 s, and nothing for rows in view or a quick refresh.
    let (failed_notice, failed_shown, failed_error) = collection.refresh_outcome_notice(a, 0usize, false, 0i64, true, "build", "builds", zero, zero)
    if failed_error != ok || !failed_shown || !same_text(failed_notice.text, "Couldn't refresh. Check your connection") || !same_text(failed_notice.action_label, "Retry") { os.exit(178i32) }
    let (one_notice, one_shown, one_error) = collection.refresh_outcome_notice(a, 1usize, true, 0i64, false, "build", "builds", zero, zero)
    let (many_notice, many_shown, many_error) = collection.refresh_outcome_notice(a, 12usize, true, 0i64, false, "build", "builds", zero, zero)
    if one_error != ok || many_error != ok || !one_shown || !many_shown || !same_text(one_notice.text, "1 new build") || !same_text(many_notice.text, "12 new builds") { os.exit(179i32) }
    let (_, in_view_shown, _) = collection.refresh_outcome_notice(a, 3usize, false, 0i64, false, "build", "builds", zero, zero)
    let (_, quick_shown, _) = collection.refresh_outcome_notice(a, 0usize, false, 1000000000i64, false, "build", "builds", zero, zero)
    let (slow_notice, slow_shown, _) = collection.refresh_outcome_notice(a, 0usize, false, 3000000000i64, false, "build", "builds", zero, zero)
    if in_view_shown || quick_shown || !slow_shown || !same_text(slow_notice.text, "Up to date") { os.exit(180i32) }
    // (D1539) A table toolbar: the title, a chip per active filter whose remove
    // reports its index, Clear filters while any stands, the search and Columns.
    var unfilter_log = UnfilterLog { count: 0usize, index: 0usize }
    let (query_bytes, query_bytes_error) = mem.alloc[u8](a, 16usize)
    if query_bytes_error != ok { os.exit(181i32) }
    var active_filters: [2]str = zero
    active_filters[0usize] = "Failed"
    active_filters[1usize] = "This week"
    var toolbar_step = 0usize
    while toolbar_step < 2usize {
        var bar: collection.TableToolbar = zero
        bar.title = "Builds"
        bar.query = query_bytes
        if toolbar_step == 0usize { bar.filters = active_filters[..] }
        bar.unfilter = widget.Change[usize] { ctx: mem.cast[*void](&unfilter_log), invoke: on_unfilter }
        bar.has_columns = true
        f = mem.arena_from(storage)
        let (toolbar, toolbar_error) = collection.table_toolbar(&f, 9000u64, &theme, bar, 640.0)
        let (toolbar_page, toolbar_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if toolbar_error != ok || toolbar_page_error != ok { os.exit(181i32) }
        toolbar_page[0usize] = toolbar
        if testing.pump(&harness, widget.box(0u64, control.sized_style(640.0, 600.0), toolbar_page[0usize..1usize]), time.Instant { nanos: 95000000000i64 + i64(toolbar_step) }) != ok { os.exit(181i32) }
        if testing.by_text(&harness, "Builds").count == 0usize || testing.by_key(&harness, 9001u64).count == 0usize || testing.by_key(&harness, 9003u64).count == 0usize { os.exit(182i32) }
        if toolbar_step == 0usize {
            let (dropper, has_dropper) = bounds(&harness, &runtime, 9019u64)
            if testing.by_key(&harness, 9002u64).count == 0usize || !has_dropper || testing.by_text(&harness, "This week").count == 0usize { os.exit(183i32) }
            if testing.tap(&harness, dropper.x + dropper.width * 0.5, dropper.y + dropper.height * 0.5) != ok || unfilter_log.count != 1usize || unfilter_log.index != 1usize { os.exit(184i32) }
        }
        if toolbar_step == 1usize && testing.by_key(&harness, 9002u64).count != 0usize { os.exit(185i32) }
        toolbar_step += 1usize
    }
    // (D1540) A virtual grid: its first row 12 below the top; all ten tiles in
    // view, it asks for the next page once (not on the build that found it
    // first, nor again for the same count); Ctrl+plus and Ctrl+minus report the
    // levels either side of 1.
    var grid_log = GridLog { pages: 0usize, zooms: 0usize, level: 0usize }
    var grid_levels: [3]f32 = zero
    grid_levels[0usize] = 112.0
    grid_levels[1usize] = 160.0
    grid_levels[2usize] = 240.0
    var grid_step = 0usize
    while grid_step < 3usize {
        var wall = collection.virtual_grid_options()
        wall.width = 400.0
        wall.height = 500.0
        wall.levels = grid_levels[..]
        wall.level = 1usize
        wall.zoom = widget.Change[usize] { ctx: mem.cast[*void](&grid_log), invoke: on_grid_zoom }
        wall.near_end = widget.Submit { ctx: mem.cast[*void](&grid_log), invoke: on_grid_page }
        f = mem.arena_from(storage)
        let (wall_node, wall_error) = collection.virtual_grid_of(&f, 8000u64, &theme, "Photos", collection.TileSource { ctx: mem.cast[*void](&grid_log), count: wall_count, key: wall_key, tile: wall_tile }, wall)
        let (wall_page, wall_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if wall_error != ok || wall_page_error != ok { os.exit(186i32) }
        wall_page[0usize] = wall_node
        if testing.pump(&harness, widget.box(0u64, control.sized_style(640.0, 600.0), wall_page[0usize..1usize]), time.Instant { nanos: 96000000000i64 + i64(grid_step) }) != ok { os.exit(186i32) }
        if grid_step == 0usize && grid_log.pages != 0usize { os.exit(187i32) }
        if grid_step >= 1usize && grid_log.pages != 1usize { os.exit(187i32) }
        grid_step += 1usize
    }
    let (wall_box, has_wall_box) = bounds(&harness, &runtime, 8000u64)
    let (first_tile, has_first_tile) = bounds(&harness, &runtime, 8100u64)
    if !has_wall_box || !has_first_tile || !(first_tile.y - wall_box.y > 11.5) || !(first_tile.y - wall_box.y < 12.5) { os.exit(188i32) }
    var grid_ctrl: input.Modifiers = zero
    grid_ctrl.control = true
    if widget.focus(&runtime, testing.by_key(&harness, 8100u64).element) != ok || testing.press_key(&harness, 187u32, grid_ctrl) != ok || grid_log.zooms != 1usize || grid_log.level != 2usize { os.exit(189i32) }
    if testing.press_key(&harness, 109u32, grid_ctrl) != ok || grid_log.zooms != 2usize || grid_log.level != 0usize { os.exit(190i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(54i32) }
    try io.print("ui collections6 v2 ok\n")
    ret ok
}
