// The spreadsheet (e.ui.sheet.sheet), docs/ui/looks/<look>/sheet.png in all ten looks. Lettered column headers over row
// numbers, a bold header row, a right-aligned number column, a merged title cell and a frozen first row and column.
// Cells: rest, a range selection, the cell editor open, hover, focus, pressed, a scrolled sheet, disabled. The sheet draws
// through the shared tokens (surface, outline variant, primary ring), so no look has a profile-specific shape; derived, not
// compared with a real spreadsheet.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.looks
use e.ui.sheet as sh
use e.ui.widget

var draft: [32]u8 = zero

fn texts(row: usize, col: usize) -> str {
    let head = [5]str{ "Card", "Qty", "Price", "Total", "Set" }
    let names = [6]str{ "Lightning Bolt", "Counterspell", "Llanowar Elves", "Swords to Plowshares", "Dark Ritual", "Birds of Paradise" }
    let qty = [6]str{ "4", "3", "4", "2", "1", "4" }
    let price = [6]str{ "1.25", "0.90", "0.40", "2.10", "0.75", "3.00" }
    let total = [6]str{ "5.00", "2.70", "1.60", "4.20", "0.75", "12.00" }
    let sets = [6]str{ "M11", "CMR", "M19", "STA", "LEB", "M12" }
    if row == 0usize { ret head[col % 5usize] }
    let r = (row - 1usize) % 6usize
    if col == 0usize { ret names[r] }
    if col == 1usize { ret qty[r] }
    if col == 2usize { ret price[r] }
    if col == 3usize { ret total[r] }
    ret sets[r]
}

var grouped: bool = false

fn source_cell(ctx: *void, row: usize, col: usize) -> sh.SheetCell {
    var c: sh.SheetCell = zero
    c.text = texts(row, col)
    if row == 0usize {
        c.style.bold = true
        c.style.filled = true
        c.style.fill = paint.rgba(0.5, 0.5, 0.5, 0.18)
        // Cupertino: the system fill (secondarySystemFill, 12 % of 787880), not a heavy grey band
        if grouped { c.style.fill = paint.rgba(0.47, 0.47, 0.5, 0.12) }
    }
    if row > 0usize && (col == 1usize || col == 2usize || col == 3usize) { c.style.align = .Right }
    if row == 5usize && col == 4usize { c.read_only = true }
    ret c
}

fn on_event(ctx: *void, e: sh.SheetEvent) -> err { ret ok }

fn one(a: *mem.Arena, t: *const control.Theme, i: usize, state: sh.SheetState, disabled: bool) -> (widget.Node, err) {
    let (rows, rows_error) = sh.axis(a, 60usize, 24.0, zero)
    if rows_error != ok { ret (zero, rows_error) }
    grouped = t.tokens.profile == .CupertinoLike
    // Cupertino: the first column is wide enough for the longest card name, which was cut at the column edge
    var first_width: f32 = 128.0
    if grouped { first_width = 156.0 }
    let col_over = [2]sh.Override{ sh.Override { index: 0usize, size: first_width }, sh.Override { index: 1usize, size: 44.0 } }
    let (cols, cols_error) = sh.axis(a, 8usize, 60.0, col_over[0..])
    if cols_error != ok { ret (zero, cols_error) }
    let merge_list = [1]sh.Merge{ sh.Merge { row: 6usize, col: 3usize, rows: 1usize, cols: 2usize } }
    let (merge_set, merges_error) = sh.merges(a, merge_list[0..], 60usize, 8usize)
    if merges_error != ok { ret (zero, merges_error) }
    let (g, grid_error) = sh.grid(rows, cols, merge_set, 1usize, 1usize)
    if grid_error != ok { ret (zero, grid_error) }
    var options = sh.sheet_options()
    options.disabled = disabled
    let source = sh.SheetSource { ctx: nil, cell: source_cell }
    let change = widget.Change[sh.SheetEvent] { ctx: nil, invoke: on_event }
    let (node, node_error) = sh.sheet(a, u64(i + 1usize) * 100000u64, t, "Deck list", g, source, state, draft[0..], zero, change, 360.0, 168.0, options)
    ret (node, node_error)
}

fn sel(row: usize, col: usize, row2: usize, col2: usize) -> sh.Selection {
    ret sh.Selection { row: row, col: col, anchor_row: row2, anchor_col: col2 }
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [8]str{ "rest", "range selected", "editing a cell", "hover", "focus", "pressed", "scrolled", "disabled" }
    draft[0usize] = 51u8
    draft[1usize] = 46u8
    draft[2usize] = 53u8
    draft[3usize] = 48u8
    var i = 0usize
    while i < 8usize {
        var state = sh.SheetState { selection: sel(2usize, 2usize, 2usize, 2usize), editing: false, len: 0usize, scroll_x: 0.0, scroll_y: 0.0 }
        var disabled = false
        var drive: looks.Drive = .None
        if i == 1usize { state.selection = sel(3usize, 3usize, 1usize, 1usize) }
        if i == 2usize {
            state.editing = true
            state.len = 4usize
        }
        if i == 3usize { drive = .Hover }
        if i == 4usize { drive = .Focus }
        if i == 5usize { drive = .Press }
        if i == 6usize {
            state.scroll_x = 70.0
            state.scroll_y = 96.0
            state.selection = sel(7usize, 2usize, 7usize, 2usize)
        }
        if i == 7usize { disabled = true }
        let (node, node_error) = one(a, t, i, state, disabled)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        if i >= 3usize && i <= 5usize { looks.aim(i, -68.0, 24.0) }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "sheet", cells: 8usize, columns: 2usize, cell_w: 380.0, cell_h: 188.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    try looks.run_linux(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    ret looks.run_material(a, &sheet)
}
