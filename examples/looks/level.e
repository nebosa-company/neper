// The level (control.level) in all ten looks: docs/ui/looks/<look>/level.png. Derived: bar, limit mark and segments read the
// shared tokens (Primary, Warning, Error, Success, SurfaceContainerHighest); no platform draws this control.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_b_run
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [9]str{ "40 %", "empty", "full", "warning 75 %", "danger 95 %", "small", "limit mark", "3 segments", "bars" }
    let values = [9]f32{ 40.0, 0.0, 100.0, 75.0, 95.0, 40.0, 60.0, 66.0, 60.0 }
    var i = 0usize
    while i < 9usize {
        var options = control.level_options()
        var warn: f32 = 2.0
        var danger: f32 = 2.0
        if i == 3usize || i == 4usize || i == 6usize {
            warn = 0.7
            danger = 0.9
        }
        if i == 4usize { options.status = "Almost full" }
        if i == 5usize { options.small = true }
        if i == 6usize { options.limit = true }
        if i == 7usize { options.segments = 3u32 }
        if i == 8usize { options.bars = true }
        let (node, node_error) = control.level_of(a, u64((i + 1usize) * 10usize), t, "Storage", values[i], 0.0, 100.0, warn, danger, 150.0, options)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: .None }
        i += 1usize
    }
    ret (9usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "level", cells: 9usize, columns: 3usize, cell_w: 180.0, cell_h: 70.0, ctx: zero, build: build }
    ret looks_b_run.run_ten(a, &sheet)
}
