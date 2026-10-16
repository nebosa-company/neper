// The Cupertino inset grouped list (list_box): docs/ui/looks/cupertino/list_box.png (and cupertino-dark). A list with one
// row chosen (trailing accent tick), the same with a row hovered, a row pressed, keyboard focus on the list, and a long list
// in a short viewport (scrolls).

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (picks, picks_error) = mem.alloc[widget.Submit](a, 6usize)
    if picks_error != ok { ret (0usize, picks_error) }
    var n = 0usize
    while n < 6usize {
        picks[n] = widget.Submit { ctx: zero, invoke: noop_submit }
        n += 1usize
    }
    let options = [6]str{ "Airplane Mode", "Wi-Fi", "Bluetooth", "Cellular", "Notifications", "Sounds & Haptics" }
    let names = [5]str{ "rest", "hover (row 3)", "pressed (row 3)", "focus", "scrolling, 3 rows" }
    var i = 0usize
    while i < 5usize {
        var rows = 4u32
        if i == 4usize { rows = 3u32 }
        let (node, node_error) = control.list_box(a, u64((i + 1usize) * 100usize), t, "Settings", options[0usize..6usize], 1usize, picks[0usize..6usize], rows, 260.0)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "list_box", cells: 5usize, columns: 3usize, cell_w: 280.0, cell_h: 190.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
