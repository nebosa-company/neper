// The Linux look's spin button against the real GTK 4.14 / libadwaita 1.5 one (docs/ui/looks/ref/linux, scripts/linux_cmp_l2.py): at 50 (both
// arrows live) at rest, over each arrow, pressed on each arrow, focused and disabled; at its minimum, disabled at its minimum and at its
// maximum. docs/ui/looks/linux[-dark]/spin_edit.png. Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_change(ctx: *void, value: i64) -> err { ret ok }
fn noop_typed(ctx: *void, value: str) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    control.set_native_caret_off(true)
    let names = [10]str{ "rest", "hover +", "hover -", "press +", "press -", "focus", "disabled", "at minimum", "disabled at minimum", "at maximum" }
    let values = [10]i64{ 50i64, 50i64, 50i64, 50i64, 50i64, 50i64, 50i64, 0i64, 0i64, 100i64 }
    var i = 0usize
    while i < 10usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 24usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let enabled = i != 6usize && i != 8usize
        let key = u64(10usize * (i + 1usize))
        let (spin, spin_error) = control.spin_box_full(a, key, t, "Value", buffer, values[i], 0i64, 100i64, 1i64, widget.Change[i64] { ctx: zero, invoke: noop_change }, widget.Change[str] { ctx: zero, invoke: noop_typed }, 120.0, enabled, false)
        if spin_error != ok { ret (0usize, spin_error) }
        var drive: looks.Drive = .None
        if i == 1usize || i == 2usize { drive = .Hover }
        if i == 3usize || i == 4usize { drive = .Press }
        if i == 5usize { drive = .Focus }
        // The pointer goes to an arrow: the + one is centred 43.5 px right of the control's middle, the - one 10.5.
        if i == 1usize || i == 3usize { looks.aim(i, 43.5, 0.0) }
        if i == 2usize || i == 4usize { looks.aim(i, 10.5, 0.0) }
        // The focus click lands on the value, not on the arrow at the middle.
        if i == 5usize { looks.aim(i, -40.0, 0.0) }
        cells[i] = looks.Cell { caption: names[i], node: spin, drive: drive }
        i += 1usize
    }
    ret (10usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "spin_edit", cells: 10usize, columns: 4usize, cell_w: 130.0, cell_h: 44.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
