// The Cupertino group box (TcxGroupBox): docs/ui/looks/cupertino/group_box.png (and cupertino-dark). Outlined is the macOS
// box (faint fill in a hairline, the title above it), Filled the iOS inset grouped section (header in the secondary
// label colour over white rows with inset separators); plain has no box. Rest, disabled, long caption, empty, invalid.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn row_texts(a: *mem.Arena, t: *const control.Theme) -> ([]widget.Node, err) {
    let (nodes, nodes_error) = mem.alloc[widget.Node](a, 2usize)
    if nodes_error != ok { ret (zero, nodes_error) }
    var options = control.text_options()
    options.wrap = .None
    let (one, one_error) = control.text(a, 0u64, "And", t, options)
    if one_error != ok { ret (zero, one_error) }
    let (two, two_error) = control.text(a, 0u64, "Or", t, options)
    if two_error != ok { ret (zero, two_error) }
    nodes[0usize] = one
    nodes[1usize] = two
    ret (nodes, ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [8]str{ "macOS box", "iOS section", "macOS, disabled", "iOS, disabled", "iOS, long caption", "plain", "macOS, invalid", "iOS, empty" }
    var i = 0usize
    while i < 8usize {
        let (nodes, nodes_error) = row_texts(a, t)
        if nodes_error != ok { ret (0usize, nodes_error) }
        var options = control.group_options()
        options.width = 200.0
        var label = "Operator"
        var count = 2usize
        options.variant = .Outlined
        if i == 1usize || i == 3usize || i == 4usize || i == 7usize { options.variant = .Filled }
        if i == 2usize || i == 3usize { options.enabled = false }
        if i == 4usize { label = "Probability of drawing the current combo" }
        if i == 5usize { options.variant = .Plain }
        if i == 6usize { options.message = "Pick one operator" }
        if i == 7usize { count = 0usize }
        let (node, node_error) = control.group_box_of(a, u64(100usize * (i + 1usize)), t, label, options, nodes[0usize..count])
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: .None }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "group_box", cells: 8usize, columns: 4usize, cell_w: 220.0, cell_h: 150.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
