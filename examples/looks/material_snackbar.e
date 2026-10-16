// The Android look's snackbar, docs/ui/looks/material/snackbar.png: single line, with an action, with an action and a
// close icon, and a long two line message. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
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

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "snackbar", cells: 6usize, columns: 2usize, cell_w: 360.0, cell_h: 84.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
