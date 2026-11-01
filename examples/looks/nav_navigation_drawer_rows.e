// The standing navigation drawer rows, docs/ui/looks/<look>/navigation_drawer_rows.png: three destinations with the first selected, the second hovered,
// pressed, keyboard-focused, and four destinations. Derived: the library's standard drawer through each look's tokens; no platform capture.
// Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_e
use e.ui.looks_y63
use e.ui.navigation
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (subs, subs_error) = looks_e.submits(a, 4usize)
    if subs_error != ok { ret (0usize, subs_error) }
    let labels = [4]str{ "Inbox", "Sent", "Drafts", "Trash" }
    let (items, items_error) = navigation.destinations_of(a, labels[0usize..4usize])
    if items_error != ok { ret (0usize, items_error) }
    let names = [5]str{ "rest", "hover", "pressed", "focus", "four, last selected" }
    var i = 0usize
    while i < 5usize {
        var count = 3usize
        var selected = 0usize
        if i == 4usize {
            count = 4usize
            selected = 3usize
        }
        // the focus cell: the middle destination selected and the stack centred, where the harness clicks before Tab
        if i == 3usize { selected = 1usize }
        let (rail, rail_error) = navigation.navigation_drawer_standard(a, u64((i + 1usize) * 100usize), t, "Mail", items[0usize..count], selected, subs[0usize..count], 240.0, 220.0)
        if rail_error != ok { ret (0usize, rail_error) }
        let (boxed, boxed_error) = looks_e.framed(a, u64((i + 1usize) * 100usize + 90usize), 240.0, 220.0, rail)
        var shown = boxed
        if i == 3usize {
            let (middle, middle_error) = looks_y63.framed_center(a, u64((i + 1usize) * 100usize + 90usize), 240.0, 220.0, rail)
            if middle_error != ok { ret (0usize, middle_error) }
            shown = middle
        }
        if boxed_error != ok { ret (0usize, boxed_error) }
        cells[i] = looks.Cell { caption: names[i], node: shown, drive: looks_e.drive_of(i, 1usize, 2usize, 3usize) }
        i += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "navigation_drawer_rows", cells: 5usize, columns: 3usize, cell_w: 260.0, cell_h: 260.0, ctx: zero, build: build }
    ret looks_e.run_ten(a, &sheet)
}
