// The text edit (TcxTextEdit) in every state under every look: docs/ui/looks/<look>/text_edit.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_change(ctx: *void, value: str) -> err { ret ok }
fn noop_submit(ctx: *void) -> err { ret ok }

// Selects the whole text of the edit keyed `key` once the runtime has it (a driven cell's rebuild).
fn select_all(t: *const control.Theme, key: widget.Key, len: usize) {
    if mem.address_of(t.runtime) == 0usize { ret }
    let (s, state_error) = widget.state_of(t.runtime)
    if state_error != ok { ret }
    let (id, found) = widget.find_by_key(s, key)
    if found != 1usize { ret }
    let unused = widget.edit_select(t.runtime, id, 0usize, len)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [10]str{ "Rest", "Hover", "Focused", "Disabled", "Read-only", "Invalid", "Empty, placeholder", "Selected text", "Long text", "Empty, focused" }
    let texts = [10]str{ "Terminate", "Terminate", "Terminate", "Terminate", "Terminate", "Terminate", "", "Terminate", "Heroic Intervention of the Marvel Universe", "" }
    var i = 0usize
    while i < 10usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 128usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        var n = 0usize
        while n < texts[i].len {
            buffer[n] = texts[i][n]
            n += 1usize
        }
        var options = control.field_options()
        options.width = 140.0
        options.placeholder = "Card name"
        if i == 3usize { options.enabled = false }
        if i == 4usize { options.read_only = true }
        if i == 5usize { options.invalid = true }
        if i != 6usize && i != 9usize { options.placeholder = "" }
        let key = u64(i + 1usize)
        let (node, node_error) = control.text_field(a, key, t, "Card name", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Submit { ctx: zero, invoke: noop_submit }, options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize || i == 7usize || i == 9usize { drive = .Focus }
        if i == 7usize { select_all(t, key, n) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (10usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "text_edit", cells: 10usize, columns: 5usize, cell_w: 160.0, cell_h: 56.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
