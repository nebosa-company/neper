// The button in every state under every look: docs/ui/looks/<look>/button.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn one(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, key: widget.Key, variant: style.ControlVariant, enabled: bool) -> (widget.Node, err) {
    var options = control.button_options()
    options.variant = variant
    options.enabled = enabled
    let (node, node_error) = control.button(a, key, t, "Cancel", action, options)
    ret (node, node_error)
}

// Eight cells: the plain button at rest, hovered, pressed, keyboard-focused and disabled, then
// the default button (the one Enter presses) at rest, hovered and focused.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let action = &actions[0usize]
    let captions = [8]str{ "Normal", "Hover", "Pressed", "Focus", "Disabled", "Default", "Default hover", "Default focus" }
    var i = 0usize
    while i < 8usize {
        var variant: style.ControlVariant = .Filled
        if i >= 5usize { variant = .Default }
        let (node, node_error) = one(a, t, action, u64(i + 1usize), variant, i != 4usize)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize || i == 6usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        if i == 3usize || i == 7usize { drive = .Focus }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "button", cells: 8usize, columns: 4usize, cell_w: 110.0, cell_h: 40.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
