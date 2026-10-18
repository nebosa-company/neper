// The Linux look's spin button against the real GTK 4.14 / libadwaita 1.5 one (docs/ui/looks/ref/linux, scripts/linux_cmp_l2.py): at 50 (both
// arrows live) at rest, over each arrow, pressed on each arrow, focused and disabled; at its minimum, disabled at its minimum and at its
// maximum. docs/ui/looks/linux[-dark]/spin_edit.png. Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_change(ctx: *void, value: i64) -> err { ret ok }
fn noop_typed(ctx: *void, value: str) -> err { ret ok }

fn one_node(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret zero }
    held[0usize] = node
    ret held[0usize..1usize]
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    control.set_native_caret_off(true)
    let names = [11]str{ "rest", "hover +", "hover -", "press +", "press -", "focus", "disabled", "at minimum", "disabled at minimum", "at maximum", "vertical class" }
    let values = [11]i64{ 50i64, 50i64, 50i64, 50i64, 50i64, 50i64, 50i64, 0i64, 0i64, 100i64, 42i64 }
    var i = 0usize
    while i < 11usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 24usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let enabled = i != 6usize && i != 8usize
        let key = u64(10usize * (i + 1usize))
        var spin: widget.Node = zero
        var spin_error: err = ok
        if i == 10usize {
            let (tall, tall_error) = control.spin_box_linux_tall(a, key, t, "Value", buffer, values[i], 0i64, 100i64, 1i64, widget.Change[i64] { ctx: zero, invoke: noop_change }, widget.Change[str] { ctx: zero, invoke: noop_typed }, 98.0)
            // 35 high: the sheet centres on whole pixels in a 36 high box, as the capture's crop sits in its cell
            spin = widget.aligned(0u64, .Start, .Start, control.sized_style(98.0, 36.0), one_node(a, tall))
            spin_error = tall_error
        } else {
            let (plain, plain_error) = control.spin_box_full(a, key, t, "Value", buffer, values[i], 0i64, 100i64, 1i64, widget.Change[i64] { ctx: zero, invoke: noop_change }, widget.Change[str] { ctx: zero, invoke: noop_typed }, 120.0, enabled, false)
            spin = plain
            spin_error = plain_error
        }
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
    ret (11usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "spin_edit", cells: 11usize, columns: 4usize, cell_w: 130.0, cell_h: 44.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
