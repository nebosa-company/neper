// The Android look's list items, docs/ui/looks/material/list.png: one, two and three line items with a leading icon, a
// trailing icon and a meta label, then enabled, hovered, focused, pressed, selected and disabled. Run from the
// repository root.

use e.mem
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn item_of(i: usize, none: widget.Submit) -> collection.RowItem {
    var item: collection.RowItem = zero
    item.action = none
    item.headline = "List item"
    if i == 0usize || i >= 8usize {
        item.leading = .Person
        item.has_leading = true
    }
    if i == 11usize { item.disabled = true }
    if i == 1usize || i == 6usize || i == 7usize {
        item.supporting = "Supporting line text lorem ipsum"
        item.leading = .Person
        item.has_leading = true
        item.trailing = .ChevronRight
        item.has_trailing = true
    }
    if i == 2usize {
        item.overline = "Overline"
        item.supporting = "Supporting line text lorem ipsum"
        item.meta = "100+"
        item.leading = .Picture
        item.has_leading = true
    }
    if i >= 3usize && i <= 5usize {
        item.supporting = "Supporting line text"
        item.leading = .Person
        item.has_leading = true
    }
    if i == 6usize { item.selected = true }
    if i == 7usize { item.disabled = true }
    ret item
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let none = widget.Submit { ctx: zero, invoke: noop_submit }
    let (items, items_error) = mem.alloc[collection.RowItem](a, 12usize)
    if items_error != ok { ret (0usize, items_error) }
    let names = [12]str{ "One line", "Two lines", "Three lines, meta", "Hovered", "Focused", "Pressed", "Selected", "Disabled", "One line, hovered", "One line, focused", "One line, pressed", "One line, disabled" }
    var i = 0usize
    while i < 12usize {
        items[i] = item_of(i, none)
        let (node, node_error) = collection.row_of(a, u64((i + 1usize) * 8usize), t, &items[i], i, 12usize, 340.0)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 3usize || i == 8usize { drive = .Hover }
        if i == 4usize || i == 9usize { drive = .Focus }
        if i == 5usize || i == 10usize { drive = .Press }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (12usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "list", cells: 12usize, columns: 4usize, cell_w: 350.0, cell_h: 96.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
