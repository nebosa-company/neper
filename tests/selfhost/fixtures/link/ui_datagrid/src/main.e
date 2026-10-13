// `e.ui.datagrid` (G006 first to sixth increments, G007 editing) over a 3,000-row `e.data.table` with its view and
// grouping, driven through the UI test harness: the virtual body builds only the visible rows,
// a header tap reports the sort and the application re-sorts, a group row expands on a tap and
// shows its rows, the footer carries the summaries, a tap on a data row reports the storage
// row, and a filter that matches nothing shows the no-data text; a custom cell column asks the
// application for its node, a row role colours a row's text, and the filter row's field reports
// what is typed; and a second grid with bands, the row indicator and the navigator. Every check
// has its own exit code. Fourth: in-place editing (typed commit, invalid text, nulls, dictionary
// growth, read-only) and the saved layout (round trip, unknown lines and columns tolerated).
// Fifth: the preview row and pixel probes (band fill, selected row, a stable frame).
// Sixth: Tab, Shift+Tab and Escape in the editor, column hide / move and the layout's order.
// G007: a boolean flips, a small dictionary edits through a select, a locked cell refuses, old and
// new text reach `value_changed`, a batch holds the events back.
use e.algo.hash as hash
use e.gpu
use e.mem
use e.os
use e.fs
use e.str
use e.time
use e.data.table as table
use e.data.tableview as view
use e.data.tablegroup as grp
use e.gfx.geometry
use e.gfx.image
use e.text.shape
use e.gfx.scene
use e.ui.collection
use e.ui.control
use e.ui.input
use e.gfx.paint
use e.ui.datagrid as dg
use e.ui.gridrules as gr
use e.ui.gridlook as gl
use e.ui.style
use e.ui.testing
use e.ui.widget

const ROWS: usize = 3000usize
const C_NAME: usize = 0usize
const C_RARITY: usize = 1usize
const C_CMC: usize = 2usize
const C_PRICE: usize = 3usize
const C_FOIL: usize = 4usize
const GRID_KEY: u64 = 100u64

type App = struct {
    tbl: table.Table,
    rows_view: view.View,
    grouping: grp.Grouping,
    scratch: mem.Arena,
    store: mem.Arena,
    group_rarity: bool,
    sort_calls: usize,
    sort_spec: usize,
    sort_desc: bool,
    picked: usize,
    pick_calls: usize,
    filter_calls: usize,
    filter_spec: usize,
    filter_text: [32]u8,
    filter_len: usize,
    custom_calls: usize,
    role_calls: usize,
    role_data: usize,
    edit_calls: usize,
    value_calls: usize,
    value_old: [32]u8,
    value_old_len: usize,
    value_new: [32]u8,
    value_new_len: usize,
    locked_row: usize,
    batch_total: usize,
    batch_calls: usize,
    edited_row: usize,
    edited_spec: usize
}

fn mix(x: u64) -> u64 {
    var v = x *% 6364136223846793005u64 +% 1442695040888963407u64
    v = v ^ (v >> 29u64)
    v = v *% 6364136223846793005u64
    ret v ^ (v >> 32u64)
}

fn rarity_of(row: usize) -> str {
    let p = mix(u64(row) + 9u64) % 4u64
    if p == 0u64 { ret "Common" }
    if p == 1u64 { ret "Uncommon" }
    if p == 2u64 { ret "Rare" }
    ret "Mythic"
}

fn name_of(a: *mem.Arena, row: usize) -> str {
    let (b, b_error) = str.builder(a, 24usize)
    if b_error != ok { ret "" }
    var sb = b
    if str.push(&sb, "Card ") != ok || str.push_usize(&sb, (row * 7919usize) % 10007usize) != ok { ret "" }
    ret str.done(&sb)
}

fn load(a: *mem.Arena, app: *App) {
    var spec: [5]table.Spec = zero
    spec[C_NAME] = table.Spec { name: "Name", kind: table.Kind.Dict, heap_bytes: 65536usize, dict_cap: ROWS }
    spec[C_RARITY] = table.Spec { name: "Rarity", kind: table.Kind.Dict, heap_bytes: 256usize, dict_cap: 8usize }
    spec[C_CMC] = table.Spec { name: "CMC", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_PRICE] = table.Spec { name: "Price", kind: table.Kind.F64, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_FOIL] = table.Spec { name: "Foil", kind: table.Kind.Bool, heap_bytes: 0usize, dict_cap: 0usize }
    let (made, made_error) = table.create(a, spec[0..], ROWS)
    if made_error != ok { os.exit(1) }
    app.tbl = made
    table.begin_load(&app.tbl)
    let (scratch_names, scratch_error) = mem.alloc[u8](a, 65536usize)
    if scratch_error != ok { os.exit(2) }
    var names = mem.arena_from(scratch_names)
    var row = 0usize
    while row < ROWS {
        let (got, append_error) = table.append_row(&app.tbl)
        if append_error != ok || got != row { os.exit(3) }
        mem.reset(&names, 0usize)
        if table.set_str(&app.tbl, C_NAME, row, name_of(&names, row)) != ok { os.exit(4) }
        if table.set_str(&app.tbl, C_RARITY, row, rarity_of(row)) != ok { os.exit(5) }
        if row % 7usize != 0usize { table.set_i32(&app.tbl, C_CMC, row, i32(mix(u64(row) + 1u64) % 9u64)) }
        table.set_f64(&app.tbl, C_PRICE, row, f64(mix(u64(row) + 2u64) % 10000u64) / 100.0f64)
        table.set_bool(&app.tbl, C_FOIL, row, mix(u64(row) + 3u64) % 5u64 == 0u64)
        row += 1usize
    }
    table.end_load(&app.tbl)
}

fn summarise(app: *App) -> err {
    var specs: [2]grp.SummarySpec = zero
    specs[0usize] = grp.SummarySpec { column: C_CMC }
    specs[1usize] = grp.SummarySpec { column: C_PRICE }
    mem.reset(&app.store, 0usize)
    ret grp.apply_summaries(&app.grouping, specs[0usize..2usize], &app.store)
}

// The application's side of the grid: sort (and group) from the header state.
fn rebuild(app: *App, spec: usize, descending: bool) -> err {
    var levels: [1]grp.GroupLevel = zero
    var level_count = 0usize
    if app.group_rarity {
        levels[0usize] = grp.GroupLevel { column: C_RARITY, descending: false, fold: true }
        level_count = 1usize
    }
    var keys: [1]view.Key = zero
    var key_count = 0usize
    if spec < 5usize {
        keys[0usize] = view.column_key(spec, descending, true)
        key_count = 1usize
    }
    let marker = mem.mark(&app.scratch)
    let group_error = grp.group_by(&app.grouping, levels[0usize..level_count], keys[0usize..key_count], &app.scratch)
    mem.reset(&app.scratch, marker)
    if group_error != ok { ret group_error }
    ret summarise(app)
}

fn on_sort_changed(ctx: *void, spec: usize, descending: bool) -> err {
    let app = mem.cast[*App](ctx)
    app.sort_calls += 1usize
    app.sort_spec = spec
    app.sort_desc = descending
    ret rebuild(app, spec, descending)
}

fn on_row_picked(ctx: *void, row: usize) -> err {
    let app = mem.cast[*App](ctx)
    app.pick_calls += 1usize
    app.picked = row
    ret ok
}

// The filter row: the typed text becomes a Contains filter on the field's column.
fn on_filter_changed(ctx: *void, spec: usize, text: str) -> err {
    let app = mem.cast[*App](ctx)
    app.filter_calls += 1usize
    app.filter_spec = spec
    var at = 0usize
    while at < text.len && at < app.filter_text.len {
        app.filter_text[at] = text[at]
        at += 1usize
    }
    app.filter_len = at
    if text.len == 0usize {
        view.clear_filter(&app.rows_view)
    } else {
        var nodes: [1]view.Node = zero
        nodes[0usize] = view.leaf_node(app_column_of(spec), view.Op.Contains, view.text_operand(text))
        let marker = mem.mark(&app.scratch)
        let filter_error = view.apply_filter(&app.rows_view, nodes[0..], false, &app.scratch)
        mem.reset(&app.scratch, marker)
        if filter_error != ok { ret filter_error }
    }
    let marker = mem.mark(&app.scratch)
    let refresh_error = grp.refresh(&app.grouping, &app.scratch)
    mem.reset(&app.scratch, marker)
    if refresh_error != ok { ret refresh_error }
    ret summarise(app)
}

fn app_column_of(spec: usize) -> usize { ret spec }

// A Foil cell: a marker box with text, built by the application.
fn on_custom_cell(ctx: *void, a: *mem.Arena, t: *const control.Theme, row: usize, spec: usize, out: *widget.Node) -> err {
    let app = mem.cast[*App](ctx)
    app.custom_calls += 1usize
    var label = "-"
    if table.get_bool(&app.tbl, C_FOIL, row) { label = "FOIL" }
    let (node, node_error) = control.text(a, 0u64, label, t, control.text_options())
    if node_error != ok { ret node_error }
    *out = node
    ret ok
}

// Mythic rows are drawn in the first data colour.
fn on_row_role(ctx: *void, row: usize) -> style.ColorRole {
    let app = mem.cast[*App](ctx)
    app.role_calls += 1usize
    let name = table.get_str(&app.tbl, C_RARITY, row)
    if name.len == 6usize && name[0usize] == 77u8 {
        app.role_data += 1usize
        ret .Data1
    }
    ret .Text
}

// Scrolls so that the storage row is in the first rows of the window.
fn show_row(grid: *dg.Grid, g: *grp.Grouping, row: usize) {
    var at = 0usize
    while at < grp.visible_len(g) {
        if !grp.visible_is_group(g, at) && grp.visible_row(g, at) == row {
            grid.offset = f32(at) * grid.row_height
            ret
        }
        at += 1usize
    }
}

const W: usize = 1000usize

fn px(x: f32, y: f32) -> usize {
    ret (usize(y) * W + usize(x)) * 4usize
}

