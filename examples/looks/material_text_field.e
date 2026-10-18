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
    let extra = [4]str{ "Value", "Value, hovered", "Empty, disabled", "Empty, error" }
    var i = 0usize
    while i < 20usize {
        // Cells 12 to 19 (filled 12 to 15, outlined 16 to 19): with a value, hovered; with a value; empty, disabled; empty, error.
        var column = i % 6usize
        let more = i >= 12usize
        var kind = 0usize
        if more { kind = (i - 12usize) % 4usize }
        var filled_row = i < 6usize
        if more {
            filled_row = i < 16usize
            let mapped = [4]usize{ 0usize, 1usize, 4usize, 5usize }
            column = mapped[kind]
        }
        let words = "Terminate"
        var n = 0usize
        let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        var has_value = column == 3usize || column == 4usize || column == 5usize
        if more { has_value = kind == 0usize || kind == 1usize }
        if has_value {
            while n < words.len {
                buffer[n] = words[n]
                n += 1usize
            }
        }
        var options = control.field_options()
        options.width = 240.0
        options.filled = filled_row
        options.enabled = column != 4usize
        options.invalid = column == 5usize
        if more {
            options.enabled = kind != 2usize
            options.invalid = kind == 3usize
        }
        let key = u64(i + 1usize)
        let (field, field_error) = control.text_field(a, key, t, "Label", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Submit { ctx: zero, invoke: noop_submit }, options)
        if field_error != ok { ret (0usize, field_error) }
        var support = control.text_options()
        support.role = .BodySmall
        support.wrap = .None
        support.color = .OnSurfaceVariant
        if column == 4usize { support.color = .OnSurface }
        var line = "Supporting text"
        if column == 5usize {
            support.color = .Error
            line = "Error text"
        }
        let (note, note_error) = control.text(a, 0u64, line, t, support)
        if note_error != ok { ret (0usize, note_error) }
        var inset = style.defaults()
        if column == 4usize { inset.opacity = 0.38 }
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
        var caption = captions[column]
        if column == 1usize {
            drive = .Hover
        }
        if column == 2usize || column == 3usize { drive = .Focus }
        if more {
            caption = extra[kind]
            drive = .None
            if kind == 1usize { drive = .Hover }
        }
        cells[i] = looks.Cell { caption: caption, node: column_node, drive: drive }
        i += 1usize
    }
    // Cells 20 and 21: a leading search icon and a trailing clear icon (24 dp in `on-surface-variant`, 12 in from the sides), filled then outlined.
    var j = 0usize
    while j < 2usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let words = "Terminate"
        var n = 0usize
        while n < words.len {
            buffer[n] = words[n]
            n += 1usize
        }
        var options = control.field_options()
        options.width = 240.0
        options.filled = j == 0usize
        options.start_space = 36.0
        options.end_space = 36.0
        let (field, field_error) = control.text_field(a, u64(100usize + j), t, "Label", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Submit { ctx: zero, invoke: noop_submit }, options)
        if field_error != ok { ret (0usize, field_error) }
        let ink = style.color(t.tokens, .OnSurfaceVariant)
        let (lens, lens_error) = control.icon_square(a, ink, .Search, 24.0)
        if lens_error != ok { ret (0usize, lens_error) }
        let (clear, clear_error) = control.icon_square(a, ink, .Cross, 24.0)
        if clear_error != ok { ret (0usize, clear_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 2usize)
        if held_error != ok { ret (0usize, held_error) }
        held[0usize] = lens
        held[1usize] = clear
        let (layers, layers_error) = mem.alloc[widget.Node](a, 3usize)
        if layers_error != ok { ret (0usize, layers_error) }
        layers[0usize] = field
        layers[1usize] = widget.positioned(0u64, 12.0, 16.0, style.defaults(), held[0usize..1usize])
        layers[2usize] = widget.positioned(0u64, 204.0, 16.0, style.defaults(), held[1usize..2usize])
        var support = control.text_options()
        support.role = .BodySmall
        support.wrap = .None
        support.color = .OnSurfaceVariant
        let (note, note_error) = control.text(a, 0u64, "Supporting text", t, support)
        if note_error != ok { ret (0usize, note_error) }
        var inset = style.defaults()
        inset.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: style.Length { Px: 4.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
        let (under, under_error) = mem.alloc[widget.Node](a, 1usize)
        if under_error != ok { ret (0usize, under_error) }
        under[0usize] = note
        let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
        if pair_error != ok { ret (0usize, pair_error) }
        pair[0usize] = widget.stack(0u64, style.defaults(), layers[0usize..3usize])
        pair[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, inset, under[0usize..1usize])
        cells[20usize + j] = looks.Cell { caption: "Icons", node: widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), pair[0usize..2usize]), drive: .None }
        j += 1usize
    }
    ret (22usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "text_field", cells: 22usize, columns: 6usize, cell_w: 270.0, cell_h: 96.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
