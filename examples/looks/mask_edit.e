// The mask edit (TcxMaskEdit) in every state under every look: docs/ui/looks/<look>/mask_edit.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
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

// Ten cells: a valid number at rest, hovered, focused, text selected, a number the mask rejects
// (invalid), disabled, read-only, empty with a placeholder, a password (echoed as bullets) and
// a long value.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [10]str{ "Rest", "Hover", "Focused", "Selected text", "Invalid (mask)", "Disabled", "Read-only", "Empty, placeholder", "Password", "Long text" }
    let texts = [10]str{ "1234567890", "1234567890", "1234567890", "1234567890", "12345ab", "1234567890", "1234567890", "", "secret1", "123456789012345678901234567890" }
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
        options.width = 140.0
        options.placeholder = ""
        if i == 5usize { options.enabled = false }
        if i == 6usize { options.read_only = true }
        if i == 7usize { options.placeholder = "DCI number" }
        let key = u64(i + 1usize)
        var node: widget.Node = zero
        if i == 8usize {
            let (secret, secret_error) = control.password_field(a, key, t, "Password", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Submit { ctx: zero, invoke: noop_submit }, options)
            if secret_error != ok { ret (0usize, secret_error) }
            node = secret
        } else {
            let (masked, masked_error) = control.formatted_field(a, key, t, "DCI number", buffer, n, adapter, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Change[str] { ctx: zero, invoke: noop_change }, options)
            if masked_error != ok { ret (0usize, masked_error) }
            node = masked
        }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize || i == 3usize { drive = .Focus }
        if i == 3usize { select_all(t, key, n) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (10usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "mask_edit", cells: 10usize, columns: 5usize, cell_w: 160.0, cell_h: 56.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
