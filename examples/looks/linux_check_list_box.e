// The Linux look's check list box against the real GTK 4.14 / libadwaita 1.5 boxed list of check buttons:
// docs/ui/looks/linux[-dark]/check_list_box.png (the library's one picture: three rows, the middle one ticked). Run from the
// repository root; see docs/ui/looks-howto.md. The strict compare is scripts/linux_cmp_l4.py.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (toggles, toggles_error) = mem.alloc[widget.Submit](a, 3usize)
    if toggles_error != ok { ret (0usize, toggles_error) }
    var n = 0usize
    while n < 3usize {
        toggles[n] = widget.Submit { ctx: zero, invoke: noop_submit }
        n += 1usize
    }
    let items = [3]str{ "One", "Two", "Three" }
    let picked = [3]bool{ false, true, false }
    let (node, node_error) = control.multi_select_list(a, 100u64, t, "Blocks", items[0usize..3usize], picked[0usize..3usize], toggles[0usize..3usize], 3u32, 220.0)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "rest", node: node, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "check_list_box", cells: 1usize, columns: 1usize, cell_w: 240.0, cell_h: 112.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
