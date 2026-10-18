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
    // Three more linear forms: a buffer to 70 % behind the value, the four-colour form (the same at rest) and the disabled one.
    let more = [3]str{ "Buffer", "Four colour", "Disabled" }
    var j = 0usize
    while j < 3usize {
        var options = control.progress_options()
        options.phase = 0.0 - 1.0
        if j == 0usize { options.buffer = 0.7 }
        let (n, e) = control.progress_bar_of(a, u64(20usize + j), t, "Loading", 0.4, false, 240.0, options)
        if e != ok { ret (0usize, e) }
        var shown = n
        if j == 2usize { shown.style.opacity = 0.38 }
        cells[10usize + j] = looks.Cell { caption: more[j], node: shown, drive: .None }
        j += 1usize
    }
    ret (13usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "progress", cells: 13usize, columns: 5usize, cell_w: 270.0, cell_h: 64.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
