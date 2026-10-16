// The Android look's radio group: M3 radio buttons in 48 dp targets under a group label (docs/ui/looks/material/radio_group.png).
// Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

// Six cells: the first option selected, the second selected, hovered, pressed, focused, disabled.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 3usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    actions[1usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    actions[2usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let labels = [3]str{ "Move to next column", "Move to next row", "Stay on the cell" }
    let names = [6]str{ "Enabled", "Second selected", "Hovered", "Pressed", "Focused", "Disabled" }
    var i = 0usize
    while i < 6usize {
        var selected = 0usize
        if i == 1usize { selected = 1usize }
        let key = u64(i * 8usize + 1usize)
        let (node, node_error) = control.radio_group(a, key, t, "Enter key action", labels[0usize..3usize], selected, actions[0usize..3usize], i != 5usize)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        // The harness drives the pointer to the centre of the cell: the middle radio.
        if i == 2usize { drive = .Hover }
        if i == 3usize { drive = .Press }
        if i == 4usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "radio_group", cells: 6usize, columns: 3usize, cell_w: 260.0, cell_h: 190.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
