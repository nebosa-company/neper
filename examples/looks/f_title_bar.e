// navigation.title_bar under all ten looks: docs/ui/looks/<look>/title_bar_all.png (title_bar.png is the older Windows
// dialog sheet and stays as it is). An application drawn caption with the platform buttons: Windows buttons for the Neper,
// Windows and Material looks, a GNOME header for Linux, traffic lights at the start for Cupertino. Active, inactive,
// maximised, no maximise, close only and a hovered close button.
// Derived from the shared tokens; no platform capture. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.looks_f
use e.ui.navigation
use e.ui.widget
use e.ui.window as win

fn platform_of(t: *const control.Theme) -> win.Platform {
    if t.tokens.profile == .Linux { ret .Linux }
    if t.tokens.profile == .CupertinoLike { ret .Mac }
    ret .Windows
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [6]str{ "Active", "Inactive", "Maximised", "No maximise", "Close only", "Close hovered" }
    var i = 0usize
    while i < 6usize {
        var options = navigation.title_bar_options(platform_of(t))
        options.frameless = true
        options.minimizable = true
        options.maximizable = true
        options.resizable = true
        options.active = i != 1usize
        if i == 2usize { options.mode = .Maximized }
        if i == 3usize { options.maximizable = false }
        if i == 4usize {
            options.minimizable = false
            options.maximizable = false
            options.resizable = false
        }
        let (node, node_error) = navigation.title_bar(a, u64((i + 1usize) * 100usize), t, "Deck editor", options, 420.0)
        if node_error != ok { ret (0usize, node_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (0usize, held_error) }
        held[0usize] = node
        let boxed = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(420.0, 32.0), held[0usize..1usize])
        var drive: looks.Drive = .None
        if i == 5usize {
            drive = .Hover
            var dx: f32 = 195.0
            if options.platform == .Mac { dx = -190.0 }
            looks.aim(i, dx, 0.0)
        }
        cells[i] = looks.Cell { caption: captions[i], node: boxed, drive: drive }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "title_bar_all", cells: 6usize, columns: 2usize, cell_w: 440.0, cell_h: 70.0, ctx: zero, build: build }
    ret looks_f.run_ten(a, &sheet)
}
