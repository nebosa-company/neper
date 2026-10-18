// The Android look's floating action buttons and icon buttons, docs/ui/looks/material/fab.png: small, regular, large and
// extended FABs, and the four icon button kinds (standard, filled, tonal, outlined) off, toggled, hovered, pressed and
// disabled. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn kind_of(row: usize) -> style.ControlVariant {
    if row == 1usize { ret .Filled }
    if row == 2usize { ret .Tonal }
    if row == 3usize { ret .Outlined }
    ret .Plain
}

// Row 0: FABs (small, regular, large, extended, extended hovered, extended pressed); rows 1 to 4: icon buttons.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let fab_names = [6]str{ "Small", "Regular", "Large", "Extended", "Extended, hovered", "Extended, pressed" }
    var i = 0usize
    while i < 6usize {
        var size: control.FabSize = .Default
        if i == 0usize { size = .Small }
        if i == 2usize { size = .Large }
        if i >= 3usize { size = .Extended }
        let (node, node_error) = control.material_fab(a, u64((i + 1usize) * 4usize), t, .Edit, "Compose", &actions[0usize], size)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 4usize { drive = .Hover }
        if i == 5usize { drive = .Press }
        cells[i] = looks.Cell { caption: fab_names[i], node: node, drive: drive }
        i += 1usize
    }
    let states = [6]str{ "Enabled", "Toggled", "Hovered", "Focused", "Pressed", "Disabled" }
    var j = 0usize
    while j < 24usize {
        let row = j / 6usize
        let column = j % 6usize
        let (node, node_error) = control.material_icon_button(a, u64(1000usize + j * 4usize), t, .Settings, "Settings", &actions[0usize], kind_of(row), column != 5usize, column == 1usize)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if column == 2usize { drive = .Hover }
        if column == 3usize { drive = .Focus }
        if column == 4usize { drive = .Press }
        cells[6usize + j] = looks.Cell { caption: states[column], node: node, drive: drive }
        j += 1usize
    }
    ret (30usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "fab", cells: 30usize, columns: 6usize, cell_w: 150.0, cell_h: 108.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
