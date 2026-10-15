// The popup menu (TdxBarPopupMenu) in its states under every look: docs/ui/looks/<look>/popup_menu.png
// (static menus) and popup_menu-hover.png (a hovered row, which needs a pointer, and an open menu
// is modal, so each sheet of pointer-driven cells holds only that cell). Run from the repository
// root; see docs/ui/looks-howto.md. The commands are v3's Cards menu and grid context menu.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.navigation
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn actions_of(a: *mem.Arena) -> (*widget.Submit, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (zero, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    ret (&actions[0usize], ok)
}

fn command(action: widget.Submit, label: str, shortcut: str, enabled: bool, separated: bool) -> navigation.BarCommand {
    var c: navigation.BarCommand = zero
    c.label = label
    c.shortcut = shortcut
    c.enabled = enabled
    c.separated = separated
    c.action = action
    ret c
}

fn picture(c: navigation.BarCommand, glyph: control.GlyphKind) -> navigation.BarCommand {
    var out = c
    out.pictured = true
    out.glyph = glyph
    ret out
}

// The grid's context menu: pictured commands, disabled ones, separators and shortcuts (C1).
fn plain(a: *mem.Arena, action: widget.Submit) -> ([]navigation.BarCommand, err) {
    let (list, list_error) = mem.alloc[navigation.BarCommand](a, 9usize)
    if list_error != ok { ret (zero, list_error) }
    list[0usize] = picture(command(action, "Add to Deck", "", false, false), .Add)
    list[1usize] = picture(command(action, "Add to Sideboard", "", false, false), .Add)
    list[2usize] = picture(command(action, "Add to Collection", "", true, true), .Add)
    list[3usize] = picture(command(action, "Add Foil to Collection", "", true, false), .Add)
    list[4usize] = picture(command(action, "Search...", "Ctrl+F", true, true), .Search)
    list[5usize] = picture(command(action, "Advanced Filter...", "Ctrl+Alt+F", true, false), .Filter)
    list[6usize] = picture(command(action, "Show Columns...", "Ctrl+Alt+C", true, true), .Settings)
    ret (list[0usize..7usize], ok)
}

// Checked and radio entries, a command with no picture, submenu arrows (EX1, AL1).
fn mixed(a: *mem.Arena, action: widget.Submit) -> ([]navigation.BarCommand, err) {
    let (list, list_error) = mem.alloc[navigation.BarCommand](a, 8usize)
    if list_error != ok { ret (zero, list_error) }
    list[0usize] = command(action, "Cut", "Ctrl+X", false, false)
    list[1usize] = command(action, "Paste", "Ctrl+V", true, false)
    list[2usize] = command(action, "Print", "", true, true)
    list[3usize] = command(action, "Export", "", true, false)
    list[3usize].submenu = list[2usize..3usize]
    list[2usize].submenu = list[2usize..3usize]
    list[4usize] = picture(command(action, "Footer", "", true, true), .Menu)
    list[4usize].checked = true
    list[5usize] = command(action, "Group Footers", "", false, false)
    list[6usize] = command(action, "Show Grid Lines", "", true, false)
    list[6usize].checkable = true
    list[6usize].checked = true
    list[7usize] = command(action, "Delete All", "Ctrl+Alt+Shift+Del", true, true)
    ret (list[0usize..8usize], ok)
}

// The menu hanging 2 below an anchor at (x, y) in a w x h cell.
fn hung(a: *mem.Arena, t: *const control.Theme, base: widget.Key, commands: []const navigation.BarCommand, x: f32, y: f32, w: f32, h: f32, action: *const widget.Submit) -> (widget.Node, err) {
    let (menu, menu_error) = navigation.bar_menu(a, base + 1u64, t, base, "Menu", commands, true, action)
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

// Static sheet: the context menu, then the mixed one, then a cascade (the Export row open).
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (action, action_error) = actions_of(a)
    if action_error != ok { ret (0usize, action_error) }
    let (first, first_error) = plain(a, *action)
    if first_error != ok { ret (0usize, first_error) }
    let (second, second_error) = mixed(a, *action)
    if second_error != ok { ret (0usize, second_error) }
    let (node_a, node_a_error) = hung(a, t, 100u64, first, 4.0, 0.0, 300.0, 250.0, action)
    if node_a_error != ok { ret (0usize, node_a_error) }
    let (node_b, node_b_error) = hung(a, t, 20000u64, second, 4.0, 0.0, 300.0, 250.0, action)
    if node_b_error != ok { ret (0usize, node_b_error) }
    cells[0usize] = looks.Cell { caption: "Commands, disabled, separators, shortcuts", node: node_a, drive: .None }
    cells[1usize] = looks.Cell { caption: "Checked, arrows, narrow", node: node_b, drive: .None }
    ret (2usize, ok)
}

// A hovered row (Add Foil to Collection, the fourth) under the pointer at the cell's centre.
fn build_hover(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (action, action_error) = actions_of(a)
    if action_error != ok { ret (0usize, action_error) }
    let (first, first_error) = plain(a, *action)
    if first_error != ok { ret (0usize, first_error) }
    let (node, node_error) = hung(a, t, 100u64, first, 150.0 - 100.0, 125.0 - 85.0, 300.0, 250.0, action)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "Hover", node: node, drive: .Hover }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "popup_menu", cells: 2usize, columns: 2usize, cell_w: 300.0, cell_h: 250.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    let hover = looks.Sheet { name: "popup_menu-hover", cells: 1usize, columns: 1usize, cell_w: 300.0, cell_h: 250.0, ctx: zero, build: build_hover }
    ret looks.run_all(a, &hover)
}
