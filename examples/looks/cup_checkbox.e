// The Cupertino (macOS) check box: docs/ui/looks/cupertino/checkbox.png (and cupertino-dark). Rows unchecked, checked,
// mixed; columns rest, hover, pressed, keyboard focus, disabled. See docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let action = &actions[0usize]
    let columns = [5]str{ "rest", "hover", "pressed", "focus", "disabled" }
    var i = 0usize
    while i < 15usize {
        let row = i / 5usize
        let column = i % 5usize
        let (node, node_error) = control.checkbox(a, u64(i + 1usize), t, "Show hidden files", row == 1usize, row == 2usize, action, column != 4usize)
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
    let sheet = looks.Sheet { name: "checkbox", cells: 15usize, columns: 5usize, cell_w: 140.0, cell_h: 30.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
