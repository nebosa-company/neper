// The check box in the interaction states the live v3 captures show: docs/ui/looks/<look>/checkbox_states.png.
// Rows are controls of the Options pages (Interface hide splash, Grids filter row and foil symbol,
// Morph use, Interface tooltips), columns rest, pressed (mouse down) and keyboard focus. Reference
// composite: ref/windows/checkbox_states.png (scripts/looks_refs_b.py), crops of
// ref/windows/states/*. A blank cell has no capture. Show Foil Symbol's pressed grab (cell 7) shows only the focus
// rectangle on a checked box, so that cell is driven with the focus.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget
use e.ui.winbutton

// The label without its '&' mnemonic mark (only the Windows look draws it).
fn plain(a: *mem.Arena, label: str) -> str {
    let (shown, mark, shown_error) = winbutton.mnemonic(a, label)
    if shown_error != ok { ret label }
    ret shown
}

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let action = &actions[0usize]
    let labels = [5]str{ "Hide splash screen on start", "Show Filter &Row", "Show Foil &Symbol", "&Use Morph effect", "Show tooltips" }
    let checked = [5]bool{ false, false, true, true, true }
    let columns = [3]str{ "rest", "pressed", "focus" }
    let window_xs = [5]f32{ 215.0, 224.0, 224.0, 215.0, 215.0 }
    let window_ys = [5]f32{ 74.0, 132.0, 102.0, 71.0, 155.0 }
    let skip = [15]bool{ false, false, false, false, false, true, false, false, false, false, false, false, false, false, false }
    let (held, held_error) = mem.alloc[widget.Node](a, 15usize)
    if held_error != ok { ret (0usize, held_error) }
    let first = looks.size_style(160.0, 29.0)
    var i = 0usize
    while i < 15usize {
        let row = i / 3usize
        let column = i % 3usize
        if skip[i] {
            cells[i] = looks.Cell { caption: "no capture", node: widget.stack(0u64, first, zero), drive: .None }
            i += 1usize
            continue
        }
        var box: widget.Node = zero
        if t.tokens.profile == .Windows {
            let (made, made_error) = control.windows_checkbox_phase(a, u64(i + 1usize), t, labels[row], checked[row], false, action, true, 21.0, false, 0u32, window_xs[row], window_ys[row])
            if made_error != ok { ret (0usize, made_error) }
            box = made
        } else {
            let (made, made_error) = control.checkbox(a, u64(i + 1usize), t, plain(a, labels[row]), checked[row], false, action, true)
            if made_error != ok { ret (0usize, made_error) }
            box = made
        }
        held[i] = box
        let placed = widget.positioned(0u64, 4.0, 4.0, style.defaults(), held[i..i + 1usize])
        var drive: looks.Drive = .None
        if column == 1usize { drive = .Press }
        if column == 2usize || i == 7usize { drive = .Focus }
        cells[i] = looks.Cell { caption: columns[column], node: widget.stack(0u64, first, zero), drive: drive }
        let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
        if inner_error != ok { ret (0usize, inner_error) }
        inner[0usize] = placed
        cells[i].node = widget.stack(0u64, first, inner[0usize..1usize])
        i += 1usize
    }
    ret (15usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "checkbox_states", cells: 15usize, columns: 3usize, cell_w: 160.0, cell_h: 29.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
