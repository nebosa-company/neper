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

fn noop_submit(ctx: *void) -> err { ret ok }

// round 22: a tooltip capture is its anchor button (Hover me, 100 x 28 at (20, 14)) and the tip at (30, 52): here at (20, 3) and (30, 40).
fn with_anchor(a: *mem.Arena, t: *const control.Theme, tip: widget.Node, anchor_x: f32) -> (widget.Node, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (zero, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var options = control.button_options()
    options.width = 100.0
    options.height = 27.0
    let (anchor, anchor_error) = control.button(a, 7090u64, t, "Hover me", &actions[0usize], options)
    if anchor_error != ok { ret (zero, anchor_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = widget.positioned(0u64, anchor_x, 3.0, style.defaults(), control.mem_one_node(a, anchor))
    parts[1usize] = widget.positioned(0u64, 30.0, 40.0, style.defaults(), control.mem_one_node(a, tip))
    ret (widget.stack(0u64, sized(cell_w(), cell_h()), parts[0usize..2usize]), ok)
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
    let (tcell, tcell_error) = with_anchor(a, t, tip, 20.0)
    if tcell_error != ok { ret (0usize, tcell_error) }
    cells[at] = looks.Cell { caption: "tooltip-rest", node: tcell, drive: .None }
    at += 1usize
    // round 13, cells 3 to 7: the other scroll bar captures that differ from rest. 3 vscroll-pressed-arrow (the pointer held on the up
    // arrow), 4 vscroll-disabled (nothing to scroll), 5 hscroll-pressed-arrow, 6 hscroll-disabled, 7 hscroll-hover-track
    let (vp, vp_error) = control.windows_scroll_bar(a, 7030u64, t, true, 170.0, 29.0, 100.0, 24.63)
    if vp_error != ok { ret (0usize, vp_error) }
    let (vp_cell, vp_cell_error) = placed(a, vp, 20.0, 10.0)
    if vp_cell_error != ok { ret (0usize, vp_cell_error) }
    looks.aim(at, 0.0 - 102.0, 0.0 - 82.0)
    cells[at] = looks.Cell { caption: "vscroll-pressed-arrow", node: vp_cell, drive: .Press }
    at += 1usize
    let (vd, vd_error) = control.windows_scroll_bar(a, 7040u64, t, true, 170.0, 100.0, 100.0, 0.0)
    if vd_error != ok { ret (0usize, vd_error) }
    let (vd_cell, vd_cell_error) = placed(a, vd, 20.0, 10.0)
    if vd_cell_error != ok { ret (0usize, vd_cell_error) }
    cells[at] = looks.Cell { caption: "vscroll-disabled", node: vd_cell, drive: .None }
    at += 1usize
    let (hp, hp_error) = control.windows_scroll_bar(a, 7050u64, t, false, 178.0, 29.45, 100.0, 24.7)
    if hp_error != ok { ret (0usize, hp_error) }
    let (hp_cell, hp_cell_error) = placed(a, hp, 16.0, 20.0)
    if hp_cell_error != ok { ret (0usize, hp_cell_error) }
    looks.aim(at, 0.0 - 106.0, 0.0 - 72.0)
    cells[at] = looks.Cell { caption: "hscroll-pressed-arrow", node: hp_cell, drive: .Press }
    at += 1usize
    let (hd, hd_error) = control.windows_scroll_bar(a, 7060u64, t, false, 178.0, 100.0, 100.0, 0.0)
    if hd_error != ok { ret (0usize, hd_error) }
    let (hd_cell, hd_cell_error) = placed(a, hd, 16.0, 20.0)
    if hd_cell_error != ok { ret (0usize, hd_cell_error) }
    cells[at] = looks.Cell { caption: "hscroll-disabled", node: hd_cell, drive: .None }
    at += 1usize
    let (ht, ht_error) = control.windows_scroll_bar(a, 7070u64, t, false, 178.0, 29.45, 100.0, 24.7)
    if ht_error != ok { ret (0usize, ht_error) }
    let (ht_cell, ht_cell_error) = placed(a, ht, 16.0, 20.0)
    if ht_cell_error != ok { ret (0usize, ht_cell_error) }
    cells[at] = looks.Cell { caption: "hscroll-hover-track", node: ht_cell, drive: .Hover }
    at += 1usize
    // 8: tooltip-balloon (159 x 74 at (30, 52) of its 260 x 126 capture; here at (30, 40))
    let (balloon, balloon_error) = control.win_native_balloon(a, 7080u64, t, "Tip title", "This is the tooltip text")
    if balloon_error != ok { ret (0usize, balloon_error) }
    let (balloon_cell, balloon_cell_error) = with_anchor(a, t, balloon, 21.0)
    if balloon_cell_error != ok { ret (0usize, balloon_cell_error) }
    cells[at] = looks.Cell { caption: "tooltip-balloon", node: balloon_cell, drive: .None }
    at += 1usize
    ret (at, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "native_dark2", cells: 9usize, columns: 4usize, cell_w: cell_w(), cell_h: cell_h(), ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
