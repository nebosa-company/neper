// The Windows dark look beside the native Windows 11 dark captures, second sheet (round 12): scroll bars, tooltips, popup menus, list box,
// check list, tree and list view, each at the capture's own text and size so scripts/looks_strict_dark.py (SHEET2) can diff every one.
// Only windows-dark matters: run with NEPER_LOOKS_OUT=<scratch> and copy <scratch>/windows-dark/native_dark2.png into docs/ui/looks/windows-dark.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn cell_w() -> f32 { ret 260.0 }
fn cell_h() -> f32 { ret 200.0 }

fn sized(w: f32, h: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    ret s
}

// `node` at a whole pixel (x, y) of a cell-sized holder.
fn placed(a: *mem.Arena, node: widget.Node, x: f32, y: f32) -> (widget.Node, err) {
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = widget.positioned(0u64, x, y, style.defaults(), control.mem_one_node(a, node))
    ret (widget.stack(0u64, sized(cell_w(), cell_h()), inner[0usize..1usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    var at = 0usize
    // 0: vscroll-rest (17 x 170 at (20, 10)): a thumb 40 long from row 51
    let (vbar, vbar_error) = control.windows_scroll_bar(a, 7000u64, t, true, 170.0, 29.0, 100.0, 24.63)
    if vbar_error != ok { ret (0usize, vbar_error) }
    let (vcell, vcell_error) = placed(a, vbar, 20.0, 10.0)
    if vcell_error != ok { ret (0usize, vcell_error) }
    cells[at] = looks.Cell { caption: "vscroll-rest", node: vcell, drive: .None }
    at += 1usize
    // 1: hscroll-rest (178 x 17 at (16, 20)): a thumb from column 53
    let (hbar, hbar_error) = control.windows_scroll_bar(a, 7010u64, t, false, 178.0, 29.45, 100.0, 24.7)
    if hbar_error != ok { ret (0usize, hbar_error) }
    let (hcell, hcell_error) = placed(a, hbar, 16.0, 20.0)
    if hcell_error != ok { ret (0usize, hcell_error) }
    cells[at] = looks.Cell { caption: "hscroll-rest", node: hcell, drive: .None }
    at += 1usize
    // 2: tooltip-rest (126 x 20 at (30, 52) of its 260 x 110 capture; here at (30, 40)) and 3: tooltip-balloon (159 x 74)
    let (tip, tip_error) = control.win_native_tooltip(a, 7020u64, t, "This is the tooltip text", 126.0, 20.0)
    if tip_error != ok { ret (0usize, tip_error) }
    let (tcell, tcell_error) = placed(a, tip, 30.0, 40.0)
    if tcell_error != ok { ret (0usize, tcell_error) }
    cells[at] = looks.Cell { caption: "tooltip-rest", node: tcell, drive: .None }
    at += 1usize
    ret (at, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "native_dark2", cells: 3usize, columns: 4usize, cell_w: cell_w(), cell_h: cell_h(), ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
