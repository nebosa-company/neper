// The Android look's data grid: the Material 3 data table idiom, a header row with the sort arrow, 52 dp rows with
// hairline dividers, a selected row on secondary-container and (select mode) a leading check box column
// (docs/ui/looks/material/data_grid.png). Run from the repository root; `material_data_grid.exe sel` for the selection sheet.

use e.mem
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_key(ctx: *void, value: widget.Key) -> err { ret ok }
fn noop_sort(ctx: *void, value: usize) -> err { ret ok }
fn noop_reorder(ctx: *void, value: collection.Reorder) -> err { ret ok }
fn noop_resize(ctx: *void, value: collection.ColumnResize) -> err { ret ok }
fn noop_scroll(ctx: *void, value: f32) -> err { ret ok }
fn noop_select(ctx: *void, value: collection.ListSelect) -> err { ret ok }

fn count_of(ctx: *void) -> usize { ret 6usize }
fn key_of(ctx: *void, row: usize) -> widget.Key { ret u64(row) + 1u64 }

fn name_of(row: usize) -> str {
    if row == 0usize { ret "Lightning Bolt" }
    if row == 1usize { ret "Counterspell" }
    if row == 2usize { ret "Llanowar Elves" }
    if row == 3usize { ret "Sol Ring" }
    if row == 4usize { ret "Swords to Plowshares" }
    ret "Dark Ritual"
}

fn edition_of(row: usize) -> str {
    if row == 0usize { ret "Alpha" }
    if row == 1usize { ret "Beta" }
    if row == 2usize { ret "Unlimited" }
    if row == 3usize { ret "Commander" }
    if row == 4usize { ret "Revised" }
    ret "Fourth Edition"
}

fn qty_of(row: usize) -> str {
    if row == 0usize { ret "4" }
    if row == 1usize { ret "2" }
    if row == 2usize { ret "12" }
    if row == 3usize { ret "1" }
    if row == 4usize { ret "3" }
    ret "20"
}

fn price_of(row: usize) -> str {
    if row == 0usize { ret "$1.20" }
    if row == 1usize { ret "$0.95" }
    if row == 2usize { ret "$0.30" }
    if row == 3usize { ret "$1.80" }
    if row == 4usize { ret "$3.10" }
    ret "$0.15"
}

fn cell_of(ctx: *void, a: *mem.Arena, row: usize, column: usize, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    var words = name_of(row)
    var color = style.color(t.tokens, .OnSurface)
    if column == 1usize {
        words = edition_of(row)
        color = style.color(t.tokens, .OnSurfaceVariant)
    }
    if column == 2usize { words = qty_of(row) }
    if column == 3usize { words = price_of(row) }
    let (made, made_error) = control.colored_text(a, 0u64, words, t, control.text_options(), color)
    if made_error != ok { ret made_error }
    *out = made
    ret ok
}

fn grid(a: *mem.Arena, t: *const control.Theme, key: widget.Key, picked: usize, choosable: bool, descending: bool) -> (widget.Node, err) {
    let (columns, columns_error) = mem.alloc[collection.Column](a, 4usize)
    if columns_error != ok { ret (zero, columns_error) }
    columns[0usize] = collection.Column { title: "Name", width: 180.0 }
    columns[1usize] = collection.Column { title: "Edition", width: 120.0 }
    columns[2usize] = collection.Column { title: "Qty", width: 60.0 }
    columns[3usize] = collection.Column { title: "Price", width: 80.0 }
    let (chosen, chosen_error) = mem.alloc[widget.Key](a, 2usize)
    if chosen_error != ok { ret (zero, chosen_error) }
    var how_many = 0usize
    if picked < 6usize {
        chosen[0usize] = u64(picked) + 1u64
        how_many = 1usize
    }
    if choosable && picked < 5usize {
        chosen[1usize] = u64(picked) + 3u64
        how_many = 2usize
    }
    let source = collection.TableSource { ctx: mem.cast[*void](t), count: count_of, key: key_of, cell: cell_of }
    var numeric = [4]bool{ false, false, true, true }
    var options: collection.TableOptions = zero
    options.numeric = numeric[0usize..4usize]
    if choosable { options.select = widget.Change[collection.ListSelect] { ctx: zero, invoke: noop_select } }
    let (node, node_error) = collection.table_with(a, key, t, "Cards", columns[0usize..4usize], source, chosen[0usize..how_many], 0usize, descending, widget.Change[usize] { ctx: zero, invoke: noop_sort }, widget.Change[collection.Reorder] { ctx: zero, invoke: noop_reorder }, widget.Change[collection.ColumnResize] { ctx: zero, invoke: noop_resize }, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, 52.0, 0.0, widget.Change[f32] { ctx: zero, invoke: noop_scroll }, 52.0 * 7.0, options)
    ret (node, node_error)
}

// Four cells: at rest, a row selected, the pointer on a row, the sort descending. `sel`: the select mode with two rows
// chosen, one hovered, focused.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [4]str{ "Enabled", "Row selected", "Row hovered", "Sorted descending" }
    var i = 0usize
    while i < 4usize {
        var picked = 99usize
        if i == 1usize { picked = 1usize }
        let (node, node_error) = grid(a, t, u64(1000usize * (i + 1usize)), picked, false, i == 3usize)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 2usize { drive = .Hover }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (4usize, ok)
}

fn build_select(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [3]str{ "Select mode, two rows chosen", "Row hovered", "Focused" }
    var i = 0usize
    while i < 3usize {
        var picked = 99usize
        if i == 0usize { picked = 1usize }
        let (node, node_error) = grid(a, t, u64(1000usize * (i + 1usize)), picked, true, false)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (3usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize {
        let chosen = looks.Sheet { name: "data_grid_select", cells: 3usize, columns: 3usize, cell_w: 460.0, cell_h: 380.0, ctx: zero, build: build_select }
        ret looks.run_material(a, &chosen)
    }
    let sheet = looks.Sheet { name: "data_grid", cells: 4usize, columns: 2usize, cell_w: 460.0, cell_h: 380.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
