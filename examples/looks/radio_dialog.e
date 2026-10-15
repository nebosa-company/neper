// The radio button as v3's dialogs lay it out: docs/ui/looks/<look>/radio_dialog.png. Two cells
// reproduce crops of the live 100 % captures (docs/ui/looks/ref/windows/dialogs): the "Show Cards"
// group of the Missing Set Cards dialog (three TcxRadioButton, 17 tall, in a TcxGroupBox) and the
// Blocks / Formats / Editions row of the Filter dialog. Reference: ref/windows/radio_dialog.png.

use e.mem
use e.gfx.paint
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

// A radio at (x, y) of its cell, `high` tall (the Windows look's TcxRadioButton; another look's own radio).
fn one(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, key: u64, label: str, selected: bool, x: f32, y: f32, high: f32) -> (widget.Node, err) {
    var made: widget.Node = zero
    if t.tokens.profile == .Windows {
        let (radio, radio_error) = control.windows_radio_sized(a, key, t, label, selected, action, true, high)
        if radio_error != ok { ret (zero, radio_error) }
        made = radio
    } else {
        let (radio, radio_error) = control.radio(a, key, t, label, selected, action, true)
        if radio_error != ok { ret (zero, radio_error) }
        made = radio
    }
    let (placed, placed_error) = at(a, made, x, y)
    ret (placed, placed_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let action = &actions[0usize]
    let (parts, parts_error) = mem.alloc[widget.Node](a, 8usize)
    if parts_error != ok { ret (0usize, parts_error) }
    // Missing Set Cards: crop (8,340)-(262,460); the group at (16,351) 234 x 99, radios at (+8,+21/45/69).
    let (r0, e0) = one(a, t, action, 1u64, "&Missing Only", true, 8.0, 21.0, 17.0)
    if e0 != ok { ret (0usize, e0) }
    let (r1, e1) = one(a, t, action, 2u64, "&Available Only", false, 8.0, 45.0, 17.0)
    if e1 != ok { ret (0usize, e1) }
    let (r2, e2) = one(a, t, action, 3u64, "&Both Missing and Available", false, 8.0, 69.0, 17.0)
    if e2 != ok { ret (0usize, e2) }
    parts[0usize] = r0
    parts[1usize] = r1
    parts[2usize] = r2
    var frame: widget.Node = zero
    if t.tokens.profile == .Windows {
        let (group, group_error) = control.windows_group_sized(a, 10u64, t, "Show Cards ", true, 234.0, 99.0, false, parts[0usize..3usize])
        if group_error != ok { ret (0usize, group_error) }
        frame = group
    } else {
        frame = widget.stack(0u64, style.defaults(), parts[0usize..3usize])
    }
    let (framed, framed_error) = at(a, frame, 8.0, 11.0)
    if framed_error != ok { ret (0usize, framed_error) }
    // Filter: crop (10,56)-(290,92); radios at (21,65) (82 wide), (109,65), (204,65), 17 tall.
    let (f0, g0) = one(a, t, action, 21u64, "Blocks", true, 11.0, 9.0, 17.0)
    if g0 != ok { ret (0usize, g0) }
    let (f1, g1) = one(a, t, action, 22u64, "Formats", false, 99.0, 9.0, 17.0)
    if g1 != ok { ret (0usize, g1) }
    let (f2, g2) = one(a, t, action, 23u64, "Editions", false, 194.0, 9.0, 17.0)
    if g2 != ok { ret (0usize, g2) }
    parts[3usize] = f0
    parts[4usize] = f1
    parts[5usize] = f2
    // The Filter dialog's tab page is #F9F9F9, lighter than the dialog face (measured); the crop is 30 tall.
    var page = looks.size_style(280.0, 120.0)
    if t.tokens.profile == .Windows { page.background = paint.Brush { Solid: style.hex(16382457u32) } }
    cells[1usize] = looks.Cell { caption: "Filter dialog (on its #F9F9F9 tab page)", node: widget.stack(0u64, page, parts[3usize..6usize]), drive: .None }
    parts[6usize] = framed
    cells[0usize] = looks.Cell { caption: "Show Cards (TcxRadioButton in a TcxGroupBox)", node: widget.stack(0u64, looks.size_style(280.0, 120.0), parts[6usize..7usize]), drive: .None }
    ret (2usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "radio_dialog", cells: 2usize, columns: 2usize, cell_w: 280.0, cell_h: 120.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
