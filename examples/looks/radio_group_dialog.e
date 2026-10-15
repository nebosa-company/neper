// The radio group as v3's dialogs lay it out: docs/ui/looks/<look>/radio_group_dialog.png. Two cells
// reproduce crops of the live 100 % captures (docs/ui/looks/ref/windows/dialogs): the Options
// Grids page's two groups (486 x 105, long captions) and the Search for Card dialog's "Search in"
// group (289 x 105). Reference: ref/windows/radio_group_dialog.png.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn at(a: *mem.Arena, node: widget.Node, x: f32, y: f32) -> (widget.Node, err) {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = node
    ret (widget.positioned(0u64, x, y, style.defaults(), held[0usize..1usize]), ok)
}

fn group(a: *mem.Arena, t: *const control.Theme, actions: []const widget.Submit, key: u64, label: str, labels: []const str, selected: usize, width: f32, x: f32, y: f32, flat: bool) -> (widget.Node, err) {
    var made: widget.Node = zero
    if t.tokens.profile == .Windows {
        if flat {
            // The Search for Card dialog's group has Style.BorderStyle = ebsFlat: a square frame.
            let (framed, framed_error) = control.windows_radio_group_flat(a, key, t, label, labels, selected, actions, true, width, 105.0)
            if framed_error != ok { ret (zero, framed_error) }
            made = framed
        } else {
            let (framed, framed_error) = control.windows_radio_group_sized(a, key, t, label, labels, selected, actions, true, width, 105.0)
            if framed_error != ok { ret (zero, framed_error) }
            made = framed
        }
    } else {
        let (framed, framed_error) = control.radio_group(a, key, t, label, labels, selected, actions, true)
        if framed_error != ok { ret (zero, framed_error) }
        made = framed
    }
    let (placed, placed_error) = at(a, made, x, y)
    ret (placed, placed_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    actions[1usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let incremental = [2]str{ "Search from start (typing \"War\" would not find \"Fog of War\")", "Search within (typing \"War\" would find \"Fog of War\")" }
    let enter = [2]str{ "Move to next column", "Move to next row" }
    let scope = [2]str{ "Cards", "Collection" }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (0usize, parts_error) }
    // Grids page: crop (220,190)-(716,414); the groups at (224,194) and (224,305), 486 x 105.
    let (g0, e0) = group(a, t, actions[0usize..2usize], 1u64, "Incremental Search: ", incremental[0usize..2usize], 0usize, 486.0, 4.0, 4.0, false)
    if e0 != ok { ret (0usize, e0) }
    let (g1, e1) = group(a, t, actions[0usize..2usize], 11u64, "Enter Key Action: ", enter[0usize..2usize], 0usize, 486.0, 4.0, 115.0, false)
    if e1 != ok { ret (0usize, e1) }
    parts[0usize] = g0
    parts[1usize] = g1
    cells[0usize] = looks.Cell { caption: "Options, Grids page", node: widget.stack(0u64, looks.size_style(496.0, 224.0), parts[0usize..2usize]), drive: .None }
    // Search for Card: crop (14,96)-(316,212); the group at (20,102), 289 x 105.
    let (g2, e2) = group(a, t, actions[0usize..2usize], 21u64, "Search in ", scope[0usize..2usize], 0usize, 289.0, 6.0, 6.0, true)
    if e2 != ok { ret (0usize, e2) }
    parts[2usize] = g2
    cells[1usize] = looks.Cell { caption: "Search for Card", node: widget.stack(0u64, looks.size_style(496.0, 224.0), parts[2usize..3usize]), drive: .None }
    ret (2usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "radio_group_dialog", cells: 2usize, columns: 1usize, cell_w: 496.0, cell_h: 224.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
