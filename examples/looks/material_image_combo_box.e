// The Android look's image combo box: an exposed dropdown menu whose head and rows carry a 24 dp leading icon.
// Run from the repository root; docs/ui/looks/material/image_combo_box.png.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget
use e.ui.layout as ui_layout

fn noop_submit(ctx: *void) -> err { ret ok }

fn cell_w() -> f32 { ret 440.0 }

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
fn placed(a: *mem.Arena, node: widget.Node, above: f32, left: f32, high: f32) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = widget.box(0u64, looks.size_style(1.0, above), zero)
    parts[1usize] = node
    var column = looks.size_style(cell_w(), high)
    column.padding = style.EdgeLengths { left: style.Length { Px: left }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column, parts[0usize..2usize]), ok)
}

// The 16 x 16 picture of an option: a drawn glyph stands in for the image list's bitmap.
fn picture(a: *mem.Arena, t: *const control.Theme, i: usize) -> (widget.Node, err) {
    var ink = style.color(t.tokens, .OnSurfaceVariant)
    var kind: control.GlyphKind = .Person
    if i == 1usize {
        ink = style.color(t.tokens, .OnSurfaceVariant)
        kind = .Check
    }
    if i == 2usize {
        ink = style.color(t.tokens, .OnSurfaceVariant)
        kind = .Alert
    }
    if i == 3usize {
        ink = style.color(t.tokens, .OnSurfaceVariant)
        kind = .Settings
    }
    if i == 4usize {
        ink = style.color(t.tokens, .OnSurfaceVariant)
        kind = .Warning
    }
    if i == 5usize {
        ink = style.color(t.tokens, .OnSurfaceVariant)
        kind = .Picture
    }
    let (made, made_error) = control.mark_glyph(a, ink, kind, 24.0)
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

// Sheet 0 (cell 90 high, the control under the pointer): enabled, hovered, focused, disabled, error-less variants.
// Sheet 1 (cell 330 high): the menu open, the pointer on the head's side or on a row.
fn high_of(sheet_no: usize) -> f32 {
    if sheet_no == 0usize { ret 90.0 }
    ret 400.0
}

fn count_of(sheet_no: usize) -> usize {
    if sheet_no == 0usize { ret 6usize }
    ret 3usize
}

fn drive_of(sheet_no: usize, i: usize) -> looks.Drive {
    if sheet_no == 0usize {
        if i == 1usize { ret .Hover }
        if i == 2usize { ret .Focus }
        ret .None
    }
    ret .Hover
}

fn build_set(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, sheet_no: usize) -> (usize, err) {
    let state_captions = [6]str{ "Enabled", "Hovered", "Focused", "Disabled", "No pictures", "Nothing chosen" }
    let list_captions = [3]str{ "Open, Normal chosen", "Open, row hovered", "Open, Needed chosen (hovered)" }
    let names = [6]str{ "Junk", "Needed", "Needed Badly", "Normal", "Not Needed", "Unassigned" }
    let n = count_of(sheet_no)
    var drives = [8]looks.Drive{ .None, .None, .None, .None, .None, .None, .None, .None }
    var i = 0usize
    while i < n {
        drives[i] = drive_of(sheet_no, i)
        i += 1usize
    }
    let now = pass_of(ctx, n, drives[0usize..n])
    i = 0usize
    while i < n {
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
        var selected = 3usize
        var open = false
        var enabled = true
        var above: f32 = 17.0
        var left: f32 = 110.0
        if sheet_no == 0usize {
            if i == 3usize { enabled = false }
            if i == 4usize { shown = icons[0usize..0usize] }
            if i == 5usize { selected = 99usize }
        } else {
            open = now == i
            above = 12.0
            left = 60.0
            // Cell 0: the pointer (cell centre) is right of the field, on no row; 1: on a row of the menu.
            if i == 0usize { left = 0.0 }
            if i == 2usize { selected = 1usize }
        }
        let (picks, picks_error) = pick_actions(a, 6usize)
        if picks_error != ok { ret (0usize, picks_error) }
        let (toggle, toggle_error) = pick_actions(a, 1usize)
        if toggle_error != ok { ret (0usize, toggle_error) }
        let (combo, combo_error) = control.image_select(a, u64(i + 1usize) * 100u64, t, "Format", names[0usize..6usize], shown, selected, open, enabled, &toggle[0usize], picks)
        if combo_error != ok { ret (0usize, combo_error) }
        let (node, node_error) = placed(a, combo, above, left, high_of(sheet_no))
        if node_error != ok { ret (0usize, node_error) }
        var caption = state_captions[i]
        if sheet_no == 1usize { caption = list_captions[i] }
        cells[i] = looks.Cell { caption: caption, node: node, drive: drives[i] }
        i += 1usize
    }
    ret (n, ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (made, made_error) = build_set(ctx, a, t, cells, 0usize)
    ret (made, made_error)
}

fn build_lists(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (made, made_error) = build_set(ctx, a, t, cells, 1usize)
    ret (made, made_error)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (passes, passes_error) = mem.alloc[Pass](a, 1usize)
    if passes_error != ok { ret passes_error }
    passes[0usize] = Pass { call: 0usize }
    if args.len > 1usize {
        let lists = looks.Sheet { name: "image_combo_box_lists", cells: 3usize, columns: 3usize, cell_w: cell_w(), cell_h: 400.0, ctx: mem.cast[*void](&passes[0usize]), build: build_lists }
        ret looks.run_material(a, &lists)
    }
    let sheet = looks.Sheet { name: "image_combo_box", cells: 6usize, columns: 3usize, cell_w: cell_w(), cell_h: 90.0, ctx: mem.cast[*void](&passes[0usize]), build: build }
    ret looks.run_material(a, &sheet)
}
