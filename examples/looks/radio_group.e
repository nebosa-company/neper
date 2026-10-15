// The radio group in its states under every look: docs/ui/looks/<look>/radio_group.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

// Four cells: the first option selected, the second selected under long captions, a disabled
// group, and one with the keyboard on its first radio.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    actions[1usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let labels = [2]str{ "Move to next column", "Move to next row" }
    let long_labels = [2]str{ "Search from start (typing \"War\" would not find \"Fog of War\")", "Search within (typing \"War\" would find \"Fog of War\")" }
    let names = [4]str{ "First selected", "Second selected, long captions", "Disabled", "Focus on first" }
    var i = 0usize
    while i < 4usize {
        var selected = 0usize
        if i == 1usize { selected = 1usize }
        var shown = labels[0usize..2usize]
        var caption = "Enter Key Action: "
        if i == 1usize {
            shown = long_labels[0usize..2usize]
            caption = "Incremental Search: "
        }
        let key = u64(i * 4usize + 1usize)
        let (node, node_error) = control.radio_group(a, key, t, caption, shown, selected, actions[0usize..2usize], i != 2usize)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        // The harness drives the pointer to the centre of the cell: the radios' rows.
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "radio_group", cells: 4usize, columns: 2usize, cell_w: 420.0, cell_h: 100.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
