// The Cupertino stepper and spin box: docs/ui/looks/cupertino/spin_edit.png (and cupertino-dark). The stepper at
// rest, at its lower bound, upper bound, hover and pressed (the plus half), with keyboard focus and disabled (both
// halves at a bound), then the spin box (field and stepper) at rest, at a bound, hover, disabled and invalid.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_change(ctx: *void, value: i64) -> err { ret ok }
fn noop_typed(ctx: *void, value: str) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [12]str{ "rest", "lower bound", "upper bound", "hover (plus half)", "pressed (plus half)", "keyboard focus", "disabled", "spin box", "spin box at bound", "spin box hover", "spin box disabled", "spin box invalid" }
    let values = [12]i64{ 5i64, 0i64, 10i64, 5i64, 5i64, 5i64, 5i64, 12i64, 0i64, 12i64, 12i64, 120i64 }
    let change = widget.Change[i64] { ctx: zero, invoke: noop_change }
    let typed = widget.Change[str] { ctx: zero, invoke: noop_typed }
    var i = 0usize
    while i < 12usize {
        let key = u64((i + 1usize) * 10usize)
        var node: widget.Node = zero
        if i < 7usize {
            var high = 10i64
            var low = 0i64
            if i == 6usize {
                low = 5i64
                high = 5i64
            }
            let (made, made_error) = control.stepper(a, key, t, "Quantity", values[i], low, high, 1i64, change)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        } else {
            let (buffer, buffer_error) = mem.alloc[u8](a, 32usize)
            if buffer_error != ok { ret (0usize, buffer_error) }
            let (made, made_error) = control.spin_box_full(a, key, t, "Copies", buffer, values[i], 0i64, 99i64, 1i64, change, typed, 96.0, i != 10usize, i == 11usize)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        var drive: looks.Drive = .None
        if i == 3usize || i == 9usize { drive = .Hover }
        if i == 4usize { drive = .Press }
        if i == 5usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (12usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "spin_edit", cells: 12usize, columns: 4usize, cell_w: 190.0, cell_h: 56.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
