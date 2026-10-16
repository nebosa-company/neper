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

fn cell_w() -> f32 { ret 290.0 }
fn cell_h() -> f32 { ret 600.0 }

// The control `above` px below the top of its cell box, so the cell's centre (where the harness
// puts the pointer) falls where a state needs it.
fn placed(a: *mem.Arena, node: widget.Node, above: f32, left: f32) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = widget.box(0u64, looks.size_style(1.0, above), zero)
    parts[1usize] = node
    if left < 0.0 {
        // The node pulled left so that its drop button lands on the cell's centre.
        var pull = style.defaults()
        pull.margin = style.EdgeLengths { left: style.Length { Px: left }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, held_error) }
        held[0usize] = node
        parts[1usize] = widget.box(0u64, pull, held[0usize..1usize])
    }
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
    if i <= 1usize || i == 3usize { ret .Hover }
    if i == 5usize { ret .Focus }
    ret .None
}

// Eight cells: the calendar open on a chosen day, open with the pointer on a day (these two on top,
// so that the window has room under them), at rest, hovered, the drop button hot and pressed, an
// empty edit, focused. Open cells are driven so that they
// stand open in their own frame only (the focused cell is last: the runtime keeps the focus on a
// tree slot, which a later pass could land in a cell).
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [6]str{ "Open", "Open, day hover", "Normal", "Hover", "Empty", "Focus" }
    var drives = [6]looks.Drive{ .None, .None, .None, .None, .None, .None }
    var i = 0usize
    while i < 6usize {
        drives[i] = drive_of(i)
        i += 1usize
    }
    let now = pass_of(ctx, 6usize, drives[0usize..6usize])
    let today = time.Date { year: 2026i32, month: 10u8, day: 15u8 }
    let chosen = time.Date { year: 2026i32, month: 10u8, day: 8u8 }
    i = 0usize
    while i < 6usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 32usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        var n = control.copy_text(buffer, "10/8/2026")
        if i == 4usize { n = 0usize }
        let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
        if actions_error != ok { ret (0usize, actions_error) }
        actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
        actions[1usize] = widget.Submit { ctx: zero, invoke: noop_submit }
        var footer = overlay.DateFooter { today: today, clear: &actions[1usize], typing: true, buffer: buffer, len: n, typed: zero }
        var open = false
        var above: f32 = cell_h() * 0.5 - 17.0
        var left: f32 = 10.0
        if i == 0usize {
            // The pointer, at the cell's centre, rests on the weekday row: no day is under it.
            open = now == i
            above = cell_h() * 0.5 - 17.0 - 34.0 - 6.0 - 12.0 - 38.0 - 17.0
        }
        if i == 1usize {
            open = now == i
            above = cell_h() * 0.5 - 17.0 - 34.0 - 6.0 - 12.0 - 38.0 - 17.0 - 38.0 - 34.0
        }
        let (node, node_error) = overlay.date_picker_with(a, u64(i + 1usize) * 100u64, t, "Created", chosen, n > 0usize, open, &actions[0usize], chosen, zero, zero, footer)
        if node_error != ok { ret (0usize, node_error) }
        let (shown, shown_error) = placed(a, node, above, left)
        if shown_error != ok { ret (0usize, shown_error) }
        cells[i] = looks.Cell { caption: captions[i], node: shown, drive: drives[i] }
        i += 1usize
    }
    ret (6usize, ok)
}

// The drop button hot and pressed: two cells where the pointer rests on the calendar glyph (the head at the cell's
// right edge so its centre is the cell's).
fn build_drop(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [2]str{ "Drop button hot", "Drop button pressed" }
    var i = 0usize
    while i < 2usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 32usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let n = control.copy_text(buffer, "10/8/2026")
        let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
        if actions_error != ok { ret (0usize, actions_error) }
        actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
        actions[1usize] = widget.Submit { ctx: zero, invoke: noop_submit }
        let today = time.Date { year: 2026i32, month: 10u8, day: 15u8 }
        let chosen = time.Date { year: 2026i32, month: 10u8, day: 8u8 }
        var footer = overlay.DateFooter { today: today, clear: &actions[1usize], typing: true, buffer: buffer, len: n, typed: zero }
        let (node, node_error) = overlay.date_picker_with(a, u64(i + 1usize) * 100u64, t, "Created", chosen, true, false, &actions[0usize], chosen, zero, zero, footer)
        if node_error != ok { ret (0usize, node_error) }
        var pull = style.defaults()
        pull.margin = style.EdgeLengths { left: style.Length { Px: 0.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
        let (held, held_error) = mem.alloc[widget.Node](a, 2usize)
        if held_error != ok { ret (0usize, held_error) }
        held[0usize] = node
        held[1usize] = widget.box(0u64, looks.size_style(1.0, 1.0), zero)
        var drive: looks.Drive = .Hover
        if i == 1usize { drive = .Press }
        var box = looks.size_style(520.0, 60.0)
        box.padding = style.EdgeLengths { left: style.Length { Px: 0.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 242.0 }, bottom: style.Length { Px: 0.0 } }
        cells[i] = looks.Cell { caption: captions[i], node: widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .End, cross: .Center, gap: 0.0 }, box, held[0usize..1usize]), drive: drive }
        i += 1usize
    }
    ret (2usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize {
        let drop = looks.Sheet { name: "date_edit_button", cells: 2usize, columns: 2usize, cell_w: 520.0, cell_h: 60.0, ctx: zero, build: build_drop }
        ret looks.run_cupertino(a, &drop)
    }
    let (passes, passes_error) = mem.alloc[Pass](a, 1usize)
    if passes_error != ok { ret passes_error }
    passes[0usize] = Pass { call: 0usize }
    let sheet = looks.Sheet { name: "date_edit", cells: 6usize, columns: 3usize, cell_w: cell_w(), cell_h: cell_h(), ctx: mem.cast[*void](&passes[0usize]), build: build }
    ret looks.run_cupertino(a, &sheet)
}
