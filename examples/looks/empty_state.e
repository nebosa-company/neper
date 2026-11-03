// Round 62 c: the empty state in all ten looks: glyph art with a filled action, with two actions, compact with one outlined
// action, no art and no action, a picture as the art (the sample landscape of looks_c, standing in for an illustration),
// and the action hovered and pressed. Derived from the shared tokens, no platform capture. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_c
use e.ui.looks_y85
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, base: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    // Cupertino only: the filled action takes the blue that white text holds 4.5:1 on (the link takes its own in the control).
    let (tokens, tokens_error) = looks_y85.tinted_ring(a, base.tokens, 0x0A60FFu32, 0x0B57D0u32)
    if tokens_error != ok { ret (0usize, tokens_error) }
    var themed = *base
    themed.tokens = tokens
    let t = &themed
    let go = widget.Submit { ctx: zero, invoke: noop_submit }
    let (hold, hold_error) = mem.alloc[widget.Submit](a, 1usize)
    if hold_error != ok { ret (0usize, hold_error) }
    hold[0usize] = go
    let captions = [7]str{ "Glyph, action", "Two actions", "Compact", "Text only", "Picture art", "Action hovered", "Action pressed" }
    var i = 0usize
    while i < 7usize {
        let key = u64((i + 1usize) * 16usize)
        var node: widget.Node = zero
        var node_error = ok
        if i == 4usize {
            let (made, made_error) = control.empty_state(a, key, t, looks_c.picture, "No decks yet", "Create a deck to see it here.", "New deck", &hold[0usize], 320.0)
            node = made
            node_error = made_error
        } else {
            var options = control.empty_options()
            options.width = 320.0
            options.action_label = "New deck"
            options.action = &hold[0usize]
            if i == 1usize {
                options.other_label = "Import"
                options.other = &hold[0usize]
            }
            if i == 2usize {
                options.compact = true
                options.width = 280.0
            }
            if i == 3usize {
                options.art = false
                options.action_label = ""
            }
            let (made, made_error) = control.empty_state_of(a, key, t, "No decks yet", "Create a deck to see it here.", options)
            node = made
            node_error = made_error
        }
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 5usize { drive = .Hover }
        if i == 6usize { drive = .Press }
        if i == 5usize || i == 6usize { looks.aim(i, 0.0, 83.0) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (7usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "empty_state", cells: 7usize, columns: 4usize, cell_w: 350.0, cell_h: 300.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    try looks.run_material(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    ret looks.run_linux(a, &sheet)
}
