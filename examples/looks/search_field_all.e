// The search field in every look: docs/ui/looks/<look>/search_field_all.png (cup_text_field.e already owns search_field.png for
// Cupertino). Empty (placeholder), filled with its clear button, hover, keyboard focus, disabled and invalid. Run from the
// repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_a
use e.ui.widget

fn noop_change(ctx: *void, value: str) -> err { ret ok }
fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [6]str{ "empty", "filled", "hover", "focus", "disabled", "invalid" }
    let values = [6]str{ "", "mana curve", "mana curve", "mana curve", "mana curve", "mana curve" }
    let (cleared, cleared_error) = mem.alloc[widget.Submit](a, 1usize)
    if cleared_error != ok { ret (0usize, cleared_error) }
    cleared[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var i = 0usize
    while i < 6usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 128usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let len = control.copy_text(buffer, values[i])
        var options = control.field_options()
        options.width = 200.0
        if i == 4usize { options.enabled = false }
        if i == 5usize { options.invalid = true }
        let change = widget.Change[str] { ctx: zero, invoke: noop_change }
        let submit = widget.Submit { ctx: zero, invoke: noop_submit }
        let (node, node_error) = control.search_field(a, u64((i + 1usize) * 10usize), t, buffer, len, change, submit, &cleared[0usize], options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 2usize { drive = .Hover }
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "search_field_all", cells: 6usize, columns: 3usize, cell_w: 236.0, cell_h: 60.0, ctx: zero, build: build }
    ret looks_a.run_every(a, &sheet)
}
