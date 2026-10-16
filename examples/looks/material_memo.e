// The Android look's memo: a multi-line outlined or filled text field with its supporting text and character counter
// (docs/ui/looks/material/memo.png). Run from the repository root.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_change(ctx: *void, value: str) -> err { ret ok }

fn select_all(t: *const control.Theme, key: widget.Key, len: usize) {
    if mem.address_of(t.runtime) == 0usize { ret }
    let (s, state_error) = widget.state_of(t.runtime)
    if state_error != ok { ret }
    let (id, found) = widget.find_by_key(s, key)
    if found != 1usize { ret }
    let unused = widget.edit_select(t.runtime, id, 0usize, len)
}

fn supporting(a: *mem.Arena, t: *const control.Theme, field: widget.Node, line: str, counter: str, bad: bool, width: f32) -> (widget.Node, err) {
    var support = control.text_options()
    support.role = .BodySmall
    support.wrap = .None
    support.color = .OnSurfaceVariant
    if bad { support.color = .Error }
    let (note, note_error) = control.text(a, 0u64, line, t, support)
    if note_error != ok { ret (zero, note_error) }
    var count_options = support
    count_options.color = .OnSurfaceVariant
    let (count, count_error) = control.text(a, 0u64, counter, t, count_options)
    if count_error != ok { ret (zero, count_error) }
    var grow = style.defaults()
    grow.width = style.Length { Flex: 1.0 }
    var note_grown = note
    var inset = style.defaults()
    inset.width = style.Length { Px: width }
    inset.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: style.Length { Px: 4.0 }, right: style.Length { Px: 16.0 }, bottom: style.Length { Px: 0.0 } }
    let (under, under_error) = mem.alloc[widget.Node](a, 3usize)
    if under_error != ok { ret (zero, under_error) }
    under[0usize] = note_grown
    under[1usize] = widget.box(0u64, grow, zero)
    under[2usize] = count
    let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
    if pair_error != ok { ret (zero, pair_error) }
    pair[0usize] = field
    pair[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, inset, under[0usize..3usize])
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), pair[0usize..2usize]), ok)
}

// Ten cells, 5 per row: outlined enabled, hovered, focused with text selected, disabled, read-only; then error, empty with a
// placeholder, the text longer than its rows (the scrollbar), filled, filled focused.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [10]str{ "Enabled", "Hovered", "Focused, selected", "Disabled", "Read-only", "Error", "Empty, placeholder", "Scrolling", "Filled", "Filled, focused" }
    let short = "Permanents you control gain hexproof and indestructible until end of turn."
    let long = "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8\nLine 9\nLine 10"
    var i = 0usize
    while i < 10usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 256usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        var words = short
        if i == 6usize { words = "" }
        if i == 7usize { words = long }
        var n = 0usize
        while n < words.len {
            buffer[n] = words[n]
            n += 1usize
        }
        var options = control.field_options()
        options.width = 200.0
        options.rows = 4u32
        options.end_space = 8.0
        options.placeholder = ""
        if i == 6usize { options.placeholder = "Write a note" }
        if i == 3usize { options.enabled = false }
        if i == 4usize { options.read_only = true }
        if i == 5usize { options.invalid = true }
        if i >= 8usize { options.filled = true }
        let key = u64(1000usize * (i + 1usize))
        let (node, node_error) = control.text_area(a, key, t, "Notes", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, options)
        if node_error != ok { ret (0usize, node_error) }
        var line = "Supporting text"
        var counter = "74 / 120"
        if i == 5usize {
            line = "Too long"
            counter = "74 / 60"
        }
        if i == 6usize { counter = "0 / 120" }
        if i == 7usize { counter = "56 / 120" }
        let (full, full_error) = supporting(a, t, node, line, counter, i == 5usize, 200.0)
        if full_error != ok { ret (0usize, full_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize || i == 9usize { drive = .Press }
        if i == 2usize { select_all(t, key, 11usize) }
        cells[i] = looks.Cell { caption: captions[i], node: full, drive: drive }
        i += 1usize
    }
    ret (10usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "memo", cells: 10usize, columns: 5usize, cell_w: 230.0, cell_h: 150.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
