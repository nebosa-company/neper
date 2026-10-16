// The Android look's text fields, docs/ui/looks/material/text_field.png: filled and outlined with a floating label, in
// enabled, hovered, focused (empty and with text), with a value, disabled and error, with supporting text under them.
// Run from the repository root.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_change(ctx: *void, value: str) -> err { ret ok }
fn noop_submit(ctx: *void) -> err { ret ok }

// 12 cells, 6 per row: filled then outlined; enabled, hovered, focused, focused with text, disabled, error.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [6]str{ "Enabled", "Hovered", "Focused", "Focused, text", "Disabled", "Error" }
    var i = 0usize
    while i < 12usize {
        let column = i % 6usize
        let words = "Terminate"
        var n = 0usize
        let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        if column == 3usize || column == 4usize || column == 5usize {
            while n < words.len {
                buffer[n] = words[n]
                n += 1usize
            }
        }
        var options = control.field_options()
        options.width = 200.0
        options.filled = i < 6usize
        options.enabled = column != 4usize
        options.invalid = column == 5usize
        let key = u64(i + 1usize)
        let (field, field_error) = control.text_field(a, key, t, "Label", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Submit { ctx: zero, invoke: noop_submit }, options)
        if field_error != ok { ret (0usize, field_error) }
        var support = control.text_options()
        support.role = .BodySmall
        support.wrap = .None
        support.color = .OnSurfaceVariant
        var line = "Supporting text"
        if column == 5usize {
            support.color = .Error
            line = "Error text"
        }
        let (note, note_error) = control.text(a, 0u64, line, t, support)
        if note_error != ok { ret (0usize, note_error) }
        var inset = style.defaults()
        inset.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: style.Length { Px: 4.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
        let (under, under_error) = mem.alloc[widget.Node](a, 1usize)
        if under_error != ok { ret (0usize, under_error) }
        under[0usize] = note
        let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
        if pair_error != ok { ret (0usize, pair_error) }
        pair[0usize] = field
        pair[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, inset, under[0usize..1usize])
        let column_node = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), pair[0usize..2usize])
        var drive: looks.Drive = .None
        if column == 1usize { drive = .Hover }
        if column == 2usize || column == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: captions[column], node: column_node, drive: drive }
        i += 1usize
    }
    ret (12usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "text_field", cells: 12usize, columns: 6usize, cell_w: 210.0, cell_h: 84.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
