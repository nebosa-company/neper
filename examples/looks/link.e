// The link in every look: docs/ui/looks/<look>/link.png. At rest, hover (the underline and the state layer), pressed and
// keyboard focus. Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_a
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let names = [4]str{ "rest", "hover", "pressed", "focus" }
    var i = 0usize
    while i < 4usize {
        let (node, node_error) = control.link(a, u64((i + 1usize) * 10usize), t, "Terms of service", &actions[0usize])
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "link", cells: 4usize, columns: 2usize, cell_w: 170.0, cell_h: 64.0, ctx: zero, build: build }
    ret looks_a.run_every(a, &sheet)
}
