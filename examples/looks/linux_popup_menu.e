// The Linux look's popup menu against the real GTK 4.14 / libadwaita 1.5 GtkPopoverMenu: an Edit menu (accelerators, a disabled
// row, sections) and a View menu (check, radio, a submenu row), docs/ui/looks/linux[-dark]/popup_menu.png; run with `hover` or
// `active` for the Paste row under the pointer or pressed (a modal overlay renders one per process): popup_menu-hover.png and
// popup_menu-active.png. Reference: scripts/linux_cmp_l3.py. Run from the repository root.

use e.gfx.geometry
use e.mem
use e.str as strs
use e.ui.control
use e.ui.looks
use e.ui.overlay
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn command(action: widget.Submit, label: str, shortcut: str, enabled: bool, separated: bool) -> overlay.MenuCommand {
    var c = overlay.menu_command(label, action)
    c.shortcut = shortcut
    c.enabled = enabled
    c.separated = separated
    ret c
}

fn edit_menu(a: *mem.Arena, action: widget.Submit) -> ([]overlay.MenuCommand, err) {
    let (list, list_error) = mem.alloc[overlay.MenuCommand](a, 6usize)
    if list_error != ok { ret (zero, list_error) }
    list[0usize] = command(action, "Undo", "Ctrl+Z", true, false)
    list[1usize] = command(action, "Redo", "Shift+Ctrl+Z", false, false)
    list[2usize] = command(action, "Cut", "Ctrl+X", true, true)
    list[3usize] = command(action, "Copy", "Ctrl+C", true, false)
    list[4usize] = command(action, "Paste", "Ctrl+V", true, false)
    list[5usize] = command(action, "Select All", "Ctrl+A", true, true)
    ret (list[0usize..6usize], ok)
}

fn view_menu(a: *mem.Arena, action: widget.Submit) -> ([]overlay.MenuCommand, err) {
    let (list, list_error) = mem.alloc[overlay.MenuCommand](a, 6usize)
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
    list[4usize] = command(action, "Sort By", "", true, false)
    list[4usize].submenu = list[2usize..3usize]
    list[5usize] = command(action, "Full Screen", "F11", true, true)
    ret (list[0usize..6usize], ok)
}

// The menu's top-left corner on the cell's (24, 22), where the reference crop has its popover surface: it hangs from a 1 px anchor
// 1 px above.
fn hung(a: *mem.Arena, t: *const control.Theme, base: widget.Key, commands: []const overlay.MenuCommand, action: *const widget.Submit) -> (widget.Node, err) {
    let (menu, menu_error) = overlay.menu_at(a, base + 1u64, t, base, "Menu", commands, true, action, .Below, geometry.Point { x: 0.0, y: 0.0 }, 4.0, true)
    if menu_error != ok { ret (zero, menu_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = widget.box(base, control.sized_style(1.0, 1.0), zero)
    parts[1usize] = menu
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, row_error) }
    row[0usize] = widget.stack(0u64, control.sized_style(1.0, 1.0), parts[0usize..2usize])
    ret (widget.padded(0u64, 24.0, 21.0, 0.0, 0.0, control.sized_style(210.0, 278.0), row[0usize..1usize]), ok)
}

fn actions_of(a: *mem.Arena) -> (*widget.Submit, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (zero, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    ret (&actions[0usize], ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (action, action_error) = actions_of(a)
    if action_error != ok { ret (0usize, action_error) }
    let (first, first_error) = edit_menu(a, *action)
    if first_error != ok { ret (0usize, first_error) }
    let (second, second_error) = view_menu(a, *action)
    if second_error != ok { ret (0usize, second_error) }
    let (node_a, node_a_error) = hung(a, t, 100u64, first, action)
    if node_a_error != ok { ret (0usize, node_a_error) }
    let (node_b, node_b_error) = hung(a, t, 20000u64, second, action)
    if node_b_error != ok { ret (0usize, node_b_error) }
    cells[0usize] = looks.Cell { caption: "Edit: accelerators, disabled", node: node_a, drive: .None }
    cells[1usize] = looks.Cell { caption: "View: check, radio, submenu", node: node_b, drive: .None }
    ret (2usize, ok)
}

// The Paste row (the fifth, 169 to 201 of the crop) under the pointer: the cell's centre is (105, 139) of the 210 x 278 cell.
fn build_state(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (action, action_error) = actions_of(a)
    if action_error != ok { ret (0usize, action_error) }
    let (first, first_error) = edit_menu(a, *action)
    if first_error != ok { ret (0usize, first_error) }
    let (node, node_error) = hung(a, t, 100u64, first, action)
    if node_error != ok { ret (0usize, node_error) }
    var drive: looks.Drive = .Hover
    var caption = "Paste hovered"
    let word = *mem.cast[*const str](ctx)
    if word.len == 6usize {
        drive = .Press
        caption = "Paste pressed"
    }
    cells[0usize] = looks.Cell { caption: caption, node: node, drive: drive }
    looks.aim(0usize, 0.0, 46.0)
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize {
        let (word, word_error) = mem.alloc[str](a, 1usize)
        if word_error != ok { ret word_error }
        word[0usize] = args[1usize]
        var name = "popup_menu-hover"
        if strs.eq(args[1usize], "active") { name = "popup_menu-active" }
        let state = looks.Sheet { name: name, cells: 1usize, columns: 1usize, cell_w: 210.0, cell_h: 278.0, ctx: mem.cast[*void](&word[0usize]), build: build_state }
        ret looks.run_linux(a, &state)
    }
    let sheet = looks.Sheet { name: "popup_menu", cells: 2usize, columns: 2usize, cell_w: 210.0, cell_h: 278.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