fn close_to(value: u8, expected: f32) -> bool {
    let e = expected * 255.0
    let v = f32(value)
    ret v - e < 4.0 && e - v < 4.0
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn tap_text(h: *testing.Harness, runtime: *widget.Runtime, text: str) -> bool {
    let (b, found) = widget.bounds_of(runtime, testing.by_text(h, text).element)
    if !found { ret false }
    ret testing.tap(h, b.x + b.width * 0.5, b.y + b.height * 0.5) == ok
}

// old and new text of a written cell
fn on_value_changed(ctx: *void, row: usize, spec: usize, old: str, new: str) -> err {
    let app = mem.cast[*App](ctx)
    app.value_calls += 1usize
    var at = 0usize
    while at < old.len && at < app.value_old.len {
        app.value_old[at] = old[at]
        at += 1usize
    }
    app.value_old_len = at
    at = 0usize
    while at < new.len && at < app.value_new.len {
        app.value_new[at] = new[at]
        at += 1usize
    }
    app.value_new_len = at
    ret ok
}

// a row the application keeps locked
fn on_can_edit(ctx: *void, row: usize, spec: usize) -> bool {
    let app = mem.cast[*App](ctx)
    ret row != app.locked_row
}

fn on_batch_done(ctx: *void, count: usize) -> err {
    let app = mem.cast[*App](ctx)
    app.batch_calls += 1usize
    app.batch_total += count
    ret ok
}

// A cell was written: the order is stale, so the application sorts again.
fn on_cell_edited(ctx: *void, row: usize, spec: usize) -> err {
    let app = mem.cast[*App](ctx)
    app.edit_calls += 1usize
    app.edited_row = row
    app.edited_spec = spec
    ret ok
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

// Frames at a quarter second apart: elements that left the tree finish their exit.
fn settle(h: *testing.Harness, root: widget.Node, start: i64) -> err {
    var step = 0i64
    while step < 6i64 {
        try testing.pump(h, root, time.Instant { nanos: start + step * 250000000i64 })
        step += 1i64
    }
    ret ok
}

// Number of data rows (storage rows) currently built into the tree.
fn built_rows(h: *testing.Harness, grid: *const dg.Grid) -> usize {
    var n = 0usize
    var row = 0usize
    while row < ROWS {
        if testing.by_key(h, dg.row_key(grid, row)).count != 0usize { n += 1usize }
        row += 1usize
    }
    ret n
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(10) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(11) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(12) }
    var renderer = r
    let tokens = style.reference(.Light)
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(13) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 4096usize, max_states: 256usize, state_bytes: 1024usize, state_classes: 8u16, max_depth: 48u16, max_commands: 16384usize })
    if runtime_error != ok { os.exit(14) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (hh, harness_error) = testing.harness(a, &runtime, 1000u32, 600u32, 1.0)
    if harness_error != ok { os.exit(15) }
    var harness = hh

    let (apps, apps_error) = mem.alloc[App](a, 1usize)
    if apps_error != ok { os.exit(16) }
    var seed: App = zero
    apps[0usize] = seed
    let app = &apps[0usize]
    load(a, app)
    let (made_view, view_error) = view.create(a, &app.tbl)
    if view_error != ok { os.exit(17) }
    app.rows_view = made_view
    let (made_group, group_error) = grp.create(a, &app.rows_view, 64usize)
    if group_error != ok { os.exit(18) }
    app.grouping = made_group
    let (scratch_bytes, scratch_bytes_error) = mem.alloc[u8](a, 8388608usize)
    if scratch_bytes_error != ok { os.exit(19) }
    app.scratch = mem.arena_from(scratch_bytes)
    let (store_bytes, store_bytes_error) = mem.alloc[u8](a, 65536usize)
    if store_bytes_error != ok { os.exit(20) }
    app.store = mem.arena_from(store_bytes)
    app.sort_spec = 5usize
    app.locked_row = ROWS
    if rebuild(app, 5usize, false) != ok { os.exit(21) }

    var specs: [5]dg.ColumnSpec = zero
    specs[0usize] = dg.ColumnSpec { title: "Name", width: 220.0, column: C_NAME, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: true, editable: false, choice: false }
    specs[1usize] = dg.ColumnSpec { title: "Rarity", width: 120.0, column: C_RARITY, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: true, editable: false, choice: false }
    specs[2usize] = dg.ColumnSpec { title: "CMC", width: 80.0, column: C_CMC, kind: dg.CellKind.Int, decimals: 0u8, summary: 0, summary_kind: grp.SummaryKind.Avg, filter: false, editable: false, choice: false }
    specs[3usize] = dg.ColumnSpec { title: "Price", width: 120.0, column: C_PRICE, kind: dg.CellKind.Currency, decimals: 2u8, summary: 1, summary_kind: grp.SummaryKind.Sum, filter: false, editable: false, choice: false }
    specs[4usize] = dg.ColumnSpec { title: "Foil", width: 70.0, column: C_FOIL, kind: dg.CellKind.Custom, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: false, choice: false }
    let events = dg.Events { ctx: mem.cast[*void](app), sort_changed: on_sort_changed, row_picked: on_row_picked, filter_changed: on_filter_changed, cell_edited: on_cell_edited, value_changed: on_value_changed, can_edit: on_can_edit, batch_done: on_batch_done, custom_cell: on_custom_cell, row_role: on_row_role }
    let (made_grid, grid_error) = dg.create(a, &app.tbl, &app.grouping, specs[0..], events, GRID_KEY)
    if grid_error != ok { os.exit(22) }
    var grid = made_grid

    let (frame_storage, storage_error) = mem.alloc[u8](a, 8388608usize)
    if storage_error != ok { os.exit(23) }
    var f = mem.arena_from(frame_storage)
    var now = time.Instant { nanos: 1000000000i64 }

    // 1. the first frame: the table, only the visible rows, the footer
    let (root1, build1_error) = dg.build(&f, &grid, &theme, 400.0)
    if build1_error != ok { os.exit(30) }
    if testing.pump(&harness, root1, now) != ok { os.exit(31) }
    if testing.by_key(&harness, GRID_KEY).count != 1usize { os.exit(32) }
    let visible_rows = built_rows(&harness, &grid)
    if visible_rows == 0usize || visible_rows > 30usize { os.exit(33) }
    // storage row of the first displayed entry: row 0 (no sort, no groups)
    if testing.by_key(&harness, dg.row_key(&grid, grp.visible_row(&app.grouping, 0usize))).count == 0usize { os.exit(34) }
    if testing.by_key(&harness, dg.footer_key(&grid)).count == 0usize { os.exit(35) }
    // the footer sum of the price column, summed here independently
    var sum = 0.0f64
    var row = 0usize
    while row < ROWS {
        sum += table.get_f64(&app.tbl, C_PRICE, row)
        row += 1usize
    }
    let (sb_made, sb_error) = str.builder(&f, 40usize)
    if sb_error != ok { os.exit(36) }
    var sb = sb_made
    if str.push(&sb, "$") != ok || str.push_f64_fixed(&sb, sum, 2u8) != ok { os.exit(37) }
    if testing.by_text(&harness, str.done(&sb)).count == 0usize { os.exit(38) }

    // 2. a header tap: the grid reports the sort, the application re-sorts, the next frame follows
    let (price_title, price_found) = widget.bounds_of(&runtime, testing.by_text(&harness, "Price").element)
    if !price_found { os.exit(40) }
    if testing.tap(&harness, price_title.x + price_title.width * 0.5, price_title.y + price_title.height * 0.5) != ok { os.exit(41) }
    if app.sort_calls != 1usize || app.sort_spec != 3usize || app.sort_desc { os.exit(42) }
    mem.reset(&f, 0usize)
    now = time.Instant { nanos: 2000000000i64 }
    let (root2, build2_error) = dg.build(&f, &grid, &theme, 400.0)
    if build2_error != ok { os.exit(43) }
    if testing.pump(&harness, root2, now) != ok { os.exit(44) }
    // the cheapest price is first: its row is built, and the old first row is not (unless it ties)
    var cheapest = 0usize
    row = 1usize
    while row < ROWS {
        if table.get_f64(&app.tbl, C_PRICE, row) < table.get_f64(&app.tbl, C_PRICE, cheapest) { cheapest = row }
        row += 1usize
    }
    if grp.visible_row(&app.grouping, 0usize) != cheapest && table.get_f64(&app.tbl, C_PRICE, grp.visible_row(&app.grouping, 0usize)) != table.get_f64(&app.tbl, C_PRICE, cheapest) { os.exit(45) }
    if testing.by_key(&harness, dg.row_key(&grid, grp.visible_row(&app.grouping, 0usize))).count == 0usize { os.exit(46) }
    // a second tap on the same header reverses it
    let (price_again, price_again_found) = widget.bounds_of(&runtime, testing.by_text(&harness, "Price").element)
    if !price_again_found { os.exit(47) }
    if testing.tap(&harness, price_again.x + price_again.width * 0.5, price_again.y + price_again.height * 0.5) != ok { os.exit(48) }
    if app.sort_calls != 2usize || !app.sort_desc { os.exit(49) }

    // 3. a tap on a data row reports its storage row
    mem.reset(&f, 0usize)
    now = time.Instant { nanos: 3000000000i64 }
    let (root3, build3_error) = dg.build(&f, &grid, &theme, 400.0)
    if build3_error != ok { os.exit(50) }
    if testing.pump(&harness, root3, now) != ok { os.exit(51) }
    let second_row = grp.visible_row(&app.grouping, 1usize)
    if !tap_key(&harness, &runtime, dg.row_key(&grid, second_row)) { os.exit(52) }
    if app.pick_calls != 1usize || app.picked != second_row || !grid.has_selection || grid.selected_row != second_row { os.exit(53) }

    // 4. grouped by rarity: group rows, collapsed; a tap expands one and its rows follow
    app.group_rarity = true
    if rebuild(app, 5usize, false) != ok { os.exit(60) }
    dg.show_sort(&grid, 5usize, false)
    mem.reset(&f, 0usize)
    now = time.Instant { nanos: 4000000000i64 }
    let (root4, build4_error) = dg.build(&f, &grid, &theme, 400.0)
    if build4_error != ok { os.exit(61) }
    if settle(&harness, root4, 4000000000i64) != ok { os.exit(62) }
    if grp.group_len(&app.grouping) != 4usize || grp.visible_len(&app.grouping) != 4usize { os.exit(63) }
    var g = 0usize
    while g < 4usize {
        if testing.by_key(&harness, dg.group_key(&grid, g)).count == 0usize { os.exit(64) }
        g += 1usize
    }
    if built_rows(&harness, &grid) != 0usize { os.exit(65) }
    if !tap_key(&harness, &runtime, dg.group_key(&grid, 1usize)) { os.exit(66) }
    if !grp.is_expanded(&app.grouping, 1usize) || grp.visible_len(&app.grouping) != 4usize + grp.group_count(&app.grouping, 1usize) { os.exit(67) }
    mem.reset(&f, 0usize)
    now = time.Instant { nanos: 5000000000i64 }
    let (root5, build5_error) = dg.build(&f, &grid, &theme, 400.0)
    if build5_error != ok { os.exit(68) }
    if settle(&harness, root5, 5000000000i64) != ok { os.exit(69) }
    let first_in_group = grp.row_at(&app.grouping, grp.group_first(&app.grouping, 1usize))
    if testing.by_key(&harness, dg.row_key(&grid, first_in_group)).count == 0usize { os.exit(70) }
    // a tap on the group row collapses it again
    if !tap_key(&harness, &runtime, dg.group_key(&grid, 1usize)) { os.exit(71) }
    if grp.is_expanded(&app.grouping, 1usize) || grp.visible_len(&app.grouping) != 4usize { os.exit(72) }

    // 4b. custom cells and the row role: a Foil cell is built by the application; a Mythic row's name
    // is drawn in the first data colour, another row's in the text colour
    app.group_rarity = false
    if rebuild(app, 5usize, false) != ok { os.exit(90) }
    mem.reset(&f, 0usize)
    let (root7, build7_error) = dg.build(&f, &grid, &theme, 400.0)
    if build7_error != ok { os.exit(91) }
    if settle(&harness, root7, 7000000000i64) != ok { os.exit(92) }
    if app.custom_calls == 0usize { os.exit(93) }
    if testing.by_text(&harness, "FOIL").count == 0usize && testing.by_text(&harness, "-").count == 0usize { os.exit(94) }
    // the role is asked once per built data row, and Mythic rows get the data colour
    if app.role_calls == 0usize || app.role_data == 0usize || app.role_data >= app.role_calls { os.exit(95) }
    var expected_data = 0usize
    var scan = 0usize
    while scan < 40usize {
        let rarity = table.get_str(&app.tbl, C_RARITY, scan)
        if rarity.len == 6usize && rarity[0usize] == 77u8 { expected_data += 1usize }
        scan += 1usize
    }
    if expected_data == 0usize { os.exit(96) }

    // 4c. the filter row: a field under each filterable column; typing reports the text and the
    // application filters
    dg.show_filter_row(&grid, true)
    mem.reset(&f, 0usize)
    let (root8, build8_error) = dg.build(&f, &grid, &theme, 400.0)
    if build8_error != ok { os.exit(100) }
    if settle(&harness, root8, 8000000000i64) != ok { os.exit(101) }
    if testing.by_key(&harness, GRID_KEY + 2048u64 + 1u64).count == 0usize { os.exit(102) }
    if testing.by_key(&harness, GRID_KEY + 2048u64 + 2u64).count != 0usize { os.exit(103) }
    if !tap_key(&harness, &runtime, GRID_KEY + 2048u64 + 1u64) { os.exit(104) }
    if testing.type_text(&harness, "rare") != ok { os.exit(105) }
    if app.filter_calls == 0usize || app.filter_spec != 1usize || app.filter_len != 4usize { os.exit(106) }
    var want = 0usize
    row = 0usize
    while row < ROWS {
        let level_name = table.get_str(&app.tbl, C_RARITY, row)
        if level_name.len == 4usize && (level_name[0usize] == 82u8 || level_name[0usize] == 114u8) && level_name[1usize] == 97u8 { want += 1usize }
        row += 1usize
    }
    if want == 0usize || grp.visible_len(&app.grouping) != want { os.exit(107) }
    if dg.filter_value(&grid, 1usize).len != 4usize { os.exit(108) }
    // clearing the field (the application's filter off) restores every row
    view.clear_filter(&app.rows_view)
    if grp.refresh(&app.grouping, &app.scratch) != ok { os.exit(109) }
    dg.show_filter_row(&grid, false)

    // 5. a filter that matches nothing: the no-data text, no table
    var nodes: [1]view.Node = zero
    nodes[0usize] = view.leaf_node(C_RARITY, view.Op.Eq, view.text_operand("nothing"))
    if view.apply_filter(&app.rows_view, nodes[0..], false, &app.scratch) != ok { os.exit(80) }
    if grp.refresh(&app.grouping, &app.scratch) != ok { os.exit(81) }
    mem.reset(&f, 0usize)
    now = time.Instant { nanos: 6000000000i64 }
    let (root6, build6_error) = dg.build(&f, &grid, &theme, 400.0)
    if build6_error != ok { os.exit(82) }
    if settle(&harness, root6, 6000000000i64) != ok { os.exit(83) }
    if testing.by_text(&harness, "No data to display").count == 0usize { os.exit(84) }
    if testing.by_key(&harness, dg.footer_key(&grid)).count != 0usize { os.exit(85) }
    // 6. a second grid: bands over the columns, the row indicator and the navigator
    view.clear_filter(&app.rows_view)
    app.group_rarity = false
    if rebuild(app, 5usize, false) != ok { os.exit(110) }
    var specs2: [4]dg.ColumnSpec = zero
    specs2[0usize] = dg.ColumnSpec { title: "", width: 30.0, column: C_NAME, kind: dg.CellKind.Indicator, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: false, choice: false }
    specs2[1usize] = dg.ColumnSpec { title: "Name", width: 200.0, column: C_NAME, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: false, choice: false }
    specs2[2usize] = dg.ColumnSpec { title: "Rarity", width: 120.0, column: C_RARITY, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: true, choice: false }
    specs2[3usize] = dg.ColumnSpec { title: "Price", width: 120.0, column: C_PRICE, kind: dg.CellKind.Currency, decimals: 2u8, summary: 1, summary_kind: grp.SummaryKind.Sum, filter: false, editable: true, choice: false }
    let (made2, grid2_error) = dg.create(a, &app.tbl, &app.grouping, specs2[0..], events, 9000u64)
    if grid2_error != ok { os.exit(111) }
    var grid2 = made2
    var bands: [2]dg.Band = zero
    bands[0usize] = dg.Band { title: "Card", first: 1usize, count: 2usize }
    bands[1usize] = dg.Band { title: "Money", first: 3usize, count: 1usize }
    dg.set_bands(&grid2, bands[0..])
    dg.show_navigator(&grid2, true)
    mem.reset(&f, 0usize)
    let (root9, build9_error) = dg.build(&f, &grid2, &theme, 400.0)
    if build9_error != ok { os.exit(112) }
    if settle(&harness, root9, 9000000000i64) != ok { os.exit(113) }
    if testing.by_key(&harness, dg.band_key(&grid2)).count == 0usize { os.exit(114) }
    if testing.by_text(&harness, "Card").count == 0usize || testing.by_text(&harness, "Money").count == 0usize { os.exit(115) }
    if testing.by_text(&harness, "Row - of 3000").count == 0usize { os.exit(116) }
    if testing.by_key(&harness, dg.navigator_key(&grid2)).count == 0usize { os.exit(117) }
    // Next from nothing goes to the first data row
    let calls_before = app.pick_calls
    if !tap_text(&harness, &runtime, "Next") { os.exit(118) }
    if app.pick_calls != calls_before + 1usize || app.picked != grp.visible_row(&app.grouping, 0usize) { os.exit(119) }
    mem.reset(&f, 0usize)
    let (root10, build10_error) = dg.build(&f, &grid2, &theme, 400.0)
    if build10_error != ok { os.exit(120) }
    if settle(&harness, root10, 10000000000i64) != ok { os.exit(121) }
    if testing.by_text(&harness, "Row 1 of 3000").count == 0usize { os.exit(122) }
    if !grid2.has_selection { os.exit(123) }
    if !tap_text(&harness, &runtime, "Next") { os.exit(124) }
    if app.picked != grp.visible_row(&app.grouping, 1usize) { os.exit(125) }
    if !tap_text(&harness, &runtime, "Last") { os.exit(126) }
    if app.picked != grp.visible_row(&app.grouping, ROWS - 1usize) || grid2.position != ROWS - 1usize { os.exit(127) }
    if !tap_text(&harness, &runtime, "Prev") { os.exit(128) }
    if app.picked != grp.visible_row(&app.grouping, ROWS - 2usize) { os.exit(129) }
    if !tap_text(&harness, &runtime, "First") { os.exit(130) }
    if app.picked != grp.visible_row(&app.grouping, 0usize) { os.exit(131) }
    // Prev from the first row has nowhere to go: nothing is reported
    let calls_at_first = app.pick_calls
    if !tap_text(&harness, &runtime, "Prev") { os.exit(132) }
    if app.pick_calls != calls_at_first { os.exit(133) }
    // the scroll offset follows the current row (row 2999 is far below the first window)
    if dg.navigate(&grid2, dg.Nav.Last) != ok { os.exit(134) }
    if grid2.offset < f32(ROWS - 10usize) * grid2.row_height { os.exit(135) }
    // 7. in-place editing of the second grid's Rarity (spec 2) and Price (spec 3) columns
    app.group_rarity = false
    if rebuild(app, 5usize, false) != ok { os.exit(140) }
    dg.show_navigator(&grid2, false)
    dg.set_bands(&grid2, bands[0usize..0usize])
    grid2.offset = 0.0
    var edit_clock = 11000000000i64
    // a first tap selects the row, a second tap on the same current row starts editing its first
    // editable column
    dg.clear_selection(&grid2)
    show_row(&grid2, &app.grouping, 11usize)
    mem.reset(&f, 0usize)
    let (root_t, build_t_error) = dg.build(&f, &grid2, &theme, 400.0)
    if build_t_error != ok { os.exit(220) }
    if settle(&harness, root_t, edit_clock) != ok { os.exit(221) }
    edit_clock += 2000000000i64
    if !tap_key(&harness, &runtime, dg.row_key(&grid2, 11usize)) { os.exit(222) }
    if grid2.editing || !grid2.has_selection || grid2.selected_row != 11usize { os.exit(223) }
    if !tap_key(&harness, &runtime, dg.row_key(&grid2, 11usize)) { os.exit(224) }
    if !grid2.editing || grid2.edit_row != 11usize || grid2.edit_spec != 2usize { os.exit(225) }
    dg.cancel_edit(&grid2)
    // a read-only grid and a column that is not editable refuse
    if dg.begin_edit(&grid2, 5usize, 1usize) != dg.NotEditable { os.exit(141) }
    grid2.read_only = true
    if dg.begin_edit(&grid2, 5usize, 3usize) != dg.NotEditable { os.exit(142) }
    grid2.read_only = false
    // begin: the editor holds the cell's text
    let old_price = table.get_f64(&app.tbl, C_PRICE, 5usize)
    let (pb, pb_error) = str.builder(&f, 32usize)
    if pb_error != ok { os.exit(143) }
    var pbuilder = pb
    if str.push_f64_fixed(&pbuilder, old_price, 2u8) != ok { os.exit(144) }
    let price_text = str.done(&pbuilder)
    if dg.begin_edit(&grid2, 5usize, 3usize) != ok || !grid2.editing { os.exit(145) }
    if grid2.edit_len != price_text.len { os.exit(146) }
    var same = true
    var c = 0usize
    while c < price_text.len {
        if grid2.edit_text[c] != price_text[c] { same = false }
        c += 1usize
    }
    if !same { os.exit(147) }
    // the editor is a field in the cell; typing then Enter commits the parsed value
    show_row(&grid2, &app.grouping, 5usize)
    mem.reset(&f, 0usize)
    let (root11, build11_error) = dg.build(&f, &grid2, &theme, 400.0)
    if build11_error != ok { os.exit(148) }
    if settle(&harness, root11, edit_clock) != ok { os.exit(149) }
    edit_clock += 2000000000i64
    if testing.by_key(&harness, 9000u64 + dg.EDIT_KEY).count == 0usize { os.exit(150) }
    if !tap_key(&harness, &runtime, 9000u64 + dg.EDIT_KEY) { os.exit(151) }
    if testing.type_text(&harness, "1") != ok { os.exit(152) }
    if grid2.edit_len != price_text.len + 1usize { os.exit(153) }
    // the text the editor holds now (the caret decides where the typed digit went)
    let (typed_value, typed_error) = str.parse_f64(grid2.edit_text[0usize..grid2.edit_len])
    if typed_error != ok { os.exit(156) }
    let edits_before = app.edit_calls
    if testing.press_key(&harness, 13u32, zero) != ok { os.exit(154) }
    if app.edit_calls != edits_before + 1usize || app.edited_row != 5usize || app.edited_spec != 3usize || grid2.editing { os.exit(155) }
    if table.get_f64(&app.tbl, C_PRICE, 5usize) != typed_value || typed_value == old_price { os.exit(158) }
    // text that does not parse keeps the editor open and marked invalid; nothing is written
    if dg.begin_edit(&grid2, 5usize, 3usize) != ok { os.exit(159) }
    show_row(&grid2, &app.grouping, 5usize)
    mem.reset(&f, 0usize)
    let (root12, build12_error) = dg.build(&f, &grid2, &theme, 400.0)
    if build12_error != ok { os.exit(160) }
    if settle(&harness, root12, edit_clock) != ok { os.exit(161) }
    edit_clock += 2000000000i64
    if !tap_key(&harness, &runtime, 9000u64 + dg.EDIT_KEY) { os.exit(162) }
    if testing.type_text(&harness, "x") != ok { os.exit(163) }
    let kept = table.get_f64(&app.tbl, C_PRICE, 5usize)
    let calls_kept = app.edit_calls
    if testing.press_key(&harness, 13u32, zero) != ok { os.exit(164) }
    if app.edit_calls != calls_kept || !grid2.editing || !grid2.edit_invalid || table.get_f64(&app.tbl, C_PRICE, 5usize) != kept { os.exit(165) }
    dg.cancel_edit(&grid2)
    if grid2.editing { os.exit(166) }
    // a dictionary cell: a new entry appears
    let entries_before = table.dict_len(&app.tbl, C_RARITY)
    if dg.begin_edit(&grid2, 7usize, 2usize) != ok { os.exit(167) }
    show_row(&grid2, &app.grouping, 7usize)
    mem.reset(&f, 0usize)
    let (root13, build13_error) = dg.build(&f, &grid2, &theme, 400.0)
    if build13_error != ok { os.exit(168) }
    if settle(&harness, root13, edit_clock) != ok { os.exit(169) }
    edit_clock += 2000000000i64
    if !tap_key(&harness, &runtime, 9000u64 + dg.EDIT_KEY) { os.exit(170) }
    if testing.type_text(&harness, "Z") != ok || testing.press_key(&harness, 13u32, zero) != ok { os.exit(171) }
    let new_rarity = table.get_str(&app.tbl, C_RARITY, 7usize)
    var has_z = false
    var zi = 0usize
    while zi < new_rarity.len {
        if new_rarity[zi] == 90u8 { has_z = true }
        zi += 1usize
    }
    if new_rarity.len < 2usize || !has_z || table.dict_len(&app.tbl, C_RARITY) != entries_before + 1usize { os.exit(172) }
    // an emptied editor is a null cell
    if dg.begin_edit(&grid2, 9usize, 3usize) != ok { os.exit(173) }
    show_row(&grid2, &app.grouping, 9usize)
    mem.reset(&f, 0usize)
    let (root14, build14_error) = dg.build(&f, &grid2, &theme, 400.0)
    if build14_error != ok { os.exit(174) }
    if settle(&harness, root14, edit_clock) != ok { os.exit(175) }
    edit_clock += 2000000000i64
    if !tap_key(&harness, &runtime, 9000u64 + dg.EDIT_KEY) { os.exit(176) }
    // Backspace deletes before the caret and Delete after it: both, wherever the caret is
    var back = grid2.edit_len
    while back > 0usize {
        if testing.press_key(&harness, 8u32, zero) != ok { os.exit(177) }
        if testing.press_key(&harness, 46u32, zero) != ok { os.exit(177) }
        back -= 1usize
    }
    if testing.press_key(&harness, 13u32, zero) != ok { os.exit(178) }
    if !table.is_null(&app.tbl, C_PRICE, 9usize) || grid2.editing { os.exit(179) }

    // 8. the layout: widths, sort indicator, rows, filter texts round trip; foreign text loads
    dg.resize_column(&grid2, 1usize, 333.0)
    dg.resize_column(&grid2, 3usize, 5.0)
    if dg.column_width(&grid2, 3usize) != 24.0 { os.exit(180) }
    dg.show_sort(&grid2, 3usize, true)
    dg.show_filter_row(&grid2, true)
    dg.show_navigator(&grid2, true)
    let (saved, save_error) = dg.save_layout(&f, &grid2)
    if save_error != ok || saved.len == 0usize { os.exit(181) }
    let (made3, grid3_error) = dg.create(a, &app.tbl, &app.grouping, specs2[0..], events, 9100u64)
    if grid3_error != ok { os.exit(182) }
    var grid3 = made3
    if dg.load_layout(&grid3, saved) != ok { os.exit(183) }
    if dg.column_width(&grid3, 1usize) != 333.0 || dg.column_width(&grid3, 3usize) != 24.0 || dg.column_width(&grid3, 0usize) != dg.column_width(&grid2, 0usize) { os.exit(184) }
    if grid3.sort_column != 3usize || !grid3.descending || !grid3.filter_visible || !grid3.navigator_visible { os.exit(185) }
    // foreign text: an unknown line, more widths than columns, a sort out of range, a filter text
    let foreign = "datagrid 1\nbogus 1 2 3\nwidths 111 112 113 114 115 116 117\nsort 99 asc\nfilter 2 ab\nfilterrow 1\n"
    let (made4, grid4_error) = dg.create(a, &app.tbl, &app.grouping, specs2[0..], events, 9200u64)
    if grid4_error != ok { os.exit(186) }
    var grid4 = made4
    if dg.load_layout(&grid4, foreign) != ok { os.exit(187) }
    if dg.column_width(&grid4, 0usize) != 111.0 || dg.column_width(&grid4, 3usize) != 114.0 || grid4.sort_column != 4usize || !grid4.filter_visible { os.exit(188) }
    if dg.filter_value(&grid4, 2usize).len != 2usize { os.exit(189) }
    // fewer widths than columns: the rest keep theirs; no version line: refused
    let (made5, grid5_error) = dg.create(a, &app.tbl, &app.grouping, specs2[0..], events, 9300u64)
    if grid5_error != ok { os.exit(190) }
    var grid5 = made5
    if dg.load_layout(&grid5, "datagrid 1\nwidths 90\n") != ok || dg.column_width(&grid5, 0usize) != 90.0 || dg.column_width(&grid5, 1usize) != 200.0 { os.exit(191) }
    if dg.load_layout(&grid5, "widths 10 20\n") != dg.BadLayout { os.exit(192) }
    // (the layout test left the Price column at its 24 px minimum: give it room again)
    dg.resize_column(&grid2, 3usize, 120.0)
    // 9. the preview row: a disclosure on each data row opens, under it, the row's text
    app.group_rarity = false
    if rebuild(app, 5usize, false) != ok { os.exit(230) }
    dg.show_filter_row(&grid2, false)
    dg.show_navigator(&grid2, false)
    grid2.offset = 0.0
    dg.clear_selection(&grid2)
    dg.show_preview(&grid2, 1usize)
    var preview_clock = 20000000000i64
    let first_row = grp.visible_row(&app.grouping, 0usize)
    mem.reset(&f, 0usize)
    let (root15, build15_error) = dg.build(&f, &grid2, &theme, 400.0)
    if build15_error != ok { os.exit(231) }
    if settle(&harness, root15, preview_clock) != ok { os.exit(232) }
    preview_clock += 2000000000i64
    let first_name = table.get_str(&app.tbl, C_NAME, first_row)
    let before_open = testing.by_text(&harness, first_name).count
    if before_open == 0usize { os.exit(233) }
    if !tap_key(&harness, &runtime, dg.row_key(&grid2, first_row) ^ hash.fnv1a64("row-disclose")) { os.exit(234) }
    if grid2.preview_count != 1usize || !dg.preview_is_open(&grid2, dg.row_key(&grid2, first_row)) { os.exit(235) }
    mem.reset(&f, 0usize)
    let (root16, build16_error) = dg.build(&f, &grid2, &theme, 400.0)
    if build16_error != ok { os.exit(236) }
    if settle(&harness, root16, preview_clock) != ok { os.exit(237) }
    preview_clock += 2000000000i64
    if testing.by_text(&harness, first_name).count <= before_open { os.exit(238) }
    // closing it takes the text away again
    if !tap_key(&harness, &runtime, dg.row_key(&grid2, first_row) ^ hash.fnv1a64("row-disclose")) { os.exit(239) }
    if grid2.preview_count != 0usize { os.exit(240) }
    dg.hide_preview(&grid2)

    // 10. pixels: the band's fill and the selected row's fill are the theme's colours, and the
    // same frame renders to the same pixels
    dg.set_bands(&grid2, bands[0usize..2usize])
    grid2.has_selection = true
    grid2.selected_row = grp.visible_row(&app.grouping, 2usize)
    mem.reset(&f, 0usize)
    let (root17, build17_error) = dg.build(&f, &grid2, &theme, 400.0)
    if build17_error != ok { os.exit(241) }
    if settle(&harness, root17, preview_clock) != ok { os.exit(242) }
    let (shot_a, shot_a_error) = testing.snapshot(&harness, a)
    if shot_a_error != ok { os.exit(243) }
    let (band_bounds, has_band) = bounds(&harness, &runtime, dg.band_key(&grid2))
    let (row_bounds, has_row) = bounds(&harness, &runtime, dg.row_key(&grid2, grid2.selected_row))
    if !has_band || !has_row { os.exit(244) }
    // the "Card" band covers Name and Rarity: 30 in (the indicator's column) and 100 across
    if !is_color(shot_a, px(band_bounds.x + 130.0, band_bounds.y + 6.0), style.color(&tokens, .SurfaceVariant)) { os.exit(245) }
    // the selected row: secondary-container, where no text stands (right of the price column)
    if !is_color(shot_a, px(row_bounds.x + 520.0, row_bounds.y + row_bounds.height * 0.5), style.color(&tokens, .SecondaryContainer)) { os.exit(246) }
    // a row that is not selected is not
    let (other_bounds, has_other) = bounds(&harness, &runtime, dg.row_key(&grid2, grp.visible_row(&app.grouping, 4usize)))
    if !has_other || is_color(shot_a, px(other_bounds.x + 520.0, other_bounds.y + other_bounds.height * 0.5), style.color(&tokens, .SecondaryContainer)) { os.exit(247) }
    // the same tree again: the same pixels
    if testing.pump(&harness, root17, time.Instant { nanos: preview_clock + 9000000000i64 }) != ok { os.exit(248) }
    let (shot_b, shot_b_error) = testing.snapshot(&harness, a)
    if shot_b_error != ok { os.exit(249) }
    var differing = 0usize
    var pix = 0usize
    while pix < W * 600usize * 4usize {
        if shot_a.pixels[pix] != shot_b.pixels[pix] { differing += 1usize }
        pix += 1usize
    }
    if differing != 0usize { os.exit(250) }
    // 11. Tab and Shift+Tab move the editor; Escape cancels it
    dg.hide_preview(&grid2)
    dg.set_bands(&grid2, bands[0usize..0usize])
    dg.show_filter_row(&grid2, false)
    dg.resize_column(&grid2, 0usize, 30.0)
    dg.resize_column(&grid2, 1usize, 200.0)
    dg.resize_column(&grid2, 3usize, 120.0)
    dg.clear_selection(&grid2)
    var tab_clock = 30000000000i64
    let tab_row = grp.visible_row(&app.grouping, 6usize)
    let next_row = grp.visible_row(&app.grouping, 7usize)
    show_row(&grid2, &app.grouping, tab_row)
    if dg.begin_edit(&grid2, tab_row, 2usize) != ok { os.exit(260) }
    mem.reset(&f, 0usize)
    let (root18, build18_error) = dg.build(&f, &grid2, &theme, 400.0)
    if build18_error != ok { os.exit(261) }
    if settle(&harness, root18, tab_clock) != ok { os.exit(262) }
    tab_clock += 2000000000i64
    if !tap_key(&harness, &runtime, 9000u64 + dg.EDIT_KEY) { os.exit(263) }
    let tab_edits = app.edit_calls
    if testing.press_key(&harness, 9u32, zero) != ok { os.exit(264) }
    // the Rarity edit committed (an event) and the Price cell of the same row is being edited
    if app.edit_calls != tab_edits + 1usize || !grid2.editing || grid2.edit_row != tab_row || grid2.edit_spec != 3usize { os.exit(265) }
    mem.reset(&f, 0usize)
    let (root19, build19_error) = dg.build(&f, &grid2, &theme, 400.0)
    if build19_error != ok { os.exit(266) }
    if settle(&harness, root19, tab_clock) != ok { os.exit(267) }
    tab_clock += 2000000000i64
    if !tap_key(&harness, &runtime, 9000u64 + dg.EDIT_KEY) { os.exit(268) }
    // past the last editable cell: the first editable cell of the next row (the order may have
    // changed under the application's re-sort, so the row is looked up by what the grid says)
    if testing.press_key(&harness, 9u32, zero) != ok { os.exit(269) }
    if !grid2.editing || grid2.edit_spec != 2usize || grid2.edit_row == tab_row { os.exit(270) }
    let moved_to = grid2.edit_row
    // Shift+Tab goes back: the previous row's last editable cell
    mem.reset(&f, 0usize)
    show_row(&grid2, &app.grouping, moved_to)
    let (root20, build20_error) = dg.build(&f, &grid2, &theme, 400.0)
    if build20_error != ok { os.exit(271) }
    if settle(&harness, root20, tab_clock) != ok { os.exit(272) }
    tab_clock += 2000000000i64
    if !tap_key(&harness, &runtime, 9000u64 + dg.EDIT_KEY) { os.exit(273) }
    var shift_tab: input.Modifiers = zero
    shift_tab.shift = true
    if testing.press_key(&harness, 9u32, shift_tab) != ok { os.exit(274) }
    if !grid2.editing || grid2.edit_spec != 3usize || grid2.edit_row == moved_to { os.exit(275) }
    // Escape cancels
    mem.reset(&f, 0usize)
    show_row(&grid2, &app.grouping, grid2.edit_row)
    let (root21, build21_error) = dg.build(&f, &grid2, &theme, 400.0)
    if build21_error != ok { os.exit(276) }
    if settle(&harness, root21, tab_clock) != ok { os.exit(277) }
    tab_clock += 2000000000i64
    if !tap_key(&harness, &runtime, 9000u64 + dg.EDIT_KEY) { os.exit(278) }
    if testing.press_key(&harness, 27u32, zero) != ok { os.exit(279) }
    if grid2.editing { os.exit(280) }
    if next_row == tab_row { os.exit(281) }

    // 12. columns: hide one, move one; events and layout speak of the list given to create
    // Rarity and Price ask for filter fields (the specs array is the grid's list)
    specs2[2usize].filter = true
    specs2[3usize].filter = true
    dg.show_filter_row(&grid2, false)
    dg.set_hidden(&grid2, 2usize, true)
    if grid2.specs.len != 3usize || !dg.is_hidden(&grid2, 2usize) { os.exit(282) }
    let (price_at, price_shown) = dg.display_of(&grid2, 3usize)
    if !price_shown || price_at != 2usize { os.exit(283) }
    let (rarity_at, rarity_shown) = dg.display_of(&grid2, 2usize)
    if rarity_shown || rarity_at != 0usize { os.exit(284) }
    grid2.offset = 0.0
    mem.reset(&f, 0usize)
    let (root22, build22_error) = dg.build(&f, &grid2, &theme, 400.0)
    if build22_error != ok { os.exit(285) }
    if settle(&harness, root22, tab_clock) != ok { os.exit(286) }
    tab_clock += 2000000000i64
    if testing.by_text(&harness, "Rarity").count != 0usize || testing.by_text(&harness, "Price").count == 0usize { os.exit(287) }
    // a header tap on Price reports spec 3, not its display position 2
    let sorts_before = app.sort_calls
    if !tap_text(&harness, &runtime, "Price") { os.exit(288) }
    if app.sort_calls != sorts_before + 1usize || app.sort_spec != 3usize { os.exit(289) }
    // the filter field of a column keeps its key from the list, hidden or not
    dg.show_filter_row(&grid2, true)
    mem.reset(&f, 0usize)
    let (root23, build23_error) = dg.build(&f, &grid2, &theme, 400.0)
    if build23_error != ok { os.exit(302) }
    if settle(&harness, root23, tab_clock) != ok { os.exit(303) }
    tab_clock += 2000000000i64
    if testing.by_key(&harness, 9000u64 + dg.FILTER_KEY + 3u64).count == 0usize { os.exit(290) }
    if testing.by_key(&harness, 9000u64 + dg.FILTER_KEY + 2u64).count != 0usize { os.exit(291) }
    // move Price to the front
    dg.move_column(&grid2, 3usize, 0usize)
    let (price_first, price_first_shown) = dg.display_of(&grid2, 3usize)
    if !price_first_shown || price_first != 0usize { os.exit(292) }
    let (name_at, name_shown) = dg.display_of(&grid2, 1usize)
    if !name_shown || name_at != 2usize { os.exit(293) }
    // the layout carries the order and the hidden columns; a fresh grid takes them
    let (saved2, save2_error) = dg.save_layout(&f, &grid2)
    if save2_error != ok { os.exit(294) }
    let (made6, grid6_error) = dg.create(a, &app.tbl, &app.grouping, specs2[0..], events, 9400u64)
    if grid6_error != ok { os.exit(295) }
    var grid6 = made6
    if dg.load_layout(&grid6, saved2) != ok { os.exit(296) }
    let (price_6, price_6_shown) = dg.display_of(&grid6, 3usize)
    if !dg.is_hidden(&grid6, 2usize) || !price_6_shown || price_6 != 0usize || grid6.specs.len != 3usize { os.exit(297) }
    // an order naming columns the grid does not have, and a hidden list with an unknown one
    let (made7, grid7_error) = dg.create(a, &app.tbl, &app.grouping, specs2[0..], events, 9500u64)
    if grid7_error != ok { os.exit(298) }
    var grid7 = made7
    if dg.load_layout(&grid7, "datagrid 1\norder 3 9 3 1\nhidden 7 0\n") != ok { os.exit(299) }
    let (p7, p7_shown) = dg.display_of(&grid7, 3usize)
    if !p7_shown || p7 != 0usize || !dg.is_hidden(&grid7, 0usize) || grid7.specs.len != 3usize { os.exit(300) }
    // a column shown again returns at its place in the order
    dg.set_hidden(&grid2, 2usize, false)
    if grid2.specs.len != 4usize { os.exit(301) }
    // 13. editors by kind, the lock, old and new text, and batches
    dg.set_hidden(&grid2, 2usize, false)
    dg.show_filter_row(&grid2, false)
    dg.resize_column(&grid2, 0usize, 30.0)
    grid2.offset = 0.0
    // a boolean flips with no editor
    var flag_specs: [2]dg.ColumnSpec = zero
    flag_specs[0usize] = dg.ColumnSpec { title: "Name", width: 200.0, column: C_NAME, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: false, choice: false }
    flag_specs[1usize] = dg.ColumnSpec { title: "Foil", width: 120.0, column: C_FOIL, kind: dg.CellKind.Bool, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: true, choice: false }
    let (made8, grid8_error) = dg.create(a, &app.tbl, &app.grouping, flag_specs[0..], events, 9600u64)
    if grid8_error != ok { os.exit(310) }
    var grid8 = made8
    let foil_before = table.get_bool(&app.tbl, C_FOIL, 20usize)
    let values_before = app.value_calls
    let edits_at_flip = app.edit_calls
    if dg.begin_edit(&grid8, 20usize, 1usize) != ok { os.exit(311) }
    if grid8.editing || table.get_bool(&app.tbl, C_FOIL, 20usize) == foil_before { os.exit(312) }
    if app.value_calls != values_before + 1usize || app.edit_calls != edits_at_flip + 1usize { os.exit(313) }
    var expect_old = "no"
    var expect_new = "yes"
    if foil_before {
        expect_old = "yes"
        expect_new = "no"
    }
    if !str.eq(app.value_old[0usize..app.value_old_len], expect_old) || !str.eq(app.value_new[0usize..app.value_new_len], expect_new) { os.exit(314) }
    // a locked row refuses, the others do not
    app.locked_row = 20usize
    if dg.begin_edit(&grid8, 20usize, 1usize) != dg.Locked { os.exit(315) }
    if dg.begin_edit(&grid8, 21usize, 1usize) != ok { os.exit(316) }
    app.locked_row = ROWS
    // the text editor's old and new text: Price of row 5 to a new number
    let values_text = app.value_calls
    var price_text_before: [32]u8 = zero
    if dg.begin_edit(&grid2, 5usize, 3usize) != ok { os.exit(317) }
    let held = grid2.edit_len
    var h = 0usize
    while h < held {
        price_text_before[h] = grid2.edit_text[h]
        h += 1usize
    }
    grid2.edit_text[0usize] = 52u8
    grid2.edit_len = 1usize
    if dg.commit_edit(&grid2) != ok { os.exit(318) }
    if app.value_calls != values_text + 1usize || app.value_new_len != 1usize || app.value_new[0usize] != 52u8 { os.exit(319) }
    if app.value_old_len != held || !str.eq(app.value_old[0usize..held], price_text_before[0usize..held]) { os.exit(320) }
    // a batch holds the events back and ends with one
    let values_batch = app.value_calls
    let edits_batch = app.edit_calls
    dg.begin_batch(&grid2)
    var n = 0usize
    while n < 3usize {
        if dg.begin_edit(&grid2, 30usize + n, 3usize) != ok { os.exit(321) }
        grid2.edit_text[0usize] = 55u8
        grid2.edit_len = 1usize
        if dg.commit_edit(&grid2) != ok { os.exit(322) }
        n += 1usize
    }
    if app.value_calls != values_batch || app.edit_calls != edits_batch || app.batch_calls != 0usize { os.exit(323) }
    if dg.end_batch(&grid2) != ok || app.batch_calls != 1usize || app.batch_total != 3usize { os.exit(324) }
    if table.get_f64(&app.tbl, C_PRICE, 31usize) != 7.0f64 { os.exit(325) }
    // a select editor over a small dictionary: the pick writes the dictionary value and commits
    var choice_specs: [2]dg.ColumnSpec = zero
    choice_specs[0usize] = dg.ColumnSpec { title: "Name", width: 200.0, column: C_NAME, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: false, choice: false }
    choice_specs[1usize] = dg.ColumnSpec { title: "Rarity", width: 160.0, column: C_RARITY, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: true, choice: true }
    let (made9, grid9_error) = dg.create(a, &app.tbl, &app.grouping, choice_specs[0..], events, 9700u64)
    if grid9_error != ok { os.exit(326) }
    var grid9 = made9
    show_row(&grid9, &app.grouping, 40usize)
    if dg.begin_edit(&grid9, 40usize, 1usize) != ok { os.exit(327) }
    var select_clock = 40000000000i64
    mem.reset(&f, 0usize)
    let (root24, build24_error) = dg.build(&f, &grid9, &theme, 400.0)
    if build24_error != ok { os.exit(328) }
    if settle(&harness, root24, select_clock) != ok { os.exit(329) }
    select_clock += 2000000000i64
    if testing.by_key(&harness, 9700u64 + dg.EDIT_KEY).count == 0usize { os.exit(330) }
    // open it, then pick the entry whose text is "Mythic"
    if !tap_key(&harness, &runtime, 9700u64 + dg.EDIT_KEY) { os.exit(331) }
    if !grid9.select_open { os.exit(332) }
    mem.reset(&f, 0usize)
    let (root25, build25_error) = dg.build(&f, &grid9, &theme, 400.0)
    if build25_error != ok { os.exit(333) }
    if settle(&harness, root25, select_clock) != ok { os.exit(334) }
    select_clock += 2000000000i64
    let choices_before = app.edit_calls
    if !tap_text(&harness, &runtime, "Mythic") { os.exit(335) }
    if grid9.editing || app.edit_calls != choices_before + 1usize { os.exit(336) }
    if !str.eq(table.get_str(&app.tbl, C_RARITY, 40usize), "Mythic") { os.exit(337) }
    // 14. conditional formatting: a cell-is rule fills a cell, a data bar fills a fraction of it
    var rule_specs: [3]dg.ColumnSpec = zero
    rule_specs[0usize] = dg.ColumnSpec { title: "Name", width: 200.0, column: C_NAME, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: false, choice: false }
    rule_specs[1usize] = dg.ColumnSpec { title: "Rarity", width: 160.0, column: C_RARITY, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: false, choice: false }
    rule_specs[2usize] = dg.ColumnSpec { title: "Cmc", width: 120.0, column: C_CMC, kind: dg.CellKind.Int, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: false, choice: false }
    let (made10, grid10_error) = dg.create(a, &app.tbl, &app.grouping, rule_specs[0..], events, 9800u64)
    if grid10_error != ok { os.exit(340) }
    var grid10 = made10
    let (rset_made, rset_error) = gr.create(a, &app.tbl, 4usize)
    if rset_error != ok { os.exit(341) }
    var rset = rset_made
    let rule_fill = paint.rgba(0.2, 0.7, 0.3, 1.0)
    var big = gr.rule(C_RARITY, gr.Kind.CellIs)
    big.op = gr.Op.Eq
    big.text = "Mythic"
    big.has_fill = true
    big.fill = rule_fill
    let (_r1, r1_error) = gr.add(a, &rset, big)
    var price_bar = gr.rule(C_CMC, gr.Kind.Bar)
    price_bar.fill = paint.rgba(0.1, 0.2, 0.9, 1.0)
    let (_r2, r2_error) = gr.add(a, &rset, price_bar)
    if r1_error != ok || r2_error != ok || gr.refresh(&rset, a) != ok { os.exit(342) }
    dg.set_rules(&grid10, &rset)
    grid10.offset = 0.0
    mem.reset(&f, 0usize)
    let (root26, build26_error) = dg.build(&f, &grid10, &theme, 400.0)
    if build26_error != ok { os.exit(343) }
    var rules_clock = 70000000000i64
    if settle(&harness, root26, rules_clock) != ok { os.exit(344) }
    let (shot_r, shot_r_error) = testing.snapshot(&harness, a)
    if shot_r_error != ok { os.exit(345) }
    // the first visible data rows: a Mythic one and another, the largest Cmc and the smallest
    var hi_row = ROWS
    var lo_row = ROWS
    var wide_row = ROWS
    var short_row = ROWS
    var probe_at = 0usize
    while probe_at < 16usize && probe_at < grp.visible_len(&app.grouping) {
        if !grp.visible_is_group(&app.grouping, probe_at) {
            let candidate = grp.visible_row(&app.grouping, probe_at)
            let mythic = str.eq(table.get_str(&app.tbl, C_RARITY, candidate), "Mythic")
            if mythic && hi_row == ROWS { hi_row = candidate }
            if !mythic && lo_row == ROWS { lo_row = candidate }
            if wide_row == ROWS || table.get_i32(&app.tbl, C_CMC, candidate) > table.get_i32(&app.tbl, C_CMC, wide_row) { wide_row = candidate }
            if short_row == ROWS || table.get_i32(&app.tbl, C_CMC, candidate) < table.get_i32(&app.tbl, C_CMC, short_row) { short_row = candidate }
        }
        probe_at += 1usize
    }
    if hi_row == ROWS || lo_row == ROWS { os.exit(346) }
    let (hi_bounds, hi_found) = bounds(&harness, &runtime, dg.row_key(&grid10, hi_row))
    let (lo_bounds, lo_found) = bounds(&harness, &runtime, dg.row_key(&grid10, lo_row))
    if !hi_found || !lo_found { os.exit(347) }
    // inside the Rarity cell (x 200..360), clear of its text
    if !is_color(shot_r, px(hi_bounds.x + 330.0, hi_bounds.y + hi_bounds.height * 0.5), rule_fill) { os.exit(348) }
    if is_color(shot_r, px(lo_bounds.x + 330.0, lo_bounds.y + lo_bounds.height * 0.5), rule_fill) { os.exit(349) }
    // the bar: the row with the largest Cmc shows more of it than the smallest
    let (wide_bounds, wide_found) = bounds(&harness, &runtime, dg.row_key(&grid10, wide_row))
    let (short_bounds, short_found) = bounds(&harness, &runtime, dg.row_key(&grid10, short_row))
    if !wide_found || !short_found { os.exit(350) }
    var wide_blue = 0usize
    var short_blue = 0usize
    var across: f32 = 364.0
    while across < 476.0 {
        if is_color(shot_r, px(wide_bounds.x + across, wide_bounds.y + wide_bounds.height * 0.5), paint.rgba(0.1, 0.2, 0.9, 1.0)) { wide_blue += 1usize }
        if is_color(shot_r, px(short_bounds.x + across, short_bounds.y + short_bounds.height * 0.5), paint.rgba(0.1, 0.2, 0.9, 1.0)) { short_blue += 1usize }
        across += 4.0
    }
    if wide_blue == 0usize || wide_blue <= short_blue { os.exit(351) }
    // detaching the rules takes the fill away
    dg.clear_rules(&grid10)
    mem.reset(&f, 0usize)
    let (root27, build27_error) = dg.build(&f, &grid10, &theme, 400.0)
    if build27_error != ok { os.exit(352) }
    rules_clock += 2000000000i64
    if settle(&harness, root27, rules_clock) != ok { os.exit(353) }
    let (shot_n, shot_n_error) = testing.snapshot(&harness, a)
    if shot_n_error != ok { os.exit(354) }
    if is_color(shot_n, px(hi_bounds.x + 330.0, hi_bounds.y + hi_bounds.height * 0.5), rule_fill) { os.exit(355) }
    // 15. the measured v3 look: row pitch 19, zebra #FFFFFF / #EFEFEF, the selected row #A6D2FF
    var look_specs: [2]dg.ColumnSpec = zero
    look_specs[0usize] = dg.ColumnSpec { title: "Name", width: 200.0, column: C_NAME, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: false, choice: false }
    look_specs[1usize] = dg.ColumnSpec { title: "Cmc", width: 120.0, column: C_CMC, kind: dg.CellKind.Int, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: false, choice: false }
    let (made11, grid11_error) = dg.create(a, &app.tbl, &app.grouping, look_specs[0..], events, 9900u64)
    if grid11_error != ok { os.exit(360) }
    var grid11 = made11
    dg.set_look(&grid11, gl.v3())
    grid11.offset = 0.0
    var first_look = ROWS
    var second_look = ROWS
    var third_look = ROWS
    var look_at = 0usize
    while look_at < 8usize && look_at < grp.visible_len(&app.grouping) {
        if !grp.visible_is_group(&app.grouping, look_at) {
            let candidate_row = grp.visible_row(&app.grouping, look_at)
            if first_look == ROWS {
                first_look = candidate_row
            } else if second_look == ROWS {
                second_look = candidate_row
            } else if third_look == ROWS {
                third_look = candidate_row
            }
        }
        look_at += 1usize
    }
    if third_look == ROWS { os.exit(361) }
    grid11.has_selection = true
    grid11.selected_row = second_look
    mem.reset(&f, 0usize)
    let (root28, build28_error) = dg.build(&f, &grid11, &theme, 400.0)
    if build28_error != ok { os.exit(362) }
    if settle(&harness, root28, 80000000000i64) != ok { os.exit(363) }
    let (shot_l, shot_l_error) = testing.snapshot(&harness, a)
    if shot_l_error != ok { os.exit(364) }
    let (b0, f0) = bounds(&harness, &runtime, dg.row_key(&grid11, first_look))
    let (b1, f1) = bounds(&harness, &runtime, dg.row_key(&grid11, second_look))
    let (b2, f2) = bounds(&harness, &runtime, dg.row_key(&grid11, third_look))
    if !f0 || !f1 || !f2 { os.exit(365) }
    // the pitch of a row (its height with no line between rows)
    if b0.height < 18.9 || b0.height > 19.1 || b1.y - b0.y < 18.9 || b1.y - b0.y > 19.1 { os.exit(366) }
    // inside the Cmc cell, clear of its digit: even row, selected row, odd row
    if !is_color(shot_l, px(b0.x + 300.0, b0.y + 9.0), gl.rgb(0xFFFFFFu32)) { os.exit(367) }
    if !is_color(shot_l, px(b1.x + 300.0, b1.y + 9.0), gl.rgb(0xA6D2FFu32)) { os.exit(368) }
    if !is_color(shot_l, px(b2.x + 300.0, b2.y + 9.0), gl.rgb(0xFFFFFFu32)) && !is_color(shot_l, px(b2.x + 300.0, b2.y + 9.0), gl.rgb(0xEFEFEFu32)) { os.exit(369) }
    // P006: the selected row carries a 1 px dark border on its top and bottom edge
    if !is_color(shot_l, px(b1.x + 300.0, b1.y + 0.5), gl.rgb(0x83878Bu32)) { os.exit(495) }
    if !is_color(shot_l, px(b1.x + 300.0, b1.y + b1.height - 0.5), gl.rgb(0x83878Bu32)) { os.exit(496) }
    // P007: an unselected body row has full-height column lines (#E6E6E6) between its cells
    var line_seen = false
    var line_x: f32 = 0.0
    while line_x < 300.0 {
        if is_color(shot_l, px(b0.x + line_x, b0.y + 9.0), gl.rgb(0xE6E6E6u32)) { line_seen = true }
        line_x += 1.0
    }
    if !line_seen { os.exit(497) }
    // P008: the header cell above the first row is white
    if !is_color(shot_l, px(b0.x + 300.0, b0.y - 8.0), gl.rgb(0xFFFFFFu32)) { os.exit(498) }
    // two neighbouring unselected rows differ (the zebra)
    dg.clear_selection(&grid11)
    mem.reset(&f, 0usize)
    let (root29, build29_error) = dg.build(&f, &grid11, &theme, 400.0)
    if build29_error != ok { os.exit(370) }
    if settle(&harness, root29, 82000000000i64) != ok { os.exit(371) }
    let (shot_z, shot_z_error) = testing.snapshot(&harness, a)
    if shot_z_error != ok { os.exit(372) }
    let (z0, zf0) = bounds(&harness, &runtime, dg.row_key(&grid11, first_look))
    let (z1, zf1) = bounds(&harness, &runtime, dg.row_key(&grid11, second_look))
    if !zf0 || !zf1 { os.exit(373) }
    let upper = is_color(shot_z, px(z0.x + 300.0, z0.y + 9.0), gl.rgb(0xFFFFFFu32)) || is_color(shot_z, px(z0.x + 300.0, z0.y + 9.0), gl.rgb(0xEFEFEFu32))
    let lower_same = is_color(shot_z, px(z1.x + 300.0, z1.y + 9.0), gl.rgb(0xFFFFFFu32)) == is_color(shot_z, px(z0.x + 300.0, z0.y + 9.0), gl.rgb(0xFFFFFFu32))
    if !upper || lower_same { os.exit(374) }
    // 16. the favourite star: a Star column shows it in its header and, set, in its cells; the
    // navigator of the measured look is drawn with arrow marks
    var nine: [9]dg.ColumnSpec = zero
    var ni = 0usize
    while ni < 9usize {
        nine[ni] = dg.ColumnSpec { title: "C", width: 80.0, column: C_NAME, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: false, choice: false }
        ni += 1usize
    }
    let (made13, grid13_error) = dg.create(a, &app.tbl, &app.grouping, nine[0..], events, 10100u64)
    if grid13_error != ok { os.exit(390) }
    var grid13 = made13
    dg.set_look(&grid13, gl.v3())
    mem.reset(&f, 0usize)
    let (root31, build31_error) = dg.build(&f, &grid13, &theme, 400.0)
    if build31_error != ok { os.exit(391) }
    if settle(&harness, root31, 89000000000i64) != ok { os.exit(392) }
    var star_specs: [2]dg.ColumnSpec = zero
    star_specs[0usize] = dg.ColumnSpec { title: "Fav", width: 40.0, column: C_FOIL, kind: dg.CellKind.Star, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: true, choice: false }
    star_specs[1usize] = dg.ColumnSpec { title: "Name", width: 200.0, column: C_NAME, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: false, choice: false }
    let (made12, grid12_error) = dg.create(a, &app.tbl, &app.grouping, star_specs[0..], events, 10000u64)
    if grid12_error != ok { os.exit(380) }
    var grid12 = made12
    dg.set_look(&grid12, gl.v3())
    dg.show_navigator(&grid12, true)
    mem.reset(&f, 0usize)
    let (root30, build30_error) = dg.build(&f, &grid12, &theme, 400.0)
    if build30_error != ok { os.exit(381) }
    if settle(&harness, root30, 90000000000i64) != ok { os.exit(382) }
    // the four navigator buttons exist under their keys
    if testing.by_key(&harness, dg.navigator_key(&grid12) + 1u64).count == 0usize { os.exit(383) }
    if testing.by_key(&harness, dg.navigator_key(&grid12) + 4u64).count == 0usize { os.exit(384) }
    // 17. the group box and the drawn expanders of the measured look, with the grid grouped
    let (made14, grid14_error) = dg.create(a, &app.tbl, &app.grouping, look_specs[0..], events, 10200u64)
    if grid14_error != ok { os.exit(395) }
    var grid14 = made14
    dg.set_look(&grid14, gl.v3())
    dg.show_group_box(&grid14, true)
    app.group_rarity = true
    if rebuild(app, 5usize, false) != ok { os.exit(396) }
    mem.reset(&f, 0usize)
    let (root32, build32_error) = dg.build(&f, &grid14, &theme, 400.0)
    if build32_error != ok { os.exit(397) }
    if settle(&harness, root32, 91000000000i64) != ok { os.exit(398) }
    app.group_rarity = false
    if rebuild(app, 5usize, false) != ok { os.exit(399) }
    // 18. a picture of v3's data folder drawn by an image node keeps its pixels (skipped when absent)
    let (symbol, symbol_error) = gl.load_picture(a, widget.renderer_of(&runtime), "D:/repos/mtg.studio.src/version-3/bin/data/png/symbols/2.png")
    if symbol_error == gl.BadPicture { os.exit(400) }
    if symbol_error == ok {
        mem.reset(&f, 0usize)
        let (picture, picture_error) = control.image(&f, 10300u64, symbol, 36.0, 36.0, .Fill, "")
        if picture_error != ok { os.exit(401) }
        if settle(&harness, picture, 92000000000i64) != ok { os.exit(402) }
        let (shot_p, shot_p_error) = testing.snapshot(&harness, a)
        if shot_p_error != ok { os.exit(403) }
        let (pic_b, pic_f) = bounds(&harness, &runtime, 10300u64)
        if !pic_f { os.exit(404) }
        // an image node draws the whole picture, not one texel: the symbol's middle (dark grey ring and
        // numeral) differs from its transparent corner
        let centre = px(pic_b.x + 18.0, pic_b.y + 18.0)
        let corner = px(pic_b.x + 1.0, pic_b.y + 1.0)
        var distinct = 0usize
        var channel = 0usize
        while channel < 3usize {
            if shot_p.pixels[centre + channel] != shot_p.pixels[corner + channel] { distinct += 1usize }
            channel += 1usize
        }
        if distinct == 0usize { os.exit(405) }
        // and its left and right halves differ somewhere along the middle row
        var varied = false
        var pic_x: f32 = 2.0
        while pic_x < 34.0 {
            let at = px(pic_b.x + pic_x, pic_b.y + 18.0)
            if shot_p.pixels[at] != shot_p.pixels[centre] { varied = true }
            pic_x += 1.0
        }
        if !varied { os.exit(406) }
    }
    // 19. an SVG mark (v3's edition symbol, dark blue-black fill) is drawn at the size of its box
    let (svg_text, svg_error) = fs.read_file(a, "D:/repos/mtg.studio.src/v5/cardgrid/symbols/ed_10e.svg", 65536usize)
    if svg_error != ok { os.exit(409) }
    if true {
        mem.reset(&f, 0usize)
        let (drawing, drawing_error) = gl.svg_mark(&f, svg_text, paint.rgba(1.0, 1.0, 1.0, 1.0), 64.0, 64.0)
        if drawing_error != ok { os.exit(410) }
        var holder: [1]widget.Node = zero
        holder[0usize] = drawing
        let boxed = widget.box(10400u64, style.defaults(), holder[0usize..1usize])
        if settle(&harness, boxed, 93000000000i64) != ok { os.exit(411) }
        let (shot_s, shot_s_error) = testing.snapshot(&harness, a)
        if shot_s_error != ok { os.exit(412) }
        let (svg_b, svg_f) = bounds(&harness, &runtime, 10400u64)
        if !svg_f { os.exit(413) }
        var svg_min_x = 9999usize
        var svg_max_x = 0usize
        var svg_min_y = 9999usize
        var svg_max_y = 0usize
        var yy: f32 = 0.0
        while yy < 70.0 {
            var xx: f32 = 0.0
            while xx < 70.0 {
                let at = px(svg_b.x + xx, svg_b.y + yy)
                if shot_s.pixels[at + 2usize] > 8u8 {
                    let ix = usize(xx)
                    let iy = usize(yy)
                    if ix < svg_min_x { svg_min_x = ix }
                    if ix > svg_max_x { svg_max_x = ix }
                    if iy < svg_min_y { svg_min_y = iy }
                    if iy > svg_max_y { svg_max_y = iy }
                }
                xx += 1.0
            }
            yy += 1.0
        }
        // the symbol's ink spans 20 of its 32 units: 40 of the 64 high box
        let ink_height = svg_max_y - svg_min_y + 1usize
        if ink_height < 38usize || ink_height > 42usize { os.exit(414) }
    }
    // 19b. a fitted SVG mark (v3's edition symbol, dark blue-black fill) is drawn at the size of its box
    let (fit_text, fit_error) = fs.read_file(a, "D:/repos/mtg.studio.src/v5/cardgrid/symbols/ed_10e.svg", 65536usize)
    if fit_error != ok { os.exit(409) }
    if true {
        mem.reset(&f, 0usize)
        let (fit_drawing, fit_drawing_error) = gl.svg_fit_mark(&f, fit_text, paint.rgba(1.0, 1.0, 1.0, 1.0), 64.0, 64.0)
        if fit_drawing_error != ok { os.exit(410) }
        var fit_holder: [1]widget.Node = zero
        fit_holder[0usize] = fit_drawing
        let fit_boxed = widget.box(10450u64, style.defaults(), fit_holder[0usize..1usize])
        if settle(&harness, fit_boxed, 93500000000i64) != ok { os.exit(411) }
        let (shot_fit, shot_fit_error) = testing.snapshot(&harness, a)
        if shot_fit_error != ok { os.exit(412) }
        let (fit_b, fit_f) = bounds(&harness, &runtime, 10450u64)
        if !fit_f { os.exit(413) }
        var fit_min_x = 9999usize
        var fit_max_x = 0usize
        var fit_min_y = 9999usize
        var fit_max_y = 0usize
        var yy: f32 = 0.0
        while yy < 70.0 {
            var xx: f32 = 0.0
            while xx < 70.0 {
                let at = px(fit_b.x + xx, fit_b.y + yy)
                if shot_fit.pixels[at + 2usize] > 8u8 {
                    let ix = usize(xx)
                    let iy = usize(yy)
                    if ix < fit_min_x { fit_min_x = ix }
                    if ix > fit_max_x { fit_max_x = ix }
                    if iy < fit_min_y { fit_min_y = iy }
                    if iy > fit_max_y { fit_max_y = iy }
                }
                xx += 1.0
            }
            yy += 1.0
        }
        // the symbol's ink spans 20 of its 32 units: 40 of the 64 high box
        let fit_ink_width = fit_max_x - fit_min_x + 1usize
        if fit_ink_width < 60usize || fit_ink_width > 66usize { os.exit(415) }
    }
    // 20. the keyboard trace recorded from v3 (docs/grid-parity/traces.json): a tap makes a row current,
    // Down moves it one row each, Up one back, End goes to the last row and Home to the first
    var key_specs: [1]dg.ColumnSpec = zero
    key_specs[0usize] = dg.ColumnSpec { title: "Name", width: 300.0, column: C_NAME, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: false, choice: false }
    let (made15, grid15_error) = dg.create(a, &app.tbl, &app.grouping, key_specs[0..], events, 10500u64)
    if grid15_error != ok { os.exit(420) }
    var grid15 = made15
    dg.set_look(&grid15, gl.v3())
    app.group_rarity = false
    if rebuild(app, 5usize, false) != ok { os.exit(421) }
    mem.reset(&f, 0usize)
    let (root33, build33_error) = dg.build(&f, &grid15, &theme, 400.0)
    if build33_error != ok { os.exit(422) }
    if settle(&harness, root33, 94000000000i64) != ok { os.exit(423) }
    let first_data = grp.visible_row(&app.grouping, 0usize)
    if !tap_key(&harness, &runtime, dg.row_key(&grid15, first_data)) { os.exit(424) }
    let (start_at, start_has) = dg.current_position(&grid15)
    if !start_has || start_at != 0usize { os.exit(425) }
    var trace_clock = 95000000000i64
    var presses = 0usize
    while presses < 3usize {
        if testing.press_key(&harness, 40u32, zero) != ok { os.exit(426) }
        mem.reset(&f, 0usize)
        let (root34, build34_error) = dg.build(&f, &grid15, &theme, 400.0)
        if build34_error != ok { os.exit(436) }
        if settle(&harness, root34, trace_clock) != ok { os.exit(437) }
        trace_clock += 2000000000i64
        presses += 1usize
    }
    let (down_at, down_has) = dg.current_position(&grid15)
    if !down_has || down_at != 3usize { os.exit(427) }
    if testing.press_key(&harness, 38u32, zero) != ok { os.exit(428) }
    mem.reset(&f, 0usize)
    let (root35, build35_error) = dg.build(&f, &grid15, &theme, 400.0)
    if build35_error != ok { os.exit(438) }
    if settle(&harness, root35, trace_clock) != ok { os.exit(439) }
    trace_clock += 2000000000i64
    let (up_at, up_has) = dg.current_position(&grid15)
    if !up_has || up_at != 2usize { os.exit(429) }
    if testing.press_key(&harness, 35u32, zero) != ok { os.exit(430) }
    mem.reset(&f, 0usize)
    let (root36, build36_error) = dg.build(&f, &grid15, &theme, 400.0)
    if build36_error != ok { os.exit(440) }
    if settle(&harness, root36, trace_clock) != ok { os.exit(441) }
    trace_clock += 2000000000i64
    var again = 0usize
    while again < 3usize {
        mem.reset(&f, 0usize)
        let (root38, build38_error) = dg.build(&f, &grid15, &theme, 400.0)
        if build38_error != ok { os.exit(444) }
        if settle(&harness, root38, trace_clock) != ok { os.exit(445) }
        trace_clock += 2000000000i64
        again += 1usize
    }
    let (end_at, end_has) = dg.current_position(&grid15)
    if !end_has || end_at != grp.visible_len(&app.grouping) - 1usize { os.exit(431) }
    if testing.press_key(&harness, 36u32, zero) != ok { os.exit(432) }
    mem.reset(&f, 0usize)
    let (root37, build37_error) = dg.build(&f, &grid15, &theme, 400.0)
    if build37_error != ok { os.exit(442) }
    if settle(&harness, root37, trace_clock) != ok { os.exit(443) }
    trace_clock += 2000000000i64
    again = 0usize
    while again < 3usize {
        mem.reset(&f, 0usize)
        let (root39, build39_error) = dg.build(&f, &grid15, &theme, 400.0)
        if build39_error != ok { os.exit(446) }
        if settle(&harness, root39, trace_clock) != ok { os.exit(447) }
        trace_clock += 2000000000i64
        again += 1usize
    }
    let (home_at, home_has) = dg.current_position(&grid15)
    if !home_has || home_at != 0usize { os.exit(433) }
    // 21. the extent of a drawing is measured from its path data (the 10th Edition symbol:
    // x 0.03 to 26.4, y 5.87 to 26.13 of a 27 by 32 view box)
    let (ink_text, ink_error) = fs.read_file(a, "D:/repos/mtg.studio.src/v5/cardgrid/symbols/ed_10e.svg", 65536usize)
    if ink_error != ok { os.exit(449) }
    let (ink, ink_w, ink_h) = gl.svg_ink(ink_text)
    if !ink.any { os.exit(450) }
    if ink_w != 27.0 || ink_h != 32.0 { os.exit(451) }
    if ink.x0 > 0.1 || ink.x1 < 26.3 || ink.x1 > 26.5 { os.exit(452) }
    if ink.y0 < 5.8 || ink.y0 > 5.95 || ink.y1 < 26.0 || ink.y1 > 26.2 { os.exit(453) }
    // 22. the v3 trace of a sort: the current card stays current and the view moves the least that
    // shows it (docs/grid-parity/traces.json S2)
    if rebuild(app, 5usize, false) != ok { os.exit(460) }
    mem.reset(&f, 0usize)
    let (root40, build40_error) = dg.build(&f, &grid15, &theme, 400.0)
    if build40_error != ok { os.exit(461) }
    if settle(&harness, root40, trace_clock) != ok { os.exit(462) }
    trace_clock += 2000000000i64
    let kept_row = grid15.selected_row
    let old_at = grid15.position
    // a different order: by the second column, descending
    if rebuild(app, 3usize, true) != ok { os.exit(463) }
    mem.reset(&f, 0usize)
    let (root41, build41_error) = dg.build(&f, &grid15, &theme, 400.0)
    if build41_error != ok { os.exit(464) }
    if settle(&harness, root41, trace_clock) != ok { os.exit(465) }
    if !grid15.has_selection || grid15.selected_row != kept_row { os.exit(466) }
    if !grid15.has_position || grp.visible_row(&app.grouping, grid15.position) != kept_row { os.exit(467) }
    // the view shows it
    let shown_top = usize(grid15.offset / grid15.row_height)
    if grid15.position < shown_top || grid15.position >= shown_top + grid15.page_rows + 1usize { os.exit(468) }
    // 23. a double tap on a column's resize handle asks for its best fit (v3 trace A1): the width becomes
    // the content's, here far under the 300 given (the harness has no fonts, so the least)
    let before_fit = dg.column_width(&grid15, 0usize)
    if dg.on_resize(mem.cast[*void](&grid15), collection.ColumnResize { column: 0usize, width: -1.0 }) != ok { os.exit(470) }
    mem.reset(&f, 0usize)
    let (root42, build42_error) = dg.build(&f, &grid15, &theme, 400.0)
    if build42_error != ok { os.exit(471) }
    if dg.column_width(&grid15, 0usize) >= before_fit { os.exit(472) }
    // 24. v3 trace G1: grouping keeps the current card current and opens the group that holds it
    let grouped_row = grid15.selected_row
    app.group_rarity = true
    if rebuild(app, 5usize, false) != ok { os.exit(480) }
    dg.reveal_current(&grid15)
    mem.reset(&f, 0usize)
    let (root43, build43_error) = dg.build(&f, &grid15, &theme, 400.0)
    if build43_error != ok { os.exit(481) }
    if settle(&harness, root43, trace_clock) != ok { os.exit(482) }
    trace_clock += 2000000000i64
    if !grid15.has_position || grid15.selected_row != grouped_row { os.exit(483) }
    if grp.visible_is_group(&app.grouping, grid15.position) || grp.visible_row(&app.grouping, grid15.position) != grouped_row { os.exit(484) }
    // and removing the grouping again keeps it current too
    app.group_rarity = false
    if rebuild(app, 5usize, false) != ok { os.exit(485) }
    mem.reset(&f, 0usize)
    let (root44, build44_error) = dg.build(&f, &grid15, &theme, 400.0)
    if build44_error != ok { os.exit(486) }
    if !grid15.has_position || grp.visible_row(&app.grouping, grid15.position) != grouped_row { os.exit(487) }
    // 25. v3 trace E1: an immediate-edit grid keeps the row after a commit, and Tab edits the next cell
    dg.set_immediate_edit(&grid2, true)
    grid2.has_selection = true
    grid2.selected_row = 5usize
    if dg.begin_edit(&grid2, 5usize, 3usize) != ok { os.exit(488) }
    grid2.edit_text[0usize] = 53u8
    grid2.edit_len = 1usize
    if dg.commit_edit(&grid2) != ok || grid2.editing { os.exit(489) }
    if !grid2.rest_pending || grid2.rest_row != 5usize || grid2.rest_spec != 3usize { os.exit(490) }
    // Tab after the last editable cell edits nothing; on the next row it starts at the first editable cell
    if dg.on_row_tab(mem.cast[*void](&grid2)) != ok { os.exit(494) }
    let (rested_at, rested_shown) = dg.display_of(&grid2, grid2.rest_spec)
    if !rested_shown || (grid2.editing && grid2.edit_spec <= rested_at) { os.exit(491) }
    if grid2.editing && dg.commit_edit(&grid2) != ok { os.exit(493) }
    grid2.selected_row = 6usize
    var first_edit = 0usize
    while first_edit < grid2.specs.len && !grid2.specs[first_edit].editable { first_edit += 1usize }
    if dg.on_row_tab(mem.cast[*void](&grid2)) != ok || !grid2.editing || grid2.edit_spec != first_edit { os.exit(492) }
    // 26. v3 trace M1: several rows selected. Shift+Down extends from the anchor, Ctrl toggles one row,
    // a plain move selects one again, Ctrl+A selects every row
    dg.set_multi_select(&grid15, true)
    if dg.navigate(&grid15, dg.Nav.First) != ok { os.exit(500) }
    if dg.selection_size(&grid15) != 1usize { os.exit(501) }
    if dg.extend_selection(&grid15, dg.Nav.Next) != ok || dg.extend_selection(&grid15, dg.Nav.Next) != ok { os.exit(502) }
    if dg.selection_size(&grid15) != 3usize { os.exit(503) }
    let (m_first, m_has) = dg.current_position(&grid15)
    if !m_has || m_first != 2usize { os.exit(504) }
    let m_second = grp.visible_row(&app.grouping, 1usize)
    dg.set_mark(&grid15, m_second, !dg.is_marked(&grid15, m_second))
    if dg.selection_size(&grid15) != 2usize || dg.is_marked(&grid15, m_second) { os.exit(505) }
    if dg.navigate(&grid15, dg.Nav.Next) != ok || dg.selection_size(&grid15) != 1usize { os.exit(506) }
    dg.select_all(&grid15)
    if dg.selection_size(&grid15) != grp.visible_len(&app.grouping) { os.exit(507) }
    dg.set_multi_select(&grid15, false)
    if dg.is_marked(&grid15, m_second) { os.exit(508) }
    os.exit(0)
    ret ok
}
