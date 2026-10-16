// The Android look's tree list: an expandable list, one row per node 48 dp high with a chevron, the label body-large and a
// trailing supporting column, below a header row with the sort arrow (docs/ui/looks/material/tree_list.png). Run from the
// repository root.

use e.mem
use e.ui.collection
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.looks
use e.ui.widget

fn noop_key(ctx: *void, value: widget.Key) -> err { ret ok }
fn noop_sort(ctx: *void, value: usize) -> err { ret ok }
fn noop_reorder(ctx: *void, value: collection.Reorder) -> err { ret ok }
fn noop_resize(ctx: *void, value: collection.ColumnResize) -> err { ret ok }

fn name_of(node: widget.Key) -> str {
    if node == 1u64 { ret "Expansions" }
    if node == 2u64 { ret "Core Sets" }
    if node == 3u64 { ret "Masters" }
    if node == 4u64 { ret "Draft Innovation" }
    if node == 5u64 { ret "Duel Decks" }
    if node == 6u64 { ret "Alchemy" }
    if node == 201u64 { ret "Tenth Edition" }
    if node == 301u64 { ret "Modern Masters" }
    ret "Archenemy"
}

fn year_of(node: widget.Key) -> str {
    if node == 1u64 { ret "1993" }
    if node == 2u64 { ret "2007" }
    if node == 3u64 { ret "2013" }
    if node == 4u64 { ret "2019" }
    if node == 5u64 { ret "2007" }
    if node == 6u64 { ret "2021" }
    ret "2013"
}

fn count_of(ctx: *void, parent: widget.Key) -> usize {
    if parent == 0u64 { ret 6usize }
    if parent == 2u64 || parent == 3u64 { ret 1usize }
    ret 0usize
}

fn key_of(ctx: *void, parent: widget.Key, index: usize) -> widget.Key {
    if parent == 0u64 { ret u64(index) + 1u64 }
    ret parent * 100u64 + u64(index) + 1u64
}

fn has_children(ctx: *void, node: widget.Key) -> bool {
    ret node == 2u64 || node == 3u64
}

fn build_row(ctx: *void, a: *mem.Arena, node: widget.Key, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    let (made, made_error) = control.colored_text(a, 0u64, name_of(node), t, control.text_options(), style.color(t.tokens, .OnSurface))
    if made_error != ok { ret made_error }
    *out = made
    ret ok
}

fn build_cell(ctx: *void, a: *mem.Arena, node: widget.Key, column: usize, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    let (made, made_error) = control.colored_text(a, 0u64, year_of(node), t, control.text_options(), style.color(t.tokens, .OnSurfaceVariant))
    if made_error != ok { ret made_error }
    *out = made
    ret ok
}

fn tree(a: *mem.Arena, t: *const control.Theme, key: widget.Key, picked: widget.Key) -> (widget.Node, err) {
    let (columns, columns_error) = mem.alloc[collection.Column](a, 2usize)
    if columns_error != ok { ret (zero, columns_error) }
    columns[0usize] = collection.Column { title: "Block/Edition", width: 220.0 }
    columns[1usize] = collection.Column { title: "Released", width: 90.0 }
    let (open, open_error) = mem.alloc[widget.Key](a, 2usize)
    if open_error != ok { ret (zero, open_error) }
    open[0usize] = 2u64
    open[1usize] = 3u64
    let (chosen, chosen_error) = mem.alloc[widget.Key](a, 1usize)
    if chosen_error != ok { ret (zero, chosen_error) }
    chosen[0usize] = picked
    let source = collection.TreeSource { ctx: mem.cast[*void](t), count: count_of, key: key_of, has_children: has_children, build: build_row }
    let cells = collection.CellSource { ctx: mem.cast[*void](t), cell: build_cell }
    var options: collection.TreeOptions = zero
    options.height = 300.0
    let (node, node_error) = collection.tree_table_with(a, key, t, "Blocks", columns[0usize..2usize], source, cells, open[0usize..2usize], chosen[0usize..1usize], widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, 0usize, false, widget.Change[usize] { ctx: zero, invoke: noop_sort }, widget.Change[collection.Reorder] { ctx: zero, invoke: noop_reorder }, widget.Change[collection.ColumnResize] { ctx: zero, invoke: noop_resize }, 48.0, options)
    ret (node, node_error)
}

// Three cells: at rest with the second branch open and the first row selected, a row hovered (the pointer is at the cell's
// middle), the keyboard on a row.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [3]str{ "Enabled, first row selected", "Row hovered", "Focused" }
    var i = 0usize
    while i < 3usize {
        var picked = 0u64
        if i == 0usize { picked = 1u64 }
        let (node, node_error) = tree(a, t, u64(1000usize * (i + 1usize)), picked)
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
    let sheet = looks.Sheet { name: "tree_list", cells: 3usize, columns: 3usize, cell_w: 330.0, cell_h: 300.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
