// The window caption against the native Windows 11 captures (docs/ui/looks/ref/windows-native/{light,dark}/window-*,
// dialog-*): a resizable window (minimise, maximise, close) and a dialog (close only), active and inactive, 302 and 296
// wide, 31 tall. The light look shows the light caption (v3's DevExpress dialogs draw it), the dark look the dark one.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.navigation
use e.ui.style
use e.ui.widget
use e.ui.window as win

fn one(a: *mem.Arena, t: *const control.Theme, key: widget.Key, title: str, active: bool, window: bool, width: f32) -> (widget.Node, err) {
    var options = navigation.title_bar_options(.Windows)
    options.active = active
    options.minimizable = window
    options.maximizable = window
    options.icon = window
    options.light = t.tokens.palette != .Dark
    let (node, node_error) = navigation.title_bar(a, key, t, title, options, width)
    if node_error != ok { ret (zero, node_error) }
    let holder = control.sized_style(width, 31.0)
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = node
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, holder, held[0usize..1usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let titles = [4]str{ "Window title", "Window title", "Dialog", "Dialog" }
    let captions = [4]str{ "window-active", "window-inactive", "dialog-active", "dialog-inactive" }
    var i = 0usize
    while i < 4usize {
        let window = i < 2usize
        var width: f32 = 296.0
        if window { width = 302.0 }
        let (node, node_error) = one(a, t, u64(i + 1usize) * 10u64, titles[i], i % 2usize == 0usize, window, width)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "title_bar_native", cells: 4usize, columns: 1usize, cell_w: 304.0, cell_h: 33.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
