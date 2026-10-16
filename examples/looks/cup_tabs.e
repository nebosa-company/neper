// The Cupertino tab list: docs/ui/looks/cupertino/page_control.png (and cupertino-dark). Row one: the macOS tab view's
// segmented strip (24 tall) at rest, hover and pressed on a tab, keyboard focus, one tab disabled. Row two: the iOS tab
// bar (icons over 10 pt labels) with the first, second tab chosen, hover, pressed.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (picks, picks_error) = mem.alloc[widget.Submit](a, 4usize)
    if picks_error != ok { ret (0usize, picks_error) }
    var n = 0usize
    while n < 4usize {
        picks[n] = widget.Submit { ctx: zero, invoke: noop_submit }
        n += 1usize
    }
    let labels = [3]str{ "General", "Display", "Advanced" }
    let names = [10]str{ "strip", "strip hover", "strip pressed", "strip focus", "tab disabled", "bar: first", "bar: second", "bar hover", "bar pressed", "bar disabled" }
    let (off, off_error) = mem.alloc[bool](a, 3usize)
    if off_error != ok { ret (0usize, off_error) }
    off[0usize] = false
    off[1usize] = false
    off[2usize] = true
    let icons = [3]control.GlyphKind{ .Search, .Calendar, .Settings }
    var i = 0usize
    while i < 10usize {
        var options = control.tabs_options()
        var chosen = 0usize
        if i == 4usize { options.disabled = off[0usize..3usize] }
        if i >= 5usize {
            options.icons = icons[0usize..3usize]
            options.bottom = true
        }
        if i == 6usize { chosen = 1usize }
        if i == 9usize { options.disabled = off[0usize..3usize] }
        let (node, node_error) = control.tabs_of(a, u64((i + 1usize) * 100usize), t, labels[0usize..3usize], chosen, picks[0usize..3usize], options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize || i == 7usize { drive = .Hover }
        if i == 2usize || i == 8usize { drive = .Press }
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (10usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "page_control", cells: 10usize, columns: 5usize, cell_w: 236.0, cell_h: 64.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
