// The radio group's items in the states the live v3 captures show: docs/ui/looks/<look>/radio_group_states.png.
// Rows: Cards and Collection of the Search for Card dialog (a flat group), "Search from start" and "Search
// within" of the Options Grids page; columns rest and pressed (mouse down). The short items stand at x 136 of
// their cell so the harness's pointer, at the cell centre, lands on them. Reference composite:
// ref/windows/radio_group_states.png (scripts/looks_refs_b.py).

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let action = &actions[0usize]
    let labels = [4]str{ "Cards", "Collection", "Search from start (typing \"War\" would not find \"Fog of War\")", "Search within (typing \"War\" would find \"Fog of War\")" }
    let selected = [4]bool{ true, false, true, false }
    let xs = [4]f32{ 140.0, 140.0, 4.0, 4.0 }
    let (held, held_error) = mem.alloc[widget.Node](a, 16usize)
    if held_error != ok { ret (0usize, held_error) }
    var i = 0usize
    while i < 8usize {
        let row = i / 2usize
        let column = i % 2usize
        var made: widget.Node = zero
        if t.tokens.profile == .Windows {
            if row < 2usize {
                let (radio, radio_error) = control.windows_radio_sized(a, u64(i + 1usize), t, labels[row], selected[row], action, true, 42.0)
                if radio_error != ok { ret (0usize, radio_error) }
                made = radio
            } else {
                let (radio, radio_error) = control.windows_radio_options(a, u64(i + 1usize), t, labels[row], selected[row], action, true, 42.0)
                if radio_error != ok { ret (0usize, radio_error) }
                made = radio
            }
        } else {
            let (radio, radio_error) = control.radio(a, u64(i + 1usize), t, labels[row], selected[row], action, true)
            if radio_error != ok { ret (0usize, radio_error) }
            made = radio
        }
        held[i] = made
        held[8usize + i] = widget.positioned(0u64, xs[row], 4.0, style.defaults(), held[i..i + 1usize])
        var drive: looks.Drive = .None
        if column == 1usize { drive = .Press }
        var caption = "rest"
        if column == 1usize { caption = "pressed" }
        cells[i] = looks.Cell { caption: caption, node: widget.stack(0u64, looks.size_style(340.0, 50.0), held[8usize + i..9usize + i]), drive: drive }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "radio_group_states", cells: 8usize, columns: 2usize, cell_w: 340.0, cell_h: 50.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
