// The Android look's menu, docs/ui/looks/material/menu.png: a dropdown menu with leading icons, a trailing shortcut, a
// divider and a disabled item. An open menu is modal, so a hovered row has its own sheet (menu_hover.png). Run from the
// repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.overlay
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn command(action: widget.Submit, label: str, glyph: control.GlyphKind, shortcut: str, enabled: bool, separated: bool) -> overlay.MenuCommand {
    var c: overlay.MenuCommand = zero
    c.label = label
    c.action = action
    c.enabled = enabled
    c.pictured = true
    c.glyph = glyph
    c.shortcut = shortcut
    c.separated = separated
    ret c
}

fn menu_cell(a: *mem.Arena, t: *const control.Theme) -> (widget.Node, err) {
    let (nones, nones_error) = mem.alloc[widget.Submit](a, 1usize)
    if nones_error != ok { ret (zero, nones_error) }
    nones[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let none = nones[0usize]
    let (list, list_error) = mem.alloc[overlay.MenuCommand](a, 5usize)
    if list_error != ok { ret (zero, list_error) }
    list[0usize] = command(none, "Edit", .Edit, "Ctrl+E", true, false)
    list[1usize] = command(none, "Search", .Search, "Ctrl+F", true, false)
    list[2usize] = command(none, "Settings", .Settings, "", true, true)
    list[3usize] = command(none, "Refresh", .Refresh, "", false, false)
    list[4usize] = command(none, "Add", .Add, "", true, false)
    let (anchor_parts, anchor_error) = mem.alloc[widget.Node](a, 2usize)
    if anchor_error != ok { ret (zero, anchor_error) }
    anchor_parts[0usize] = widget.box(100u64, control.sized_style(1.0, 1.0), zero)
    let (menu, menu_error) = overlay.menu_of(a, 101u64, t, 100u64, "Menu", list[0usize..5usize], true, &nones[0usize])
    if menu_error != ok { ret (zero, menu_error) }
    anchor_parts[1usize] = menu
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, row_error) }
    row[0usize] = widget.stack(0u64, control.sized_style(1.0, 1.0), anchor_parts[0usize..2usize])
    ret (widget.padded(0u64, 8.0, 0.0, 0.0, 0.0, control.sized_style(300.0, 290.0), row[0usize..1usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (node, node_error) = menu_cell(a, t)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "Menu", node: node, drive: .None }
    ret (1usize, ok)
}

fn build_hover(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (node, node_error) = menu_cell(a, t)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "Hovered row", node: node, drive: .Hover }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let plain = looks.Sheet { name: "menu", cells: 1usize, columns: 1usize, cell_w: 320.0, cell_h: 290.0, ctx: zero, build: build }
    try looks.run_material(a, &plain)
    let hover = looks.Sheet { name: "menu_hover", cells: 1usize, columns: 1usize, cell_w: 320.0, cell_h: 290.0, ctx: zero, build: build_hover }
    ret looks.run_material(a, &hover)
}
