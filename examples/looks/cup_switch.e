// The Cupertino (iOS) switch: docs/ui/looks/cupertino/switch.png (and cupertino-dark). Rows off, on; columns rest,
// hover, pressed (thumb stretched), keyboard focus, disabled.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let columns = [5]str{ "rest", "hover", "pressed", "focus", "disabled" }
    var i = 0usize
    while i < 10usize {
        let row = i / 5usize
        let column = i % 5usize
        let (node, node_error) = control.switch_control(a, u64(i + 1usize), t, "Wi-Fi", row == 1usize, &actions[0usize], column != 4usize)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if column == 1usize { drive = .Hover }
        if column == 2usize { drive = .Press }
        if column == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: columns[column], node: node, drive: drive }
        i += 1usize
    }
    ret (10usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "switch", cells: 10usize, columns: 5usize, cell_w: 150.0, cell_h: 48.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
