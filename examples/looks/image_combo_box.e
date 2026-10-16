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

// The image combo boxes as the v3 dialogs show them (Options > Defaults, Internet Authentication and
// Morph: no picture in the head, the widths of their DFMs), one per cell at (4, 4) of a cell as large as
// the capture's crop; `image_combo_box.exe dialog` writes image_combo_box_dialog.png, which
// compares pixel for pixel with ref/windows/image_combo_box_dialog.png (scripts/looks_refs_d.py).
fn build_dialog(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let values = [3]str{ "Unknown", "No Authentication", "Stretch" }
    let widths = [3]f32{ 335.0, 189.0, 151.0 }
    let ys = [3]f32{ 99.0, 71.0, 278.0 }
    let xs = [3]f32{ 371.0, 371.0, 406.0 }
    var i = 0usize
    while i < 3usize {
        let names = [2]str{ values[i], "Other" }
        let (picks, picks_error) = pick_actions(a, 2usize)
        if picks_error != ok { ret (0usize, picks_error) }
        let (toggle, toggle_error) = pick_actions(a, 1usize)
        if toggle_error != ok { ret (0usize, toggle_error) }
        var none: []const widget.Node = zero
        let (combo, combo_error) = control.image_select_at(a, u64(i + 1usize) * 100u64, t, "Condition", names[0usize..2usize], none, 0usize, false, true, &toggle[0usize], picks, widths[i], ys[i], xs[i])
        if combo_error != ok { ret (0usize, combo_error) }
        let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
        if parts_error != ok { ret (0usize, parts_error) }
        parts[0usize] = widget.box(0u64, looks.size_style(1.0, 4.0), zero)
        parts[1usize] = combo
        var column = looks.size_style(343.0, 29.0)
        column.padding = style.EdgeLengths { left: style.Length { Px: 4.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
        cells[i] = looks.Cell { caption: "", node: widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column, parts[0usize..2usize]), drive: .None }
        i += 1usize
    }
    ret (3usize, ok)
}

// The open drop-down of the image combo boxes (ref/windows/states/combo-box-open-*; these dialog combos
// are TcxImageComboBox): the head at (4, 4) of a one-cell sheet with its popup right under it.
// `image_combo_box.exe o<n>`: 1 Authentication, 2 the same with row 2 lit, 3 Card Art Position (Stretch),
// 4 Condition (15 rows), 5 Condition with row 4 lit.
type Open = struct { name: str, width: f32, rows: usize, active: usize, edge_x: f32, edge_y: f32, set: usize }

fn open_spec(n: usize) -> Open {
    if n == 1usize { ret Open { name: "image_combo_box_open_auth", width: 189.0, rows: 2usize, active: 0usize, edge_x: 371.0, edge_y: 71.0, set: 0usize } }
    if n == 2usize { ret Open { name: "image_combo_box_open_auth2", width: 189.0, rows: 2usize, active: 1usize, edge_x: 371.0, edge_y: 71.0, set: 0usize } }
    if n == 3usize { ret Open { name: "image_combo_box_open_art", width: 151.0, rows: 3usize, active: 0usize, edge_x: 10406.0, edge_y: 278.0, set: 1usize } }
    if n == 4usize { ret Open { name: "image_combo_box_open_condition", width: 335.0, rows: 15usize, active: 0usize, edge_x: 10371.0, edge_y: 99.0, set: 2usize } }
    if n == 6usize { ret Open { name: "image_combo_box_open_art2", width: 151.0, rows: 3usize, active: 2usize, edge_x: 406.0, edge_y: 278.0, set: 1usize } }
    ret Open { name: "image_combo_box_open_condition2", width: 335.0, rows: 15usize, active: 3usize, edge_x: 371.0, edge_y: 99.0, set: 2usize }
}

fn open_high(o: Open) -> f32 { ret 4.0 + 21.0 + f32(o.rows) * 15.0 + 2.0 + 4.0 }

fn build_open_n(a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, n: usize) -> (usize, err) {
    let o = open_spec(n)
    let auth = [2]str{ "No Authentication", "Basic Authentication" }
    let art = [3]str{ "Stretch", "Center", "Top-Left Corner" }
    let conds = [15]str{ "Unknown", "Sealed", "Brand New", "Mint", "Near Mint", "Fine", "Good", "Fair", "Poor", "Misprint", "Signed", "Foreign", "Graded", "Laminated", "Proof" }
    var names: []const str = auth[0usize..2usize]
    if o.set == 1usize { names = art[0usize..3usize] }
    if o.set == 2usize { names = conds[0usize..15usize] }
    let (picks, picks_error) = pick_actions(a, o.rows)
    if picks_error != ok { ret (0usize, picks_error) }
    let (toggle, toggle_error) = pick_actions(a, 1usize)
    if toggle_error != ok { ret (0usize, toggle_error) }
    var none: []const widget.Node = zero
    let (combo, combo_error) = control.image_select_at(a, 100u64, t, "Image", names, none, o.active, true, true, &toggle[0usize], picks, o.width, o.edge_y, o.edge_x)
    if combo_error != ok { ret (0usize, combo_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (0usize, parts_error) }
    parts[0usize] = widget.box(0u64, looks.size_style(1.0, 4.0), zero)
    parts[1usize] = combo
    var column = looks.size_style(o.width + 8.0, open_high(o))
    column.padding = style.EdgeLengths { left: style.Length { Px: 4.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    cells[0usize] = looks.Cell { caption: "", node: widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column, parts[0usize..2usize]), drive: .None }
    ret (1usize, ok)
}

fn build_o1(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_open_n(a, t, cells, 1usize)
    ret (m, e)
}
fn build_o2(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_open_n(a, t, cells, 2usize)
    ret (m, e)
}
fn build_o3(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_open_n(a, t, cells, 3usize)
    ret (m, e)
}
fn build_o4(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_open_n(a, t, cells, 4usize)
    ret (m, e)
}
fn build_o5(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_open_n(a, t, cells, 5usize)
    ret (m, e)
}

fn build_o6(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_open_n(a, t, cells, 6usize)
    ret (m, e)
}

fn run_open(a: *mem.Arena, n: usize) -> err {
    let o = open_spec(n)
    var maker: looks.Build = build_o1
    if n == 2usize { maker = build_o2 }
    if n == 3usize { maker = build_o3 }
    if n == 4usize { maker = build_o4 }
    if n == 5usize { maker = build_o5 }
    if n == 6usize { maker = build_o6 }
    let sheet = looks.Sheet { name: o.name, cells: 1usize, columns: 1usize, cell_w: o.width + 8.0, cell_h: open_high(o), ctx: zero, build: maker }
    ret looks.run_all(a, &sheet)
}

// The popup windows of the captures on their own (ref/windows/states/combo-box-open-list-* and
// image-combo-box-open-list-sort), one cell the size of the window: `image_combo_box.exe L<n>`: 1 and 2 Authentication
// (rows 1, 2 lit), 3 and 4 Card Art Position (1, 3), 5 and 6 Condition (1, 4), 7 the Sort Order list (pictures).
type Listed = struct { name: str, width: f32, high: f32, active: usize, set: usize }

fn listed_spec(n: usize) -> Listed {
    if n == 1usize { ret Listed { name: "image_combo_box_list_auth", width: 189.0, high: 32.0, active: 0usize, set: 0usize } }
    if n == 2usize { ret Listed { name: "image_combo_box_list_auth2", width: 189.0, high: 32.0, active: 1usize, set: 0usize } }
    if n == 3usize { ret Listed { name: "image_combo_box_list_art", width: 151.0, high: 47.0, active: 0usize, set: 1usize } }
    if n == 4usize { ret Listed { name: "image_combo_box_list_art2", width: 151.0, high: 47.0, active: 2usize, set: 1usize } }
    if n == 5usize { ret Listed { name: "image_combo_box_list_condition", width: 335.0, high: 227.0, active: 0usize, set: 2usize } }
    if n == 6usize { ret Listed { name: "image_combo_box_list_condition2", width: 335.0, high: 227.0, active: 3usize, set: 2usize } }
    ret Listed { name: "image_combo_box_list_sort", width: 153.0, high: 56.0, active: 0usize, set: 3usize }
}

fn build_listed_n(a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, n: usize) -> (usize, err) {
    let o = listed_spec(n)
    let auth = [2]str{ "No Authentication", "Basic Authentication" }
    let art = [3]str{ "Stretch", "Center", "Top-Left Corner" }
    let conds = [15]str{ "Unknown", "Sealed", "Brand New", "Mint", "Near Mint", "Fine", "Good", "Fair", "Poor", "Misprint", "Signed", "Foreign", "Graded", "Laminated", "Proof" }
    let sorts = [3]str{ "None", "Ascending", "Descending" }
    var names: []const str = auth[0usize..2usize]
    if o.set == 1usize { names = art[0usize..3usize] }
    if o.set == 2usize { names = conds[0usize..15usize] }
    if o.set == 3usize { names = sorts[0usize..3usize] }
    var ground = 0u32
    if o.set == 3usize { ground = 15724527u32 }
    let (picks, picks_error) = pick_actions(a, names.len)
    if picks_error != ok { ret (0usize, picks_error) }
    var icons: []const widget.Node = zero
    if o.set == 3usize {
        let (made, made_error) = mem.alloc[widget.Node](a, 3usize)
        if made_error != ok { ret (0usize, made_error) }
        made[0usize] = widget.box(0u64, looks.size_style(0.0, 16.0), zero)
        let (one, one_error) = picture(a, t, 3usize)
        if one_error != ok { ret (0usize, one_error) }
        made[1usize] = one
        made[2usize] = one
        icons = made[0usize..3usize]
    }
    let (node, node_error) = control.win_list_standalone(a, 100u64, t, "List", names, icons, o.active, picks, o.width, 0.0, 15usize, ground)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "", node: node, drive: .None }
    ret (1usize, ok)
}

fn build_l1(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_listed_n(a, t, cells, 1usize)
    ret (m, e)
}
fn build_l2(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_listed_n(a, t, cells, 2usize)
    ret (m, e)
}
fn build_l3(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_listed_n(a, t, cells, 3usize)
    ret (m, e)
}
fn build_l4(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_listed_n(a, t, cells, 4usize)
    ret (m, e)
}
fn build_l5(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_listed_n(a, t, cells, 5usize)
    ret (m, e)
}
fn build_l6(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_listed_n(a, t, cells, 6usize)
    ret (m, e)
}
fn build_l7(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_listed_n(a, t, cells, 7usize)
    ret (m, e)
}

fn run_listed(a: *mem.Arena, n: usize) -> err {
    let o = listed_spec(n)
    var maker: looks.Build = build_l1
    if n == 2usize { maker = build_l2 }
    if n == 3usize { maker = build_l3 }
    if n == 4usize { maker = build_l4 }
    if n == 5usize { maker = build_l5 }
    if n == 6usize { maker = build_l6 }
    if n == 7usize { maker = build_l7 }
    let sheet = looks.Sheet { name: o.name, cells: 1usize, columns: 1usize, cell_w: o.width, cell_h: o.high, ctx: zero, build: maker }
    ret looks.run_all(a, &sheet)
}

// The editor of the Sort window's Sort Order cell (a TcxImageComboBox in a grid): `image_combo_box.exe C` at rest with the
// editor active, `image_combo_box.exe H` with its list open (ref/windows/states/image-combo-box-*-sort at (175, 98), 155 x 21).
fn build_cell_n(a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, held: bool) -> (usize, err) {
    let (node, node_error) = control.image_select_cell(a, 100u64, t, "None", 155.0, held)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "", node: node, drive: .None }
    ret (1usize, ok)
}

fn build_cell(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_cell_n(a, t, cells, false)
    ret (m, e)
}

fn build_cell_held(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_cell_n(a, t, cells, true)
    ret (m, e)
}

// The open heads on their own (exact crops of ref/windows/states/combo-box-open-dialog-*): `image_combo_box.exe E<n>` as `o<n>`,
// written <open name>_head.
fn build_head_n(a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, n: usize) -> (usize, err) {
    let o = open_spec(n)
    let (toggle, toggle_error) = pick_actions(a, 1usize)
    if toggle_error != ok { ret (0usize, toggle_error) }
    var none: []const widget.Node = zero
    var shown = "No Authentication"
    if o.set == 1usize { shown = "Stretch" }
    if o.set == 2usize { shown = "Unknown" }
    if n == 4usize || n == 6usize { shown = shown }
    let (head, head_error) = control.win_head(a, 100u64, t, "Head", shown, true, true, &toggle[0usize], true, none, o.width, o.edge_y, o.edge_x)
    if head_error != ok { ret (0usize, head_error) }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (0usize, held_error) }
    held[0usize] = head
    cells[0usize] = looks.Cell { caption: "", node: widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, looks.size_style(o.width + 1.0, 22.0), held[0usize..1usize]), drive: .None }
    ret (1usize, ok)
}

