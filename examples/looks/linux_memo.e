// The Linux look's memo (a text area) against the real GTK 4.14 / libadwaita 1.5 text view in a framed scrolled window
// (scripts/linux_cmp_l2.py): rest, focus (the view shows no ring), disabled, and text selected (no GTK twin).
// docs/ui/looks/linux[-dark]/memo.png. Run from the repository root; see docs/ui/looks-howto.md.

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

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    control.set_native_caret_off(true)
    let captions = [4]str{ "rest", "focus", "disabled", "selected" }
    var i = 0usize
    while i < 4usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 128usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let text = "Multi-line\ntext area"
        var n = 0usize
        while n < text.len {
            buffer[n] = text[n]
            n += 1usize
        }
        var options = control.field_options()
        options.width = 220.0
        options.height = 100.0
        options.rows = 2u32
        if i == 2usize { options.enabled = false }
        let key = u64(10usize * (i + 1usize))
        let (node, node_error) = control.text_area(a, key, t, "Notes", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Focus }
        if i == 3usize {
            drive = .Select
            select_all(t, key, n)
        }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "memo", cells: 4usize, columns: 2usize, cell_w: 230.0, cell_h: 110.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
