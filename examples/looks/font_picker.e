// The font picker (control.font_picker) in all ten looks: docs/ui/looks/<look>/font_picker.png. Derived: a list box, a
// segmented control, a stepper and a preview on the shared tokens; the family rows use the theme's face (the picker takes no
// per-family fonts), so the sample does not change with the family. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_b_run
use e.ui.widget

fn noop_index(ctx: *void, value: usize) -> err { ret ok }
fn noop_size(ctx: *void, value: i64) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [5]str{ "Rest", "Second family, Bold", "Hover", "Focus", "Large size" }
    let drives = [5]looks.Drive{ .None, .None, .Hover, .Focus, .None }
    let families = [6]str{ "Cantarell", "Roboto", "Segoe UI", "SF Pro", "Tahoma", "Verdana" }
    let styles = [3]str{ "Regular", "Italic", "Bold" }
    var i = 0usize
    while i < 5usize {
        var family = 0usize
        var style_index = 0usize
        var size = 12i64
        if i == 1usize {
            family = 2usize
            style_index = 2usize
        }
        if i == 4usize { size = 48i64 }
        let (node, node_error) = control.font_picker(a, u64((i + 1usize) * 100usize), t, "Font", families[0usize..6usize], family, styles[0usize..3usize], style_index, size, "The quick brown fox", widget.Change[usize] { ctx: zero, invoke: noop_index }, widget.Change[usize] { ctx: zero, invoke: noop_index }, widget.Change[i64] { ctx: zero, invoke: noop_size }, 4u32, 220.0)
        if node_error != ok { ret (0usize, node_error) }
        if i == 2usize && t.tokens.profile == .MaterialLike { looks.aim(2usize, 0.0, -85.0) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drives[i] }
        i += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "font_picker", cells: 5usize, columns: 3usize, cell_w: 250.0, cell_h: 300.0, ctx: zero, build: build }
    ret looks_b_run.run_ten(a, &sheet)
}
