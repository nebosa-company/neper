// The icon button in every look: docs/ui/looks/<look>/icon_button.png. Three variants (plain, tonal, outlined) in rest, hover,
// pressed, keyboard focus and disabled. The picture is a control-kit glyph (a rig has no texture); Linux draws the Adwaita
// symbolic icon. Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_a
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let states = [5]str{ "rest", "hover", "pressed", "focus", "disabled" }
    let kinds = [3]str{ "plain", "tonal", "outlined" }
    var i = 0usize
    while i < 15usize {
        let row = i / 5usize
        let column = i % 5usize
        var options = control.button_options()
        options.enabled = column != 4usize
        if row == 0usize { options.variant = .Plain }
        if row == 1usize { options.variant = .Tonal }
        if row == 2usize { options.variant = .Outlined }
        let (node, node_error) = looks_a.icon_button_glyph(a, u64((i + 1usize) * 10usize), t, .Settings, "Settings", &actions[0usize], options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if column == 1usize { drive = .Hover }
        if column == 2usize { drive = .Press }
        if column == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: states[column], node: node, drive: drive }
        i += 1usize
    }
    ret (15usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "icon_button", cells: 15usize, columns: 5usize, cell_w: 84.0, cell_h: 64.0, ctx: zero, build: build }
    ret looks_a.run_every(a, &sheet)
}
