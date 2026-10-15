// The vertical grid / property grid (TcxVerticalGrid) under every look:
// docs/ui/looks/<look>/vertical_grid.png. Run from the repository root; see docs/ui/looks-howto.md.
//
// Left: v3's Deck Properties grid as the live 100 % capture shows it (ref/windows/vertical_grid.png,
// cropped from ref/windows/dialogs/deck-properties@1x.png at (16, 79), 330 x 425): the General
// category with its nine rows (the Name row focused), the Computed category with the rows that are
// plain text (the capture's picture, bar and multi-cell rows are not reproduced). Right: the same
// grid with both categories shut. Row header 164 px, 330 px in all, as in the DFM.

use e.mem
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
    if index == 2usize { ret "e-mail" }
    if index == 3usize { ret "Created" }
    if index == 4usize { ret "Modified" }
    if index == 5usize { ret "Version" }
    if index == 6usize { ret "Description" }
    if index == 7usize { ret "File Name" }
    if index == 8usize { ret "File Type" }
    if index == 9usize { ret "Archetype" }
    if index == 10usize { ret "Deck" }
    ret "Sideboard"
}

fn values(index: usize) -> str {
    if index == 0usize { ret "New Deck" }
    if index == 1usize { ret "gaddl" }
    if index == 3usize || index == 4usize { ret "10/11/2026" }
    if index == 5usize { ret "1.0" }
    if index == 7usize { ret "C:\\Users\\gaddl\\Desktop\\New..." }
    if index == 8usize { ret "MTG Studio (Xml)" }
    if index == 9usize { ret "Unspecified" }
    if index == 10usize { ret "12" }
    if index == 11usize { ret "0" }
    ret ""
}

fn property_at(ctx: *void, index: usize) -> collection.Property {
    var group = "General"
    if index > 8usize { group = "Computed" }
    ret collection.Property { key: NAME_KEY + u64(index), name: names(index), group: group }
}

fn count_of(ctx: *void) -> usize { ret COUNT }

// The idle cell: plain text, in Tahoma under the Windows look (v3 draws an editor only in the
// focused row).
fn editor_of(ctx: *void, a: *mem.Arena, index: usize, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    var made: widget.Node = zero
    var made_error: err = ok
    if t.tokens.profile == .Windows {
        let (tahoma, tahoma_error) = control.windows_tahoma_theme(a, t, 11.0)
        if tahoma_error != ok { ret tahoma_error }
        let (copies, copies_error) = mem.alloc[control.Theme](a, 1usize)
        if copies_error != ok { ret copies_error }
        copies[0usize] = tahoma
        let (node, node_error) = control.text(a, 0u64, values(index), &copies[0usize], control.text_options())
        made = node
        made_error = node_error
    } else {
        let (node, node_error) = control.text(a, 0u64, values(index), t, control.text_options())
        made = node
        made_error = node_error
    }
    if made_error != ok { ret made_error }
    *out = made
    ret ok
}

fn grid(a: *mem.Arena, t: *const control.Theme, key: widget.Key, collapsed: []const widget.Key) -> (widget.Node, err) {
    let source = collection.PropertySource { ctx: mem.cast[*void](t), count: count_of, property: property_at, editor: editor_of }
    var options = collection.property_grid_options()
    options.selected = NAME_KEY
    options.height = 425.0
    let (made, made_error) = collection.property_grid_of(a, key, t, "Deck properties", source, collapsed, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, 164.0, 330.0, options)
    ret (made, made_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (shut, shut_error) = mem.alloc[widget.Key](a, 2usize)
    if shut_error != ok { ret (0usize, shut_error) }
    shut[0usize] = collection.property_group_key("General")
    shut[1usize] = collection.property_group_key("Computed")
    let (left, left_error) = grid(a, t, 1000u64, shut[0usize..0usize])
    if left_error != ok { ret (0usize, left_error) }
    let (right, right_error) = grid(a, t, 2000u64, shut[0usize..2usize])
    if right_error != ok { ret (0usize, right_error) }
    cells[0usize] = looks.Cell { caption: "Deck Properties: all categories open, Name focused", node: left, drive: .None }
    cells[1usize] = looks.Cell { caption: "General and Computed shut", node: right, drive: .None }
    ret (2usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "vertical_grid", cells: 2usize, columns: 2usize, cell_w: 330.0, cell_h: 425.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
