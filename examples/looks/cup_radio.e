// The Cupertino (macOS) radio button and group: docs/ui/looks/cupertino/radio.png (and cupertino-dark). Rows off, on;
// columns rest, hover, pressed, focus, disabled; then a three-item group at rest and disabled.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 3usize)
    if actions_error != ok { ret (0usize, actions_error) }
    var n = 0usize
    while n < 3usize {
        actions[n] = widget.Submit { ctx: zero, invoke: noop_submit }
        n += 1usize
    }
    let columns = [5]str{ "rest", "hover", "pressed", "focus", "disabled" }
    var i = 0usize
    while i < 10usize {
        let row = i / 5usize
        let column = i % 5usize
        let (node, node_error) = control.radio(a, u64(i + 1usize), t, "Sort by name", row == 1usize, &actions[0usize], column != 4usize)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if column == 1usize { drive = .Hover }
        if column == 2usize { drive = .Press }
        if column == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: columns[column], node: node, drive: drive }
        i += 1usize
    }
    let labels = [3]str{ "Name", "Date modified", "Size" }
    let (g1, g1_error) = control.radio_group(a, 100u64, t, "Sort", labels[0usize..3usize], 1usize, actions[0usize..3usize], true)
    if g1_error != ok { ret (0usize, g1_error) }
    let (g2, g2_error) = control.radio_group(a, 200u64, t, "Sort", labels[0usize..3usize], 0usize, actions[0usize..3usize], false)
    if g2_error != ok { ret (0usize, g2_error) }
    cells[10usize] = looks.Cell { caption: "group", node: g1, drive: .None }
    cells[11usize] = looks.Cell { caption: "group disabled", node: g2, drive: .None }
    ret (12usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "radio", cells: 12usize, columns: 5usize, cell_w: 140.0, cell_h: 72.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
