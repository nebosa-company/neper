// Round 62 (g): collection.table and collection.tree_table in all ten looks: docs/ui/looks/<look>/table.png and tree_table.png.
// States: at rest, a row selected, a column sorted (descending), the pointer over a row, keyboard focus. Derived: both draw
// through the shared tokens of each look (no profile has its own table face); nothing here is compared with a real screen.
// `surf_table table` or `surf_table tree_table`.

use e.mem
use e.str as strs
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.looks_y87
use e.ui.looks_z88
use e.ui.widget

type Host = struct { t: *const control.Theme, base: u64, first: u64 }

fn noop_sort(ctx: *void, value: usize) -> err { ret ok }
fn noop_reorder(ctx: *void, value: collection.Reorder) -> err { ret ok }
fn noop_resize(ctx: *void, value: collection.ColumnResize) -> err { ret ok }
fn noop_key(ctx: *void, value: widget.Key) -> err { ret ok }
fn noop_select(ctx: *void, value: collection.ListSelect) -> err { ret ok }
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

// Android: the table's own parts are keyed key + 1, 2, 3 ..., which the rows' keys base + 1 + index collided with, so a row never hovered; the rows start 100 up.
fn table_key(ctx: *void, index: usize) -> widget.Key { ret host_of(ctx).base + host_of(ctx).first + u64(index) }

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

fn columns_of(a: *mem.Arena, t: *const control.Theme) -> ([]collection.Column, err) {
    let (columns, columns_error) = mem.alloc[collection.Column](a, 3usize)
    if columns_error != ok { ret (zero, columns_error) }
    columns[0usize] = collection.Column { title: "Name", width: 150.0 }
    columns[1usize] = collection.Column { title: "Qty", width: 60.0 }
    columns[2usize] = collection.Column { title: "Type", width: 90.0 }
    // Cupertino: the 15 pt body face cut "Creature" in 90 (no ellipsis); the Type column takes 104
    if t.tokens.profile == .CupertinoLike {
        columns[1usize].width = 56.0
        columns[2usize].width = 104.0
    }
    // Android: M3's 16 dp cell padding leaves the sort arrow no room in 60 dp, so it ran over the Qty label.  Name is 200 so "Swords to Plowshares" stays on one line.
    if t.tokens.profile == .MaterialLike {
        columns[0usize].width = 200.0
        columns[1usize].width = 76.0

    }
    ret (columns[0usize..3usize], ok)
}

// The header's height, so the pointer lands on a row: 33 in the other looks, the 56 dp M3 table header on Android.
fn header_of(t: *const control.Theme) -> f32 {
    if t.tokens.profile == .MaterialLike { ret 56.0 }
    ret 33.0
}

// Cupertino: the keyboard ring at 80 % of the strong blue (3:1 or better); any other look is passed through unchanged.
fn build_table(ctx: *void, a: *mem.Arena, original: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let tones = [1]looks_y87.RoleTone{ looks_y87.ring_tone() }
    let (tokens, tokens_error) = looks_y87.retoned(a, original.tokens, tones[0usize..1usize])
    if tokens_error != ok { ret (0usize, tokens_error) }
    var themed = *original
    themed.tokens = tokens
    let (count, count_error) = build_table_base(ctx, a, &themed, cells)
    ret (count, count_error)
}

