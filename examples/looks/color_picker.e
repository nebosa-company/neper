// The colour picker (overlay.color_picker) in all ten looks: docs/ui/looks/<look>/color_picker.png. Derived: a swatch beside
// RGB(A) sliders on the shared tokens; each look's slider draws as its own slider does. Platforms' own colour dialogs are not
// drawn. Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.gfx.paint
use e.ui.control
use e.ui.looks
use e.ui.looks_b_run
use e.ui.overlay
use e.ui.widget

fn noop_color(ctx: *void, value: paint.Color) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [6]str{ "Orange", "With alpha", "Black", "Hover", "Focus", "Pressed" }
    let drives = [6]looks.Drive{ .None, .None, .None, .Hover, .Focus, .Press }
    var i = 0usize
    while i < 6usize {
        var colour = paint.rgba(0.95, 0.55, 0.1, 1.0)
        if i == 1usize { colour = paint.rgba(0.2, 0.5, 0.9, 0.6) }
        if i == 2usize { colour = paint.rgba(0.0, 0.0, 0.0, 1.0) }
        let (node, node_error) = overlay.color_picker(a, u64((i + 1usize) * 10usize), t, "Colour", colour, i == 1usize, widget.Change[paint.Color] { ctx: zero, invoke: noop_color }, 240.0)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drives[i] }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "color_picker", cells: 6usize, columns: 3usize, cell_w: 270.0, cell_h: 150.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    try looks.run_linux(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    // Android: each slider has its channel letter and reading beside it, so the picker is 68 wider
    let android = looks.Sheet { name: "color_picker", cells: 6usize, columns: 3usize, cell_w: 340.0, cell_h: 150.0, ctx: zero, build: build }
    ret looks.run_material(a, &android)
}
