// The Android look's navigation bar, docs/ui/looks/material/navigation_bar.png: three and four destinations with icons,
// the active indicator, a badge and a dot. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.navigation
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (picks, picks_error) = mem.alloc[widget.Submit](a, 4usize)
    if picks_error != ok { ret (0usize, picks_error) }
    var p = 0usize
    while p < 4usize {
        picks[p] = widget.Submit { ctx: zero, invoke: noop_submit }
        p += 1usize
    }
    let (items, items_error) = mem.alloc[navigation.Destination](a, 4usize)
    if items_error != ok { ret (0usize, items_error) }
    items[0usize] = navigation.destination("Home")
    items[0usize].glyph = .Menu
    items[0usize].pictured = true
    items[1usize] = navigation.destination("Search")
    items[1usize].glyph = .Search
    items[1usize].pictured = true
    items[2usize] = navigation.destination("Alerts")
    items[2usize].glyph = .Alert
    items[2usize].pictured = true
    items[2usize].badge = "3"
    items[3usize] = navigation.destination("Profile")
    items[3usize].glyph = .Person
    items[3usize].pictured = true
    items[3usize].dot = true
    let names = [5]str{ "Three, first", "Four, second, badge and dot", "Hovered item", "Pressed item", "Four, last" }
    var i = 0usize
    while i < 5usize {
        var count = 4usize
        var selected = 1usize
        if i == 0usize {
            count = 3usize
            selected = 0usize
        }
        if i == 4usize { selected = 3usize }
        let (node, node_error) = navigation.destination_bar_of(a, u64((i + 1usize) * 100usize), t, items[0usize..count], selected, picks[0usize..count], .Bottom, 360.0)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 2usize { drive = .Hover }
        if i == 3usize { drive = .Press }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "navigation_bar", cells: 5usize, columns: 2usize, cell_w: 370.0, cell_h: 96.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
