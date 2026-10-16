// The data grid under every look: docs/ui/looks/<look>/data_grid.png. The Windows look is the
// measured v3 TcxGrid (`gridlook.v3()`, docs/grid-parity); the Neper look is the theme's own grid.
// Run from the repository root; see docs/ui/looks-howto.md.
//
// Run with an argument (`data_grid.exe states`) for the third sheet, data_grid_states.
//
// Two grids over one table. Left: a flat list with the filter row, alternating stripes, a selected
// row (the harness taps the cell's centre) and a vertical scroll bar. Right: grouped by rarity, two
// groups open, group rows, footer summaries.

use e.data.table as table
use e.data.tablegroup as grp
use e.data.tableview as view
use e.gfx.paint
use e.ui.gridlook as gl
use e.ui.layout as ui_layout
use e.mem
use e.os
use e.str as strs
use e.ui.control
use e.ui.datagrid as dg
use e.ui.looks
use e.ui.style
use e.ui.widget

const ROWS: usize = 40usize
const C_NAME: usize = 0usize
const C_RARITY: usize = 1usize
const C_QTY: usize = 2usize
const C_PRICE: usize = 3usize

type App = struct {
    a: *mem.Arena,
    ready: bool,
    windows: bool,
    tbl: table.Table,
    flat_view: view.View,
    flat: grp.Grouping,
    deep_view: view.View,
    deep: grp.Grouping,
    scratch: mem.Arena,
    store: mem.Arena,
    list_grid: dg.Grid,
    group_grid: dg.Grid
}

fn mix(x: u64) -> u64 {
    var v = x *% 6364136223846793005u64 +% 1442695040888963407u64
    v = v ^ (v >> 29u64)
    v = v *% 6364136223846793005u64
    ret v ^ (v >> 32u64)
}

fn rarity_of(row: usize) -> str {
    let p = mix(u64(row) + 9u64) % 3u64
    if p == 0u64 { ret "Common" }
    if p == 1u64 { ret "Rare" }
    ret "Mythic"
}

fn name_of(a: *mem.Arena, row: usize) -> str {
    let (b, b_error) = strs.builder(a, 24usize)
    if b_error != ok { ret "" }
    var sb = b
    if strs.push(&sb, "Card ") != ok || strs.push_usize(&sb, (row * 7919usize) % 10007usize) != ok { ret "" }
    ret strs.done(&sb)
}

fn load(a: *mem.Arena, app: *App) -> err {
    var spec: [4]table.Spec = zero
    spec[C_NAME] = table.Spec { name: "Name", kind: table.Kind.Dict, heap_bytes: 4096usize, dict_cap: ROWS }
    spec[C_RARITY] = table.Spec { name: "Rarity", kind: table.Kind.Dict, heap_bytes: 256usize, dict_cap: 8usize }
    spec[C_QTY] = table.Spec { name: "Qty", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_PRICE] = table.Spec { name: "Price", kind: table.Kind.F64, heap_bytes: 0usize, dict_cap: 0usize }
    let (made, made_error) = table.create(a, spec[0..], ROWS)
    if made_error != ok { ret made_error }
    app.tbl = made
    table.begin_load(&app.tbl)
    let (scratch_names, scratch_error) = mem.alloc[u8](a, 4096usize)
    if scratch_error != ok { ret scratch_error }
    var names = mem.arena_from(scratch_names)
    var row = 0usize
    while row < ROWS {
        let (got, append_error) = table.append_row(&app.tbl)
        if append_error != ok { ret append_error }
        mem.reset(&names, 0usize)
        try table.set_str(&app.tbl, C_NAME, got, name_of(&names, row))
        try table.set_str(&app.tbl, C_RARITY, got, rarity_of(row))
        table.set_i32(&app.tbl, C_QTY, got, i32(mix(u64(row) + 1u64) % 5u64) + 1)
        table.set_f64(&app.tbl, C_PRICE, got, f64(mix(u64(row) + 2u64) % 10000u64) / 100.0f64)
        row += 1usize
    }
    table.end_load(&app.tbl)
    ret ok
}

fn summarise(app: *App, g: *grp.Grouping) -> err {
    var specs: [2]grp.SummarySpec = zero
    specs[0usize] = grp.SummarySpec { column: C_QTY }
    specs[1usize] = grp.SummarySpec { column: C_PRICE }
    ret grp.apply_summaries(g, specs[0usize..2usize], &app.store)
}

fn columns() -> [4]dg.ColumnSpec {
    var specs: [4]dg.ColumnSpec = zero
    specs[0usize] = dg.ColumnSpec { title: "Name", width: 180.0, column: C_NAME, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: true, editable: false, choice: false }
    specs[1usize] = dg.ColumnSpec { title: "Rarity", width: 100.0, column: C_RARITY, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: true, editable: false, choice: false }
    specs[2usize] = dg.ColumnSpec { title: "Qty", width: 60.0, column: C_QTY, kind: dg.CellKind.Int, decimals: 0u8, summary: 0, summary_kind: grp.SummaryKind.Sum, filter: false, editable: false, choice: false }
    specs[3usize] = dg.ColumnSpec { title: "Price", width: 84.0, column: C_PRICE, kind: dg.CellKind.Currency, decimals: 2u8, summary: 1, summary_kind: grp.SummaryKind.Sum, filter: false, editable: false, choice: false }
    ret specs
}

