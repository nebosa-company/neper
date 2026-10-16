// The Cupertino progress bar, activity indicator and ring: docs/ui/looks/cupertino/progress_bar.png (and cupertino-dark).
// Bars at 0, 35, 100 %, thick, error, paused and indeterminate (time-dependent: this frame); indicators 20 and 37.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [12]str{ "0 %", "35 %", "100 %", "thick 35 %", "error", "paused", "indeterminate", "spinner 20", "spinner 37", "ring 35 %", "ring 100 %", "ring 64 on bar" }
    var i = 0usize
    while i < 12usize {
        var options = control.progress_options()
        let key = u64((i + 1usize) * 10usize)
        var node: widget.Node = zero
        if i < 7usize {
            var value: f32 = 0.35
            var indeterminate = false
            if i == 0usize { value = 0.0 }
            if i == 2usize { value = 1.0 }
            if i == 3usize { options.thick = true }
            if i == 4usize { options.tone = .Error }
            if i == 5usize { options.tone = .Paused }
            if i == 6usize {
                indeterminate = true
                options.phase = 0.45
            }
            let (made, made_error) = control.progress_bar_of(a, key, t, "Downloading", value, indeterminate, 160.0, options)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        if i == 7usize || i == 8usize {
            var side: f32 = 20.0
            if i == 8usize { side = 37.0 }
            options.phase = 0.25
            let (made, made_error) = control.progress_ring_of(a, key, t, "Loading", 0.0, true, side, options)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        if i >= 9usize {
            var value: f32 = 0.35
            var side: f32 = 36.0
            if i == 10usize { value = 1.0 }
            if i == 11usize { side = 64.0 }
            let (made, made_error) = control.progress_ring_of(a, key, t, "Progress", value, false, side, options)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: .None }
        i += 1usize
    }
    ret (12usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "progress_bar", cells: 12usize, columns: 4usize, cell_w: 176.0, cell_h: 70.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
