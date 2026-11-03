// The toggle button in every look: docs/ui/looks/<look>/toggle_button.png. Off as an outlined and as a tonal button, and on
// (selected), each at rest, hover, pressed, keyboard focus and disabled. Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_a
use e.ui.looks_y85
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, base: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    // Cupertino only: accent text on the ground (0045E6 light, 409CFF dark) and a fill that white text holds 4.5:1 on (0045E6, 0B57D0); other looks unchanged.
    let (text_tokens, text_error) = looks_y85.tinted_ring(a, base.tokens, 0x0045E6u32, 0x409CFFu32)
    if text_error != ok { ret (0usize, text_error) }
    let (fill_tokens, fill_error) = looks_y85.tinted_ring(a, base.tokens, 0x0045E6u32, 0x0B57D0u32)
    if fill_error != ok { ret (0usize, fill_error) }
    var text_theme = *base
    text_theme.tokens = text_tokens
    var fill_theme = *base
    fill_theme.tokens = fill_tokens
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let states = [5]str{ "rest", "hover", "pressed", "focus", "disabled" }
    var i = 0usize
    while i < 15usize {
        let row = i / 5usize
        let column = i % 5usize
        var options = control.button_options()
        options.enabled = column != 4usize
        if row == 0usize { options.variant = .Outlined }
        if row == 1usize { options.variant = .Tonal }
        var t = &text_theme
        if row == 2usize { t = &fill_theme }
        let (node, node_error) = control.toggle_button(a, u64((i + 1usize) * 10usize), t, "Bold", row == 2usize, &actions[0usize], options)
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
    let sheet = looks.Sheet { name: "toggle_button", cells: 15usize, columns: 5usize, cell_w: 100.0, cell_h: 64.0, ctx: zero, build: build }
    ret looks_a.run_every(a, &sheet)
}
