// The window title bar (the dialog's caption) under every look:
// docs/ui/looks/<look>/title_bar.png. Part of the dialog control (see dialog.e).
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.navigation
use e.ui.widget
use e.ui.window as win

fn one(a: *mem.Arena, t: *const control.Theme, key: widget.Key, active: bool, restored: bool, width: f32) -> (widget.Node, err) {
    var options = navigation.title_bar_options(.Windows)
    options.active = active
    if restored { options.mode = .Maximized }
    let (node, node_error) = navigation.title_bar(a, key, t, "Options", options, width)
    ret (node, node_error)
}

// Four bars: active, inactive, maximised (the restore glyph) and, driven, the pointer over the
// middle of a narrow bar, which is its maximise button.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [4]str{ "Active", "Inactive", "Maximised", "Maximise hover" }
    let widths = [4]f32{ 300.0, 300.0, 300.0, 160.0 }
    var i = 0usize
    while i < 4usize {
        let (node, node_error) = one(a, t, u64(i + 1usize) * 10u64, i != 1usize, i == 2usize, widths[i])
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 3usize { drive = .Hover }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "title_bar", cells: 4usize, columns: 2usize, cell_w: 310.0, cell_h: 40.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
