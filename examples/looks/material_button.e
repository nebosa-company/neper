// The Android look's buttons, docs/ui/looks/material/button.png: the five M3 variants (filled, tonal, elevated,
// outlined, text) in enabled, hovered, focused, pressed and disabled, and the same with a leading icon.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn variant_of(row: usize) -> style.ControlVariant {
    if row == 1usize { ret .Tonal }
    if row == 2usize { ret .Elevated }
    if row == 3usize { ret .Outlined }
    if row == 4usize { ret .Plain }
    ret .Filled
}

fn drive_of(column: usize) -> looks.Drive {
    if column == 1usize { ret .Hover }
    if column == 2usize { ret .Focus }
    if column == 3usize { ret .Press }
    ret .None
}

// 25 cells, 5 per row: variants down, states across.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let states = [5]str{ "Enabled", "Hovered", "Focused", "Pressed", "Disabled" }
    let names = [5]str{ "Filled", "Tonal", "Elevated", "Outlined", "Text" }
    var i = 0usize
    while i < 25usize {
        let row = i / 5usize
        let column = i % 5usize
        var options = control.button_options()
        options.variant = variant_of(row)
        options.enabled = column != 4usize
        let (node, node_error) = control.button(a, u64(i + 1usize), t, "Label", &actions[0usize], options)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: states[column], node: node, drive: drive_of(column) }
        i += 1usize
    }
    ret (25usize, ok)
}

fn build_icon(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let states = [5]str{ "Enabled", "Hovered", "Focused", "Pressed", "Disabled" }
    var i = 0usize
    while i < 25usize {
        let row = i / 5usize
        let column = i % 5usize
        var options = control.button_options()
        options.variant = variant_of(row)
        options.enabled = column != 4usize
        let (node, node_error) = control.button_with_glyph(a, u64(i + 1usize), t, .Add, "Label", &actions[0usize], options)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: states[column], node: node, drive: drive_of(column) }
        i += 1usize
    }
    ret (25usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let plain = looks.Sheet { name: "button", cells: 25usize, columns: 5usize, cell_w: 112.0, cell_h: 56.0, ctx: zero, build: build }
    try looks.run_material(a, &plain)
    let icon = looks.Sheet { name: "button_icon", cells: 25usize, columns: 5usize, cell_w: 124.0, cell_h: 56.0, ctx: zero, build: build_icon }
    ret looks.run_material(a, &icon)
}
