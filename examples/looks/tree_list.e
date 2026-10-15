// The tree list (TcxTreeList) under every look: docs/ui/looks/<look>/tree_list.png.
// Run from the repository root; see docs/ui/looks-howto.md.
//
// Left: a tree table with three columns and three levels, one branch collapsed, one leaf selected.
// Right: the shape of v3's filter form (tlAbilities): one column, branches open and shut.

use e.mem
use e.str as strs
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_key(ctx: *void, value: widget.Key) -> err { ret ok }
fn noop_sort(ctx: *void, value: usize) -> err { ret ok }
fn noop_reorder(ctx: *void, value: collection.Reorder) -> err { ret ok }
fn noop_resize(ctx: *void, value: collection.ColumnResize) -> err { ret ok }

fn name_of(node: widget.Key) -> str {
    if node == 10u64 { ret "Creatures" }
    if node == 11u64 { ret "Bird token" }
    if node == 12u64 { ret "Dragons" }
    if node == 121u64 { ret "Shivan Dragon" }
    if node == 122u64 { ret "Dragon Whelp" }
    if node == 13u64 { ret "Llanowar Elves" }
    if node == 20u64 { ret "Instants" }
    if node == 21u64 { ret "Counterspell" }
    if node == 22u64 { ret "Lightning Bolt" }
    if node == 23u64 { ret "Swords to Plowshares" }
    if node == 30u64 { ret "Lands" }
    ret "Forest"
}

fn count_of(ctx: *void, parent: widget.Key) -> usize {
    if parent == 0u64 { ret 3usize }
    if parent == 12u64 { ret 2usize }
    if parent == 10u64 || parent == 20u64 { ret 3usize }
    if parent == 30u64 { ret 1usize }
    ret 0usize
}

fn key_of(ctx: *void, parent: widget.Key, index: usize) -> widget.Key {
    if parent == 0u64 { ret (u64(index) + 1u64) * 10u64 }
    if parent == 12u64 { ret 121u64 + u64(index) }
    ret parent + u64(index) + 1u64
}

fn has_children(ctx: *void, node: widget.Key) -> bool {
    ret node % 10u64 == 0u64 || node == 12u64
}

fn build_row(ctx: *void, a: *mem.Arena, node: widget.Key, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    let (made, made_error) = control.text(a, 0u64, name_of(node), t, control.text_options())
    if made_error != ok { ret made_error }
    *out = made
    ret ok
}

fn build_cell(ctx: *void, a: *mem.Arena, node: widget.Key, column: usize, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    var value = "1"
    if column == 1usize && has_children(ctx, node) { value = "" }
    if column == 2usize {
        value = "Card"
        if has_children(ctx, node) { value = "Group" }
    }
    let (made, made_error) = control.text(a, 0u64, value, t, control.text_options())
    if made_error != ok { ret made_error }
    *out = made
    ret ok
}

fn one(a: *mem.Arena, t: *const control.Theme, key: widget.Key, wide: bool, expanded: []const widget.Key, selected: []const widget.Key) -> (widget.Node, err) {
    let (columns, columns_error) = mem.alloc[collection.Column](a, 3usize)
    if columns_error != ok { ret (zero, columns_error) }
    columns[0usize] = collection.Column { title: "Name", width: 190.0 }
    columns[1usize] = collection.Column { title: "Qty", width: 70.0 }
    columns[2usize] = collection.Column { title: "Kind", width: 110.0 }
    var shown = 3usize
    if !wide {
        columns[0usize] = collection.Column { title: "Ability", width: 300.0 }
        shown = 1usize
    }
    let source = collection.TreeSource { ctx: mem.cast[*void](t), count: count_of, key: key_of, has_children: has_children, build: build_row }
    let cells = collection.CellSource { ctx: mem.cast[*void](t), cell: build_cell }
    let (node, node_error) = collection.tree_table(a, key, t, "Cards", columns[0usize..shown], source, cells, expanded, selected, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, 99usize, false, widget.Change[usize] { ctx: zero, invoke: noop_sort }, widget.Change[collection.Reorder] { ctx: zero, invoke: noop_reorder }, widget.Change[collection.ColumnResize] { ctx: zero, invoke: noop_resize }, 0.0)
    ret (node, node_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (open, open_error) = mem.alloc[widget.Key](a, 3usize)
    if open_error != ok { ret (0usize, open_error) }
    open[0usize] = 10u64
    open[1usize] = 12u64
    open[2usize] = 20u64
    let (picked, picked_error) = mem.alloc[widget.Key](a, 1usize)
    if picked_error != ok { ret (0usize, picked_error) }
    picked[0usize] = 121u64
    let (left, left_error) = one(a, t, 1000u64, true, open[0usize..3usize], picked[0usize..1usize])
    if left_error != ok { ret (0usize, left_error) }
    let (right, right_error) = one(a, t, 2000u64, false, open[2usize..3usize], picked[0usize..0usize])
    if right_error != ok { ret (0usize, right_error) }
    cells[0usize] = looks.Cell { caption: "Three columns, three levels, selected leaf", node: left, drive: .None }
    cells[1usize] = looks.Cell { caption: "One column, branches open and shut", node: right, drive: .None }
    ret (2usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "tree_list", cells: 2usize, columns: 2usize, cell_w: 400.0, cell_h: 260.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
