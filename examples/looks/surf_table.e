// Round 62 (g): collection.table and collection.tree_table in all ten looks: docs/ui/looks/<look>/table.png and tree_table.png.
// States: at rest, a row selected, a column sorted (descending), the pointer over a row, keyboard focus. Derived: both draw
// through the shared tokens of each look (no profile has its own table face); nothing here is compared with a real screen.
// `surf_table table` or `surf_table tree_table`.

use e.mem
use e.str as strs
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.widget

type Host = struct { t: *const control.Theme, base: u64 }

fn noop_sort(ctx: *void, value: usize) -> err { ret ok }
fn noop_reorder(ctx: *void, value: collection.Reorder) -> err { ret ok }
fn noop_resize(ctx: *void, value: collection.ColumnResize) -> err { ret ok }
fn noop_key(ctx: *void, value: widget.Key) -> err { ret ok }
fn noop_scroll(ctx: *void, value: f32) -> err { ret ok }

fn host_of(ctx: *void) -> *Host { ret mem.cast[*Host](ctx) }

fn name_of(row: usize) -> str {
    let names: [6]str = [6]str{ "Black Lotus", "Llanowar Elves", "Lightning Bolt", "Counterspell", "Sol Ring", "Swords to Plowshares" }
    ret names[row % 6usize]
}

fn size_of(row: usize) -> str {
    let sizes: [6]str = [6]str{ "1", "4", "12", "3", "8", "2" }
    ret sizes[row % 6usize]
}

fn kind_of(row: usize) -> str {
    let kinds: [6]str = [6]str{ "Artifact", "Creature", "Instant", "Instant", "Artifact", "Instant" }
    ret kinds[row % 6usize]
}

fn text_cell(a: *mem.Arena, t: *const control.Theme, value: str, out: *widget.Node) -> err {
    let (node, node_error) = control.text(a, 0u64, value, t, control.text_options())
    if node_error != ok { ret node_error }
    *out = node
    ret ok
}

fn table_count(ctx: *void) -> usize { ret 6usize }

fn table_key(ctx: *void, index: usize) -> widget.Key { ret host_of(ctx).base + 1u64 + u64(index) }

fn table_cell(ctx: *void, a: *mem.Arena, row: usize, column: usize, out: *widget.Node) -> err {
    let h = host_of(ctx)
    var value = name_of(row)
    if column == 1usize { value = size_of(row) }
    if column == 2usize { value = kind_of(row) }
    ret text_cell(a, h.t, value, out)
}

// The tree: three folders (local keys 10, 20, 30) with three files each (11 to 13, 21 to 23, 31 to 33). Keys are the cell's
// base plus the local key, so two tables on a sheet never share one; the root is asked for under key 0.
fn local_of(h: *Host, node: widget.Key) -> u64 {
    if node == 0u64 { ret 0u64 }
    ret node - h.base
}

fn tree_count(ctx: *void, parent: widget.Key) -> usize {
    let local = local_of(host_of(ctx), parent)
    if local == 0u64 { ret 3usize }
    if local % 10u64 == 0u64 { ret 3usize }
    ret 0usize
}

fn tree_key(ctx: *void, parent: widget.Key, index: usize) -> widget.Key {
    let h = host_of(ctx)
    let local = local_of(h, parent)
    if local == 0u64 { ret h.base + (u64(index) + 1u64) * 10u64 }
    ret h.base + local + u64(index) + 1u64
}

fn tree_has_children(ctx: *void, node: widget.Key) -> bool {
    ret local_of(host_of(ctx), node) % 10u64 == 0u64
}

fn tree_build(ctx: *void, a: *mem.Arena, node: widget.Key, out: *widget.Node) -> err {
    let h = host_of(ctx)
    let local = local_of(h, node)
    let folders: [3]str = [3]str{ "Decks", "Collection", "Wishlist" }
    var value = name_of(usize(local % 10u64))
    if local % 10u64 == 0u64 { value = folders[usize(local / 10u64) - 1usize] }
    ret text_cell(a, h.t, value, out)
}

fn tree_cell(ctx: *void, a: *mem.Arena, node: widget.Key, column: usize, out: *widget.Node) -> err {
    let h = host_of(ctx)
    let local = local_of(h, node)
    var value = size_of(usize(local))
    if local % 10u64 == 0u64 { value = "3" }
    if column == 2usize {
        value = kind_of(usize(local))
        if local % 10u64 == 0u64 { value = "Folder" }
    }
    ret text_cell(a, h.t, value, out)
}

fn columns_of(a: *mem.Arena) -> ([]collection.Column, err) {
    let (columns, columns_error) = mem.alloc[collection.Column](a, 3usize)
    if columns_error != ok { ret (zero, columns_error) }
    columns[0usize] = collection.Column { title: "Name", width: 150.0 }
    columns[1usize] = collection.Column { title: "Qty", width: 60.0 }
    columns[2usize] = collection.Column { title: "Type", width: 90.0 }
    ret (columns[0usize..3usize], ok)
}

