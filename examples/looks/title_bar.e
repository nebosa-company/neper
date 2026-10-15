// The window title bar (the dialog's caption) under every look:
// docs/ui/looks/<look>/title_bar.png. Part of the dialog control (see dialog.e).
// Run from the repository root; see docs/ui/looks-howto.md.
//
// The Windows cells are v3's real captions at their real widths (the visible width of the captured window: the PNG
// less the 8 px invisible resize border on each side and below): Search for Card (a dialog: close only, active),
// About MTG Studio and Options (inactive), Deck Legality (resizable: minimise, maximise, close) and the main window
// with its long title. The last two cells (close hovered, maximised) have no capture.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.navigation
use e.ui.widget
use e.ui.window as win

fn one(a: *mem.Arena, t: *const control.Theme, key: widget.Key, title: str, active: bool, sizeable: bool, minimizable: bool, restored: bool, width: f32) -> (widget.Node, err) {
    var options = navigation.title_bar_options(.Windows)
    options.active = active
    options.minimizable = sizeable && minimizable
    options.maximizable = sizeable
    if restored { options.mode = .Maximized }
    let (node, node_error) = navigation.title_bar(a, key, t, title, options, width)
    ret (node, node_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [8]str{ "Search for Card: dialog, active", "About MTG Studio: inactive", "Deck Legality: resizable", "Options: inactive, wide", "Main window: long title", "Close hovered (no capture)", "Maximised (no capture)", "Main window: inactive" }
    let titles = [8]str{ "Search for Card", "About MTG Studio", "Deck Legality", "Options", "MTG Studio - Card Pool [Assertions] [No Optimization]", "Search for Card", "Deck Legality", "MTG Studio - Card Pool [Assertions] [No Optimization]" }
    let widths = [8]f32{ 309.0, 436.0, 539.0, 712.0, 784.0, 309.0, 539.0, 784.0 }
    var i = 0usize
    while i < 8usize {
        let (node, node_error) = one(a, t, u64(i + 1usize) * 10u64, titles[i], i != 1usize && i != 3usize && i != 7usize, i == 2usize || i == 4usize || i == 6usize || i == 7usize, i != 2usize && i != 6usize, i == 6usize, widths[i])
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 5usize { drive = .Hover }
        // a bar of odd margin in the cell would sit on a half pixel: a holder one wider puts it on whole ones
        var holder = control.sized_style(widths[i] + f32(u32(784.0 - widths[i]) % 2u32), 31.0)
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (0usize, held_error) }
        held[0usize] = node
        let boxed = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, holder, held[0usize..1usize])
        cells[i] = looks.Cell { caption: captions[i], node: boxed, drive: drive }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Hover is driven at the middle of the cell: for the close-only bar that is not the X, so the cell shows the rest bar.
    let sheet = looks.Sheet { name: "title_bar", cells: 8usize, columns: 1usize, cell_w: 784.0, cell_h: 31.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
