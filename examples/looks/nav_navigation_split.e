// The navigation split, docs/ui/looks/<look>/navigation_split.png: wide (list and detail side by side), compact showing the list, compact
// showing the detail under its back bar. Derived: the library's split through each look's tokens; no platform capture. Run from the
// repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_e
use e.ui.navigation
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (subs, subs_error) = looks_e.submits(a, 1usize)
    if subs_error != ok { ret (0usize, subs_error) }
    let names = [3]str{ "wide", "compact, list", "compact, detail" }
    var i = 0usize
    while i < 3usize {
        let (primary, primary_error) = looks_e.page(a, t, "Folders")
        if primary_error != ok { ret (0usize, primary_error) }
        let (detail, detail_error) = looks_e.page(a, t, "Messages")
        if detail_error != ok { ret (0usize, detail_error) }
        var options = navigation.navigation_split_options()
        options.medium = i == 0usize
        options.detail_title = "Messages"
        options.pop = subs[0usize]
        var wide: f32 = 640.0
        if i != 0usize { wide = 300.0 }
        let (split, split_error) = navigation.navigation_split_of(a, u64((i + 1usize) * 100usize), t, primary, detail, i == 2usize, 150.0, widget.Change[f32] { ctx: zero, invoke: looks_e.noop_size }, wide, 150.0, options)
        if split_error != ok { ret (0usize, split_error) }
        let (boxed, boxed_error) = looks_e.framed(a, u64((i + 1usize) * 100usize + 90usize), wide, 150.0, split)
        if boxed_error != ok { ret (0usize, boxed_error) }
        cells[i] = looks.Cell { caption: names[i], node: boxed, drive: .None }
        i += 1usize
    }
    ret (3usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "navigation_split", cells: 3usize, columns: 1usize, cell_w: 660.0, cell_h: 190.0, ctx: zero, build: build }
    ret looks_e.run_ten(a, &sheet)
}
