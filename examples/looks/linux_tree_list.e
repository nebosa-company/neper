// The Linux look's tree list against the real GTK 4.14 tree view in a scrolled window: docs/ui/looks/linux[-dark]/tree_list.png. The
// library's picture is a two column tree (Name, Value) of three parents with two children each, all open, 260 x 190 with the third
// parent cut by the frame; the second cell has the second child of the first parent chosen. Run from the repository root; see
// docs/ui/looks-howto.md. The strict compare is scripts/linux_cmp_l4.py.

use e.mem
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_key(ctx: *void, value: widget.Key) -> err { ret ok }
fn noop_sort(ctx: *void, value: usize) -> err { ret ok }
fn noop_reorder(ctx: *void, value: collection.Reorder) -> err { ret ok }
fn noop_resize(ctx: *void, value: collection.ColumnResize) -> err { ret ok }

fn name_of(node: widget.Key) -> str {
    if node == 1u64 { ret "Parent 0" }
    if node == 2u64 { ret "Parent 1" }
    if node == 3u64 { ret "Parent 2" }
    if node % 100u64 == 0u64 { ret "Child 0" }
    ret "Child 1"
}

fn value_of(node: widget.Key) -> str {
    if node == 1u64 { ret "0" }
    if node == 2u64 { ret "1" }
    if node == 3u64 { ret "2" }
    if node == 100u64 { ret "0.0" }
    if node == 101u64 { ret "0.1" }
    if node == 200u64 { ret "1.0" }
    if node == 201u64 { ret "1.1" }
    if node == 300u64 { ret "2.0" }
    ret "2.1"
}

fn count_of(ctx: *void, parent: widget.Key) -> usize {
    if parent == 0u64 { ret 3usize }
    if parent < 100u64 { ret 2usize }
    ret 0usize
}

fn key_of(ctx: *void, parent: widget.Key, index: usize) -> widget.Key {
    if parent == 0u64 { ret u64(index) + 1u64 }
    ret parent * 100u64 + u64(index)
}

fn has_children(ctx: *void, node: widget.Key) -> bool { ret node < 100u64 }

fn build_row(ctx: *void, a: *mem.Arena, node: widget.Key, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    let (made, made_error) = control.text(a, 0u64, name_of(node), t, control.text_options())
    if made_error != ok { ret made_error }
    *out = made
    ret ok
}

fn build_cell(ctx: *void, a: *mem.Arena, node: widget.Key, column: usize, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    let (made, made_error) = control.text(a, 0u64, value_of(node), t, control.text_options())
    if made_error != ok { ret made_error }
    *out = made
    ret ok
}

fn one(a: *mem.Arena, t: *const control.Theme, key: widget.Key, chosen: bool) -> (widget.Node, err) {
    let (columns, columns_error) = mem.alloc[collection.Column](a, 2usize)
    if columns_error != ok { ret (zero, columns_error) }
    columns[0usize] = collection.Column { title: "Name", width: 110.0 }
    columns[1usize] = collection.Column { title: "Value", width: 148.0 }
    let (open, open_error) = mem.alloc[widget.Key](a, 3usize)
    if open_error != ok { ret (zero, open_error) }
    open[0usize] = 1u64
    open[1usize] = 2u64
    open[2usize] = 3u64
    let (picked, picked_error) = mem.alloc[widget.Key](a, 1usize)
    if picked_error != ok { ret (zero, picked_error) }
    picked[0usize] = 101u64
    var shown: []const widget.Key = picked[0usize..0usize]
    if chosen { shown = picked[0usize..1usize] }
    let source = collection.TreeSource { ctx: mem.cast[*void](t), count: count_of, key: key_of, has_children: has_children, build: build_row }
    let cells = collection.CellSource { ctx: mem.cast[*void](t), cell: build_cell }
    var options: collection.TreeOptions = zero
    options.height = 157.0
    let (node, node_error) = collection.tree_table_with(a, key, t, "Tree", columns[0usize..2usize], source, cells, open[0usize..3usize], shown, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, 99usize, false, widget.Change[usize] { ctx: zero, invoke: noop_sort }, widget.Change[collection.Reorder] { ctx: zero, invoke: noop_reorder }, widget.Change[collection.ColumnResize] { ctx: zero, invoke: noop_resize }, 23.0, options)
    ret (node, node_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (rest, rest_error) = one(a, t, 1000u64, false)
    if rest_error != ok { ret (0usize, rest_error) }
    let (chosen, chosen_error) = one(a, t, 2000u64, true)
    if chosen_error != ok { ret (0usize, chosen_error) }
    cells[0usize] = looks.Cell { caption: "rest", node: rest, drive: .None }
    cells[1usize] = looks.Cell { caption: "selected", node: chosen, drive: .None }
    ret (2usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "tree_list", cells: 2usize, columns: 2usize, cell_w: 280.0, cell_h: 210.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