fn setup(app: *App) -> err {
    let a = app.a
    try load(a, app)
    let (scratch_bytes, scratch_error) = mem.alloc[u8](a, 1048576usize)
    if scratch_error != ok { ret scratch_error }
    app.scratch = mem.arena_from(scratch_bytes)
    let (store_bytes, store_error) = mem.alloc[u8](a, 65536usize)
    if store_error != ok { ret store_error }
    app.store = mem.arena_from(store_bytes)
    let (view_a, view_a_error) = view.create(a, &app.tbl)
    if view_a_error != ok { ret view_a_error }
    app.flat_view = view_a
    let (flat, flat_error) = grp.create(a, &app.flat_view, 8usize)
    if flat_error != ok { ret flat_error }
    app.flat = flat
    let (view_b, view_b_error) = view.create(a, &app.tbl)
    if view_b_error != ok { ret view_b_error }
    app.deep_view = view_b
    let (deep, deep_error) = grp.create(a, &app.deep_view, 8usize)
    if deep_error != ok { ret deep_error }
    app.deep = deep
    var none: [1]grp.GroupLevel = zero
    var name_key: [1]view.Key = zero
    name_key[0usize] = view.column_key(C_NAME, false, true)
    try grp.group_by(&app.flat, none[0usize..0usize], name_key[0usize..1usize], &app.scratch)
    try summarise(app, &app.flat)
    var levels: [1]grp.GroupLevel = zero
    levels[0usize] = grp.GroupLevel { column: C_RARITY, descending: false, fold: true }
    try grp.group_by(&app.deep, levels[0usize..1usize], name_key[0usize..1usize], &app.scratch)
    try summarise(app, &app.deep)
    try grp.set_expanded(&app.deep, 0usize, true)
    try grp.set_expanded(&app.deep, 1usize, true)
    let specs = columns()
    let (g1, g1_error) = dg.create(a, &app.tbl, &app.flat, specs[0usize..4usize], dg.no_events(), 100u64)
    if g1_error != ok { ret g1_error }
    app.list_grid = g1
    dg.show_filter_row(&app.list_grid, true)
    let (g2, g2_error) = dg.create(a, &app.tbl, &app.deep, specs[0usize..4usize], dg.no_events(), 200u64)
    if g2_error != ok { ret g2_error }
    app.group_grid = g2
    ret ok
}

