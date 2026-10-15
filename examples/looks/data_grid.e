// The data grid under every look: docs/ui/looks/<look>/data_grid.png. The Windows look is the
// measured v3 TcxGrid (`gridlook.v3()`, docs/grid-parity); the Neper look is the theme's own grid.
// Run from the repository root; see docs/ui/looks-howto.md.
//
// Two grids over one table. Left: a flat list with the filter row, alternating stripes, a selected
// row (the harness taps the cell's centre) and a vertical scroll bar. Right: grouped by rarity, two
// groups open, group rows, footer summaries.

use e.data.table as table
use e.data.tablegroup as grp
use e.data.tableview as view
use e.gfx.paint
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
    if !app.ready {
        try setup(app)
        app.ready = true
    }
    let (left, left_error) = framed(a, t, &app.list_grid, 460.0, 300.0)
    if left_error != ok { ret (0usize, left_error) }
    let (right, right_error) = framed(a, t, &app.group_grid, 460.0, 300.0)
    if right_error != ok { ret (0usize, right_error) }
    cells[0usize] = looks.Cell { caption: "List: filter row, stripes, selected row, scroll bar", node: left, drive: .Focus }
    cells[1usize] = looks.Cell { caption: "Grouped: group rows, summary footer", node: right, drive: .None }
    ret (2usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (apps, apps_error) = mem.alloc[App](a, 1usize)
    if apps_error != ok { ret apps_error }
    var seed: App = zero
    seed.a = a
    apps[0usize] = seed
    let sheet = looks.Sheet { name: "data_grid", cells: 2usize, columns: 2usize, cell_w: 460.0, cell_h: 300.0, ctx: mem.cast[*void](&apps[0usize]), build: build }
    ret looks.run_all(a, &sheet)
}
