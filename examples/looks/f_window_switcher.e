// navigation.window_switcher under all ten looks: docs/ui/looks/<look>/window_switcher.png. The switcher is a modal overlay
// at the top centre of the window, so the sheet is one cell the size of a small window: open over four windows with the
// second one active (the overlay has finished its fade in). Derived from the shared tokens; no platform reference is
// captured. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_f
use e.ui.navigation
use e.ui.widget

fn no_pick(ctx: *void, value: usize) -> err { ret ok }
fn no_press(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (dismiss, dismiss_error) = mem.alloc[widget.Submit](a, 1usize)
    if dismiss_error != ok { ret (0usize, dismiss_error) }
    dismiss[0usize] = widget.Submit { ctx: zero, invoke: no_press }
    let names = [4]str{ "Inbox", "Draft", "Settings", "Deck editor" }
    let (node, node_error) = navigation.window_switcher(a, 4000u64, t, "Windows", names[0usize..4usize], 1usize, true, widget.Change[usize] { ctx: zero, invoke: no_pick }, widget.Change[usize] { ctx: zero, invoke: no_pick }, &dismiss[0usize], 320.0)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "Open, second window active", node: node, drive: .Settle }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "window_switcher", cells: 1usize, columns: 1usize, cell_w: 420.0, cell_h: 300.0, ctx: zero, build: build }
    ret looks_f.run_ten(a, &sheet)
}