// A grid in the form's face (the dialog background), with the 8 px of padding a v3 form leaves.
fn framed(a: *mem.Arena, t: *const control.Theme, grid: *dg.Grid, w: f32, h: f32) -> (widget.Node, err) {
    let (body, body_error) = dg.build(a, grid, t, h - 16.0)
    if body_error != ok { ret (zero, body_error) }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = body
    var face = looks.size_style(w, h)
    face.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    ret (widget.padded(0u64, 8.0, 8.0, 8.0, 8.0, face, held[0usize..1usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let app = mem.cast[*App](ctx)
    // a grid keeps the look it was given: the pass of another look builds its grids afresh
    if app.ready && app.windows != (t.tokens.profile == .Windows) { app.ready = false }
    if !app.ready {
        try setup(app)
        app.ready = true
        app.windows = t.tokens.profile == .Windows
    }
    if t.tokens.profile != .Windows {
        // the grids keep their look between renders: the Neper pass must not inherit the Windows one
    }
    let (left, left_error) = framed(a, t, &app.list_grid, 460.0, 300.0)
    if left_error != ok { ret (0usize, left_error) }
    let (right, right_error) = framed(a, t, &app.group_grid, 460.0, 300.0)
    if right_error != ok { ret (0usize, right_error) }
    cells[0usize] = looks.Cell { caption: "List: filter row, stripes, selected row, scroll bar", node: left, drive: .Focus }
    cells[1usize] = looks.Cell { caption: "Grouped: group rows, summary footer", node: right, drive: .None }
    ret (2usize, ok)
}

// ---- sheet 2: data_grid_main, the two grids of the live v3 main window ---------------------
// docs/ui/looks/ref/windows/main-window@1x.png at 100 %: the pool grid (group box with the Rarity
// tab, header and filter row, group rows collapsed, the yellow Count footer, the navigator) above
// and the collection grid (coloured rows, the green Rows footer, the navigator). The reference
// data_grid_main.png is the 500 x 468 crop of that capture at (292, 108); the sheet is that box.

const POOL_ROWS: usize = 120283usize
const PC_RARITY: usize = 0usize
const PC_KEY: usize = 1usize
const CC_NAME: usize = 0usize
const CC_EDITION: usize = 1usize
const CC_QTY: usize = 2usize
const CC_USED: usize = 3usize
const CC_BUY: usize = 4usize

type Main = struct {
    a: *mem.Arena,
    ready: bool,
    windows: bool,
    pool: table.Table,
    pool_view: view.View,
    pool_group: grp.Grouping,
    coll: table.Table,
    coll_view: view.View,
    coll_group: grp.Grouping,
    scratch: mem.Arena,
    store: mem.Arena,
    pool_grid: dg.Grid,
    coll_grid: dg.Grid
}

fn rarity_letter(row: usize) -> str {
    let p = mix(u64(row) + 3u64) % 7u64
    if p == 0u64 { ret "B" }
    if p == 1u64 { ret "C" }
    if p == 2u64 { ret "M" }
    if p == 3u64 { ret "R" }
    if p == 4u64 { ret "S" }
    if p == 5u64 { ret "T" }
    ret "U"
}

fn load_pool(a: *mem.Arena, m: *Main) -> err {
    var spec: [2]table.Spec = zero
    spec[PC_RARITY] = table.Spec { name: "Rarity", kind: table.Kind.Dict, heap_bytes: 256usize, dict_cap: 8usize }
    spec[PC_KEY] = table.Spec { name: "Key", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    let (made, made_error) = table.create(a, spec[0..], POOL_ROWS)
    if made_error != ok { ret made_error }
    m.pool = made
    table.begin_load(&m.pool)
    var row = 0usize
    while row < POOL_ROWS {
        let (got, append_error) = table.append_row(&m.pool)
        if append_error != ok { ret append_error }
        try table.set_str(&m.pool, PC_RARITY, got, rarity_letter(row))
        table.set_i32(&m.pool, PC_KEY, got, i32(row))
        row += 1usize
    }
    table.end_load(&m.pool)
    ret ok
}

fn coll_name(row: usize) -> str {
    if row == 0usize { ret "Forest [Default Frame]" }
    if row == 1usize { ret "Terminate" }
    if row == 2usize { ret "Tangle" }
    if row == 3usize { ret "Silkguard" }
    if row == 4usize { ret "Parallel Lives" }
    if row == 5usize { ret "Hunter's Insight" }
    if row == 6usize { ret "Heroic Intervention" }
    ret "Beast Within"
}

fn load_coll(a: *mem.Arena, m: *Main) -> err {
    var spec: [5]table.Spec = zero
    spec[CC_NAME] = table.Spec { name: "Name", kind: table.Kind.Dict, heap_bytes: 512usize, dict_cap: 16usize }
    spec[CC_EDITION] = table.Spec { name: "Edition", kind: table.Kind.Dict, heap_bytes: 64usize, dict_cap: 4usize }
    spec[CC_QTY] = table.Spec { name: "Qty", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    spec[CC_USED] = table.Spec { name: "Used", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    spec[CC_BUY] = table.Spec { name: "Buy at", kind: table.Kind.F64, heap_bytes: 0usize, dict_cap: 0usize }
    let (made, made_error) = table.create(a, spec[0..], 8usize)
    if made_error != ok { ret made_error }
    m.coll = made
    let qty: [8]i32 = [8]i32{ 1, 104, 151, 82, 34, 43, 29, 6 }
    let used: [8]i32 = [8]i32{ 0, 4, 6, 1, 6, 0, 2, 0 }
    table.begin_load(&m.coll)
    var row = 0usize
    while row < 8usize {
        let (got, append_error) = table.append_row(&m.coll)
        if append_error != ok { ret append_error }
        try table.set_str(&m.coll, CC_NAME, got, coll_name(row))
        if row == 0usize { try table.set_str(&m.coll, CC_EDITION, got, "TMT") } else { try table.set_str(&m.coll, CC_EDITION, got, "MAR") }
        table.set_i32(&m.coll, CC_QTY, got, qty[row])
        if used[row] == 0 { table.set_null(&m.coll, CC_USED, got) } else { table.set_i32(&m.coll, CC_USED, got, used[row]) }
        table.set_null(&m.coll, CC_BUY, got)
        row += 1usize
    }
    table.end_load(&m.coll)
    ret ok
}

// The ink of a collection row (card colour: colourless, multicolour, green).
fn coll_ink(ctx: *void, row: usize) -> (paint.Color, bool) {
    var letter = 71u8
    if row == 0usize { letter = 78u8 }
    if row == 1usize { letter = 77u8 }
    if row == 2usize || row == 3usize { letter = 66u8 }
    let (ink, has_ink) = gl.card_ink(letter)
    ret (ink, has_ink)
}

// The icon column: v3's orange card-back disc (the real picture is not in this repo).
fn coll_cell(ctx: *void, a: *mem.Arena, t: *const control.Theme, row: usize, spec: usize, out: *widget.Node) -> err {
    var disc = style.defaults()
    disc.width = style.Length { Px: 15.0 }
    disc.height = style.Length { Px: 15.0 }
    disc.radius = 7.5
    disc.background = paint.Brush { Solid: gl.rgb(0xF9BA7Eu32) }
    if row == 0usize { disc.background = paint.Brush { Solid: gl.rgb(0x222222u32) } }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret held_error }
    held[0usize] = widget.spacer(0u64, 0.0)
    *out = widget.padded(0u64, 0.0, 0.0, 0.0, 0.0, disc, held[0usize..1usize])
    ret ok
}

fn pool_specs(a: *mem.Arena) -> ([]dg.ColumnSpec, err) {
    let (specs, specs_error) = mem.alloc[dg.ColumnSpec](a, 9usize)
    if specs_error != ok { ret (zero, specs_error) }
    let sk = grp.SummaryKind.Rows
    specs[0usize] = dg.ColumnSpec { title: "", width: 12.0, column: PC_KEY, kind: dg.CellKind.Indicator, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[1usize] = dg.ColumnSpec { title: "Favorite", width: 38.0, column: PC_KEY, kind: dg.CellKind.Star, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[2usize] = dg.ColumnSpec { title: "ES", width: 21.0, column: PC_RARITY, kind: dg.CellKind.Picture, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[3usize] = dg.ColumnSpec { title: "Legal", width: 75.0, column: PC_RARITY, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: true, editable: false, choice: false }
    specs[4usize] = dg.ColumnSpec { title: "Name", width: 150.0, column: PC_RARITY, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: true, editable: false, choice: false }
    specs[5usize] = dg.ColumnSpec { title: "Edition", width: 70.0, column: PC_RARITY, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: true, editable: false, choice: false }
    specs[6usize] = dg.ColumnSpec { title: "Color", width: 60.0, column: PC_RARITY, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: true, editable: false, choice: false }
    specs[7usize] = dg.ColumnSpec { title: "Type", width: 54.0, column: PC_RARITY, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: true, editable: false, choice: false }
    // the columns v3 has beyond the pane (the capture's scroll thumb says the content is about 1315 px wide)
    specs[8usize] = dg.ColumnSpec { title: "Power", width: 817.0, column: PC_RARITY, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: true, editable: false, choice: false }
    ret (specs, ok)
}

fn coll_specs(a: *mem.Arena) -> ([]dg.ColumnSpec, err) {
    let (specs, specs_error) = mem.alloc[dg.ColumnSpec](a, 10usize)
    if specs_error != ok { ret (zero, specs_error) }
    let sk = grp.SummaryKind.Rows
    specs[0usize] = dg.ColumnSpec { title: "", width: 12.0, column: CC_NAME, kind: dg.CellKind.Indicator, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[1usize] = dg.ColumnSpec { title: "", width: 21.0, column: CC_EDITION, kind: dg.CellKind.Picture, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[2usize] = dg.ColumnSpec { title: "Name", width: 150.0, column: CC_NAME, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[3usize] = dg.ColumnSpec { title: "Edition", width: 70.0, column: CC_EDITION, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[4usize] = dg.ColumnSpec { title: "Qty", width: 50.0, column: CC_QTY, kind: dg.CellKind.Int, decimals: 0u8, summary: 0, summary_kind: grp.SummaryKind.Sum, filter: false, editable: false, choice: false }
    specs[5usize] = dg.ColumnSpec { title: "Used", width: 50.0, column: CC_USED, kind: dg.CellKind.Int, decimals: 0u8, summary: 1, summary_kind: grp.SummaryKind.Sum, filter: false, editable: false, choice: false }
    specs[6usize] = dg.ColumnSpec { title: "Buy at", width: 65.0, column: CC_BUY, kind: dg.CellKind.Currency, decimals: 2u8, summary: 2, summary_kind: grp.SummaryKind.Sum, filter: false, editable: false, choice: false }
    specs[7usize] = dg.ColumnSpec { title: "Sell at", width: 65.0, column: CC_BUY, kind: dg.CellKind.Currency, decimals: 2u8, summary: 2, summary_kind: grp.SummaryKind.Sum, filter: false, editable: false, choice: false }
    specs[8usize] = dg.ColumnSpec { title: "Se", width: 12.0, column: CC_BUY, kind: dg.CellKind.Currency, decimals: 2u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[9usize] = dg.ColumnSpec { title: "Set", width: 1595.0, column: CC_BUY, kind: dg.CellKind.Currency, decimals: 2u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    ret (specs, ok)
}

fn setup_main(m: *Main, windows: bool) -> err {
    let a = m.a
    try load_pool(a, m)
    try load_coll(a, m)
    let (scratch_bytes, scratch_error) = mem.alloc[u8](a, 16777216usize)
    if scratch_error != ok { ret scratch_error }
    m.scratch = mem.arena_from(scratch_bytes)
    let (store_bytes, store_error) = mem.alloc[u8](a, 65536usize)
    if store_error != ok { ret store_error }
    m.store = mem.arena_from(store_bytes)
    let (pv, pv_error) = view.create(a, &m.pool)
    if pv_error != ok { ret pv_error }
    m.pool_view = pv
    let (pg, pg_error) = grp.create(a, &m.pool_view, 16usize)
    if pg_error != ok { ret pg_error }
    m.pool_group = pg
    var levels: [1]grp.GroupLevel = zero
    levels[0usize] = grp.GroupLevel { column: PC_RARITY, descending: false, fold: true }
    var key: [1]view.Key = zero
    key[0usize] = view.column_key(PC_KEY, false, true)
    try grp.group_by(&m.pool_group, levels[0usize..1usize], key[0usize..1usize], &m.scratch)
    var pool_sum: [1]grp.SummarySpec = zero
    pool_sum[0usize] = grp.SummarySpec { column: PC_KEY }
    try grp.apply_summaries(&m.pool_group, pool_sum[0usize..1usize], &m.store)
    let (cv, cv_error) = view.create(a, &m.coll)
    if cv_error != ok { ret cv_error }
    m.coll_view = cv
    let (cg, cg_error) = grp.create(a, &m.coll_view, 8usize)
    if cg_error != ok { ret cg_error }
    m.coll_group = cg
    var none: [1]grp.GroupLevel = zero
    var order: [1]view.Key = zero
    order[0usize] = view.column_key(CC_QTY, false, true)
    try grp.group_by(&m.coll_group, none[0usize..0usize], order[0usize..0usize], &m.scratch)
    var sums: [3]grp.SummarySpec = zero
    sums[0usize] = grp.SummarySpec { column: CC_QTY }
    sums[1usize] = grp.SummarySpec { column: CC_USED }
    sums[2usize] = grp.SummarySpec { column: CC_BUY }
    try grp.apply_summaries(&m.coll_group, sums[0usize..3usize], &m.store)
    let (ps, ps_error) = pool_specs(a)
    if ps_error != ok { ret ps_error }
    let (g1, g1_error) = dg.create(a, &m.pool, &m.pool_group, ps, dg.no_events(), 100u64)
    if g1_error != ok { ret g1_error }
    m.pool_grid = g1
    var pool_look = gl.v3()
    // looks9-w1 (Windows only, in the grid): the live footer cells' edge pixels and the frame ring's colours along the left side
    pool_look.footer_edges = true
    pool_look.group_rect = true
    if windows {
        // round 13: the live pool grid's bar starts over the group box and its thumb is 88 px; the navigator thumb is 91 px of body
        pool_look.bar_up = 34.0
        pool_look.hthumb_adj = 0.0 - 2.0
        pool_look.hthumb_dx = 1.0
        pool_look.hthumb_flat = true
        pool_look.thumb_len = 88.0
    }
    pool_look.soft_a0 = 0.75
    pool_look.soft_x0 = 183.0
    pool_look.soft_slope = 0.0 - 0.0005
    pool_look.nav_rule = true
    pool_look.ring_marks = "0 1 1 999ca0;0 2 161 9599a0;0 163 1 8e9299;0 164 49 878b93;1 1 1 8d9096;1 2 1 bbbdc1;1 3 34 dddedf;1 37 1 e5e5e7;1 38 128 eaeaec;1 166 1 e5e7eb;1 167 21 e0e4e9;1 188 1 c5c8cb;1 189 1 c5c5c7;1 190 23 dddedf;479 2 34 f8f8f8;480 2 34 f7f7f7;487 18 1 d1d1d1;487 19 1 b9b9b9;487 20 16 b6b6b6;488 18 1 b7b7b7;488 19 1 8a8a8a;488 20 16 858585;489 18 1 d6d6d6;489 19 1 c1c1c1;489 20 16 bfbfbf;67 212 1 bfc2c6;68 212 1 c1c3c8 69;137 212 1 bbbec2;479 36 1 fcfcfc;480 36 1 f7f7f7;481 36 1 f0f0f0 6;487 36 1 b6b6b6;488 36 1 858585;489 36 1 bfbfbf;490 36 1 f0f0f0 6"
    dg.set_look(&m.pool_grid, pool_look)
    dg.show_filter_row(&m.pool_grid, true)
    dg.show_group_box(&m.pool_grid, true)
    dg.show_navigator(&m.pool_grid, true)
    dg.set_pane_hint(&m.pool_grid, 493.0)
    if windows { dg.set_pane_hint(&m.pool_grid, 494.0) }
    dg.set_count_column(&m.pool_grid, 4usize)
    dg.set_footer_label(&m.pool_grid, "Count")
    dg.show_sort(&m.pool_grid, 5usize, true)
    // v3 opens on the first group row: the arrow in the indicator, the dotted rectangle, "1 of n"
    m.pool_grid.has_position = true
    m.pool_grid.position = 0usize
    let (cs, cs_error) = coll_specs(a)
    if cs_error != ok { ret cs_error }
    var events = dg.no_events()
    events.custom_cell = coll_cell
    let (g2, g2_error) = dg.create(a, &m.coll, &m.coll_group, cs, events, 20000u64)
    if g2_error != ok { ret g2_error }
    m.coll_grid = g2
    var look = gl.v3()
    look.footer_band = gl.rgb(0xC0DCC0u32)
    // the collection grid's frame (live capture): lighter top, darker left, white rows inside
    look.ring_top_o = gl.rgb(0xBABDC1u32)
    look.ring_top_i = gl.rgb(0xBFC2C6u32)
    look.ring_left_o = gl.rgb(0x878B93u32)
    look.ring_left_i = gl.rgb(0xEAEAECu32)
    look.ring_bottom = gl.rgb(0xCACCCFu32)
    look.footer_edges = true
    if windows { look.hthumb_adj = 0.0 - 1.0 }
    look.soft_a0 = 0.75
    look.soft_x0 = 183.0
    look.soft_slope = 0.0 - 0.0005
    // round 13: the position field's foot row (live main window)
    look.bar_marks = "67 241 1 d2d4d7;68 241 1 d4d6d9 39;107 241 1 ccced1"
    look.ring_marks = "0 1 79 878b93;0 80 1 8d9199;0 81 160 9599a0;1 1 1 b5b8bd;1 2 192 eaeaec;1 194 1 e6e8eb;1 195 21 e0e4e9;1 216 1 cdd0d4;1 217 1 bdbec0;1 218 23 dddedf"
    dg.set_look(&m.coll_grid, look)
    dg.set_row_ink(&m.coll_grid, mem.cast[*void](m), coll_ink)
    dg.set_footer_label(&m.coll_grid, "Rows")
    dg.set_grid_lines(&m.coll_grid, dg.GridLines.Both)
    dg.set_immediate_edit(&m.coll_grid, true)
    dg.show_navigator(&m.coll_grid, true)
    dg.set_pane_hint(&m.coll_grid, 493.0)
    dg.show_sort(&m.coll_grid, 1usize, true)
    // v3 centres Edition, Qty and Used (the Alignment popup centre, aligns[origin] == 2)
    m.coll_grid.aligns[3usize] = 2u8
    m.coll_grid.aligns[4usize] = 2u8
    m.coll_grid.aligns[5usize] = 2u8
    ret ok
}

// A grid at the width and height it has in the capture, on the form's face.
fn boxed(a: *mem.Arena, t: *const control.Theme, grid: *dg.Grid, w: f32, h: f32) -> (widget.Node, err) {
    let (body, body_error) = dg.build(a, grid, t, h + 25.0)
    if body_error != ok { ret (zero, body_error) }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = body
    var wrap = looks.size_style(w, h)
    wrap.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, wrap, held[0usize..1usize]), ok)
}

fn build_main(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let m = mem.cast[*Main](ctx)
    if m.ready && m.windows != (t.tokens.profile == .Windows) { m.ready = false }
    if !m.ready {
        try setup_main(m, t.tokens.profile == .Windows)
        m.ready = true
        m.windows = t.tokens.profile == .Windows
    }
    if t.tokens.profile != .Windows {
    }
    var upper_h: f32 = 213.0
    var gap_h: f32 = 8.0
    if t.tokens.profile == .Windows {
        upper_h = 214.0
        gap_h = 7.0
    }
    let (upper, upper_error) = boxed(a, t, &m.pool_grid, 497.0, upper_h)
    if upper_error != ok { ret (0usize, upper_error) }
    var lower_h: f32 = 242.0
    if t.tokens.profile == .Windows { lower_h = 243.0 }
    let (lower, lower_error) = boxed(a, t, &m.coll_grid, 576.0, lower_h)
    if lower_error != ok { ret (0usize, lower_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (0usize, parts_error) }
    parts[0usize] = upper
    parts[1usize] = lower
    var face = looks.size_style(500.0, 468.0)
    // round 12: the live panes are 576 wide and the reference is their left 500 px
    face.overflow = .Clip
    face.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    face.padding = style.EdgeLengths { left: style.Length { Px: 3.0 }, top: style.Length { Px: 1.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    cells[0usize] = looks.Cell { caption: "Pool and collection grids as in the v3 main window", node: widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: gap_h }, face, parts[0usize..2usize]), drive: .None }
    ret (1usize, ok)
}

// ---- sheet 3: data_grid_states, the top grid of the live main window in its interaction states ------------------
// docs/ui/looks/ref/windows/states/grid-row-selected-focused-main@1x.png (576 x 179 crop at (216, 109)): a card pool as data
// rows (no group box, filter row or navigator in view), the fourth row selected with the focus rectangle. The harness taps the
// centre of the cell, which falls on that row.

const SC_NAME: usize = 0usize
const SC_ED: usize = 1usize
const SC_COLOR: usize = 2usize
const SC_TYPE: usize = 3usize
const SC_RARITY: usize = 4usize
const SC_FAV: usize = 5usize

type States = struct { a: *mem.Arena, ready: bool, windows: bool, tbl: table.Table, view: view.View, group: grp.Grouping, scratch: mem.Arena, grid: dg.Grid }

fn state_row(row: usize, col: usize) -> str {
    if col == SC_ED { ret "MBC" }
    if col == SC_COLOR { ret "N" }
    if col == SC_TYPE {
        if row == 0usize || row == 1usize { ret "Land" }
        if row == 3usize { ret "Artifact — Equipment" }
        ret "Artifact"
    }
    if col == SC_RARITY {
        if row == 0usize { ret "C" }
        if row == 1usize { ret "R" }
        ret "U"
    }
    if row == 0usize { ret "Path of Ancestry" }
    if row == 1usize { ret "Exotic Orchard" }
    if row == 2usize { ret "Thought Vessel" }
    if row == 3usize { ret "Swiftfoot Boots" }
    if row == 4usize { ret "Mind Stone" }
    if row == 5usize { ret "Jeweled Amulet" }
    if row == 6usize { ret "Fellwar Stone" }
    if row == 7usize { ret "Chromatic Lantern" }
    ret "Sol Ring"
}

// the pool's rows are colourless cards: v3 draws them in grey
fn state_ink(ctx: *void, row: usize) -> (paint.Color, bool) {
    let (ink, has_ink) = gl.card_ink(78u8)
    ret (ink, has_ink)
}

// every card of the capture is colourless: the grey of card colour N
fn states_ink(ctx: *void, row: usize) -> (paint.Color, bool) {
    let (ink, has_ink) = gl.card_ink(78u8)
    ret (ink, has_ink)
}

fn setup_states(s: *States, windows: bool) -> err {
    let a = s.a
    var spec: [6]table.Spec = zero
    spec[SC_FAV] = table.Spec { name: "Fav", kind: table.Kind.Bool, heap_bytes: 0usize, dict_cap: 0usize }
    spec[SC_NAME] = table.Spec { name: "Name", kind: table.Kind.Dict, heap_bytes: 1024usize, dict_cap: 16usize }
    spec[SC_ED] = table.Spec { name: "Edition", kind: table.Kind.Dict, heap_bytes: 64usize, dict_cap: 4usize }
    spec[SC_COLOR] = table.Spec { name: "Color", kind: table.Kind.Dict, heap_bytes: 64usize, dict_cap: 4usize }
    spec[SC_TYPE] = table.Spec { name: "Type", kind: table.Kind.Dict, heap_bytes: 256usize, dict_cap: 8usize }
    spec[SC_RARITY] = table.Spec { name: "Rarity", kind: table.Kind.Dict, heap_bytes: 64usize, dict_cap: 4usize }
    let (made, made_error) = table.create(a, spec[0..], 14usize)
    if made_error != ok { ret made_error }
    s.tbl = made
    table.begin_load(&s.tbl)
    var row = 0usize
    while row < 14usize {
        let (got, append_error) = table.append_row(&s.tbl)
        if append_error != ok { ret append_error }
        var col = 0usize
        while col < 5usize {
            try table.set_str(&s.tbl, col, got, state_row(row, col))
            col += 1usize
        }
        table.set_bool(&s.tbl, SC_FAV, got, false)
        row += 1usize
    }
    table.end_load(&s.tbl)
    let (scratch_bytes, scratch_error) = mem.alloc[u8](a, 1048576usize)
    if scratch_error != ok { ret scratch_error }
    s.scratch = mem.arena_from(scratch_bytes)
    let (v, v_error) = view.create(a, &s.tbl)
    if v_error != ok { ret v_error }
    s.view = v
    let (g, g_error) = grp.create(a, &s.view, 8usize)
    if g_error != ok { ret g_error }
    s.group = g
    var none: [1]grp.GroupLevel = zero
    var order: [1]view.Key = zero
    order[0usize] = view.column_key(SC_NAME, false, true)
    try grp.group_by(&s.group, none[0usize..0usize], order[0usize..0usize], &s.scratch)
    let (specs, specs_error) = mem.alloc[dg.ColumnSpec](a, 9usize)
    if specs_error != ok { ret specs_error }
    let sk = grp.SummaryKind.Rows
    specs[0usize] = dg.ColumnSpec { title: "", width: 12.0, column: SC_NAME, kind: dg.CellKind.Indicator, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[1usize] = dg.ColumnSpec { title: "Favorite", width: 23.0, column: SC_FAV, kind: dg.CellKind.Star, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[2usize] = dg.ColumnSpec { title: "", width: 21.0, column: SC_NAME, kind: dg.CellKind.Picture, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[3usize] = dg.ColumnSpec { title: "Name", width: 150.0, column: SC_NAME, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[4usize] = dg.ColumnSpec { title: "Edition", width: 70.0, column: SC_ED, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[5usize] = dg.ColumnSpec { title: "Color", width: 60.0, column: SC_COLOR, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[6usize] = dg.ColumnSpec { title: "Type", width: 150.0, column: SC_TYPE, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[7usize] = dg.ColumnSpec { title: "Rarity", width: 50.0, column: SC_RARITY, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[8usize] = dg.ColumnSpec { title: "", width: 24.0, column: SC_NAME, kind: dg.CellKind.Picture, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    let (g1, g1_error) = dg.create(a, &s.tbl, &s.group, specs[0usize..9usize], dg.no_events(), 300u64)
    if g1_error != ok { ret g1_error }
    s.grid = g1
    var look = gl.v3()
    look.header_height = 22.0
    look.ring_top_i = gl.rgb(0xD0D2D5u32)
    look.ring_left_o = gl.rgb(0x90949Cu32)
    look.ring_left_i = gl.rgb(0xEFF0F1u32)
    if windows {
        // looks9-w1: the live top grid's foot pixels and column lines (states/grid-row-selected-focused-main)
        look.foot_set = true
        look.foot_drift = 1.0
        look.foot_g1 = gl.rgb(0xE3E3E3u32)
        look.foot_g2 = gl.rgb(0xF2F2F2u32)
        look.foot_w1 = gl.rgb(0xE9E9E9u32)
        look.foot_w2 = gl.rgb(0xE8E8E8u32)
        look.soft_a0 = 0.75
        look.soft_x0 = 206.0
        look.soft_slope = 0.0 - 0.00055
    }
    dg.set_look(&s.grid, look)
    if windows { dg.set_grid_lines(&s.grid, dg.GridLines.Both) }
    dg.set_row_ink(&s.grid, mem.cast[*void](s), state_ink)
    s.grid.aligns[4usize] = 2u8
    s.grid.aligns[5usize] = 2u8
    s.grid.aligns[7usize] = 2u8
    ret ok
}

// looks9-w1: the Windows grid's frame ring is 3 px (2 on top, 1 under): a grid asked for the cell's whole height would be squeezed by
// that much, header and rows alike (a flex shrinks its children), so the body is asked for the rest
fn ring_free(t: *const control.Theme, height: f32) -> f32 {
    if t.tokens.profile == .Windows { ret height - 3.0 }
    ret height
}

fn build_states(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let s = mem.cast[*States](ctx)
    if s.ready && s.windows != (t.tokens.profile == .Windows) { s.ready = false }
    if !s.ready {
        try setup_states(s, t.tokens.profile == .Windows)
        s.ready = true
        s.windows = t.tokens.profile == .Windows
    }
    let (body, body_error) = dg.build(a, &s.grid, t, ring_free(t, 179.0))
    if body_error != ok { ret (0usize, body_error) }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (0usize, held_error) }
    held[0usize] = body
    var face = looks.size_style(576.0, 179.0)
    face.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    cells[0usize] = looks.Cell { caption: "Top grid of the live main window: selected focused row", node: widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, face, held[0usize..1usize]), drive: .Focus }
    ret (1usize, ok)
}

// the same grid, only its header in view: the harness presses the Name header (the cell's centre)
fn build_states_pressed(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let s = mem.cast[*States](ctx)
    if s.ready && s.windows != (t.tokens.profile == .Windows) { s.ready = false }
    if !s.ready {
        try setup_states(s, t.tokens.profile == .Windows)
        s.ready = true
        s.windows = t.tokens.profile == .Windows
    }
    let (body, body_error) = dg.build(a, &s.grid, t, ring_free(t, 101.0))
    if body_error != ok { ret (0usize, body_error) }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (0usize, held_error) }
    held[0usize] = body
    var face = looks.size_style(892.0, 179.0)
    face.padding = style.EdgeLengths { left: style.Length { Px: 316.0 }, top: style.Length { Px: 78.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    face.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    cells[0usize] = looks.Cell { caption: "Top grid of the live main window: pressed header (Name)", node: widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, face, held[0usize..1usize]), drive: .Press }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize {
        // `data_grid.exe states`: the states sheet alone (every sheet takes its own rigs; one run holds only so many)
        let (only, only_error) = mem.alloc[States](a, 1usize)
        if only_error != ok { ret only_error }
        var only_seed: States = zero
        only_seed.a = a
        only[0usize] = only_seed
        if strs.eq(args[1usize], "pressed") {
            let (held_s, held_s_error) = mem.alloc[States](a, 1usize)
            if held_s_error != ok { ret held_s_error }
            var held_seed: States = zero
            held_seed.a = a
            held_s[0usize] = held_seed
            let pressed = looks.Sheet { name: "data_grid_states_pressed", cells: 1usize, columns: 1usize, cell_w: 892.0, cell_h: 179.0, ctx: mem.cast[*void](&held_s[0usize]), build: build_states_pressed }
            ret looks.run_all(a, &pressed)
        }
        let quick = looks.Sheet { name: "data_grid_states", cells: 1usize, columns: 1usize, cell_w: 576.0, cell_h: 179.0, ctx: mem.cast[*void](&only[0usize]), build: build_states }
        ret looks.run_all(a, &quick)
    }
    let (apps, apps_error) = mem.alloc[App](a, 1usize)
    if apps_error != ok { ret apps_error }
    var seed: App = zero
    seed.a = a
    apps[0usize] = seed
    let sheet = looks.Sheet { name: "data_grid", cells: 2usize, columns: 2usize, cell_w: 460.0, cell_h: 300.0, ctx: mem.cast[*void](&apps[0usize]), build: build }
    try looks.run_all(a, &sheet)
    let (mains, mains_error) = mem.alloc[Main](a, 1usize)
    if mains_error != ok { ret mains_error }
    var mseed: Main = zero
    mseed.a = a
    mains[0usize] = mseed
    let second = looks.Sheet { name: "data_grid_main", cells: 1usize, columns: 1usize, cell_w: 500.0, cell_h: 468.0, ctx: mem.cast[*void](&mains[0usize]), build: build_main }
    ret looks.run_all(a, &second)
}
