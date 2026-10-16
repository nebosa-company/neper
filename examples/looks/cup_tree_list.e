// The Cupertino tree list (TcxTreeList): docs/ui/looks/cupertino/tree_list.png (and cupertino-dark). The macOS outline view /
// source list: disclosure chevrons, 24 tall rows, a rounded selection (grey; the accent tint once the list holds the keyboard
// focus). Cells: rest (one row chosen), keyboard focus, a hovered row, a pressed row, all branches shut. Node keys carry the
// cell in their high bits so no two cells share a key.

use e.mem
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.widget

type Ctx = struct { t: *const control.Theme, hi: u64 }

fn noop_key(ctx: *void, value: widget.Key) -> err { ret ok }

fn mask() -> u64 { ret 0xFFFFFFFFu64 }

fn name_of(node: widget.Key) -> str {
    let local = node & mask()
    if local == 1u64 { ret "Library" }
    if local == 2u64 { ret "Cards" }
    if local == 3u64 { ret "Tools" }
    if local == 100u64 { ret "Decks" }
    if local == 101u64 { ret "Collection" }
    if local == 102u64 { ret "Wish List" }
    if local == 200u64 { ret "Sets" }
    if local == 201u64 { ret "Tokens" }
    if local == 202u64 { ret "Promos" }
    if local == 300u64 { ret "Price Watch" }
    if local == 301u64 { ret "Analytics" }
    ret "Item"
}

fn count_of(ctx: *void, parent: widget.Key) -> usize {
    if parent == 0u64 { ret 3usize }
    let local = parent & mask()
    if local == 1u64 || local == 2u64 { ret 3usize }
    if local == 3u64 { ret 2usize }
    ret 0usize
}

fn key_of(ctx: *void, parent: widget.Key, index: usize) -> widget.Key {
    let c = mem.cast[*Ctx](ctx)
    if parent == 0u64 { ret c.hi | (u64(index) + 1u64) }
    ret c.hi | ((parent & mask()) * 100u64 + u64(index))
}

fn has_children(ctx: *void, node: widget.Key) -> bool { ret (node & mask()) < 100u64 }

fn build_row(ctx: *void, a: *mem.Arena, node: widget.Key, out: *widget.Node) -> err {
    let c = mem.cast[*Ctx](ctx)
    var options = control.text_options()
    options.wrap = .None
    options.size = 13.0
    if (node & mask()) < 100u64 { options.weight = 700u32 }
    let (made, made_error) = control.text(a, 0u64, name_of(node), c.t, options)
    if made_error != ok { ret made_error }
    *out = made
    ret ok
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [5]str{ "Rest (one row chosen)", "Keyboard focus", "Hover", "Pressed", "Shut branches" }
    var i = 0usize
    while i < 5usize {
        let hi = (u64(i) + 1u64) << 32u64
        let (held, held_error) = mem.alloc[Ctx](a, 1usize)
        if held_error != ok { ret (0usize, held_error) }
        held[0usize] = Ctx { t: t, hi: hi }
        let source = collection.TreeSource { ctx: mem.cast[*void](&held[0usize]), count: count_of, key: key_of, has_children: has_children, build: build_row }
        let (open, open_error) = mem.alloc[widget.Key](a, 3usize)
        if open_error != ok { ret (0usize, open_error) }
        open[0usize] = hi | 1u64
        open[1usize] = hi | 2u64
        open[2usize] = hi | 3u64
        var shown: []const widget.Key = open[0usize..3usize]
        if i == 4usize { shown = open[0usize..0usize] }
        let (picked, picked_error) = mem.alloc[widget.Key](a, 1usize)
        if picked_error != ok { ret (0usize, picked_error) }
        picked[0usize] = hi | 101u64
        if i == 1usize { picked[0usize] = hi | 200u64 }
        if i == 4usize { picked[0usize] = hi | 2u64 }
        let (node, node_error) = collection.tree(a, hi | 1000u64, t, "Library", source, shown, picked[0usize..1usize], widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, 24.0, 230.0)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Focus }
        if i == 2usize { drive = .Hover }
        if i == 3usize { drive = .Press }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "tree_list", cells: 5usize, columns: 3usize, cell_w: 250.0, cell_h: 290.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
