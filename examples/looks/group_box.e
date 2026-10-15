// The group box (TcxGroupBox) and the option pages' grey section header in every state under
// every look: docs/ui/looks/<look>/group_box.png. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn rows(a: *mem.Arena, t: *const control.Theme, first: str, second: str) -> ([]widget.Node, err) {
    let (nodes, nodes_error) = mem.alloc[widget.Node](a, 2usize)
    if nodes_error != ok { ret (zero, nodes_error) }
    var options = control.text_options()
    options.wrap = .None
    let (one, one_error) = control.text(a, 0u64, first, t, options)
    if one_error != ok { ret (zero, one_error) }
    let (two, two_error) = control.text(a, 0u64, second, t, options)
    if two_error != ok { ret (zero, two_error) }
    nodes[0usize] = one
    nodes[1usize] = two
    ret (nodes, ok)
}

fn group(a: *mem.Arena, t: *const control.Theme, key: widget.Key, label: str, variant: control.GroupVariant, enabled: bool, count: usize) -> (widget.Node, err) {
    let (nodes, nodes_error) = rows(a, t, "And", "Or")
    if nodes_error != ok { ret (zero, nodes_error) }
    var options = control.group_options()
    options.variant = variant
    options.enabled = enabled
    options.width = 140.0
    let (made, made_error) = control.group_box_of(a, key, t, label, options, nodes[0usize..count])
    ret (made, made_error)
}

// Six cells: the group box at rest, disabled, with a long caption, plain, empty, and the
// section header of the option pages (the Windows look's bar; a plain title elsewhere).
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [6]str{ "Rest", "Disabled", "Long caption", "Plain", "Empty", "Section header" }
    var i = 0usize
    while i < 5usize {
        var label = "Operator:"
        var variant: control.GroupVariant = .Outlined
        var enabled = true
        var count = 2usize
        if i == 1usize { enabled = false }
        if i == 2usize { label = "Probability of drawing the current combo:" }
        if i == 3usize { variant = .Plain }
        if i == 4usize { count = 0usize }
        let (node, node_error) = group(a, t, u64(100usize * (i + 1usize)), label, variant, enabled, count)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    var bar: widget.Node = zero
    if t.tokens.profile == .Windows {
        let (made, made_error) = control.windows_section_header(a, 700u64, t, "Interface (F2)", "General", 220.0)
        if made_error != ok { ret (0usize, made_error) }
        bar = made
    } else {
        var heading = control.text_options()
        heading.role = .TitleSmall
        heading.wrap = .None
        let (made, made_error) = control.text(a, 700u64, "Interface (F2)", t, heading)
        if made_error != ok { ret (0usize, made_error) }
        bar = made
    }
    cells[5usize] = looks.Cell { caption: captions[5usize], node: bar, drive: .None }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "group_box", cells: 6usize, columns: 3usize, cell_w: 230.0, cell_h: 90.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
