// The memo (TcxMemo) in every state under every look: docs/ui/looks/<look>/memo.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
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

// Eight cells: at rest with wrapped lines, hovered, focused, disabled, read-only, invalid, empty
// with a placeholder, and one whose text is longer than its rows (the scrollbar).
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [8]str{ "Rest, wrapped", "Hover", "Focused, selected", "Disabled", "Read-only", "Invalid", "Empty, placeholder", "Scrollbar" }
    let short = "Permanents you control gain hexproof and indestructible until end of turn."
    let long = "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8\nLine 9\nLine 10"
    var i = 0usize
    while i < 8usize {
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
        options.placeholder = ""
        if i == 6usize { options.placeholder = "Notes" }
        if i == 3usize { options.enabled = false }
        if i == 4usize { options.read_only = true }
        if i == 5usize { options.invalid = true }
        let key = u64(1000usize * (i + 1usize))
        let (node, node_error) = control.text_area(a, key, t, "Notes", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        if i == 2usize { select_all(t, key, 11usize) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "memo", cells: 8usize, columns: 4usize, cell_w: 215.0, cell_h: 135.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
