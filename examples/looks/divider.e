// Round 62 c: the divider in all ten looks. Horizontal rule, inset, middle inset, labelled, label leading, strong, and a
// vertical rule. Derived: no platform capture; the colour and thickness come from each look's tokens (Linux draws
// libadwaita's #dddddd separator). Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [7]str{ "Full width", "Inset 56", "Middle inset 16", "Labelled", "Label leading", "Strong", "Vertical" }
    var i = 0usize
    while i < 7usize {
        var options = control.divider_options()
        options.length = 200.0
        if i == 1usize { options.start = 56.0 }
        if i == 2usize {
            options.start = 16.0
            options.end = 16.0
        }
        if i == 3usize || i == 4usize { options.label = "Or" }
        if i == 4usize { options.label_start = true }
        if i == 5usize { options.strong = true }
        if i == 6usize {
            options.axis = .Vertical
            options.length = 40.0
        }
        let (node, node_error) = control.divider_of(a, u64(i + 1usize), t, options)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (7usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "divider", cells: 7usize, columns: 4usize, cell_w: 220.0, cell_h: 56.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    try looks.run_material(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    ret looks.run_linux(a, &sheet)
}
