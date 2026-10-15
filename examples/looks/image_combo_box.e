// The image combo box (TcxImageComboBox) in every state under every look:
// docs/ui/looks/<look>/image_combo_box.png. Run from the repository root; see docs/ui/looks-howto.md.
// Under the Neper look the control is the plain select (it has no per-item image).

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget
use e.ui.layout as ui_layout

fn noop_submit(ctx: *void) -> err { ret ok }

fn cell_w() -> f32 { ret 150.0 }
fn cell_h() -> f32 { ret 230.0 }

fn pick_actions(a: *mem.Arena, n: usize) -> ([]widget.Submit, err) {
    let (picks, picks_error) = mem.alloc[widget.Submit](a, n)
    if picks_error != ok { ret (zero, picks_error) }
    var i = 0usize
    while i < n {
        picks[i] = widget.Submit { ctx: zero, invoke: noop_submit }
        i += 1usize
    }
    ret (picks, ok)
}

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

// The 16 x 16 picture of an option: a drawn glyph stands in for the image list's bitmap.
fn picture(a: *mem.Arena, t: *const control.Theme, i: usize) -> (widget.Node, err) {
    var ink = style.hex(2723289u32)
    var kind: control.GlyphKind = .Person
    if i == 1usize {
        ink = style.hex(2263842u32)
        kind = .Check
    }
    if i == 2usize {
        ink = style.hex(14431030u32)
        kind = .Alert
    }
    if i == 3usize {
        ink = style.hex(9145227u32)
        kind = .Settings
    }
    if i == 4usize {
        ink = style.hex(12603469u32)
        kind = .Warning
    }
    if i == 5usize {
        ink = style.hex(7171437u32)
        kind = .Picture
    }
    let (made, made_error) = control.mark_glyph(a, ink, kind, 16.0)
    ret (made, made_error)
}

type Pass = struct { call: usize }

// The cell whose frame this call builds (`count` when it is the resting frame). Two lists cannot
// stand open in one frame, so an open cell is built open only in its own passes (a hover is
// built twice: see looks.render_sheet).
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
    if i == 1usize || i == 2usize || i == 3usize { ret .Hover }
    if i == 7usize { ret .Focus }
    ret .None
}

// Eight cells: at rest, hovered; the list open (the chosen row lit), open with the pointer on the
// third row; disabled; no pictures; nothing chosen; focused (last: the runtime keeps the focus on
// a tree slot, which a later pass could land in a cell).
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [8]str{ "Normal", "Hover", "Open", "Open, row hover", "Disabled", "No pictures", "Nothing chosen", "Focus" }
    let names = [6]str{ "Junk", "Needed", "Needed Badly", "Normal", "Not Needed", "Unassigned" }
    var drives = [8]looks.Drive{ .None, .None, .None, .None, .None, .None, .None, .None }
    var i = 0usize
    while i < 8usize {
        drives[i] = drive_of(i)
        i += 1usize
    }
    let now = pass_of(ctx, 8usize, drives[0usize..8usize])
    i = 0usize
    while i < 8usize {
        let (icons, icons_error) = mem.alloc[widget.Node](a, 6usize)
        if icons_error != ok { ret (0usize, icons_error) }
        var k = 0usize
        while k < 6usize {
            let (pic, pic_error) = picture(a, t, k)
            if pic_error != ok { ret (0usize, pic_error) }
            icons[k] = pic
            k += 1usize
        }
        var shown: []const widget.Node = icons[0usize..6usize]
        if i == 5usize { shown = icons[0usize..0usize] }
        var selected = 3usize
        var open = false
        var enabled = true
        var above: f32 = 64.0
        if i == 2usize {
            // The pointer, at the cell's centre, rests on the head: no row is under it.
            open = now == i
            above = cell_h() * 0.5 - 18.0
        }
        if i == 3usize {
            // The pointer lands on the third row (18 each with a picture).
            open = now == i
            above = cell_h() * 0.5 - 21.0 - 18.0 - 18.0 - 9.0
            selected = 1usize
        }
        if i == 4usize { enabled = false }
        if i == 6usize { selected = 99usize }
        let (picks, picks_error) = pick_actions(a, 6usize)
        if picks_error != ok { ret (0usize, picks_error) }
        let (toggle, toggle_error) = pick_actions(a, 1usize)
        if toggle_error != ok { ret (0usize, toggle_error) }
        let (combo, combo_error) = control.image_select(a, u64(i + 1usize) * 100u64, t, "Format", names[0usize..6usize], shown, selected, open, enabled, &toggle[0usize], picks)
        if combo_error != ok { ret (0usize, combo_error) }
        let (node, node_error) = placed(a, combo, above)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drives[i] }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (passes, passes_error) = mem.alloc[Pass](a, 1usize)
    if passes_error != ok { ret passes_error }
    passes[0usize] = Pass { call: 0usize }
    let sheet = looks.Sheet { name: "image_combo_box", cells: 8usize, columns: 4usize, cell_w: cell_w(), cell_h: cell_h(), ctx: mem.cast[*void](&passes[0usize]), build: build }
    ret looks.run_all(a, &sheet)
}
