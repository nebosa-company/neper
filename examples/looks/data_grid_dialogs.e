// The grids inside v3's dialogs, under the Windows look (the Neper look gets the theme's own grid):
// docs/ui/looks/<look>/data_grid_dialogs.png. Run from the repository root.
//
// Left: the Sort dialog's grid (view-sort@1x.png, TcxGrid 331 x 259 with the Column and Sort Order
// columns). Right: the Missing Set Cards dialog's edition list (reports-missing-set-cards@1x.png,
// 234 x 256, one column, each row in the edition's own colour, the first row selected). The
// references are the crops ref/windows/data_grid_sort.png and data_grid_missing.png; the grid look
// is gridlook.v3() as the main window sheet uses it, with the dialog font, no indicator, filter
// row, navigator or footer.

use e.data.table as table
use e.data.tablegroup as grp
use e.data.tableview as view
use e.gfx.paint
use e.ui.gridlook as gl
use e.ui.layout as ui_layout
use e.mem
use e.ui.control
use e.ui.datagrid as dg
use e.ui.looks
use e.ui.style
use e.ui.widget

const SORT_ROWS: usize = 20usize
const MISSING_ROWS: usize = 14usize

type App = struct {
    a: *mem.Arena,
    ready: bool,
    sort_table: table.Table,
    sort_view: view.View,
    sort_group: grp.Grouping,
    sort_grid: dg.Grid,
    miss_table: table.Table,
    miss_view: view.View,
    miss_group: grp.Grouping,
    miss_grid: dg.Grid,
    scratch: mem.Arena
}

fn sort_name(row: usize) -> str {
    if row == 0usize { ret "Favorite" }
    if row == 1usize { ret "ES" }
    if row == 2usize { ret "Name" }
    if row == 3usize { ret "Legal" }
    if row == 4usize { ret "Edition" }
    if row == 5usize { ret "Color" }
    if row == 6usize { ret "Type" }
    if row == 7usize { ret "Rarity" }
    if row == 8usize { ret "Cost" }
    if row == 9usize { ret "P/T" }
    if row == 10usize { ret "Text" }
    if row == 11usize { ret "Flavor" }
    if row == 12usize { ret "Artist" }
    if row == 13usize { ret "Power" }
    if row == 14usize { ret "Toughness" }
    if row == 15usize { ret "Loyalty" }
    if row == 16usize { ret "Number" }
    if row == 17usize { ret "Layout" }
    if row == 18usize { ret "Price" }
    ret "Quantity"
}

// The Sort Order cell: the sort glyph's slot (about 40 px) is blank spaces here.
fn sort_order(row: usize) -> str {
    if row == 4usize { ret "           Descending" }
    if row == 7usize { ret "           Ascending" }
    ret "           None"
}

fn miss_name(row: usize) -> str {
    if row == 0usize { ret "Mystery Booster Commander Edition" }
    if row == 1usize { ret "Reality Fracture" }
    if row == 2usize { ret "Reality Fracture Commander" }
    if row == 3usize { ret "The Zeta Set" }
    if row == 4usize { ret "The Hobbit" }
    if row == 5usize { ret "The Hobbit Eternal" }
    if row == 6usize { ret "Marvel Super Heroes" }
    if row == 7usize { ret "Marvel Super Heroes Commander" }
    if row == 8usize { ret "Secrets of Strixhaven" }
    if row == 9usize { ret "Secrets of Strixhaven Commander" }
    if row == 10usize { ret "Secrets of Strixhaven Mystical Archive" }
    if row == 11usize { ret "Teenage Mutant Ninja Turtles" }
    if row == 12usize { ret "Teenage Mutant Ninja Turtles Eternal" }
    ret "Teenage Mutant Ninja Turtles Commander"
}

fn miss_ink(ctx: *void, row: usize) -> (paint.Color, bool) {
    var rgb = 0xFF0000u32
    if row == 0usize { rgb = 0xFF00FFu32 }
    if row == 2usize || row == 7usize || row == 9usize { rgb = 0x0000FFu32 }
    if row == 3usize { rgb = 0xD2691Eu32 }
    if row == 10usize { rgb = 0xFF7F50u32 }
    ret (gl.rgb(rgb), true)
}

