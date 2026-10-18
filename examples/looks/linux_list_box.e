// The Linux look's list box against the real GTK 4.14 / libadwaita 1.5 boxed list: docs/ui/looks/linux[-dark]/list_box.png. Three cells as
// the library's gallery has them: rest, the second row chosen, the pointer over the third row. Run from the repository root;
// see docs/ui/looks-howto.md. The reference composite and the strict compare are scripts/linux_cmp_l4.py.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (picks, picks_error) = mem.alloc[widget.Submit](a, 4usize)
    if picks_error != ok { ret (0usize, picks_error) }
    var n = 0usize
    while n < 4usize {
        picks[n] = widget.Submit { ctx: zero, invoke: noop_submit }
        n += 1usize
    }
    let items = [4]str{ "Alpha", "Beta", "Gamma", "Delta" }
    let names = [3]str{ "rest", "selected", "hover" }
    var i = 0usize
    while i < 3usize {
        var chosen = 99usize
        if i == 1usize { chosen = 1usize }
        let (node, node_error) = control.list_box(a, u64((i + 1usize) * 100usize), t, "Format", items[0usize..4usize], chosen, picks[0usize..4usize], 4u32, 220.0)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 2usize {
            drive = .Hover
            looks.aim(i, 0.0, 24.0)
        }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (3usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "list_box", cells: 3usize, columns: 3usize, cell_w: 240.0, cell_h: 211.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
