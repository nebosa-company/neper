// navigation.command_palette under all ten looks: docs/ui/looks/<look>/command_palette.png. The palette is a modal overlay
// at the top centre of the window, so the sheet is one cell the size of a small window: open with the second command
// active (the overlay has finished its fade in); no typed-query state. Derived from the shared
// tokens; no platform reference is captured. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_f
use e.ui.navigation
use e.ui.widget

fn no_text(ctx: *void, value: str) -> err { ret ok }
fn no_pick(ctx: *void, value: usize) -> err { ret ok }
fn no_press(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
    if buffer_error != ok { ret (0usize, buffer_error) }
    let (dismiss, dismiss_error) = mem.alloc[widget.Submit](a, 1usize)
    if dismiss_error != ok { ret (0usize, dismiss_error) }
    dismiss[0usize] = widget.Submit { ctx: zero, invoke: no_press }
    let commands = [5]str{ "Save all", "Save as", "Close all", "Open recent", "Toggle sidebar" }
    let (node, node_error) = navigation.command_palette(a, 4000u64, t, "Commands", buffer, 0usize, widget.Change[str] { ctx: zero, invoke: no_text }, commands[0usize..5usize], 1usize, true, widget.Change[usize] { ctx: zero, invoke: no_pick }, widget.Change[usize] { ctx: zero, invoke: no_pick }, &dismiss[0usize], 420.0)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "Open, second command active", node: node, drive: .Settle }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "command_palette", cells: 1usize, columns: 1usize, cell_w: 520.0, cell_h: 340.0, ctx: zero, build: build }
    ret looks_f.run_ten(a, &sheet)
}
