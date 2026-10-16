// The button edit (TcxButtonEdit, the ellipsis kind) in every state under every look:
// docs/ui/looks/<look>/button_edit.png. Run from the repository root; see docs/ui/looks-howto.md.

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
fn aimed(a: *mem.Arena, node: widget.Node, above: f32, below: f32, right: f32) -> (widget.Node, err) {
    let (column, column_error) = mem.alloc[widget.Node](a, 3usize)
    if column_error != ok { ret (zero, column_error) }
    column[0usize] = widget.box(0u64, sized(1.0, above), zero)
    column[1usize] = node
    column[2usize] = widget.box(0u64, sized(1.0, below), zero)
    let (row, row_error) = mem.alloc[widget.Node](a, 2usize)
    if row_error != ok { ret (zero, row_error) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), column[0usize..3usize])
    row[1usize] = widget.box(0u64, sized(right, 1.0), zero)
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), row[0usize..2usize]), ok)
}

fn sized(w: f32, h: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    ret s
}

// Ten cells: at rest, hovered over the field, over the button, the button pressed, focused,
// disabled, read-only, invalid, empty with a placeholder and a long path (ellipsis kept clear).
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [10]str{ "Rest", "Hover field", "Hover button", "Press button", "Focused", "Disabled", "Read-only", "Invalid", "Empty, placeholder", "Long text" }
    var i = 0usize
    while i < 10usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 128usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        var words = "D:/Decks"
        if i == 8usize { words = "" }
        if i == 9usize { words = "D:/Games/Magic/Decks/Modern/Tron" }
        var n = 0usize
        while n < words.len {
            buffer[n] = words[n]
            n += 1usize
        }
        var options = control.field_options()
        options.width = 170.0
        options.placeholder = ""
        if i == 8usize { options.placeholder = "Folder" }
        if i == 5usize { options.enabled = false }
        if i == 6usize { options.read_only = true }
        if i == 7usize { options.invalid = true }
        let key = u64(10usize * (i + 1usize))
        let action = widget.Submit { ctx: zero, invoke: noop_submit }
        let actions = [1]widget.Submit{ action }
        let (edit, edit_error) = control.button_edit(a, key, t, "Folder", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, action, &actions[0usize], "Browse", options)
        if edit_error != ok { ret (0usize, edit_error) }
        var node = edit
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 4usize { drive = .Focus }
        if i == 2usize || i == 3usize {
            let (aim, aim_error) = aimed(a, edit, 0.0, 0.0, 134.0)
            if aim_error != ok { ret (0usize, aim_error) }
            node = aim
            drive = .Hover
            if i == 3usize { drive = .Press }
        }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (10usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "button_edit", cells: 10usize, columns: 3usize, cell_w: 310.0, cell_h: 56.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
