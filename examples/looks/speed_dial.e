// The speed dial in every look: docs/ui/looks/<look>/speed_dial.png (the closed head at rest, hover, pressed and keyboard focus)
// and speed_dial_open.png (open: the close head and the three action pills above it). Run from the repository root; see
// docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.looks_a
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn actions_of(a: *mem.Arena, n: usize) -> ([]widget.Submit, err) {
    let (list, list_error) = mem.alloc[widget.Submit](a, n)
    if list_error != ok { ret (zero, list_error) }
    var i = 0usize
    while i < n {
        list[i] = widget.Submit { ctx: zero, invoke: noop_submit }
        i += 1usize
    }
    ret (list, ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (toggle, toggle_error) = actions_of(a, 1usize)
    if toggle_error != ok { ret (0usize, toggle_error) }
    let (items, items_error) = actions_of(a, 3usize)
    if items_error != ok { ret (0usize, items_error) }
    let (labels, labels_error) = mem.alloc[str](a, 3usize)
    if labels_error != ok { ret (0usize, labels_error) }
    labels[0usize] = "Share"
    labels[1usize] = "Print"
    labels[2usize] = "Copy link"
    let names = [4]str{ "rest", "hover", "pressed", "focus" }
    var i = 0usize
    while i < 4usize {
        let (node, node_error) = control.speed_dial(a, u64((i + 1usize) * 100usize), t, "Actions", labels[0usize..3usize], items[0usize..3usize], false, &toggle[0usize])
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

fn one_node(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret zero }
    held[0usize] = node
    ret held[0usize..1usize]
}

fn build_open(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (toggle, toggle_error) = actions_of(a, 1usize)
    if toggle_error != ok { ret (0usize, toggle_error) }
    let (items, items_error) = actions_of(a, 3usize)
    if items_error != ok { ret (0usize, items_error) }
    let (labels, labels_error) = mem.alloc[str](a, 3usize)
    if labels_error != ok { ret (0usize, labels_error) }
    labels[0usize] = "Share"
    labels[1usize] = "Print"
    labels[2usize] = "Copy link"
    let (node, node_error) = control.speed_dial(a, 100u64, t, "Actions", labels[0usize..3usize], items[0usize..3usize], true, &toggle[0usize])
    if node_error != ok { ret (0usize, node_error) }
    var room = looks.size_style(260.0, 290.0)
    room.padding = style.EdgeLengths { left: style.Length { Px: 20.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 20.0 } }
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .End, cross: .Start, gap: 0.0 }, room, one_node(a, node))
    cells[0usize] = looks.Cell { caption: "open", node: column, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let closed = looks.Sheet { name: "speed_dial", cells: 4usize, columns: 4usize, cell_w: 140.0, cell_h: 90.0, ctx: zero, build: build }
    try looks_a.run_every(a, &closed)
    let open = looks.Sheet { name: "speed_dial_open", cells: 1usize, columns: 1usize, cell_w: 260.0, cell_h: 290.0, ctx: zero, build: build_open }
    ret looks_a.run_every(a, &open)
}
