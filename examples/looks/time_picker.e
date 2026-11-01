// The time picker (overlay.time_picker) in all ten looks: docs/ui/looks/<look>/time_picker.png. Derived: hour, minute and
// second steppers with colons between, on the shared tokens; each look's stepper draws as its own stepper does. Material's
// dial dialog (overlay.time_picker_modal) is a different control and is not on this sheet.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.time
use e.ui.control
use e.ui.looks
use e.ui.looks_b_run
use e.ui.overlay
use e.ui.widget

fn noop_time(ctx: *void, value: time.Time) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [6]str{ "Hours and minutes", "With seconds", "Midnight", "Hover", "Focus", "Pressed" }
    let drives = [6]looks.Drive{ .None, .None, .None, .Hover, .Focus, .Press }
    var i = 0usize
    while i < 6usize {
        var value: time.Time = zero
        value.hour = 14u8
        value.minute = 35u8
        value.second = 8u8
        if i == 2usize {
            value.hour = 0u8
            value.minute = 0u8
            value.second = 0u8
        }
        let (node, node_error) = overlay.time_picker(a, u64((i + 1usize) * 10usize), t, "Time", value, i == 1usize, widget.Change[time.Time] { ctx: zero, invoke: noop_time })
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drives[i] }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "time_picker", cells: 6usize, columns: 3usize, cell_w: 330.0, cell_h: 90.0, ctx: zero, build: build }
    ret looks_b_run.run_ten(a, &sheet)
}
