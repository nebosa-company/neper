// The Linux look's data grid against the real GTK 4.14 column view in a scrolled window: docs/ui/looks/linux[-dark]/data_grid.png. The
// library's picture is a two column view (Name, Detail) of six rows, the second chosen, in a 280 x 200 frame with the overlay scroll
// bar showing. Run from the repository root; see docs/ui/looks-howto.md. The strict compare is scripts/linux_cmp_l4.py.

use e.data.table as table
use e.data.tablegroup as grp
use e.data.tableview as view
use e.mem
use e.str as strs
use e.ui.control
use e.ui.datagrid as dg
use e.ui.looks
use e.ui.widget

const ROWS: usize = 6usize

type App = struct { a: *mem.Arena, ready: bool, tbl: table.Table, v: view.View, g: grp.Grouping, scratch: mem.Arena, grid: dg.Grid }

var app: App = zero

fn item_name(a: *mem.Arena, row: usize) -> str {
    let (b, b_error) = strs.builder(a, 16usize)
    if b_error != ok { ret "" }
    var sb = b
    if strs.push(&sb, "Item ") != ok || strs.push_usize(&sb, row) != ok { ret "" }
    ret strs.done(&sb)
}

fn setup(a: *mem.Arena) -> err {
    var spec: [2]table.Spec = zero
    spec[0] = table.Spec { name: "Name", kind: table.Kind.Dict, heap_bytes: 512usize, dict_cap: 8usize }
    spec[1] = table.Spec { name: "Detail", kind: table.Kind.Dict, heap_bytes: 64usize, dict_cap: 2usize }
    let (made, made_error) = table.create(a, spec[0..], ROWS)
    if made_error != ok { ret made_error }
    app.tbl = made
    let (names_bytes, names_error) = mem.alloc[u8](a, 1024usize)
    if names_error != ok { ret names_error }
    var names = mem.arena_from(names_bytes)
    table.begin_load(&app.tbl)
    var row = 0usize
    while row < ROWS {
        let (got, append_error) = table.append_row(&app.tbl)
        if append_error != ok { ret append_error }
        mem.reset(&names, 0usize)
        try table.set_str(&app.tbl, 0usize, got, item_name(&names, row))
        try table.set_str(&app.tbl, 1usize, got, "detail")
        row += 1usize
    }
    table.end_load(&app.tbl)
    let (view_made, view_error) = view.create(a, &app.tbl)
    if view_error != ok { ret view_error }
    app.v = view_made
    let (flat, flat_error) = grp.create(a, &app.v, 4usize)
    if flat_error != ok { ret flat_error }
    app.g = flat
    let (scratch_bytes, scratch_error) = mem.alloc[u8](a, 65536usize)
    if scratch_error != ok { ret scratch_error }
    app.scratch = mem.arena_from(scratch_bytes)
    var none: [1]grp.GroupLevel = zero
    var key: [1]view.Key = zero
    key[0usize] = view.column_key(0usize, false, true)
    try grp.group_by(&app.g, none[0usize..0usize], key[0usize..1usize], &app.scratch)
    var specs: [2]dg.ColumnSpec = zero
    specs[0usize] = dg.ColumnSpec { title: "Name", width: 56.0, column: 0usize, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: false, choice: false }
    specs[1usize] = dg.ColumnSpec { title: "Detail", width: 48.0, column: 1usize, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: grp.SummaryKind.Rows, filter: false, editable: false, choice: false }
    let (grid, grid_error) = dg.create(a, &app.tbl, &app.g, specs[0usize..2usize], dg.no_events(), 100u64)
    if grid_error != ok { ret grid_error }
    app.grid = grid
    app.grid.fill_width = 280.0
    app.grid.has_selection = true
    app.grid.selected_row = 1usize
    dg.set_mark(&app.grid, 1usize, true)
    ret ok
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    if !app.ready {
        try setup(app.a)
        app.ready = true
    }
    let (node, node_error) = dg.build(a, &app.grid, t, 198.0)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "rest", node: node, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    app.a = a
    let sheet = looks.Sheet { name: "data_grid", cells: 1usize, columns: 1usize, cell_w: 300.0, cell_h: 220.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
