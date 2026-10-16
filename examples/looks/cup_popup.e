// The Cupertino pop-up button (macOS NSPopUpButton) and its menu: docs/ui/looks/cupertino/combo_box.png (closed states)
// and combo_box_open.png (open: the menu hangs from it, the open one held pressed), and cupertino-dark.
// An open menu is a modal overlay, so the open sheet holds that one cell.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn actions_of(a: *mem.Arena) -> ([]widget.Submit, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 4usize)
    if actions_error != ok { ret (zero, actions_error) }
    var n = 0usize
    while n < 4usize {
        actions[n] = widget.Submit { ctx: zero, invoke: noop_submit }
        n += 1usize
    }
    ret (actions[0usize..4usize], ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = actions_of(a)
    if actions_error != ok { ret (0usize, actions_error) }
    let options = [4]str{ "Small", "Medium", "Large", "Extra large" }
    let names = [6]str{ "rest", "hover", "pressed", "focus", "no choice", "long value" }
    var i = 0usize
    while i < 6usize {
        var chosen = 1usize
        if i == 4usize { chosen = 9usize }
        let (node, node_error) = control.select(a, u64((i + 1usize) * 100usize), t, "Size", options[0usize..4usize], chosen, false, &actions[0usize], actions[0usize..4usize])
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (6usize, ok)
}

fn build_open(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = actions_of(a)
    if actions_error != ok { ret (0usize, actions_error) }
    let options = [4]str{ "Small", "Medium", "Large", "Extra large" }
    let (node, node_error) = control.select(a, 100u64, t, "Size", options[0usize..4usize], 1usize, true, &actions[0usize], actions[0usize..4usize])
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "open", node: node, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize {
        let open = looks.Sheet { name: "combo_box_open", cells: 1usize, columns: 1usize, cell_w: 200.0, cell_h: 300.0, ctx: zero, build: build_open }
        ret looks.run_cupertino(a, &open)
    }
    let sheet = looks.Sheet { name: "combo_box", cells: 6usize, columns: 3usize, cell_w: 180.0, cell_h: 44.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
