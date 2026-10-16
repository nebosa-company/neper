// The Linux look's button against the real GTK 4.14 / libadwaita 1.5 one: eight kinds (default, suggested-action,
// destructive-action, flat, circular, icon, flat icon, icon with caption) in five states (rest, hover, pressed, keyboard
// focus, disabled), docs/ui/looks/linux[-dark]/button.png. Next to it, button-vs-ref.png puts the library's own
// pixels on the left (docs/ui/looks/ref/linux/composite, built by scripts/linux/compose_ref.py). Run from the repository
// root; see docs/ui/looks-howto.md.

use e.mem
use e.str as strs
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

// Row `row` of the sheet in state `state` (0 rest, 1 hover, 2 pressed, 3 focus, 4 disabled), key `key`.
fn one(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, key: widget.Key, row: usize, state: usize) -> (widget.Node, err) {
    var options = control.button_options()
    options.enabled = state != 4usize
    // The kinds, in the order of the library's gallery: default (Tonal), suggested (Filled), destructive (Danger), flat (Plain).
    if row == 0usize { options.variant = .Tonal }
    if row == 1usize { options.variant = .Filled }
    if row == 2usize { options.variant = .Danger }
    if row == 3usize || row == 6usize { options.variant = .Plain }
    if row == 4usize {
        options.variant = .Tonal
        options.circular = true
        let (node, node_error) = control.button_with_glyph(a, key, t, .Add, "", action, options)
        ret (node, node_error)
    }
    if row == 5usize || row == 6usize {
        if row == 5usize { options.variant = .Tonal }
        let (node, node_error) = control.button_with_glyph(a, key, t, .Maximize, "", action, options)
        ret (node, node_error)
    }
    if row == 7usize {
        options.variant = .Tonal
        let (node, node_error) = control.button_with_glyph(a, key, t, .Add, "Button", action, options)
        ret (node, node_error)
    }
    let (node, node_error) = control.button(a, key, t, "Button", action, options)
    ret (node, node_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let rows = [8]str{ "default", "suggested", "destructive", "flat", "circular", "icon", "flat icon", "icon + label" }
    let states = [5]str{ "rest", "hover", "pressed", "focus", "disabled" }
    var i = 0usize
    while i < 40usize {
        let row = i / 5usize
        let state = i % 5usize
        let (node, node_error) = one(a, t, &actions[0usize], u64(i + 1usize), row, state)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if state == 1usize { drive = .Hover }
        if state == 2usize { drive = .Press }
        if state == 3usize { drive = .Focus }
        let (caption, caption_error) = looks_caption(a, rows[row], states[state])
        if caption_error != ok { ret (0usize, caption_error) }
        cells[i] = looks.Cell { caption: caption, node: node, drive: drive }
        i += 1usize
    }
    ret (40usize, ok)
}

fn looks_caption(a: *mem.Arena, kind: str, state: str) -> (str, err) {
    let parts = [2]str{ kind, state }
    let (joined, joined_error) = strs.join(a, parts[0usize..2usize], " ")
    ret (joined, joined_error)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "button", cells: 40usize, columns: 5usize, cell_w: 100.0, cell_h: 44.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
