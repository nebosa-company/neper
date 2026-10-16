// The Android look's switch, docs/ui/looks/material/switch.png: off and on, plain and with the thumb icon, in
// enabled, hovered, focused, pressed and disabled. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn drive_of(column: usize) -> looks.Drive {
    if column == 1usize { ret .Hover }
    if column == 2usize { ret .Focus }
    if column == 3usize { ret .Press }
    ret .None
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let states = [5]str{ "Enabled", "Hovered", "Focused", "Pressed", "Disabled" }
    var i = 0usize
    while i < 20usize {
        let row = i / 5usize
        let column = i % 5usize
        // rows: off, on, off with icon, on with icon
        let (node, node_error) = control.material_switch(a, u64(i + 1usize), t, "Label", row == 1usize || row == 3usize, row >= 2usize, &actions[0usize], column != 4usize)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: states[column], node: node, drive: drive_of(column) }
        i += 1usize
    }
    ret (20usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "switch", cells: 20usize, columns: 5usize, cell_w: 130.0, cell_h: 56.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
