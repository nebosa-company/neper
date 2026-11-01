// navigation.wizard under all ten looks: docs/ui/looks/<look>/wizard.png. A three step wizard on its first, middle and
// last step, with Next disabled (cannot advance), and the Next button hovered and pressed.
// Derived from the shared tokens; no platform reference is captured. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_f
use e.ui.navigation
use e.ui.widget

fn no_press(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [6]str{ "First step", "Middle step", "Last step", "Cannot advance", "Next hovered", "Next pressed" }
    let (presses, presses_error) = mem.alloc[widget.Submit](a, 4usize)
    if presses_error != ok { ret (0usize, presses_error) }
    var p = 0usize
    while p < 4usize {
        presses[p] = widget.Submit { ctx: zero, invoke: no_press }
        p += 1usize
    }
    let steps = [3]str{ "Account", "Address", "Review" }
    var i = 0usize
    while i < 6usize {
        var current = 0usize
        if i == 1usize { current = 1usize }
        if i == 2usize { current = 2usize }
        let (page, page_error) = control.text(a, 0u64, "Step content", t, control.text_options())
        if page_error != ok { ret (0usize, page_error) }
        let (node, node_error) = navigation.wizard(a, u64((i + 1usize) * 1000usize), t, "Setup", steps[0usize..3usize], current, page, i != 3usize, &presses[0usize], &presses[1usize], &presses[2usize], &presses[3usize], 400.0, 200.0)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 4usize || i == 5usize {
            drive = .Hover
            looks.aim(i, 130.0, 85.0)
        }
        if i == 5usize { drive = .Press }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "wizard", cells: 6usize, columns: 3usize, cell_w: 420.0, cell_h: 240.0, ctx: zero, build: build }
    ret looks_f.run_ten(a, &sheet)
}
