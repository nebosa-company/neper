// The Linux look's group of radio buttons (First, Second, Third; the first selected) against GTK 4.14 / libadwaita 1.5:
// docs/ui/looks/linux[-dark]/radio_group.png, with radio_group-vs-ref.png beside it (reference on the left, built by
// scripts/linux_cmp_l1.py). Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 3usize)
    if actions_error != ok { ret (0usize, actions_error) }
    var i = 0usize
    while i < 3usize {
        actions[i] = widget.Submit { ctx: zero, invoke: noop_submit }
        i += 1usize
    }
    let labels = [3]str{ "First", "Second", "Third" }
    let (node, node_error) = control.radio_group(a, 1u64, t, "", labels[0usize..3usize], 0usize, actions[0usize..3usize], true)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "group", node: node, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "radio_group", cells: 1usize, columns: 1usize, cell_w: 101.0, cell_h: 96.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
