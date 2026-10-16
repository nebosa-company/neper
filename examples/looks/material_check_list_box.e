// The Android look's check list box: list items with a leading check box (docs/ui/looks/material/check_list_box.png).
// Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

// Six cells: at rest (two rows checked), the pointer over its middle row, a row pressed, the keyboard on the first row, and an
// empty list.
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
    let names = [5]str{ "Enabled", "Hovered", "Pressed", "Focused", "Empty" }
    i = 0usize
    while i < 5usize {
        var count = 3usize
        if i == 4usize { count = 0usize }
        let (shown, shown_error) = control.multi_select_list(a, u64(i * 10usize + 1usize), t, "Blocks", options[0usize..count], picked[0usize..count], toggles[0usize..count], 3u32, 220.0)
        if shown_error != ok { ret (0usize, shown_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: shown, drive: drive }
        i += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "check_list_box", cells: 5usize, columns: 5usize, cell_w: 232.0, cell_h: 190.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
