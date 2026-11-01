// The group box and the Options pages' header bar as v3's dialogs draw them:
// docs/ui/looks/<look>/group_box_dialog.png. Cells reproduce crops of the live 100 % captures
// (docs/ui/looks/ref/windows/dialogs): the Deck Legality dialog's "Select Format" TcxGroupBox
// (513 x 93; its twelve buttons are blanked in the reference, they belong to the button sheet) and
// the TGradient header of the Interface, Rules and Grids pages. Reference: ref/windows/group_box_dialog.png.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn at(a: *mem.Arena, node: widget.Node, x: f32, y: f32) -> (widget.Node, err) {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = node
    ret (widget.positioned(0u64, x, y, style.defaults(), held[0usize..1usize]), ok)
}

// A header bar for page `title` at (x, y) of its cell.
fn bar(a: *mem.Arena, t: *const control.Theme, key: u64, title: str, y: f32) -> (widget.Node, err) {
    var made: widget.Node = zero
    if t.tokens.profile == .Windows {
        let (header, header_error) = control.windows_section_header(a, key, t, title, "General", 505.0)
        if header_error != ok { ret (zero, header_error) }
        made = header
    } else {
        var heading = control.text_options()
        heading.role = .TitleSmall
        heading.wrap = .None
        let (header, header_error) = control.text(a, key, title, t, heading)
        if header_error != ok { ret (zero, header_error) }
        made = header
    }
    let (placed, placed_error) = at(a, made, 2.0, y)
    ret (placed, placed_error)
}

fn noop_submit(ctx: *void) -> err { ret ok }

// The twelve format buttons of the live Deck Legality dialog (75 x 23 at its client positions, the form's DPI phase of examples/looks/dialog.e),
// placed relative to the group at (26, 39): round 12 builds them so the cell compares with the untouched capture, not a blanked one.
fn format_buttons(a: *mem.Arena, t: *const control.Theme, out: []widget.Node) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let names = [12]str{ "&Standard", "&Pioneer", "&Legacy", "&Vintage", "&All", "&Modern", "&Pauper", "&2HG", "&Commander", "Comm &1v1", "&Brawl", "P&easant" }
    let xs = [12]f32{ 41.0, 203.0, 284.0, 365.0, 446.0, 122.0, 41.0, 122.0, 203.0, 284.0, 365.0, 446.0 }
    let ys = [12]f32{ 66.0, 66.0, 66.0, 66.0, 66.0, 66.0, 95.0, 95.0, 95.0, 95.0, 95.0, 95.0 }
    var i = 0usize
    while i < 12usize {
        var bo = control.button_options()
        bo.width = 75.0
        bo.height = 23.0
        bo.shift_x = 0.01 + xs[i] * 0.000769
        bo.shift_y = ys[i] * 0.001099
        bo.ring_x = 0.0 - 0.0027 + xs[i] * 0.000745
        bo.ring_y = 0.0 - 0.0221 + ys[i] * 0.000748
        let (b, b_error) = control.button(a, 20u64 + u64(i), t, names[i], &actions[0usize], bo)
        if b_error != ok { ret (0usize, b_error) }
        let (placed, placed_error) = at(a, b, xs[i] - 26.0 + 1.0, ys[i] - 39.0 + 1.0)
        if placed_error != ok { ret (0usize, placed_error) }
        out[i] = placed
        i += 1usize
    }
    ret (12usize, ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 6usize)
    if parts_error != ok { ret (0usize, parts_error) }
    let (fmt, fmt_error) = mem.alloc[widget.Node](a, 12usize)
    if fmt_error != ok { ret (0usize, fmt_error) }
    var shown_buttons = 0usize
    if t.tokens.profile == .Windows {
        let (made_buttons, buttons_error) = format_buttons(a, t, fmt)
        if buttons_error != ok { ret (0usize, buttons_error) }
        shown_buttons = made_buttons
    }
    // Deck Legality: crop (20,30)-(545,138); the group at (26,39), 513 x 93, so at (6, 9); its right line sits 0.4 past
    // the 513 (the capture splits it over two columns, 530.4 to 531.4).
    var group: widget.Node = zero
    if t.tokens.profile == .Windows {
        let (framed, framed_error) = control.windows_group_exact(a, 1u64, t, "Select Format ", true, 513.0, 93.0, 0.0, 6.35, 513.4, 92.35, fmt[0usize..shown_buttons])
        if framed_error != ok { ret (0usize, framed_error) }
        group = framed
    } else {
        var options = control.group_options()
        options.width = 513.0
        let (framed, framed_error) = control.group_box_of(a, 1u64, t, "Select Format", options, parts[0usize..0usize])
        if framed_error != ok { ret (0usize, framed_error) }
        group = framed
    }
    let (placed, placed_error) = at(a, group, 6.0, 9.0)
    if placed_error != ok { ret (0usize, placed_error) }
    parts[0usize] = placed
    cells[0usize] = looks.Cell { caption: "Deck Legality: Select Format", node: widget.stack(0u64, looks.size_style(525.0, 108.0), parts[0usize..1usize]), drive: .None }
    // Options pages: crop (208,34)-(718,62); the TGradient at (210,36), so at (2, 2).
    let (b0, f0) = bar(a, t, 11u64, "Interface (F2)", 2.0)
    if f0 != ok { ret (0usize, f0) }
    let (b1, f1) = bar(a, t, 12u64, "Rules (F7)", 2.0)
    if f1 != ok { ret (0usize, f1) }
    let (b2, f2) = bar(a, t, 13u64, "Grids (F9)", 2.0)
    if f2 != ok { ret (0usize, f2) }
    parts[1usize] = b0
    parts[2usize] = b1
    parts[3usize] = b2
    cells[1usize] = looks.Cell { caption: "Options header: Interface", node: widget.stack(0u64, looks.size_style(525.0, 108.0), parts[1usize..2usize]), drive: .None }
    cells[2usize] = looks.Cell { caption: "Options header: Rules", node: widget.stack(0u64, looks.size_style(525.0, 108.0), parts[2usize..3usize]), drive: .None }
    cells[3usize] = looks.Cell { caption: "Options header: Grids", node: widget.stack(0u64, looks.size_style(525.0, 108.0), parts[3usize..4usize]), drive: .None }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "group_box_dialog", cells: 4usize, columns: 1usize, cell_w: 525.0, cell_h: 108.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