fn build_e1(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_head_n(a, t, cells, 1usize)
    ret (m, e)
}
fn build_e2(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_head_n(a, t, cells, 2usize)
    ret (m, e)
}
fn build_e3(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_head_n(a, t, cells, 3usize)
    ret (m, e)
}
fn build_e4(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_head_n(a, t, cells, 4usize)
    ret (m, e)
}
fn build_e5(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_head_n(a, t, cells, 5usize)
    ret (m, e)
}
fn build_e6(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_head_n(a, t, cells, 6usize)
    ret (m, e)
}

fn run_head(a: *mem.Arena, n: usize) -> err {
    let o = open_spec(n)
    var maker: looks.Build = build_e1
    if n == 2usize { maker = build_e2 }
    if n == 3usize { maker = build_e3 }
    if n == 4usize { maker = build_e4 }
    if n == 5usize { maker = build_e5 }
    if n == 6usize { maker = build_e6 }
    var name = "image_combo_box_open_auth_head"
    if n == 2usize { name = "image_combo_box_open_auth2_head" }
    if n == 3usize { name = "image_combo_box_open_art_head" }
    if n == 4usize { name = "image_combo_box_open_condition_head" }
    if n == 5usize { name = "image_combo_box_open_condition2_head" }
    if n == 6usize { name = "image_combo_box_open_art2_head" }
    let sheet = looks.Sheet { name: name, cells: 1usize, columns: 1usize, cell_w: o.width + 1.0, cell_h: 22.0, ctx: zero, build: maker }
    ret looks.run_all(a, &sheet)
}

