// The collection key-value editor (collection.key_value_editor): a row per pair (name, value, Remove) and an Add button.
// Sheet "key_value_editor": rest (three pairs), empty, keyboard focus, hover.
// Derived: fields and buttons come from the shared tokens of each look (the text field of each look, not a new drawing);
// no reference capture exists. Duplicate-name and secret-value options are not shown.

use e.mem
use e.ui.collection
use e.ui.looks_z84
use e.ui.control
use e.ui.looks
use e.ui.looks_h as h
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    var names = [4]str{ "rest", "empty", "focus", "hover" }
    // Android: keyboard focus mutes the pointer layers of the frames after it, so the hover cell comes before the focus cell.
    if t.tokens.profile == .MaterialLike { names = [4]str{ "rest", "empty", "hover", "focus" } }
    var i = 0usize
    while i < 4usize {
        var pairs: [3]collection.Pair = zero
        var count = 3usize
        if i == 1usize { count = 0usize }
        if count > 0usize {
            let (p0, e0) = h.pair(a, "Accept", "application/json")
            if e0 != ok { ret (0usize, e0) }
            let (p1, e1) = h.pair(a, "User-Agent", "neper/1.0")
            if e1 != ok { ret (0usize, e1) }
            let (p2, e2) = h.pair(a, "Cache-Control", "no-cache")
            if e2 != ok { ret (0usize, e2) }
            pairs[0usize] = p0
            pairs[1usize] = p1
            pairs[2usize] = p2
        }
        let add = widget.Submit { ctx: zero, invoke: h.noop_submit }
        let (node, node_error) = collection.key_value_editor(a, u64((i + 1usize) * 1000usize), t, "Headers", pairs[0usize..count], widget.Change[collection.PairEdit] { ctx: zero, invoke: h.noop_edit }, widget.Change[usize] { ctx: zero, invoke: h.noop_usize }, &add, 440.0)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 2usize { drive = .Focus }
        if i == 3usize { drive = .Hover }
        if t.tokens.profile == .MaterialLike {
            if i == 2usize {
                drive = .Hover
                looks.aim(2usize, -152.0, 73.0)
            }
            if i == 3usize {
                looks_z84.stops(22usize)
                drive = .Tabs
            }
        }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "key_value_editor", cells: 4usize, columns: 2usize, cell_w: 470.0, cell_h: 200.0, ctx: zero, build: build }
    ret h.run_ten(a, &sheet)
}
