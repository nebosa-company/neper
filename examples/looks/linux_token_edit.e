// The Linux look's token edit against libadwaita's `pill` buttons as GTK 4.14 draws them (scripts/linux_cmp_l2.py; GTK has no token entry):
// three tokens (alpha, beta, gamma) and the typing field after them, a hovered token, the empty edit, the field focused, a long list
// wrapped. docs/ui/looks/linux[-dark]/token_edit.png. Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_change(ctx: *void, value: str) -> err { ret ok }
fn noop_submit(ctx: *void) -> err { ret ok }
fn noop_active(ctx: *void, index: usize) -> err { ret ok }

fn one_node(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret zero }
    held[0usize] = node
    ret held[0usize..1usize]
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    control.set_native_caret_off(true)
    let captions = [5]str{ "rest", "hover token", "empty", "field focus", "wrapped" }
    let names = [7]str{ "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta" }
    var i = 0usize
    while i < 5usize {
        var count = 3usize
        if i == 2usize { count = 0usize }
        if i == 4usize { count = 7usize }
        let (shown, shown_error) = mem.alloc[str](a, 8usize)
        if shown_error != ok { ret (0usize, shown_error) }
        let (removes, removes_error) = mem.alloc[widget.Submit](a, 8usize)
        if removes_error != ok { ret (0usize, removes_error) }
        var n = 0usize
        while n < count {
            shown[n] = names[n]
            removes[n] = widget.Submit { ctx: zero, invoke: noop_submit }
            n += 1usize
        }
        let (buffer, buffer_error) = mem.alloc[u8](a, 32usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let none_words = [1]str{ "" }
        let picks = [1]widget.Submit{ widget.Submit { ctx: zero, invoke: noop_submit } }
        let dismiss = widget.Submit { ctx: zero, invoke: noop_submit }
        let key = u64(100usize * (i + 1usize))
        var width: f32 = 500.0
        if i == 4usize { width = 330.0 }
        let (edit, edit_error) = control.token_field(a, key, t, "Add", shown[0usize..count], removes[0usize..count], buffer, 0usize, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Submit { ctx: zero, invoke: noop_submit }, none_words[0usize..0usize], 0usize, false, picks[0usize..0usize], widget.Change[usize] { ctx: zero, invoke: noop_active }, &dismiss, width)
        if edit_error != ok { ret (0usize, edit_error) }
        // Every control sits at the left of a box as wide as the widest, which the harness centres, so none lands on a half pixel.
        var drive: looks.Drive = .None
        if i == 1usize {
            drive = .Hover
            // The pointer to the first pill: the pill is 102 wide, the box 500.
            looks.aim(i, 51.0 - 250.0, 0.0)
        }
        if i == 3usize {
            drive = .Focus
            looks.aim(i, 0.0, 0.0)
        }
        var box = looks.size_style(500.0, 100.0)
        if i == 4usize { box = looks.size_style(500.0, 100.0) }
        cells[i] = looks.Cell { caption: captions[i], node: widget.aligned(0u64, .Start, .Start, box, one_node(a, edit)), drive: drive }
        i += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "token_edit", cells: 5usize, columns: 1usize, cell_w: 510.0, cell_h: 100.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