// The Internet Authentication combo under the pointer (ref/windows/states/hover-combo-box-drop-* and ...-edit-*, 190 x 22 at
// (371, 71)): `image_combo_box.exe D` over the drop button (the cell is wide so that the harness's pointer, at its middle,
// lands on it), `image_combo_box.exe P` over the text (as at rest).
fn build_hover_n(a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, over_button: bool) -> (usize, err) {
    let (toggle, toggle_error) = pick_actions(a, 1usize)
    if toggle_error != ok { ret (0usize, toggle_error) }
    var none: []const widget.Node = zero
    let (head, head_error) = control.win_head(a, 100u64, t, "Head", "No Authentication", true, false, &toggle[0usize], true, none, 189.0, 71.0, 371.0)
    if head_error != ok { ret (0usize, head_error) }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (0usize, held_error) }
    held[0usize] = head
    var wide: f32 = 190.0
    if over_button { wide = 360.0 }
    cells[0usize] = looks.Cell { caption: "", node: widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, looks.size_style(wide, 22.0), held[0usize..1usize]), drive: .Hover }
    ret (1usize, ok)
}

fn build_hover_drop(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_hover_n(a, t, cells, true)
    ret (m, e)
}

fn build_hover_edit(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_hover_n(a, t, cells, false)
    ret (m, e)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len == 2usize && args[1usize][0usize] == 111u8 { ret run_open(a, usize(args[1usize][1usize]) - 48usize) }
    if args.len == 2usize && args[1usize][0usize] == 68u8 {
        let hover = looks.Sheet { name: "image_combo_box_hover_drop", cells: 1usize, columns: 1usize, cell_w: 360.0, cell_h: 22.0, ctx: zero, build: build_hover_drop }
        ret looks.run_all(a, &hover)
    }
    if args.len == 2usize && args[1usize][0usize] == 80u8 {
        let hover = looks.Sheet { name: "image_combo_box_hover_edit", cells: 1usize, columns: 1usize, cell_w: 190.0, cell_h: 22.0, ctx: zero, build: build_hover_edit }
        ret looks.run_all(a, &hover)
    }
    if args.len == 2usize && args[1usize][0usize] == 67u8 {
        let cell = looks.Sheet { name: "image_combo_box_cell", cells: 1usize, columns: 1usize, cell_w: 155.0, cell_h: 21.0, ctx: zero, build: build_cell }
        ret looks.run_all(a, &cell)
    }
    if args.len == 2usize && args[1usize][0usize] == 72u8 {
        let cell = looks.Sheet { name: "image_combo_box_cell_held", cells: 1usize, columns: 1usize, cell_w: 155.0, cell_h: 21.0, ctx: zero, build: build_cell_held }
        ret looks.run_all(a, &cell)
    }
    if args.len == 2usize && args[1usize][0usize] == 69u8 { ret run_head(a, usize(args[1usize][1usize]) - 48usize) }
    if args.len == 2usize && args[1usize][0usize] == 76u8 { ret run_listed(a, usize(args[1usize][1usize]) - 48usize) }
    if args.len == 2usize {
        let dialog = looks.Sheet { name: "image_combo_box_dialog", cells: 3usize, columns: 1usize, cell_w: 343.0, cell_h: 29.0, ctx: zero, build: build_dialog }
        ret looks.run_all(a, &dialog)
    }
    let (passes, passes_error) = mem.alloc[Pass](a, 1usize)
    if passes_error != ok { ret passes_error }
    passes[0usize] = Pass { call: 0usize }
    let sheet = looks.Sheet { name: "image_combo_box", cells: 8usize, columns: 4usize, cell_w: cell_w(), cell_h: cell_h(), ctx: mem.cast[*void](&passes[0usize]), build: build }
    ret looks.run_all(a, &sheet)
}
