// The Linux look's tooltip against the real GTK 4.14 / libadwaita 1.5 one (scripts/linux/gallery_l3.py captures the real tooltip
// node tree, `tooltip-real`): docs/ui/looks/linux[-dark]/hint.png. The tooltip hangs from a 95 px wide anchor one pixel above its
// place, so it lands on the whole pixel the reference crop sits on. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.overlay
use e.ui.style
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    var anchor = control.sized_style(95.0, 1.0)
    let (tip, tip_error) = overlay.tooltip_of(a, 5000u64, t, 100u64, "Tooltip text", "", true)
    if tip_error != ok { ret (0usize, tip_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (0usize, parts_error) }
    parts[0usize] = widget.box(100u64, anchor, zero)
    parts[1usize] = tip
    let held = widget.positioned(0u64, 57.0, 27.0, control.sized_style(95.0, 1.0), parts[0usize..2usize])
    cells[0usize] = looks.Cell { caption: "tooltip", node: widget.stack(0u64, control.sized_style(210.0, 90.0), control.widget_one_of(a, held)), drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "hint", cells: 1usize, columns: 1usize, cell_w: 210.0, cell_h: 90.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
