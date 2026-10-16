// The Android look's top app bars, docs/ui/looks/material/app_bar.png: small, centre-aligned, medium and large, at rest
// and scrolled (surface-container). Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let (icons, icons_error) = mem.alloc[control.GlyphKind](a, 3usize)
    if icons_error != ok { ret (0usize, icons_error) }
    icons[0usize] = .Search
    icons[1usize] = .Add
    icons[2usize] = .MoreVert
    let names = [6]str{ "Small", "Small, scrolled", "Centre-aligned", "Medium", "Large", "Small, no leading icon" }
    var i = 0usize
    while i < 6usize {
        var size = 0u8
        if i == 2usize { size = 1u8 }
        if i == 3usize { size = 2u8 }
        if i == 4usize { size = 3u8 }
        var count = 2usize
        if i == 3usize || i == 4usize { count = 1usize }
        let (node, node_error) = control.material_app_bar(a, u64((i + 1usize) * 40usize), t, "Page title", .Menu, i != 5usize, icons[0usize..count], size, i == 1usize, &actions[0usize], 360.0)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: .None }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "app_bar", cells: 6usize, columns: 2usize, cell_w: 360.0, cell_h: 154.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
