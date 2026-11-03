// Round 70 b: the snackbar and the badge under the Neper pair (their sheets so far were Android only), the controls the Flutter
// references SnackBar and Badge stand for. Same cells as material_snackbar.e and material_badge.e. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_b70
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build_snackbar(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    actions[1usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var none: widget.Submit = zero
    let captions = [6]str{ "Single line", "Action", "Action, close", "Two lines, action", "Action hovered", "Action pressed" }
    let words = [6]str{ "Deck saved", "Card removed from the deck", "Card removed from the deck", "The price refresh failed because the server could not be reached.", "Card removed from the deck", "Card removed from the deck" }
    var i = 0usize
    while i < 6usize {
        var label = ""
        if i >= 1usize { label = "Undo" }
        var close = &none
        if i == 2usize { close = &actions[1usize] }
        let (node, node_error) = control.material_snackbar(a, u64((i + 1usize) * 4usize), t, words[i], label, &actions[0usize], close, 344.0)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 4usize { drive = .Hover }
        if i == 5usize { drive = .Press }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (6usize, ok)
}

fn build_badge(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
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
    let bar = looks.Sheet { name: "snackbar", cells: 6usize, columns: 2usize, cell_w: 360.0, cell_h: 84.0, ctx: zero, build: build_snackbar }
    try looks_b70.run_neper(a, &bar)
    let badges = looks.Sheet { name: "badge", cells: 6usize, columns: 6usize, cell_w: 100.0, cell_h: 56.0, ctx: zero, build: build_badge }
    ret looks_b70.run_neper(a, &badges)
}