fn load(a: *mem.Arena, app: *App) -> err {
    var spec: [2]table.Spec = zero
    spec[0usize] = table.Spec { name: "Column", kind: table.Kind.Dict, heap_bytes: 512usize, dict_cap: 32usize }
    spec[1usize] = table.Spec { name: "Order", kind: table.Kind.Dict, heap_bytes: 512usize, dict_cap: 8usize }
    let (made, made_error) = table.create(a, spec[0..], SORT_ROWS)
    if made_error != ok { ret made_error }
    app.sort_table = made
    table.begin_load(&app.sort_table)
    var row = 0usize
    while row < SORT_ROWS {
        let (got, append_error) = table.append_row(&app.sort_table)
        if append_error != ok { ret append_error }
        try table.set_str(&app.sort_table, 0usize, got, sort_name(row))
        try table.set_str(&app.sort_table, 1usize, got, sort_order(row))
        row += 1usize
    }
    table.end_load(&app.sort_table)
    var spec_two: [1]table.Spec = zero
    spec_two[0usize] = table.Spec { name: "Edition", kind: table.Kind.Dict, heap_bytes: 1024usize, dict_cap: 32usize }
    let (made_two, made_two_error) = table.create(a, spec_two[0..], MISSING_ROWS)
    if made_two_error != ok { ret made_two_error }
    app.miss_table = made_two
    table.begin_load(&app.miss_table)
    row = 0usize
    while row < MISSING_ROWS {
        let (got, append_error) = table.append_row(&app.miss_table)
        if append_error != ok { ret append_error }
        try table.set_str(&app.miss_table, 0usize, got, miss_name(row))
        row += 1usize
    }
    table.end_load(&app.miss_table)
    ret ok
}

fn plain_grid(row_height: f32, a: *mem.Arena, tbl: *table.Table, v: *view.View, g: *grp.Grouping, scratch: *mem.Arena, specs: []const dg.ColumnSpec, id: u64) -> (dg.Grid, err) {
    let (vv, vv_error) = view.create(a, tbl)
    if vv_error != ok { ret (zero, vv_error) }
    *v = vv
    let (gg, gg_error) = grp.create(a, v, 8usize)
    if gg_error != ok { ret (zero, gg_error) }
    *g = gg
    var none: [1]grp.GroupLevel = zero
    var order: [1]view.Key = zero
    order[0usize] = view.column_key(0usize, false, true)
    try grp.group_by(g, none[0usize..0usize], order[0usize..0usize], scratch)
    let (made, made_error) = dg.create(a, tbl, g, specs, dg.no_events(), id)
    if made_error != ok { ret (zero, made_error) }
    var grid = made
    var look = gl.v3()
    look.text_size = 11.0
    look.header_height = 19.0
    look.header_line = gl.rgb(0xF4F4F4u32)
    look.frame_none = true
    look.row_height = row_height
    dg.set_look(&grid, look)
    dg.show_indicator(&grid, false)
    ret (grid, ok)
}

