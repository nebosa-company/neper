// The Windows dark mask edit (a formatted field) set up like the native edit captures edit-rest ... edit-disabled (round 13): there is no
// native mask edit, so it is compared as an edit with the same states and the same text. Cells: rest, hover, focus, selected, read-only,
// disabled. Run with NEPER_LOOKS_OUT=<scratch>; scripts/looks_strict13.py --mask compares them.
// (header of native_dark.e follows)
// One cell per captured state of the edit, spin edit and combo box, each at the capture's text and geometry (a native edit is
// 150 x 24: DFM width 149, the control paints one pixel more), so scripts/looks_strict_dark.py can diff every one without
// cutting rows. Only the windows-dark look is of interest: run with NEPER_LOOKS_OUT=<scratch> and copy
// <scratch>/windows-dark/native_dark.png into docs/ui/looks/windows-dark.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_change(ctx: *void, value: str) -> err { ret ok }
fn noop_value(ctx: *void, value: i64) -> err { ret ok }
fn noop_submit(ctx: *void) -> err { ret ok }

fn cell_w() -> f32 { ret 200.0 }
fn cell_h() -> f32 { ret 100.0 }

fn sized(w: f32, h: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    ret s
}

fn select_all(t: *const control.Theme, key: widget.Key, len: usize) {
    if mem.address_of(t.runtime) == 0usize { ret }
    let (s, state_error) = widget.state_of(t.runtime)
    if state_error != ok { ret }
    let (id, found) = widget.find_by_key(s, key)
    if found != 1usize { ret }
    let unused = widget.edit_select(t.runtime, id, 0usize, len)
}

// `node` with a spacer to its right (and below) so that the middle of the whole box, where the harness puts the pointer, lands `x` px
// from the control's left edge and `y` px from its top.
fn aimed(a: *mem.Arena, node: widget.Node, w: f32, h: f32, x: f32, y: f32) -> (widget.Node, err) {
    let (column, column_error) = mem.alloc[widget.Node](a, 2usize)
    if column_error != ok { ret (zero, column_error) }
    // below the control when y is past the middle, above it otherwise
    if 2.0 * y >= h {
        column[0usize] = node
        column[1usize] = widget.box(0u64, sized(1.0, 2.0 * y - h), zero)
    } else {
        column[0usize] = widget.box(0u64, sized(1.0, h - 2.0 * y), zero)
        column[1usize] = node
    }
    let (row, row_error) = mem.alloc[widget.Node](a, 2usize)
    if row_error != ok { ret (zero, row_error) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), column[0usize..2usize])
    row[1usize] = widget.box(0u64, sized(max_f(0.0, 2.0 * x - w), 1.0), zero)
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), row[0usize..2usize]), ok)
}

// `node` at a whole pixel (x, y) of a cell-sized holder, so an odd sized control does not land on a half pixel.
fn placed(a: *mem.Arena, node: widget.Node, x: f32, y: f32) -> (widget.Node, err) {
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = widget.positioned(0u64, x, y, style.defaults(), control.mem_one_node(a, node))
    ret (widget.stack(0u64, sized(cell_w(), cell_h()), inner[0usize..1usize]), ok)
}

fn max_f(a: f32, b: f32) -> f32 {
    if a > b { ret a }
    ret b
}

fn accept_all(ctx: *void, value: str) -> bool { ret true }

fn same(ctx: *void, out: []u8, value: str) -> usize {
    var n = 0usize
    while n < value.len && n < out.len {
        out[n] = value[n]
        n += 1usize
    }
    ret n
}

fn mask_cell(a: *mem.Arena, t: *const control.Theme, i: usize) -> (widget.Node, err) {
    let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
    if buffer_error != ok { ret (zero, buffer_error) }
    let n = control.copy_text(buffer, "Text value")
    var options = control.field_options()
    options.width = 149.0
    if i == 5usize { options.enabled = false }
    if i == 4usize { options.read_only = true }
    let key = u64(i + 1usize)
    let adapter = control.Format { ctx: zero, accept: accept_all, format: same }
    let (field, field_error) = control.formatted_field(a, key, t, "Mask", buffer, n, adapter, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Change[str] { ctx: zero, invoke: noop_change }, options)
    if field_error != ok { ret (zero, field_error) }
    let (whole_field, whole_field_error) = placed(a, field, 25.0, 38.0)
    ret (whole_field, whole_field_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    control.set_caret_hidden(true)
    let names = [6]str{ "mask-rest", "mask-hover", "mask-focus", "mask-selected", "mask-readonly", "mask-disabled" }
    var i = 0usize
    while i < 6usize {
        let (node, node_error) = mask_cell(a, t, i)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Focus }
        if i == 3usize {
            drive = .Focus
            select_all(t, u64(i + 1usize), 4usize)
        }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "native_dark_mask", cells: 6usize, columns: 6usize, cell_w: cell_w(), cell_h: cell_h(), ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
