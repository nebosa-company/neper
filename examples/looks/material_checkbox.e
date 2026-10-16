// The Android look's check box, docs/ui/looks/material/checkbox.png: unchecked, checked and indeterminate in
// enabled, hovered, focused, pressed, disabled and error. Run from the repository root.

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
    let states = [6]str{ "Enabled", "Hovered", "Focused", "Pressed", "Disabled", "Error" }
    let rows = [3]str{ "Unchecked", "Checked", "Indeterminate" }
    var i = 0usize
    while i < 18usize {
        let row = i / 6usize
        let column = i % 6usize
        let (node, node_error) = control.material_checkbox(a, u64(i + 1usize), t, "Label", row == 1usize, row == 2usize, &actions[0usize], column != 4usize, column == 5usize)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: states[column], node: node, drive: drive_of(column) }
        i += 1usize
    }
    ret (18usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "checkbox", cells: 18usize, columns: 6usize, cell_w: 108.0, cell_h: 56.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
