// The Linux look's splitter against the real GTK 4.14 / libadwaita 1.5: the horizontal and vertical separators and the two panes
// split by a 1 px handle, docs/ui/looks/linux[-dark]/splitter.png (reference: scripts/linux_cmp_l3.py). Run from the repository root.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_change(ctx: *void, value: f32) -> err { ret ok }

fn pane_of(a: *mem.Arena, t: *const control.Theme, word: str) -> (widget.Node, err) {
    let (said, said_error) = control.text(a, 0u64, word, t, control.text_options())
    if said_error != ok { ret (zero, said_error) }
    ret (widget.aligned(0u64, .Center, .Center, control.sized_style(100.0, 80.0), control.widget_one_of(a, said)), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [4]str{ "separator h", "separator v", "paned", "paned wide" }
    var i = 0usize
    while i < 4usize {
        var node: widget.Node = zero
        var w: f32 = 201.0
        var h: f32 = 80.0
        if i < 2usize {
            var options = control.divider_options()
            if i == 0usize {
                w = 200.0
                h = 4.0
                options.length = 200.0
                options.thick = 4.0
            } else {
                w = 4.0
                h = 60.0
                options.axis = .Vertical
                options.length = 60.0
                options.thick = 4.0
            }
            let (made, made_error) = control.divider_of(a, u64(i + 1usize) * 10u64, t, options)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        } else {
            let (left, left_error) = pane_of(a, t, "Left")
            if left_error != ok { ret (0usize, left_error) }
            let (right, right_error) = pane_of(a, t, "Right")
            if right_error != ok { ret (0usize, right_error) }
            let change = widget.Change[f32] { ctx: zero, invoke: noop_change }
            let (made, made_error) = control.split_view(a, u64(i + 1usize) * 1000u64, t, .Horizontal, left, right, 100.0, 40.0, 40.0, change, 201.0, 80.0)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        let x = f32(usize(210.0 - w) / 2usize)
        let y = f32(usize(90.0 - h) / 2usize)
        let held = widget.positioned(0u64, x, y, control.sized_style(w, h), control.widget_one_of(a, node))
        cells[i] = looks.Cell { caption: names[i], node: widget.stack(0u64, control.sized_style(210.0, 90.0), control.widget_one_of(a, held)), drive: .None }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "splitter", cells: 4usize, columns: 2usize, cell_w: 210.0, cell_h: 90.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
