// The Android look's mask edit: an outlined or filled field with the mask's fixed text as prefix and suffix, and the
// supporting text line below it (docs/ui/looks/material/mask_edit.png). Run from the repository root.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_change(ctx: *void, value: str) -> err { ret ok }
fn noop_submit(ctx: *void) -> err { ret ok }

// The mask: digits only (a DCI number); a value with anything else is invalid.
fn digits_only(ctx: *void, value: str) -> bool {
    var i = 0usize
    while i < value.len {
        if value[i] < 48u8 || value[i] > 57u8 { ret false }
        i += 1usize
    }
    ret true
}

fn same(ctx: *void, out: []u8, value: str) -> usize {
    var n = 0usize
    while n < value.len && n < out.len {
        out[n] = value[n]
        n += 1usize
    }
    ret n
}

fn select_all(t: *const control.Theme, key: widget.Key, len: usize) {
    if mem.address_of(t.runtime) == 0usize { ret }
    let (s, state_error) = widget.state_of(t.runtime)
    if state_error != ok { ret }
    let (id, found) = widget.find_by_key(s, key)
    if found != 1usize { ret }
    let unused = widget.edit_select(t.runtime, id, 0usize, len)
}

fn supporting(a: *mem.Arena, t: *const control.Theme, field: widget.Node, line: str, bad: bool) -> (widget.Node, err) {
    var support = control.text_options()
    support.role = .BodySmall
    support.wrap = .None
    support.color = .OnSurfaceVariant
    if bad { support.color = .Error }
    let (note, note_error) = control.text(a, 0u64, line, t, support)
    if note_error != ok { ret (zero, note_error) }
    var inset = style.defaults()
    inset.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: style.Length { Px: 4.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    let (under, under_error) = mem.alloc[widget.Node](a, 1usize)
    if under_error != ok { ret (zero, under_error) }
    under[0usize] = note
    let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
    if pair_error != ok { ret (zero, pair_error) }
    pair[0usize] = field
    pair[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, inset, under[0usize..1usize])
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), pair[0usize..2usize]), ok)
}

// Ten cells, 5 per row: enabled, hovered, focused, selected text, error (the mask rejects it), disabled, read-only, filled
// with prefix and suffix, empty with a placeholder, a password.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [10]str{ "Enabled", "Hovered", "Focused", "Selected text", "Error", "Disabled", "Read-only", "Filled, prefix and suffix", "Empty, placeholder", "Password" }
    let texts = [10]str{ "5551234567", "5551234567", "5551234567", "5551234567", "55512ab", "5551234567", "5551234567", "1250", "", "secret1" }
    let adapter = control.Format { ctx: zero, accept: digits_only, format: same }
    var i = 0usize
    while i < 10usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        var n = 0usize
        while n < texts[i].len {
            buffer[n] = texts[i][n]
            n += 1usize
        }
        var options = control.field_options()
        options.width = 190.0
        if i == 4usize { options.invalid = true }
        if i == 5usize { options.enabled = false }
        if i == 6usize { options.read_only = true }
        options.prefix = "+1 "
        var label = "Phone"
        var line = "Digits only"
        if i == 7usize {
            options.filled = true
            options.prefix = "$"
            options.suffix = "USD"
            label = "Amount"
            line = "Whole dollars"
        }
        if i == 8usize {
            options.prefix = ""
            options.placeholder = "5551234567"
        }
        if i == 4usize { line = "Digits only: remove the letters" }
        let key = u64(i + 1usize)
        var node: widget.Node = zero
        if i == 9usize {
            options.prefix = ""
            label = "Password"
            line = "At least 6 characters"
            let (secret, secret_error) = control.password_field(a, key, t, label, buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Submit { ctx: zero, invoke: noop_submit }, options)
            if secret_error != ok { ret (0usize, secret_error) }
            node = secret
        } else {
            let (masked, masked_error) = control.formatted_field(a, key, t, label, buffer, n, adapter, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Change[str] { ctx: zero, invoke: noop_change }, options)
            if masked_error != ok { ret (0usize, masked_error) }
            node = masked
        }
        let (full, full_error) = supporting(a, t, node, line, i == 4usize)
        if full_error != ok { ret (0usize, full_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize || i == 3usize { drive = .Focus }
        if i == 3usize { select_all(t, key, n) }
        cells[i] = looks.Cell { caption: captions[i], node: full, drive: drive }
        i += 1usize
    }
    ret (10usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "mask_edit", cells: 10usize, columns: 5usize, cell_w: 220.0, cell_h: 96.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
