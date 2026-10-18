// The Linux look's labels against GTK 4.14 / libadwaita 1.5: a plain label, a `.dim-label` and a `.heading`:
// docs/ui/looks/linux[-dark]/label.png, with label-vs-ref.png beside it (reference on the left, built by
// scripts/linux_cmp_l1.py). Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [3]str{ "label", "dim label", "heading" }
    let values = [3]str{ "Label text", "Secondary text", "Heading" }
    var i = 0usize
    while i < 3usize {
        let (node, node_error) = control.linux_label(a, u64(i + 1usize), t, values[i], u32(i))
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: .None }
        i += 1usize
    }
    ret (3usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "label", cells: 3usize, columns: 3usize, cell_w: 116.0, cell_h: 29.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
