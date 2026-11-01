// The duration picker (overlay.duration_picker) in all ten looks: docs/ui/looks/<look>/duration_picker.png. Derived: hour,
// minute and second steppers on the shared tokens; each look's stepper draws as its own stepper does. No platform has this
// control. Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.time
use e.ui.control
use e.ui.looks
use e.ui.looks_b_run
use e.ui.overlay
use e.ui.widget

fn noop_duration(ctx: *void, value: time.Duration) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [5]str{ "1 h 30 min", "Zero", "Long", "Hover", "Focus" }
    let drives = [5]looks.Drive{ .None, .None, .None, .Hover, .Focus }
    var i = 0usize
    while i < 5usize {
        var value = time.Duration { nanos: (3600i64 + 1800i64) * 1000000000i64 }
        if i == 1usize { value = time.Duration { nanos: 0i64 } }
        if i == 2usize { value = time.Duration { nanos: (123i64 * 3600i64 + 45i64 * 60i64 + 6i64) * 1000000000i64 } }
        let (node, node_error) = overlay.duration_picker(a, u64((i + 1usize) * 10usize), t, "Duration", value, widget.Change[time.Duration] { ctx: zero, invoke: noop_duration })
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drives[i] }
        i += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "duration_picker", cells: 5usize, columns: 3usize, cell_w: 250.0, cell_h: 90.0, ctx: zero, build: build }
    ret looks_b_run.run_ten(a, &sheet)
}