fn build_table_base(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (columns, columns_error) = columns_of(a, t)
    if columns_error != ok { ret (0usize, columns_error) }
    let names = [5]str{ "rest", "row selected", "sorted descending", "row hover", "keyboard focus" }
    var i = 0usize
    while i < 5usize {
        let (hosts, hosts_error) = mem.alloc[Host](a, 1usize)
        if hosts_error != ok { ret (0usize, hosts_error) }
        hosts[0usize] = Host { t: t, base: u64(i + 1usize) * 1000u64, first: 1u64 }
        if t.tokens.profile == .MaterialLike { hosts[0usize].first = 101u64 }
        let source = collection.TableSource { ctx: mem.cast[*void](&hosts[0usize]), count: table_count, key: table_key, cell: table_cell }
        let (chosen, chosen_error) = mem.alloc[widget.Key](a, 1usize)
        if chosen_error != ok { ret (0usize, chosen_error) }
        chosen[0usize] = 0u64
        var how_many = 0usize
        if i == 1usize {
            chosen[0usize] = hosts[0usize].base + hosts[0usize].first + 2u64
            how_many = 1usize
        }
        var sort_column = 0usize
        var descending = false
        if i == 2usize {
            sort_column = 1usize
            descending = true
        }
        // Android: the Flutter DataTable's shape: a checkbox column, numbers at the end, a 56 dp header on the surface, 48 dp rows
        var extent: f32 = 28.0
        var shown: f32 = 190.0
        var numeric = [3]bool{ false, true, false }
        var options: collection.TableOptions = zero
        looks_z88.head_flat(false)
        if t.tokens.profile == .MaterialLike {
            extent = 48.0
            shown = 57.0 + 48.0 * 5.0

            if i == 1usize { shown += 58.0 }
            options.numeric = numeric[0usize..3usize]
            options.select = widget.Change[collection.ListSelect] { ctx: zero, invoke: noop_select }
            looks_z88.head_flat(true)
        }
        let (node, node_error) = collection.table_with(a, hosts[0usize].base, t, "Cards", columns, source, chosen[0usize..how_many], sort_column, descending, widget.Change[usize] { ctx: zero, invoke: noop_sort }, widget.Change[collection.Reorder] { ctx: zero, invoke: noop_reorder }, widget.Change[collection.ColumnResize] { ctx: zero, invoke: noop_resize }, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, extent, 0.0, widget.Change[f32] { ctx: zero, invoke: noop_scroll }, shown, options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 3usize {
            drive = .Hover
            looks.aim(i, 0.0, 0.0 - shown * 0.5 + header_of(t) + extent * 2.5)
        }
        if i == 4usize {
            drive = .Focus
            looks.aim(i, 0.0, 0.0 - shown * 0.5 + header_of(t) + extent * 0.5)
        }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (5usize, ok)
}

// Cupertino: the keyboard ring at 80 % of the strong blue (3:1 or better); any other look is passed through unchanged.
fn build_tree(ctx: *void, a: *mem.Arena, original: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let tones = [1]looks_y87.RoleTone{ looks_y87.ring_tone() }
    let (tokens, tokens_error) = looks_y87.retoned(a, original.tokens, tones[0usize..1usize])
    if tokens_error != ok { ret (0usize, tokens_error) }
    var themed = *original
    themed.tokens = tokens
    let (count, count_error) = build_tree_base(ctx, a, &themed, cells)
    ret (count, count_error)
}

fn build_tree_base(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (columns, columns_error) = columns_of(a, t)
    if columns_error != ok { ret (0usize, columns_error) }
    // Android: the indent and the disclosure take 56 dp of the name column, so the file names need it wider (they clipped).
    if t.tokens.profile == .MaterialLike {
        columns[0usize].width = 188.0
        columns[2usize].width = 88.0
        columns[1usize].width = 54.0
    }
    let names = [5]str{ "collapsed", "folder open", "file selected", "row hover", "keyboard focus" }
    var i = 0usize
    while i < 5usize {
        let (hosts, hosts_error) = mem.alloc[Host](a, 1usize)
        if hosts_error != ok { ret (0usize, hosts_error) }
        hosts[0usize] = Host { t: t, base: u64(i + 1usize) * 1000u64, first: 1u64 }
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
            looks.aim(i, 0.0, 0.0 - 95.0 + header_of(t) + 28.0 * 2.5)
        }
        if i == 4usize {
            drive = .Focus
            looks.aim(i, 0.0, 0.0 - 95.0 + header_of(t) + 14.0)
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
    // Android: the DataTable's 48 dp rows show five, in a wider cell for the checkbox column
    var android = sheet
    if !strs.eq(which, "tree_table") { android = looks.Sheet { name: "table", cells: 5usize, columns: 3usize, cell_w: 460.0, cell_h: 450.0, ctx: zero, build: build_table } }
    try looks.run_material(a, &android)
    ret looks.run_linux(a, &sheet)
}