fn setup(app: *App) -> err {
    let a = app.a
    try load(a, app)
    let (scratch_bytes, scratch_error) = mem.alloc[u8](a, 1048576usize)
    if scratch_error != ok { ret scratch_error }
    app.scratch = mem.arena_from(scratch_bytes)
    let sk = grp.SummaryKind.Rows
    let (sort_specs, sort_specs_error) = mem.alloc[dg.ColumnSpec](a, 2usize)
    if sort_specs_error != ok { ret sort_specs_error }
    sort_specs[0usize] = dg.ColumnSpec { title: "Column", width: 156.0, column: 0usize, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    sort_specs[1usize] = dg.ColumnSpec { title: "Sort Order", width: 159.0, column: 1usize, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    let (sg, sg_error) = plain_grid(19.0, a, &app.sort_table, &app.sort_view, &app.sort_group, &app.scratch, sort_specs[0usize..2usize], 100u64)
    if sg_error != ok { ret sg_error }
    app.sort_grid = sg
    let (miss_specs, miss_specs_error) = mem.alloc[dg.ColumnSpec](a, 1usize)
    if miss_specs_error != ok { ret miss_specs_error }
    miss_specs[0usize] = dg.ColumnSpec { title: "Edition", width: 214.0, column: 0usize, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    let (mg, mg_error) = plain_grid(18.0, a, &app.miss_table, &app.miss_view, &app.miss_group, &app.scratch, miss_specs[0usize..1usize], 200u64)
    if mg_error != ok { ret mg_error }
    app.miss_grid = mg
    dg.set_row_ink(&app.miss_grid, zero, miss_ink)
    dg.set_forced_focus(&app.miss_grid, true)
    app.miss_grid.has_selection = true
    app.miss_grid.selected_row = 0usize
    app.miss_grid.has_position = true
    app.miss_grid.position = 0usize
    ret ok
}

// A grid at the box it has in the dialog, in the Tahoma theme under the Windows look.
fn boxed(a: *mem.Arena, t: *const control.Theme, grid: *dg.Grid, w: f32, h: f32) -> (widget.Node, err) {
    var use_theme = t
    if t.tokens.profile == .Windows {
        let (tahoma, tahoma_error) = control.windows_tahoma_theme(a, t, 11.0)
        if tahoma_error != ok { ret (zero, tahoma_error) }
        let (copies, copies_error) = mem.alloc[control.Theme](a, 1usize)
        if copies_error != ok { ret (zero, copies_error) }
        copies[0usize] = tahoma
        use_theme = &copies[0usize]
    }
    // the TcxGrid's frame: 1 px #828790 at the sides and below, #A7AAB0 over #D5D7DA at the top
    let (body, body_error) = dg.build(a, grid, use_theme, h - 3.0)
    if body_error != ok { ret (zero, body_error) }
    let (held, held_error) = mem.alloc[widget.Node](a, 3usize)
    if held_error != ok { ret (zero, held_error) }
    var top_a = looks.size_style(w - 2.0, 1.0)
    top_a.background = paint.Brush { Solid: gl.rgb(0xA7AAB0u32) }
    var top_b = looks.size_style(w - 2.0, 1.0)
    top_b.background = paint.Brush { Solid: gl.rgb(0xD5D7DAu32) }
    held[0usize] = widget.box(0u64, top_a, zero)
    held[1usize] = widget.box(0u64, top_b, zero)
    held[2usize] = body
    var inner = looks.size_style(w - 2.0, h - 1.0)
    inner.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, column_error) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, inner, held[0usize..3usize])
    var wrap = looks.size_style(w, h)
    wrap.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    if t.tokens.profile == .Windows { wrap.background = paint.Brush { Solid: gl.rgb(0x828790u32) } }
    wrap.padding = style.EdgeLengths { left: style.Length { Px: 1.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 1.0 }, bottom: style.Length { Px: 1.0 } }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, wrap, column[0usize..1usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let app = mem.cast[*App](ctx)
    if !app.ready {
        try setup(app)
        app.ready = true
    }
    let (left, left_error) = boxed(a, t, &app.sort_grid, 331.0, 259.0)
    if left_error != ok { ret (0usize, left_error) }
    let (right, right_error) = boxed(a, t, &app.miss_grid, 234.0, 256.0)
    if right_error != ok { ret (0usize, right_error) }
    cells[0usize] = looks.Cell { caption: "Sort dialog grid", node: left, drive: .None }
    // the cell is as large as the first one, the list at its top left, so both stand on whole pixels
    let (corner, corner_error) = mem.alloc[widget.Node](a, 1usize)
    if corner_error != ok { ret (0usize, corner_error) }
    corner[0usize] = right
    let holder = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, looks.size_style(331.0, 259.0), corner[0usize..1usize])
    cells[1usize] = looks.Cell { caption: "Missing Set Cards edition list", node: holder, drive: .None }
    ret (2usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (apps, apps_error) = mem.alloc[App](a, 1usize)
    if apps_error != ok { ret apps_error }
    var seed: App = zero
    seed.a = a
    apps[0usize] = seed
    let sheet = looks.Sheet { name: "data_grid_dialogs", cells: 2usize, columns: 2usize, cell_w: 331.0, cell_h: 259.0, ctx: mem.cast[*void](&apps[0usize]), build: build }
    ret looks.run_all(a, &sheet)
}
