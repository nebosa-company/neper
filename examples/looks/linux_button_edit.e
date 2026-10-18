// The Linux look's button edit (an entry with a flat icon button at its end) against GTK 4.14 / libadwaita 1.5:
// docs/ui/looks/linux[-dark]/button_edit.png, with button_edit-vs-ref.png beside it (reference on the left, built by
// scripts/linux_cmp_l1.py). The first cell is the captured state; the others (focus, disabled, hover over the button) have no
// reference crop. Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_change(ctx: *void, value: str) -> err { ret ok }
fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [4]str{ "rest", "focus", "disabled", "hover button" }
    var i = 0usize
    while i < 4usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 16usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let words = "Value"
        var n = 0usize
        while n < words.len {
            buffer[n] = words[n]
            n += 1usize
        }
        var options = control.field_options()
        options.width = 201.0
        options.enabled = i != 2usize
        let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
        if actions_error != ok { ret (0usize, actions_error) }
        actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
        actions[1usize] = widget.Submit { ctx: zero, invoke: noop_submit }
        let (node, node_error) = control.button_edit(a, u64(10usize * (i + 1usize)), t, "Folder", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, actions[0usize], &actions[1usize], "Browse", options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "button_edit", cells: 4usize, columns: 4usize, cell_w: 221.0, cell_h: 44.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
