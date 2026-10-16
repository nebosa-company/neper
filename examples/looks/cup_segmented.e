// The Cupertino (iOS) segmented control: docs/ui/looks/cupertino/segmented_control.png (and cupertino-dark). Rows: the
// first, middle and last segment selected; columns rest, hover (middle segment), pressed (middle), focus, disabled.

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
    let labels = [3]str{ "Day", "Week", "Month" }
    let columns = [5]str{ "rest", "hover", "pressed", "focus", "disabled" }
    var i = 0usize
    while i < 15usize {
        let row = i / 5usize
        let column = i % 5usize
        var chosen = 0usize
        if row == 1usize { chosen = 1usize }
        if row == 2usize { chosen = 2usize }
        let (node, node_error) = control.segmented_control(a, u64((i + 1usize) * 10usize), t, "Range", labels[0usize..3usize], chosen, actions[0usize..3usize], column != 4usize)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if column == 1usize { drive = .Hover }
        if column == 2usize { drive = .Press }
        if column == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: columns[column], node: node, drive: drive }
        i += 1usize
    }
    ret (15usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "segmented_control", cells: 15usize, columns: 5usize, cell_w: 190.0, cell_h: 40.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
