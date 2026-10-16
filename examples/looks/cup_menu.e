// The Cupertino (macOS) menu: docs/ui/looks/cupertino/popup_menu.png (two static menus) and popup_menu-hover.png (a hovered
// row, the accent fill), and cupertino-dark. An open menu is a modal overlay, so the hover sheet holds that one cell
// (run the app with an argument for it).

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.overlay
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn command(action: widget.Submit, label: str, shortcut: str, enabled: bool, separated: bool) -> overlay.MenuCommand {
    var c = overlay.menu_command(label, action)
    c.shortcut = shortcut
    c.enabled = enabled
    c.separated = separated
    ret c
}

// The Edit menu: shortcuts, a disabled command, separators.
fn edit_menu(a: *mem.Arena, action: widget.Submit) -> ([]overlay.MenuCommand, err) {
    let (list, list_error) = mem.alloc[overlay.MenuCommand](a, 9usize)
    if list_error != ok { ret (zero, list_error) }
    list[0usize] = command(action, "Undo", "Ctrl+Z", true, false)
    list[1usize] = command(action, "Redo", "Ctrl+Shift+Z", false, false)
    list[2usize] = command(action, "Cut", "Ctrl+X", true, true)
    list[3usize] = command(action, "Copy", "Ctrl+C", true, false)
    list[4usize] = command(action, "Paste", "Ctrl+V", true, false)
    list[5usize] = command(action, "Paste and Match Style", "", false, false)
    list[6usize] = command(action, "Select All", "Ctrl+A", true, true)
    list[7usize] = command(action, "Delete", "", true, false)
    list[7usize].destructive = true
    ret (list[0usize..8usize], ok)
}

// The View menu: checked and radio rows (the slot is reserved in every row), a submenu arrow, a section head.
fn view_menu(a: *mem.Arena, action: widget.Submit) -> ([]overlay.MenuCommand, err) {
    let (list, list_error) = mem.alloc[overlay.MenuCommand](a, 8usize)
    if list_error != ok { ret (zero, list_error) }
    list[0usize] = command(action, "Show Toolbar", "", true, false)
    list[0usize].checkable = true
    list[0usize].checked = true
    list[1usize] = command(action, "Show Sidebar", "", true, false)
    list[1usize].checkable = true
    list[2usize] = command(action, "as Icons", "", true, true)
    list[2usize].radio = true
    list[2usize].checked = true
    list[3usize] = command(action, "as List", "", true, false)
    list[3usize].radio = true
    list[4usize] = command(action, "as Columns", "", true, false)
    list[4usize].radio = true
    list[5usize] = command(action, "Sort By", "", true, true)
    list[5usize].submenu = list[2usize..3usize]
    list[6usize] = command(action, "Enter Full Screen", "Ctrl+F", true, true)
    ret (list[0usize..7usize], ok)
}

// The menu hanging below an anchor at (x, y) in a w x h cell.
fn hung(a: *mem.Arena, t: *const control.Theme, base: widget.Key, commands: []const overlay.MenuCommand, x: f32, y: f32, w: f32, h: f32, action: *const widget.Submit) -> (widget.Node, err) {
    let (menu, menu_error) = overlay.menu_of(a, base + 1u64, t, base, "Menu", commands, true, action)
    if menu_error != ok { ret (zero, menu_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = widget.box(base, control.sized_style(1.0, 1.0), zero)
    parts[1usize] = menu
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, row_error) }
    row[0usize] = widget.stack(0u64, control.sized_style(1.0, 1.0), parts[0usize..2usize])
    ret (widget.padded(0u64, x, y, 0.0, 0.0, control.sized_style(w, h), row[0usize..1usize]), ok)
}

fn actions_of(a: *mem.Arena) -> (*widget.Submit, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (zero, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    ret (&actions[0usize], actions_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (action, action_error) = actions_of(a)
    if action_error != ok { ret (0usize, action_error) }
    let (first, first_error) = edit_menu(a, *action)
    if first_error != ok { ret (0usize, first_error) }
    let (second, second_error) = view_menu(a, *action)
    if second_error != ok { ret (0usize, second_error) }
    let (node_a, node_a_error) = hung(a, t, 100u64, first, 4.0, 0.0, 300.0, 240.0, action)
    if node_a_error != ok { ret (0usize, node_a_error) }
    let (node_b, node_b_error) = hung(a, t, 20000u64, second, 4.0, 0.0, 300.0, 240.0, action)
    if node_b_error != ok { ret (0usize, node_b_error) }
    cells[0usize] = looks.Cell { caption: "Edit: shortcuts, disabled, destructive", node: node_a, drive: .None }
    cells[1usize] = looks.Cell { caption: "View: checked, radio, submenu", node: node_b, drive: .None }
    ret (2usize, ok)
}

// A hovered row (Paste, the fifth) under the pointer at the cell's centre.
fn build_hover(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (action, action_error) = actions_of(a)
    if action_error != ok { ret (0usize, action_error) }
    let (first, first_error) = edit_menu(a, *action)
    if first_error != ok { ret (0usize, first_error) }
    let (node, node_error) = hung(a, t, 100u64, first, 20.0, 5.0, 300.0, 240.0, action)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "Hover", node: node, drive: .Hover }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize {
        let hover = looks.Sheet { name: "popup_menu-hover", cells: 1usize, columns: 1usize, cell_w: 300.0, cell_h: 240.0, ctx: zero, build: build_hover }
        ret looks.run_cupertino(a, &hover)
    }
    let sheet = looks.Sheet { name: "popup_menu", cells: 2usize, columns: 2usize, cell_w: 360.0, cell_h: 240.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
