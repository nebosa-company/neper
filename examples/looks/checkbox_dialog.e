// The check box as v3's Options pages lay it out: docs/ui/looks/<look>/checkbox_dialog.png.
// Three cells reproduce crops of the live 100 % captures (docs/ui/looks/ref/windows/dialogs):
// Interface page (one unchecked, three checked), Grids page (two checked) and Morph page (a row
// 21 tall and one 17 tall that overlaps it). Reference composite: ref/windows/checkbox_dialog.png.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
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

// `node` `x` px from the left and `y` px from the top of a stack of `w` x `h`.
fn at(a: *mem.Arena, node: widget.Node, x: f32, y: f32) -> (widget.Node, err) {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = node
    ret (widget.positioned(0u64, x, y, style.defaults(), held[0usize..1usize]), ok)
}

fn one(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, key: u64, label: str, checked: bool, x: f32, y: f32, high: f32) -> (widget.Node, err) {
    var made: widget.Node = zero
    if t.tokens.profile == .Windows {
        // A row 17 tall is a TcxCheckBox without its transparent border: flush left.
        let (box, box_error) = control.windows_checkbox_sized(a, key, t, label, checked, false, action, true, high, high < 21.0)
        if box_error != ok { ret (zero, box_error) }
        made = box
    } else {
        let (box, box_error) = control.checkbox(a, key, t, plain(a, label), checked, false, action, true)
        if box_error != ok { ret (zero, box_error) }
        made = box
    }
    let (placed, placed_error) = at(a, made, x, y)
    ret (placed, placed_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let action = &actions[0usize]
    let (parts, parts_error) = mem.alloc[widget.Node](a, 12usize)
    if parts_error != ok { ret (0usize, parts_error) }
    // Interface page: crop (210,66)-(430,183); the controls at page x 215, y 74/101/128/155.
    let (a0, e0) = one(a, t, action, 1u64, "Hide splash screen on start", false, 5.0, 8.0, 21.0)
    if e0 != ok { ret (0usize, e0) }
    let (a1, e1) = one(a, t, action, 2u64, "Show card image while dragging", true, 5.0, 35.0, 21.0)
    if e1 != ok { ret (0usize, e1) }
    let (a2, e2) = one(a, t, action, 3u64, "Show card preview tooltip", true, 5.0, 62.0, 21.0)
    if e2 != ok { ret (0usize, e2) }
    let (a3, e3) = one(a, t, action, 4u64, "Show tooltips", true, 5.0, 89.0, 21.0)
    if e3 != ok { ret (0usize, e3) }
    parts[0usize] = a0
    parts[1usize] = a1
    parts[2usize] = a2
    parts[3usize] = a3
    let first = looks.size_style(290.0, 117.0)
    let one_cell = widget.stack(0u64, first, parts[0usize..4usize])
    cells[0usize] = looks.Cell { caption: "Interface page", node: one_cell, drive: .None }
    // Grids page: crop (220,96)-(510,160); the controls at page x 224, y 102/132.
    let (b0, f0) = one(a, t, action, 11u64, "Show Foil &Symbol", true, 4.0, 6.0, 21.0)
    if f0 != ok { ret (0usize, f0) }
    let (b1, f1) = one(a, t, action, 12u64, "Show Filter &Row", true, 4.0, 36.0, 21.0)
    if f1 != ok { ret (0usize, f1) }
    parts[4usize] = b0
    parts[5usize] = b1
    cells[1usize] = looks.Cell { caption: "Grids page", node: widget.stack(0u64, first, parts[4usize..6usize]), drive: .None }
    // Morph page: crop (210,240)-(500,272); Flip at page x 215 (21 tall), Back at 342 (17 tall), y 247.
    let (c0, g0) = one(a, t, action, 21u64, "Show '&Flip' button", true, 5.0, 7.0, 21.0)
    if g0 != ok { ret (0usize, g0) }
    let (c1, g1) = one(a, t, action, 22u64, "Show '&Back' button", true, 132.0, 7.0, 17.0)
    if g1 != ok { ret (0usize, g1) }
    parts[6usize] = c0
    parts[7usize] = c1
    cells[2usize] = looks.Cell { caption: "Morph page", node: widget.stack(0u64, first, parts[6usize..8usize]), drive: .None }
    ret (3usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "checkbox_dialog", cells: 3usize, columns: 3usize, cell_w: 290.0, cell_h: 117.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
