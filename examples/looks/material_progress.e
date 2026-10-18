// The Android look's progress indicators, docs/ui/looks/material/progress.png: linear (0, 30, 60, 100 %, indeterminate
// mid-sweep) and circular (the same), on the page and in the dark look. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let values = [5]f32{ 0.0, 0.3, 0.6, 1.0, 0.0 }
    let names = [5]str{ "0 %", "30 %", "60 %", "100 %", "Indeterminate" }
    var i = 0usize
    while i < 10usize {
        let column = i % 5usize
        let marquee = column == 4usize
        var node: widget.Node = zero
        var made: err = ok
        if i < 5usize {
            var options = control.progress_options()
            options.phase = 0.0 - 1.0
            if marquee { options.phase = 0.45 }
            let (n, e) = control.progress_bar_of(a, u64(i + 1usize), t, "Loading", values[column], marquee, 240.0, options)
            node = n
            made = e
        } else {
            let (n, e) = control.progress_ring(a, u64(i + 1usize), t, "Loading", values[column], marquee, 48.0)
            node = n
            made = e
        }
        if made != ok { ret (0usize, made) }
        cells[i] = looks.Cell { caption: names[column], node: node, drive: .None }
        i += 1usize
    }
    ret (10usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "progress", cells: 10usize, columns: 5usize, cell_w: 270.0, cell_h: 64.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
