// Round 62 c: the banner in all ten looks: the four severities with one action, two actions, a long wrapped message, and
// the action hovered and pressed. Derived: wells and icons come from the shared severity tokens, no platform capture.
// Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    actions[1usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let (labels, labels_error) = mem.alloc[str](a, 2usize)
    if labels_error != ok { ret (0usize, labels_error) }
    labels[0usize] = "Details"
    labels[1usize] = "Dismiss"
    let captions = [8]str{ "Info", "Success", "Warning", "Error", "Two actions", "Long message", "Action hovered", "Action pressed" }
    let words = [8]str{ "Prices were last refreshed this morning.", "The deck was saved.", "Two cards are not legal in this format.", "The collection could not be read.", "Prices were last refreshed this morning.", "Some cards in this deck changed edition after the last import, so their prices may be out of date until you refresh.", "Prices were last refreshed this morning.", "Prices were last refreshed this morning." }
    var i = 0usize
    while i < 8usize {
        var severity: control.Severity = .Info
        if i == 1usize { severity = .Success }
        if i == 2usize { severity = .Warning }
        if i == 3usize { severity = .Error }
        var count = 1usize
        if i == 4usize { count = 2usize }
        let (node, node_error) = control.banner(a, u64((i + 1usize) * 8usize), t, severity, words[i], labels[0usize..count], actions[0usize..count], 400.0)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 6usize { drive = .Hover }
        if i == 7usize { drive = .Press }
        if i == 6usize || i == 7usize { looks.aim(i, 157.0, 0.0) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "banner", cells: 8usize, columns: 2usize, cell_w: 430.0, cell_h: 110.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    try looks.run_material(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    ret looks.run_linux(a, &sheet)
}
