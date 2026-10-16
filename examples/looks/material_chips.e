// The Android look's chips, docs/ui/looks/material/chips.png: assist, filter (off and on), input and suggestion in
// enabled, hovered, focused, pressed. Run from the repository root.

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
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    actions[1usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let states = [4]str{ "Enabled", "Hovered", "Focused", "Pressed" }
    let words = [6]str{ "Assist", "Filter", "Filter", "Input", "Suggestion", "Selected input" }
    var i = 0usize
    while i < 20usize {
        let row = i / 4usize
        let column = i % 4usize
        var kind: control.ChipKind = .Assist
        var selected = false
        if row == 1usize { kind = .Filter }
        if row == 2usize {
            kind = .Filter
            selected = true
        }
        if row == 3usize { kind = .Input }
        if row == 4usize { kind = .Suggestion }
        let (node, node_error) = control.chip(a, u64((i + 1usize) * 4usize), t, words[row], kind, selected, &actions[0usize], &actions[1usize])
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: states[column], node: node, drive: drive_of(column) }
        i += 1usize
    }
    ret (20usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "chips", cells: 20usize, columns: 4usize, cell_w: 130.0, cell_h: 48.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
