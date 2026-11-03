// The password field with its reveal button in every look: docs/ui/looks/<look>/password_field.png. Empty (placeholder), masked,
// hover, keyboard focus, revealed, disabled and invalid. Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_a
use e.ui.widget

fn noop_change(ctx: *void, value: str) -> err { ret ok }
fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [7]str{ "empty", "masked", "hover", "focus", "revealed", "disabled", "invalid" }
    let values = [7]str{ "", "hunter2hunter2", "hunter2hunter2", "hunter2hunter2", "hunter2hunter2", "hunter2hunter2", "short" }
    let (reveal, reveal_error) = mem.alloc[widget.Submit](a, 1usize)
    if reveal_error != ok { ret (0usize, reveal_error) }
    reveal[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var i = 0usize
    while i < 7usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 128usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let len = control.copy_text(buffer, values[i])
        var options = control.field_options()
        options.width = 200.0
        options.placeholder = "Password"
        if i == 5usize { options.enabled = false }
        if i == 6usize { options.invalid = true }
        let change = widget.Change[str] { ctx: zero, invoke: noop_change }
        let submit = widget.Submit { ctx: zero, invoke: noop_submit }
        let (node, node_error) = control.password_field_with(a, u64((i + 1usize) * 10usize), t, "Password", buffer, len, change, submit, options, i == 4usize, &reveal[0usize])
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 2usize { drive = .Hover }
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (7usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "password_field", cells: 7usize, columns: 3usize, cell_w: 236.0, cell_h: 60.0, ctx: zero, build: build }
    ret looks_a.run_every(a, &sheet)
}
