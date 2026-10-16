// The Android look's vertical grid (property grid): a key-value list, the keys in on-surface-variant at the start, the values
// in on-surface, the categories as collapsible section headers (docs/ui/looks/material/vertical_grid.png). Run from the
// repository root.

use e.mem
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.style
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

// The idle cell: the value as `body-large` text.
fn editor_of(ctx: *void, a: *mem.Arena, index: usize, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    let (node, node_error) = control.text(a, 0u64, values(index), t, control.text_options())
    if node_error != ok { ret node_error }
    *out = node
    ret ok
}

fn grid(a: *mem.Arena, t: *const control.Theme, key: widget.Key, collapsed: []const widget.Key, selected: u64) -> (widget.Node, err) {
    let source = collection.PropertySource { ctx: mem.cast[*void](t), count: count_of, property: property_at, editor: editor_of }
    var options = collection.property_grid_options()
    options.selected = selected
    options.height = 400.0
    let (made, made_error) = collection.property_grid_of(a, key, t, "Deck properties", source, collapsed, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, 150.0, 360.0, options)
    ret (made, made_error)
}

// Three cells: all categories open with the Name row selected, General shut, a row hovered.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (shut, shut_error) = mem.alloc[widget.Key](a, 2usize)
    if shut_error != ok { ret (0usize, shut_error) }
    shut[0usize] = collection.property_group_key("General")
    shut[1usize] = collection.property_group_key("Computed")
    let (one, one_error) = grid(a, t, 1000u64, shut[0usize..0usize], NAME_KEY)
    if one_error != ok { ret (0usize, one_error) }
    let (two, two_error) = grid(a, t, 2000u64, shut[0usize..1usize], 0u64)
    if two_error != ok { ret (0usize, two_error) }
    let (three, three_error) = grid(a, t, 3000u64, shut[0usize..0usize], 0u64)
    if three_error != ok { ret (0usize, three_error) }
    cells[0usize] = looks.Cell { caption: "Enabled, Name selected", node: one, drive: .None }
    cells[1usize] = looks.Cell { caption: "General shut", node: two, drive: .None }
    cells[2usize] = looks.Cell { caption: "Row hovered", node: three, drive: .Hover }
    ret (3usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "vertical_grid", cells: 3usize, columns: 3usize, cell_w: 370.0, cell_h: 410.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
