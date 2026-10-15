// The date edit (TcxDateEdit) in every state under every look: docs/ui/looks/<look>/date_edit.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.time
use e.ui.control
use e.ui.looks
use e.ui.overlay
use e.ui.style
use e.ui.widget
use e.ui.layout as ui_layout

fn noop_submit(ctx: *void) -> err { ret ok }

fn cell_w() -> f32 { ret 210.0 }
fn cell_h() -> f32 { ret 340.0 }

// The control `above` px below the top of its cell box, so the cell's centre (where the harness
// puts the pointer) falls where a state needs it.
fn placed(a: *mem.Arena, node: widget.Node, above: f32) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = widget.box(0u64, looks.size_style(1.0, above), zero)
    parts[1usize] = node
    var column = looks.size_style(cell_w(), cell_h())
    column.padding = style.EdgeLengths { left: style.Length { Px: 10.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column, parts[0usize..2usize]), ok)
}

type Pass = struct { call: usize }

// The cell whose frame this call builds (`count` when it is the resting frame). Two calendars
// cannot stand open in one frame, so an open cell is built open only in its own passes (a hover
// is built twice: see looks.render_sheet).
fn pass_of(ctx: *void, count: usize, drives: []const looks.Drive) -> usize {
    if mem.address_of(ctx) == 0usize { ret count }
    let pass = mem.cast[*Pass](ctx)
    var period = 1usize
    var i = 0usize
    while i < count {
        if drives[i] != .None { period += 1usize }
        if drives[i] == .Hover { period += 1usize }
        i += 1usize
    }
    let at = pass.call % period
    pass.call += 1usize
    var seen = 1usize
    i = 0usize
    while i < count {
        if drives[i] != .None {
            if at == seen { ret i }
            seen += 1usize
            if drives[i] == .Hover {
                if at == seen { ret i }
                seen += 1usize
            }
        }
        i += 1usize
    }
    ret count
}

fn drive_of(i: usize) -> looks.Drive {
    if i <= 1usize || i == 3usize || i == 4usize { ret .Hover }
    if i == 5usize { ret .Press }
    if i == 7usize { ret .Focus }
    ret .None
}

// Eight cells: the calendar open on a chosen day, open with the pointer on a day (these two on top,
// so that the window has room under them), at rest, hovered, the drop button hot and pressed, an
// empty edit, focused. Open cells are driven so that they
// stand open in their own frame only (the focused cell is last: the runtime keeps the focus on a
// tree slot, which a later pass could land in a cell).
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [8]str{ "Open", "Open, day hover", "Normal", "Hover", "Drop button hot", "Drop button pressed", "Empty", "Focus" }
    var drives = [8]looks.Drive{ .None, .None, .None, .None, .None, .None, .None, .None }
    var i = 0usize
    while i < 8usize {
        drives[i] = drive_of(i)
        i += 1usize
    }
    let now = pass_of(ctx, 8usize, drives[0usize..8usize])
    let today = time.Date { year: 2026i32, month: 10u8, day: 15u8 }
    let chosen = time.Date { year: 2026i32, month: 10u8, day: 8u8 }
    i = 0usize
    while i < 8usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 32usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        var n = control.copy_text(buffer, "10/8/2026")
        if i == 6usize { n = 0usize }
        let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
        if actions_error != ok { ret (0usize, actions_error) }
        actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
        actions[1usize] = widget.Submit { ctx: zero, invoke: noop_submit }
        var footer = overlay.DateFooter { today: today, clear: &actions[1usize], typing: true, buffer: buffer, len: n, typed: zero }
        var open = false
        var above: f32 = cell_h() * 0.5 - 10.0
        if i == 0usize {
            // The pointer, at the cell's centre, rests on the weekday row: no day is under it.
            open = now == i
            above = cell_h() * 0.5 - 68.0
        }
        if i == 1usize {
            open = now == i
            above = cell_h() * 0.5 - 115.0
        }
        if i >= 3usize && i <= 5usize { above = cell_h() * 0.5 - 10.0 }
        let (node, node_error) = overlay.date_picker_with(a, u64(i + 1usize) * 100u64, t, "Created", chosen, n > 0usize, open, &actions[0usize], chosen, zero, zero, footer)
        if node_error != ok { ret (0usize, node_error) }
        let (shown, shown_error) = placed(a, node, above)
        if shown_error != ok { ret (0usize, shown_error) }
        cells[i] = looks.Cell { caption: captions[i], node: shown, drive: drives[i] }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (passes, passes_error) = mem.alloc[Pass](a, 1usize)
    if passes_error != ok { ret passes_error }
    passes[0usize] = Pass { call: 0usize }
    let sheet = looks.Sheet { name: "date_edit", cells: 8usize, columns: 4usize, cell_w: cell_w(), cell_h: cell_h(), ctx: mem.cast[*void](&passes[0usize]), build: build }
    ret looks.run_all(a, &sheet)
}
