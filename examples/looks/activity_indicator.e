// The activity indicator (control.progress_ring) in all ten looks: docs/ui/looks/<look>/activity_indicator.png. Spinners and
// rings at three sizes; the spinning arc is time dependent, so the sheet freezes it at a fixed phase. Cupertino and Linux have
// their own drawing; Neper, Windows and Material share the ring on the tokens. Derived, not compared with a real screen.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_b_run
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [9]str{ "spinner 20", "spinner 36", "spinner 64", "ring 0 %", "ring 35 %", "ring 100 %", "ring 64", "error 35 %", "paused 35 %" }
    var i = 0usize
    while i < 9usize {
        var options = control.progress_options()
        options.phase = 0.25
        var value: f32 = 0.35
        var side: f32 = 36.0
        var indeterminate = false
        if i < 3usize {
            indeterminate = true
            if i == 0usize { side = 20.0 }
            if i == 2usize { side = 64.0 }
        }
        if i == 3usize { value = 0.0 }
        if i == 5usize { value = 1.0 }
        if i == 6usize { side = 64.0 }
        if i == 7usize { options.tone = .Error }
        if i == 8usize { options.tone = .Paused }
        let (node, node_error) = control.progress_ring_of(a, u64((i + 1usize) * 10usize), t, "Loading", value, indeterminate, side, options)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: .None }
        i += 1usize
    }
    ret (9usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "activity_indicator", cells: 9usize, columns: 5usize, cell_w: 120.0, cell_h: 90.0, ctx: zero, build: build }
    ret looks_b_run.run_ten(a, &sheet)
}
