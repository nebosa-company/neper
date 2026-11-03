// The Android split button with its menu open, docs/ui/looks/material/split_button_open.png: the trailing half with the chevron
// turned up and the M3 menu (48 dp rows, surface-container, elevation 2) under it; speed_dial_open.png the speed dial's open
// list. An open menu is modal, so each sheet holds one. Run from the repository root; `material_split_open.exe x` for the dial.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.overlay
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn plain(label: str, action: widget.Submit) -> overlay.MenuCommand {
    var c: overlay.MenuCommand = zero
    c.label = label
    c.action = action
    c.enabled = true
    ret c
}

fn split_cell(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (acts, acts_error) = mem.alloc[widget.Submit](a, 1usize)
    if acts_error != ok { ret (0usize, acts_error) }
    acts[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let (list, list_error) = mem.alloc[overlay.MenuCommand](a, 3usize)
    if list_error != ok { ret (0usize, list_error) }
    list[0usize] = plain("Save as", acts[0usize])
    list[1usize] = plain("Save a copy", acts[0usize])
    list[2usize] = plain("Export", acts[0usize])
    let (button, button_error) = control.split_button(a, 10u64, t, "Save", &acts[0usize], true, &acts[0usize])
    if button_error != ok { ret (0usize, button_error) }
    let (menu, menu_error) = overlay.menu_of(a, 5000u64, t, 11u64, "More", list[0usize..3usize], true, &acts[0usize])
    if menu_error != ok { ret (0usize, menu_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (0usize, parts_error) }
    parts[0usize] = button
    parts[1usize] = menu
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(260.0, 240.0), parts[0usize..2usize])
    cells[0usize] = looks.Cell { caption: "Menu open", node: column, drive: .None }
    ret (1usize, ok)
}

fn dial_cell(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (acts, acts_error) = mem.alloc[widget.Submit](a, 4usize)
    if acts_error != ok { ret (0usize, acts_error) }
    var i = 0usize
    while i < 4usize {
        acts[i] = widget.Submit { ctx: zero, invoke: noop_submit }
        i += 1usize
    }
    let labels = [3]str{ "Share", "Print", "Copy link" }
    let (node, node_error) = control.speed_dial(a, 100u64, t, "Actions", labels[0usize..3usize], acts[0usize..3usize], true, &acts[3usize])
    if node_error != ok { ret (0usize, node_error) }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (0usize, held_error) }
    held[0usize] = node
    let low = widget.padded(0u64, 80.0, 250.0, 0.0, 0.0, control.sized_style(280.0, 330.0), held[0usize..1usize])
    cells[0usize] = looks.Cell { caption: "Open", node: low, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize {
        let dial = looks.Sheet { name: "speed_dial_open", cells: 1usize, columns: 1usize, cell_w: 280.0, cell_h: 330.0, ctx: zero, build: dial_cell }
        ret looks.run_material(a, &dial)
    }
    let sheet = looks.Sheet { name: "split_button_open", cells: 1usize, columns: 1usize, cell_w: 280.0, cell_h: 260.0, ctx: zero, build: split_cell }
    ret looks.run_material(a, &sheet)
}
