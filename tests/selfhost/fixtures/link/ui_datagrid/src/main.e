// `e.ui.datagrid` (G006, first increment) over a 3,000-row `e.data.table` with its view and
// grouping, driven through the UI test harness: the virtual body builds only the visible rows,
// a header tap reports the sort and the application re-sorts, a group row expands on a tap and
// shows its rows, the footer carries the summaries, a tap on a data row reports the storage
// row, and a filter that matches nothing shows the no-data text. Every check has its own exit
// code.
use e.gpu
use e.mem
use e.os
use e.str
use e.time
use e.data.table as table
use e.data.tableview as view
use e.data.tablegroup as grp
use e.gfx.geometry
use e.text.shape
use e.gfx.scene
use e.ui.control
use e.ui.datagrid as dg
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
    pick_calls: usize
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
    if rebuild(app, 5usize, false) != ok { os.exit(21) }

    var specs: [5]dg.ColumnSpec = zero
    specs[0usize] = dg.ColumnSpec { title: "Name", width: 220.0, column: C_NAME, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows }
    specs[1usize] = dg.ColumnSpec { title: "Rarity", width: 120.0, column: C_RARITY, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows }
    specs[2usize] = dg.ColumnSpec { title: "CMC", width: 80.0, column: C_CMC, kind: dg.CellKind.Int, decimals: 0u8, summary: 0, summary_kind: grp.SummaryKind.Avg }
    specs[3usize] = dg.ColumnSpec { title: "Price", width: 120.0, column: C_PRICE, kind: dg.CellKind.Currency, decimals: 2u8, summary: 1, summary_kind: grp.SummaryKind.Sum }
    specs[4usize] = dg.ColumnSpec { title: "Foil", width: 70.0, column: C_FOIL, kind: dg.CellKind.Bool, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows }
    let events = dg.Events { ctx: mem.cast[*void](app), sort_changed: on_sort_changed, row_picked: on_row_picked }
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
    os.exit(0)
    ret ok
}
