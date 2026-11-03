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
use e.ui.dlggrid as dlg
use e.ui.gridlook as gl
use e.ui.layout as ui_layout
use e.mem
use e.ui.control
use e.ui.datagrid as dg
use e.ui.looks
use e.ui.style
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let app = mem.cast[*dlg.App](ctx)
    // the grids keep the look they were made with: another look's pass builds them afresh
    if app.ready && app.windows != (t.tokens.profile == .Windows) { app.ready = false }
    if !app.ready {
        app.windows = t.tokens.profile == .Windows
        try dlg.setup(app)
        app.ready = true
    }
    let (left, left_error) = dlg.boxed(a, t, &app.sort_grid, 331.0, 259.0, app.windows && app.light)
    if left_error != ok { ret (0usize, left_error) }
    let (right, right_error) = dlg.boxed(a, t, &app.miss_grid, 234.0, 256.0, app.windows && app.light)
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

// `data_grid_dialogs.exe sort`: the Sort dialog's grid with its Name row selected and focused (states/grid-row-selected-focused-sort),
// compared with ref/windows/data_grid_dialogs_sort.png (the grid's 331 x 259 box in that capture).
fn build_sort_selected(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let app = mem.cast[*dlg.App](ctx)
    if app.ready && (app.windows != (t.tokens.profile == .Windows) || app.light != (t.tokens.palette != .Dark)) { app.ready = false }
    if !app.ready {
        app.windows = t.tokens.profile == .Windows
        app.light = t.tokens.palette != .Dark
        try dlg.setup(app)
        app.ready = true
    }
    dg.set_forced_focus(&app.sort_grid, true)
    app.sort_grid.has_selection = true
    app.sort_grid.selected_row = 2usize
    let (left_boxed, left_error) = dlg.boxed(a, t, &app.sort_grid, 331.0, 259.0, app.windows && app.light)
    if left_error != ok { ret (0usize, left_error) }
    let left = left_boxed
    cells[0usize] = looks.Cell { caption: "Sort dialog grid: Name selected, focused", node: left, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (apps, apps_error) = mem.alloc[dlg.App](a, 1usize)
    if apps_error != ok { ret apps_error }
    var seed: dlg.App = zero
    seed.a = a
    apps[0usize] = seed
    if args.len > 1usize {
        let (held, held_error) = mem.alloc[dlg.App](a, 1usize)
        if held_error != ok { ret held_error }
        var held_seed: dlg.App = zero
        held_seed.a = a
        held[0usize] = held_seed
        let only = looks.Sheet { name: "data_grid_dialogs_sort", cells: 1usize, columns: 1usize, cell_w: 331.0, cell_h: 259.0, ctx: mem.cast[*void](&held[0usize]), build: build_sort_selected }
        ret looks.run_all(a, &only)
    }
    let sheet = looks.Sheet { name: "data_grid_dialogs", cells: 2usize, columns: 2usize, cell_w: 331.0, cell_h: 259.0, ctx: mem.cast[*void](&apps[0usize]), build: build }
    ret looks.run_all(a, &sheet)
}