fn build_table(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (columns, columns_error) = columns_of(a)
    if columns_error != ok { ret (0usize, columns_error) }
    let names = [5]str{ "rest", "row selected", "sorted descending", "row hover", "keyboard focus" }
    var i = 0usize
    while i < 5usize {
        let (hosts, hosts_error) = mem.alloc[Host](a, 1usize)
        if hosts_error != ok { ret (0usize, hosts_error) }
        hosts[0usize] = Host { t: t, base: u64(i + 1usize) * 1000u64 }
        let source = collection.TableSource { ctx: mem.cast[*void](&hosts[0usize]), count: table_count, key: table_key, cell: table_cell }
        let (chosen, chosen_error) = mem.alloc[widget.Key](a, 1usize)
        if chosen_error != ok { ret (0usize, chosen_error) }
        chosen[0usize] = 0u64
        if i == 1usize { chosen[0usize] = hosts[0usize].base + 3u64 }
        var sort_column = 0usize
        var descending = false
        if i == 2usize {
            sort_column = 1usize
            descending = true
        }
        let (node, node_error) = collection.table(a, hosts[0usize].base, t, "Cards", columns, source, chosen[0usize..1usize], sort_column, descending, widget.Change[usize] { ctx: zero, invoke: noop_sort }, widget.Change[collection.Reorder] { ctx: zero, invoke: noop_reorder }, widget.Change[collection.ColumnResize] { ctx: zero, invoke: noop_resize }, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, 28.0, 0.0, widget.Change[f32] { ctx: zero, invoke: noop_scroll }, 190.0)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 3usize {
            drive = .Hover
            looks.aim(i, 0.0, 0.0 - 95.0 + 33.0 + 28.0 * 2.5)
        }
        if i == 4usize {
            drive = .Focus
            looks.aim(i, 0.0, 0.0 - 95.0 + 33.0 + 14.0)
        }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (5usize, ok)
}

fn build_tree(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (columns, columns_error) = columns_of(a)
    if columns_error != ok { ret (0usize, columns_error) }
    let names = [5]str{ "collapsed", "folder open", "file selected", "row hover", "keyboard focus" }
    var i = 0usize
    while i < 5usize {
        let (hosts, hosts_error) = mem.alloc[Host](a, 1usize)
        if hosts_error != ok { ret (0usize, hosts_error) }
        hosts[0usize] = Host { t: t, base: u64(i + 1usize) * 1000u64 }
        let base = hosts[0usize].base
        let tree = collection.TreeSource { ctx: mem.cast[*void](&hosts[0usize]), count: tree_count, key: tree_key, has_children: tree_has_children, build: tree_build }
        let rows = collection.CellSource { ctx: mem.cast[*void](&hosts[0usize]), cell: tree_cell }
        let (open, open_error) = mem.alloc[widget.Key](a, 1usize)
        if open_error != ok { ret (0usize, open_error) }
        open[0usize] = base + 10u64
        let (chosen, chosen_error) = mem.alloc[widget.Key](a, 1usize)
        if chosen_error != ok { ret (0usize, chosen_error) }
        chosen[0usize] = 0u64
        var expanded = open[0usize..1usize]
        if i == 0usize {
            let none: []widget.Key = zero
            expanded = none
        }
        if i == 2usize { chosen[0usize] = base + 12u64 }
        let (node, node_error) = collection.tree_table(a, base, t, "Cards", columns, tree, rows, expanded, chosen[0usize..1usize], widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, 0usize, false, widget.Change[usize] { ctx: zero, invoke: noop_sort }, widget.Change[collection.Reorder] { ctx: zero, invoke: noop_reorder }, widget.Change[collection.ColumnResize] { ctx: zero, invoke: noop_resize }, 28.0)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 3usize {
            drive = .Hover
            looks.aim(i, 0.0, 0.0 - 95.0 + 33.0 + 28.0 * 2.5)
        }
        if i == 4usize {
            drive = .Focus
            looks.aim(i, 0.0, 0.0 - 95.0 + 33.0 + 14.0)
        }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var which = "table"
    if args.len > 1usize { which = args[1usize] }
    var sheet = looks.Sheet { name: "table", cells: 5usize, columns: 3usize, cell_w: 330.0, cell_h: 210.0, ctx: zero, build: build_table }
    if strs.eq(which, "tree_table") { sheet = looks.Sheet { name: "tree_table", cells: 5usize, columns: 3usize, cell_w: 330.0, cell_h: 210.0, ctx: zero, build: build_tree } }
    try looks.run_all(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    try looks.run_material(a, &sheet)
    ret looks.run_linux(a, &sheet)
}
