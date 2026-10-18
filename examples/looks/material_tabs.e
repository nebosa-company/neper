// The Android look's tabs, docs/ui/looks/material/tabs.png: primary tabs (text, and icon with text), secondary tabs, a
// disabled tab, and hovered, focused and pressed tabs. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (picks, picks_error) = mem.alloc[widget.Submit](a, 3usize)
    if picks_error != ok { ret (0usize, picks_error) }
    var p = 0usize
    while p < 3usize {
        picks[p] = widget.Submit { ctx: zero, invoke: noop_submit }
        p += 1usize
    }
    let labels = [3]str{ "Videos", "Photos", "Audio" }
    let icons = [3]control.GlyphKind{ .Search, .Picture, .Person }
    let disabled = [3]bool{ false, false, true }
    let names = [7]str{ "Primary", "Primary, icons", "Secondary", "Secondary, second", "Primary, disabled tab", "Primary, hovered", "Primary, pressed" }
    var i = 0usize
    while i < 7usize {
        var options = control.tabs_options()
        options.fixed = true
        options.width = 300.0
        options.secondary = i == 2usize || i == 3usize
        if i == 1usize { options.icons = icons[0usize..3usize] }
        if i == 4usize { options.disabled = disabled[0usize..3usize] }
        var selected = 0usize
        if i == 3usize { selected = 1usize }
        let (node, node_error) = control.tabs_of(a, u64((i + 1usize) * 10usize), t, labels[0usize..3usize], selected, picks[0usize..3usize], options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 5usize { drive = .Hover }
        if i == 6usize { drive = .Press }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (7usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "tabs", cells: 7usize, columns: 2usize, cell_w: 310.0, cell_h: 73.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
