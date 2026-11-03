// The rating in every look: docs/ui/looks/<look>/rating.png. Three of five stars at rest, with the fourth star hovered and
// pressed, with keyboard focus, and none and all five filled. Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_z84
use e.ui.looks_a
use e.ui.widget

fn noop_rate(ctx: *void, value: u32) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [6]str{ "3 of 5", "hover star 4", "pressed star 4", "focus", "none", "all five" }
    let values = [6]u32{ 3u32, 3u32, 3u32, 3u32, 0u32, 5u32 }
    var i = 0usize
    while i < 6usize {
        let change = widget.Change[u32] { ctx: zero, invoke: noop_rate }
        let (node, node_error) = control.rating(a, u64((i + 1usize) * 100usize), t, "Rating", values[i], 5u32, change)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize || i == 2usize {
            looks.aim(i, 32.0, 0.0)
            drive = .Hover
        }
        if i == 2usize { drive = .Press }
        if i == 3usize { drive = .Focus }
        if i == 3usize && t.tokens.profile == .MaterialLike {
            looks_z84.stops(4usize)
            drive = .Tabs
        }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "rating", cells: 6usize, columns: 3usize, cell_w: 190.0, cell_h: 64.0, ctx: zero, build: build }
    ret looks_a.run_every(a, &sheet)
}
