// The vertical grid / property grid (TcxVerticalGrid) under every look:
// docs/ui/looks/<look>/vertical_grid.png. Run from the repository root; see docs/ui/looks-howto.md.
//
// Left: v3's Deck Properties grid as the live 100 % capture shows it (ref/windows/vertical_grid.png,
// cropped from ref/windows/dialogs/deck-properties@1x.png at (16, 79), 330 x 425): the General
// category with its nine rows (the Name row focused), the Computed category with the rows that are
// plain text (the capture's picture, bar and multi-cell rows are not reproduced). Right: the same
// grid with both categories shut. Row header 164 px, 330 px in all, as in the DFM.

use e.mem
use e.ui.style
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.widget

const COUNT: usize = 12usize
const NAME_KEY: u64 = 101u64


fn noop_key(ctx: *void, value: widget.Key) -> err { ret ok }

fn names(index: usize) -> str {
    if index == 0usize { ret "Name" }
    if index == 1usize { ret "Author" }
    if index == 2usize { ret "E-mail" }
    if index == 3usize { ret "Created" }
    if index == 4usize { ret "Modified" }
    if index == 5usize { ret "Version" }
    if index == 6usize { ret "File Type" }
    if index == 7usize { ret "Archetype" }
    if index == 8usize { ret "Deck" }
    ret "Sideboard"
}

fn values(index: usize) -> str {
    if index == 0usize { ret "New Deck" }
    if index == 1usize { ret "Alex Appleseed" }
    if index == 2usize { ret "Not Set" }
    if index == 3usize || index == 4usize { ret "Oct 11, 2026" }
    if index == 5usize { ret "1.0" }
    if index == 6usize { ret "MTG Studio (Xml)" }
    if index == 7usize { ret "Unspecified" }
    if index == 8usize { ret "60 cards" }
    ret "15 cards"
}

fn property_at(ctx: *void, index: usize) -> collection.Property {
    var group = "GENERAL"
    if index > 5usize { group = "COMPUTED" }
    ret collection.Property { key: NAME_KEY + u64(index), name: names(index), group: group }
}

fn count_of(ctx: *void) -> usize { ret 10usize }

fn editor_of(ctx: *void, a: *mem.Arena, index: usize, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    var options = control.text_options()
    options.wrap = .None
    let (node, node_error) = control.colored_text(a, 0u64, values(index), t, options, style.color(t.tokens, .TextMuted))
    if node_error != ok { ret node_error }
    *out = node
    ret ok
}

fn grid(a: *mem.Arena, t: *const control.Theme, key: widget.Key, collapsed: []const widget.Key, selected: u64) -> (widget.Node, err) {
    let source = collection.PropertySource { ctx: mem.cast[*void](t), count: count_of, property: property_at, editor: editor_of }
    var options = collection.property_grid_options()
    options.selected = selected
    let (made, made_error) = collection.property_grid_of(a, key, t, "Deck properties", source, collapsed, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, 150.0, 380.0, options)
    ret (made, made_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (shut, shut_error) = mem.alloc[widget.Key](a, 2usize)
    if shut_error != ok { ret (0usize, shut_error) }
    shut[0usize] = collection.property_group_key("GENERAL")
    shut[1usize] = collection.property_group_key("COMPUTED")
    let (one, one_error) = grid(a, t, 1000u64, shut[0usize..0usize], NAME_KEY + 1u64)
    if one_error != ok { ret (0usize, one_error) }
    let (two, two_error) = grid(a, t, 2000u64, shut[0usize..2usize], 0u64)
    if two_error != ok { ret (0usize, two_error) }
    let (three, three_error) = grid(a, t, 3000u64, shut[1usize..2usize], 0u64)
    if three_error != ok { ret (0usize, three_error) }
    cells[0usize] = looks.Cell { caption: "Sections open, Author row chosen", node: one, drive: .None }
    cells[1usize] = looks.Cell { caption: "Both sections shut", node: two, drive: .None }
    cells[2usize] = looks.Cell { caption: "Computed shut", node: three, drive: .None }
    ret (3usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "vertical_grid", cells: 3usize, columns: 3usize, cell_w: 400.0, cell_h: 560.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
