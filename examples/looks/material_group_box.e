// The Android look's group box: an outlined or filled card with a title, the rows divided by outline-variant lines
// (docs/ui/looks/material/group_box.png). Run from the repository root.

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

fn noop_submit(ctx: *void) -> err { ret ok }

fn group(a: *mem.Arena, t: *const control.Theme, key: widget.Key, label: str, options: control.GroupOptions, count: usize) -> (widget.Node, err) {
    let (nodes, nodes_error) = rows(a, t, "Enable alerts", "Show previews")
    if nodes_error != ok { ret (zero, nodes_error) }
    let (made, made_error) = control.group_box_of(a, key, t, label, options, nodes[0usize..count])
    ret (made, made_error)
}

// Nine cells: outlined, filled, disabled, invalid (a message), with a description, collapsed and expanded with a toggle,
// plain (a section header) and empty.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [9]str{ "Outlined", "Filled", "Disabled", "Invalid", "Description", "Collapsed", "Expanded", "Plain (section)", "Empty" }
    let (toggle, toggle_error) = mem.alloc[widget.Submit](a, 1usize)
    if toggle_error != ok { ret (0usize, toggle_error) }
    toggle[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var i = 0usize
    while i < 9usize {
        var options = control.group_options()
        options.width = 220.0
        var count = 2usize
        if i == 1usize { options.variant = .Filled }
        if i == 2usize { options.enabled = false }
        if i == 3usize { options.message = "Choose at least one" }
        if i == 4usize { options.description = "Applies to this device" }
        if i == 5usize || i == 6usize {
            options.toggle = &toggle[0usize]
            options.summary = "2 options"
            options.expanded = i == 6usize
        }
        if i == 7usize { options.variant = .Plain }
        if i == 8usize { count = 0usize }
        let (node, node_error) = group(a, t, u64(100usize * (i + 1usize)), "Notifications", options, count)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (9usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "group_box", cells: 9usize, columns: 5usize, cell_w: 240.0, cell_h: 170.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
