// The Windows dark look beside the native Windows 11 dark captures, third sheet (round 13): split and picture buttons, then the lists
// (check list, list box, list view, tree) and popup menus, each at the capture's own geometry; scripts/looks_strict13.py (SHEET3) diffs every one.
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

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    control.set_caret_hidden(true)
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var at = 0usize
    // 0 to 2: button-split (rest), -pressed, -disabled: 150 x 32 (face 148 x 30 at (1, 1)); here the face at (20, 20)
    var i = 0usize
    while i < 3usize {
        var options = control.button_options()
        options.width = 150.0
        options.height = 31.0
        if i == 2usize { options.enabled = false }
        let (split, split_error) = control.windows_split(a, u64(8000usize + 10usize * i), t, "Save", &actions[0usize], false, &actions[0usize], options)
        if split_error != ok { ret (0usize, split_error) }
        let (boxed, boxed_error) = placed(a, split, 20.0, 20.0)
        if boxed_error != ok { ret (0usize, boxed_error) }
        var drive: looks.Drive = .None
        if i == 1usize {
            drive = .Press
            looks.aim(at, 0.0 - 70.0, 0.0 - 64.0)
        }
        let names = [3]str{ "button-split", "button-split-pressed", "button-split-disabled" }
        cells[at] = looks.Cell { caption: names[i], node: boxed, drive: drive }
        at += 1usize
        i += 1usize
    }
    // 3 and 4: button-icon (rest) and -icon-disabled: 130 x 32 with a picture before the caption
    i = 0usize
    while i < 2usize {
        var options = control.button_options()
        options.width = 130.0
        options.height = 31.0
        if i == 1usize { options.enabled = false }
        let (icon, icon_error) = control.button_with_glyph(a, u64(8100usize + 10usize * i), t, .Info, "Open", &actions[0usize], options)
        if icon_error != ok { ret (0usize, icon_error) }
        let (boxed, boxed_error) = placed(a, icon, 20.0, 20.0)
        if boxed_error != ok { ret (0usize, boxed_error) }
        let names = [2]str{ "button-icon", "button-icon-disabled" }
        cells[at] = looks.Cell { caption: names[i], node: boxed, drive: .None }
        at += 1usize
        i += 1usize
    }
    ret (at, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "native_dark3", cells: 5usize, columns: 4usize, cell_w: cell_w(), cell_h: cell_h(), ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
