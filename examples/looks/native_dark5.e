// The Windows dark look beside the native Windows 11 dark captures, fifth sheet (round 13): the popup menu (an open menu is modal, so it has a
// sheet of its own), compared by element in scripts/looks_strict13.py (menu_elements).
// Only windows-dark matters: run with NEPER_LOOKS_OUT=<scratch> and copy <scratch>/windows-dark/native_dark2.png into docs/ui/looks/windows-dark.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.navigation
use e.ui.looks
use e.ui.style
use e.ui.widget

fn cell_w() -> f32 { ret 260.0 }
fn cell_h() -> f32 { ret 200.0 }

fn sized(w: f32, h: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    ret s
}

// `node` at a whole pixel (x, y) of a cell-sized holder.
fn placed(a: *mem.Arena, node: widget.Node, x: f32, y: f32) -> (widget.Node, err) {
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = widget.positioned(0u64, x, y, style.defaults(), control.mem_one_node(a, node))
    ret (widget.stack(0u64, sized(cell_w(), cell_h()), inner[0usize..1usize]), ok)
}

fn noop_submit(ctx: *void) -> err { ret ok }

fn command(action: widget.Submit, label: str, shortcut: str, enabled: bool, separated: bool) -> navigation.BarCommand {
    var c: navigation.BarCommand = zero
    c.label = label
    c.shortcut = shortcut
    c.enabled = enabled
    c.separated = separated
    c.action = action
    ret c
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    // menu-popup-rest: New, Open (checked), Save (disabled), separator, Open Recent (submenu), separator, Exit
    let (menu_list, menu_list_error) = mem.alloc[navigation.BarCommand](a, 5usize)
    if menu_list_error != ok { ret (0usize, menu_list_error) }
    menu_list[0usize] = command(actions[0usize], "New", "Ctrl+N", true, false)
    menu_list[1usize] = command(actions[0usize], "Open", "Ctrl+O", true, false)
    menu_list[1usize].checkable = true
    menu_list[1usize].checked = true
    menu_list[2usize] = command(actions[0usize], "Save", "Ctrl+S", false, false)
    menu_list[3usize] = command(actions[0usize], "Open Recent", "", true, true)
    menu_list[3usize].submenu = menu_list[2usize..3usize]
    menu_list[4usize] = command(actions[0usize], "Exit", "", true, true)
    let (menu, menu_error) = navigation.bar_menu(a, 9501u64, t, 9500u64, "Menu", menu_list[0usize..5usize], true, &actions[0usize])
    if menu_error != ok { ret (0usize, menu_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (0usize, parts_error) }
    parts[0usize] = widget.box(9500u64, control.sized_style(1.0, 1.0), zero)
    parts[1usize] = menu
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (0usize, row_error) }
    row[0usize] = widget.stack(0u64, control.sized_style(1.0, 1.0), parts[0usize..2usize])
    cells[0usize] = looks.Cell { caption: "menu-popup-rest", node: widget.padded(0u64, 20.0, 18.0, 0.0, 0.0, control.sized_style(cell_w(), cell_h()), row[0usize..1usize]), drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "native_dark5", cells: 1usize, columns: 1usize, cell_w: cell_w(), cell_h: cell_h(), ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
