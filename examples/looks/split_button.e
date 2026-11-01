// The split button in every look: docs/ui/looks/<look>/split_button.png. The primary half and the menu half at rest, each
// hovered, the primary half pressed and keyboard focused, and with the menu open (the chevron expanded; the menu itself is the
// caller's overlay and is not part of this control). Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_a
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let names = [6]str{ "rest", "hover primary", "hover menu half", "pressed", "focus", "menu open" }
    var i = 0usize
    while i < 6usize {
        let (node, node_error) = control.split_button(a, u64((i + 1usize) * 10usize), t, "Save", &actions[0usize], i == 5usize, &actions[0usize])
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize {
            drive = .Hover
            looks.aim(i, 38.0, 0.0)
        }
        if i == 3usize { drive = .Press }
        if i == 4usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "split_button", cells: 6usize, columns: 3usize, cell_w: 150.0, cell_h: 64.0, ctx: zero, build: build }
    ret looks_a.run_every(a, &sheet)
}
