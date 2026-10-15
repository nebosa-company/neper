// The check list box in its states under every look: docs/ui/looks/<look>/check_list_box.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

// Four cells: at rest (two rows checked), the pointer over its middle row, the keyboard on its
// first row, and an empty list.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (toggles, toggles_error) = mem.alloc[widget.Submit](a, 5usize)
    if toggles_error != ok { ret (0usize, toggles_error) }
    var i = 0usize
    while i < 5usize {
        toggles[i] = widget.Submit { ctx: zero, invoke: noop_submit }
        i += 1usize
    }
    let options = [5]str{ "Expansions", "Core Sets", "Masters", "Draft Innovation", "Duel Decks" }
    let picked = [5]bool{ true, false, true, false, false }
    let nothing = [1]bool{ false }
    let names = [4]str{ "Rest", "Hover", "Focus", "Empty" }
    i = 0usize
    while i < 4usize {
        var count = 5usize
        if i == 3usize { count = 0usize }
        let (node, node_error) = control.multi_select_list(a, u64(i * 10usize + 1usize), t, "Blocks", options[0usize..count], picked[0usize..count], toggles[0usize..count], 5u32, 150.0)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "check_list_box", cells: 4usize, columns: 4usize, cell_w: 170.0, cell_h: 122.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
