// The Android look's badges: the small 6 dp dot and the large count badge (error container), alone and on a navigation icon
// (docs/ui/looks/material/badge.png). Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [6]str{ "Small (dot)", "Large, 3", "Large, 99+", "Large, 1000", "On icon, dot", "On icon, count" }
    let words = [6]str{ "", "3", "99+", "999+", "", "3" }
    var i = 0usize
    while i < 6usize {
        var kind: control.BadgeKind = .Urgent
        if i == 0usize || i == 4usize { kind = .Dot }
        let (badge, badge_error) = control.badge_of(a, u64(10usize * (i + 1usize)), t, words[i], kind)
        if badge_error != ok { ret (0usize, badge_error) }
        var node = badge
        if i >= 4usize {
            let (icon, icon_error) = control.icon_square(a, style.color(t.tokens, .OnSurfaceVariant), .Alert, 24.0)
            if icon_error != ok { ret (0usize, icon_error) }
            let (anchored, anchored_error) = control.badge_anchor(a, u64(100usize + i), icon, 24.0, badge, i == 4usize)
            if anchored_error != ok { ret (0usize, anchored_error) }
            node = anchored
        }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "badge", cells: 6usize, columns: 6usize, cell_w: 100.0, cell_h: 56.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
