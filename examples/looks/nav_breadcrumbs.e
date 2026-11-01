// Breadcrumbs, docs/ui/looks/<look>/breadcrumbs.png: a four level trail at rest, a crumb hovered, pressed, keyboard-focused, a short
// trail, and the trail collapsed into an overflow crumb. Derived: the library's trail through each look's tokens; no platform capture.
// Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_e
use e.ui.navigation
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (subs, subs_error) = looks_e.submits(a, 5usize)
    if subs_error != ok { ret (0usize, subs_error) }
    let names_all = [5]str{ "Home", "Music", "Albums", "Jazz", "Kind of Blue" }
    let captions = [6]str{ "rest", "hover", "pressed", "focus", "two levels", "collapsed" }
    var i = 0usize
    while i < 6usize {
        var count = 4usize
        if i == 4usize { count = 2usize }
        if i == 5usize { count = 5usize }
        var options = navigation.breadcrumbs_options()
        if i == 5usize { options.hidden = 2usize }
        let (trail, trail_error) = navigation.breadcrumbs_of(a, u64((i + 1usize) * 100usize), t, "Path", names_all[0usize..count], subs[0usize..count], options)
        if trail_error != ok { ret (0usize, trail_error) }
        let (boxed, boxed_error) = looks_e.framed(a, u64((i + 1usize) * 100usize + 90usize), 330.0, 36.0, trail)
        if boxed_error != ok { ret (0usize, boxed_error) }
        cells[i] = looks.Cell { caption: captions[i], node: boxed, drive: looks_e.drive_of(i, 1usize, 2usize, 3usize) }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "breadcrumbs", cells: 6usize, columns: 2usize, cell_w: 350.0, cell_h: 74.0, ctx: zero, build: build }
    ret looks_e.run_ten(a, &sheet)
}
