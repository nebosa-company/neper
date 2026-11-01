// The modal navigation drawer, docs/ui/looks/<look>/navigation_drawer.png: open over the window with its scrim, three destinations, the
// second selected. One modal per sheet; the standing rows in their states are navigation_drawer_rows. Derived: the library's drawer
// through each look's tokens; no platform capture. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_e
use e.ui.navigation
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (subs, subs_error) = looks_e.submits(a, 4usize)
    if subs_error != ok { ret (0usize, subs_error) }
    let labels = [3]str{ "Inbox", "Sent", "Drafts" }
    let (drawer, drawer_error) = navigation.navigation_drawer(a, 100u64, t, labels[0usize..3usize], 1usize, subs[0usize..3usize], true, &subs[3usize], 240.0)
    if drawer_error != ok { ret (0usize, drawer_error) }
    cells[0usize] = looks.Cell { caption: "open, second selected", node: drawer, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "navigation_drawer", cells: 1usize, columns: 1usize, cell_w: 360.0, cell_h: 260.0, ctx: zero, build: build }
    ret looks_e.run_ten(a, &sheet)
}
