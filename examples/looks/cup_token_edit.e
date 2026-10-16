// The token edit (TdxTokenEdit) in every state under every look: docs/ui/looks/<look>/token_edit.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_change(ctx: *void, value: str) -> err { ret ok }
fn noop_submit(ctx: *void) -> err { ret ok }

// The control with spacers round it (above, below, right) so that the middle of the whole box,
// which is what the harness drives, lands on a chosen point of the control: an arrow button.
fn aimed(a: *mem.Arena, node: widget.Node, above: f32, below: f32, left: f32, right: f32) -> (widget.Node, err) {
    let (column, column_error) = mem.alloc[widget.Node](a, 3usize)
    if column_error != ok { ret (zero, column_error) }
    column[0usize] = widget.box(0u64, sized(1.0, above), zero)
    column[1usize] = node
    column[2usize] = widget.box(0u64, sized(1.0, below), zero)
    let (row, row_error) = mem.alloc[widget.Node](a, 3usize)
    if row_error != ok { ret (zero, row_error) }
    row[0usize] = widget.box(0u64, sized(left, 1.0), zero)
    row[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), column[0usize..3usize])
    row[2usize] = widget.box(0u64, sized(right, 1.0), zero)
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), row[0usize..3usize]), ok)
}

fn sized(w: f32, h: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    ret s
}

// Eight cells: three tokens at rest, a hovered token, a hovered close cross, the input focused
// with tokens, the empty edit focused (hint hidden), the empty edit at rest (hint), a long token
// list wrapped to two lines and one token alone.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [8]str{ "Rest", "Hover token", "Hover close", "Focused", "Empty, focused", "Empty, hint", "Wrapped", "One token" }
    let names = [8]str{ "Flying", "Trample", "Haste", "Vigilance", "Deathtouch", "Lifelink", "Reach", "Menace" }
    var i = 0usize
    while i < 8usize {
        var count = 3usize
        if i == 4usize || i == 5usize { count = 0usize }
        if i == 6usize { count = 7usize }
        if i == 3usize { count = 2usize }
        if i == 7usize { count = 1usize }
        let (shown, shown_error) = mem.alloc[str](a, 8usize)
        if shown_error != ok { ret (0usize, shown_error) }
        let (removes, removes_error) = mem.alloc[widget.Submit](a, 8usize)
        if removes_error != ok { ret (0usize, removes_error) }
        var n = 0usize
        while n < count {
            shown[n] = names[n]
            removes[n] = widget.Submit { ctx: zero, invoke: noop_submit }
            n += 1usize
        }
        let (buffer, buffer_error) = mem.alloc[u8](a, 32usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let none_words = [1]str{ "" }
        let picks = [1]widget.Submit{ widget.Submit { ctx: zero, invoke: noop_submit } }
        let dismiss = widget.Submit { ctx: zero, invoke: noop_submit }
        let key = u64(100usize * (i + 1usize))
        let (edit, edit_error) = control.token_field(a, key, t, "Add keyword", shown[0usize..count], removes[0usize..count], buffer, 0usize, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Submit { ctx: zero, invoke: noop_submit }, none_words[0usize..0usize], 0usize, false, picks[0usize..0usize], widget.Change[usize] { ctx: zero, invoke: noop_active }, &dismiss, 300.0)
        if edit_error != ok { ret (0usize, edit_error) }
        var node = edit
        var drive: looks.Drive = .None
        if i == 1usize {
            // The first token: its middle is 30 from the left.
            let (aim, aim_error) = aimed(a, edit, 0.0, 0.0, 224.0, 0.0)
            if aim_error != ok { ret (0usize, aim_error) }
            node = aim
            drive = .Hover
        }
        if i == 2usize {
            let (aim, aim_error) = aimed(a, edit, 0.0, 0.0, 184.0, 0.0)
            if aim_error != ok { ret (0usize, aim_error) }
            node = aim
            drive = .Hover
        }
        if i == 3usize {
            let (aim, aim_error) = aimed(a, edit, 0.0, 0.0, 0.0, 100.0)
            if aim_error != ok { ret (0usize, aim_error) }
            node = aim
            drive = .Focus
        }
        if i == 4usize { drive = .Focus }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (8usize, ok)
}

fn noop_active(ctx: *void, value: usize) -> err { ret ok }

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "token_edit", cells: 8usize, columns: 3usize, cell_w: 530.0, cell_h: 130.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
