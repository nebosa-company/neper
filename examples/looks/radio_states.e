// The radio button in the interaction states the live v3 captures show: docs/ui/looks/<look>/radio_states.png.
// Rows: Missing Only (selected) and Available Only (unselected) of the Missing Set Cards dialog, Blocks and
// Formats of the Filter dialog (on its #F9F9F9 tab page); columns rest, pressed (mouse down), keyboard focus.
// A blank cell has no usable capture (the focused grabs of the Filter radios show a stale pressed disc).
// Reference composite: ref/windows/radio_states.png (scripts/looks_refs_b.py).

use e.mem
use e.gfx.paint
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget
use e.ui.winbutton

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
    let labels = [4]str{ "&Missing Only", "&Available Only", "Blocks", "Formats" }
    let selected = [4]bool{ true, false, true, false }
    let xs = [4]f32{ 4.0, 4.0, 40.0, 40.0 }
    let skip = [12]bool{ false, true, false, false, false, true, false, false, true, false, false, true }
    let columns = [3]str{ "rest", "pressed", "focus" }
    let (held, held_error) = mem.alloc[widget.Node](a, 24usize)
    if held_error != ok { ret (0usize, held_error) }
    var i = 0usize
    while i < 12usize {
        let row = i / 3usize
        let column = i % 3usize
        var cell_style = looks.size_style(150.0, 25.0)
        if t.tokens.profile == .Windows && row >= 2usize { cell_style.background = paint.Brush { Solid: style.hex(16382457u32) } }
        if skip[i] {
            cells[i] = looks.Cell { caption: "no capture", node: widget.stack(0u64, cell_style, zero), drive: .None }
            i += 1usize
            continue
        }
        var made: widget.Node = zero
        if t.tokens.profile == .Windows {
            let (radio, radio_error) = control.windows_radio_sized(a, u64(i + 1usize), t, labels[row], selected[row], action, true, 17.0)
            if radio_error != ok { ret (0usize, radio_error) }
            made = radio
        } else {
            let (radio, radio_error) = control.radio(a, u64(i + 1usize), t, plain(a, labels[row]), selected[row], action, true)
            if radio_error != ok { ret (0usize, radio_error) }
            made = radio
        }
        held[i] = made
        held[12usize + i] = widget.positioned(0u64, xs[row], 4.0, style.defaults(), held[i..i + 1usize])
        var drive: looks.Drive = .None
        if column == 1usize { drive = .Press }
        if column == 2usize { drive = .Focus }
        cells[i] = looks.Cell { caption: columns[column], node: widget.stack(0u64, cell_style, held[12usize + i..13usize + i]), drive: drive }
        i += 1usize
    }
    ret (12usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "radio_states", cells: 12usize, columns: 3usize, cell_w: 150.0, cell_h: 25.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
