// The combo box (TcxComboBox) in every state under every look: docs/ui/looks/<look>/combo_box.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.gfx.paint
use e.ui.style
use e.ui.widget
use e.ui.layout as ui_layout

fn noop_submit(ctx: *void) -> err { ret ok }

fn cell_w() -> f32 { ret 170.0 }
fn cell_h() -> f32 { ret 150.0 }

// The control `above` px below the top of its cell box and `left` px from its side, so that
// the cell's centre (where the harness puts the pointer) falls where a state needs it.
fn placed(a: *mem.Arena, node: widget.Node, above: f32, left: f32, high: f32, across: f32) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = widget.box(0u64, looks.size_style(1.0, above), zero)
    parts[1usize] = node
    var column = looks.size_style(across, high)
    column.padding = style.EdgeLengths { left: style.Length { Px: left }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column, parts[0usize..2usize]), ok)
}

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

// One combo box: its value, the choices, the open list's active row, and the options.
fn one(a: *mem.Arena, t: *const control.Theme, key: widget.Key, value: str, choices: []const str, active: usize, open: bool, options: control.FieldOptions, above: f32, left: f32, high: f32, across: f32) -> (widget.Node, err) {
    let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
    if buffer_error != ok { ret (zero, buffer_error) }
    let n = control.copy_text(buffer, value)
    let (picks, picks_error) = pick_actions(a, choices.len)
    if picks_error != ok { ret (zero, picks_error) }
    let (toggle, toggle_error) = pick_actions(a, 1usize)
    if toggle_error != ok { ret (zero, toggle_error) }
    let (combo, combo_error) = control.combo_box(a, key, t, "Row Color", buffer, n, zero, choices, active, open, picks, zero, &toggle[0usize], options)
    if combo_error != ok { ret (zero, combo_error) }
    let (shown, shown_error) = placed(a, combo, above, left, high, across)
    ret (shown, shown_error)
}

// Which frame a build is for: every build of a sheet is one more call; the first is the resting
// frame, the others come per driven cell, in order (a hover is built twice: see looks.render_sheet).
// Two lists cannot stand open in one frame, so an open cell is built open only in its own passes.
type Pass = struct { call: usize }

// The cell whose frame this call builds (`count` when it is the resting frame); `drives` are the
// cells' drives.
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

// What a cell is: its caption, drive, value, choices, open list, row, and where it stands.
type Spec = struct { caption: str, drive: looks.Drive, value: str, open: bool, rows: usize, active: usize, above: f32, left: f32, high: f32, options: control.FieldOptions }

fn spec_of(sheet_no: usize, i: usize) -> Spec {
    var options = control.field_options()
    options.width = 150.0
    var s = Spec { caption: "Normal", drive: .None, value: "Against Card Color", open: false, rows: 4usize, active: 0usize, above: 25.0, left: 10.0, high: 70.0, options: options }
    if sheet_no == 0usize {
        if i == 1usize {
            s.caption = "Hover"
            s.drive = .Hover
        }
        if i == 2usize || i == 3usize {
            s.caption = "Drop button hot"
            s.drive = .Hover
            if i == 3usize {
                s.caption = "Drop button pressed"
                s.drive = .Press
            }
            s.options.width = 24.0
            s.value = ""
            s.left = cell_w() * 0.5 - 12.0
        }
        if i == 4usize {
            s.caption = "Disabled"
            s.options.enabled = false
        }
        if i == 5usize {
            s.caption = "Read only"
            s.options.read_only = true
        }
        if i == 6usize {
            s.caption = "Empty, hint"
            s.value = ""
            s.options.placeholder = "Choose a colour"
        }
        if i == 7usize {
            s.caption = "Focus"
            s.drive = .Focus
        }
    } else {
        s.high = cell_h()
        s.above = 64.0
        s.drive = .Hover
        if i == 0usize {
            // The pointer, at the cell's centre, rests on the head: no row is under it.
            s.caption = "Open"
            s.above = cell_h() * 0.5 - 10.0
            s.open = true
        }
        if i == 1usize {
            // The pointer lands on the second row.
            s.caption = "Open, row hover"
            s.above = cell_h() * 0.5 - 21.0 - 15.0 - 7.5
            s.open = true
        }
        if i == 2usize {
            s.caption = "Open, scrolling"
            s.above = 4.0
            s.rows = 22usize
            s.value = "3"
            s.active = 3usize
            s.open = true
        }
        if i == 3usize {
            s.caption = "Long text"
            s.drive = .None
            s.value = "Against Card Color and a very long name that does not fit"
        }
    }
    ret s
}

fn count_of(sheet_no: usize) -> usize {
    if sheet_no == 0usize { ret 8usize }
    ret 4usize
}

fn build_set(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, sheet_no: usize) -> (usize, err) {
    let colors = [4]str{ "Against Card Color", "Mono", "Rarity", "Frame" }
    let numbers = [22]str{ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20", "21" }
    let n = count_of(sheet_no)
    var drives = [8]looks.Drive{ .None, .None, .None, .None, .None, .None, .None, .None }
    var i = 0usize
    while i < n {
        drives[i] = spec_of(sheet_no, i).drive
        i += 1usize
    }
    let now = pass_of(ctx, n, drives[0usize..n])
    i = 0usize
    while i < n {
        let s = spec_of(sheet_no, i)
        var choices: []const str = colors[0usize..4usize]
        if s.rows == 22usize { choices = numbers[0usize..22usize] }
        let (node, node_error) = one(a, t, u64(i + 1usize) * 100u64, s.value, choices, s.active, s.open && now == i, s.options, s.above, s.left, s.high, cell_w())
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: s.caption, node: node, drive: s.drive }
        i += 1usize
    }
    ret (n, ok)
}

fn build_states(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (made, made_error) = build_set(ctx, a, t, cells, 0usize)
    ret (made, made_error)
}

fn build_lists(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (made, made_error) = build_set(ctx, a, t, cells, 1usize)
    ret (made, made_error)
}

// The Focus cell comes last of the states: the runtime keeps the focus on a tree slot, which a
// later pass could land in a cell. One sheet per run (a rig is about 100 MB of the arena):
// `combo_box.exe` writes combo_box.png (the states), `combo_box.exe lists` combo_box_lists.png.
// The toolbar combos of the v3 main window (flat, TcxBarEditItem), as the live capture
// ref/windows/combo_box_flat*.png shows them: the Mode combo with a value, the empty one at the
// left of the toolbar, a disabled one. Under the Neper look `flat` is ignored.
fn bar_line(x: f32, y: f32, w: f32, rgb: u32) -> widget.Node {
    var line = looks.size_style(w, 1.0)
    line.background = paint.Brush { Solid: style.hex(rgb) }
    ret widget.positioned(0u64, x, y, line, zero)
}

// `build_flat` is the toolbar strip of the live main window (crop 604,56 188x28): the toolbar's
// own rows, and the Mode combo at (58, 6), 127 wide. `variant`: 0 at rest, 1 under the pointer (ref/windows/states/
// hover-toolbar-combo-mode), 2 the card name combo (empty, 146 wide at (7, 6) of the crop 14,56 186x28), 3 that one under the
// pointer (hover-toolbar-combo-card-drop and ...-edit, the same pixels). `build_flat_states` are the three states.
fn build_flat_n(a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, variant: usize) -> (usize, err) {
    let colors = [4]str{ "Collection from Pool", "Collection from Deck", "Pool", "Deck" }
    var options = control.field_options()
    options.flat = true
    options.width = 127.0
    var value = "Collection from Pool"
    var at_x: f32 = 58.0
    var cw: f32 = 188.0
    if variant >= 2usize {
        options.width = 146.0
        value = ""
        at_x = 7.0
        cw = 186.0
    }
    let (combo, combo_error) = one(a, t, 100u64, value, colors[0usize..4usize], 0usize, false, options, 0.0, 0.0, 17.0, options.width)
    if combo_error != ok { ret (0usize, combo_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 12usize)
    if parts_error != ok { ret (0usize, parts_error) }
    parts[0usize] = bar_line(0.0, 0.0, cw, 14606046u32)
    parts[1usize] = bar_line(0.0, 1.0, cw, 16119285u32)
    parts[2usize] = bar_line(0.0, 26.0, cw, 12434877u32)
    parts[3usize] = bar_line(59.0, 27.0, cw - 59.0, 13882323u32)
    parts[5usize] = bar_line(0.0, 27.0, 59.0, 14474460u32)
    parts[4usize] = widget.positioned(0u64, at_x, 6.0, style.defaults(), widget_one(a, combo))
    var count = 6usize
    if variant < 2usize {
        // the toolbar's separator right of the Mode combo
        parts[6usize] = grip(187.0, 6.0, 17.0, 12961221u32)
        count = 7usize
    } else {
        // the toolbar's grip at the left of the card name combo and the foot row of that bar
        parts[3usize] = bar_line(0.0, 27.0, cw, 14474460u32)
        parts[5usize] = bar_line(0.0, 27.0, 1.0, 14474460u32)
        parts[6usize] = grip(0.0, 2.0, 22.0, 10526880u32)
        parts[7usize] = grip(1.0, 2.0, 22.0, 16777215u32)
        parts[8usize] = grip(3.0, 2.0, 22.0, 10526880u32)
        parts[9usize] = grip(4.0, 2.0, 22.0, 15724527u32)
        count = 10usize
    }
    var strip = looks.size_style(cw, 28.0)
    strip.background = paint.Brush { Solid: style.hex(15790320u32) }
    var drive = looks.Drive.None
    if variant == 1usize || variant == 3usize { drive = .Hover }
    var node = widget.stack(0u64, strip, parts[0usize..count])
    if drive == .Hover {
        // The harness puts the pointer at the middle of the cell: the cell is wide enough for it to land on the drop button.
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (0usize, held_error) }
        held[0usize] = node
        node = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, looks.size_style(hover_cell(variant), 28.0), held[0usize..1usize])
    }
    cells[0usize] = looks.Cell { caption: "", node: node, drive: drive }
    ret (1usize, ok)
}

fn grip(x: f32, y: f32, h: f32, rgb: u32) -> widget.Node {
    var line = looks.size_style(1.0, h)
    line.background = paint.Brush { Solid: style.hex(rgb) }
    ret widget.positioned(0u64, x, y, line, zero)
}

fn hover_cell(variant: usize) -> f32 {
    if variant >= 2usize { ret 294.0 }
    ret 356.0
}

fn build_flat(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_flat_n(a, t, cells, 0usize)
    ret (m, e)
}

fn build_flat_hot(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_flat_n(a, t, cells, 1usize)
    ret (m, e)
}

fn build_flat_card(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_flat_n(a, t, cells, 2usize)
    ret (m, e)
}

fn build_flat_card_hot(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_flat_n(a, t, cells, 3usize)
    ret (m, e)
}

fn widget_one(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret zero }
    held[0usize] = node
    ret held[0usize..1usize]
}

fn build_flat_states(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let colors = [4]str{ "Collection from Pool", "Collection from Deck", "Pool", "Deck" }
    let captions = [3]str{ "Mode", "Empty", "Disabled" }
    var i = 0usize
    while i < 3usize {
        var options = control.field_options()
        options.flat = true
        options.width = 127.0
        var value = "Collection from Pool"
        if i == 1usize {
            options.width = 148.0
            value = ""
        }
        if i == 2usize {
            options.enabled = false
        }
        let (node, node_error) = one(a, t, u64(i + 1usize) * 100u64, value, colors[0usize..4usize], 0usize, false, options, 6.0, 8.0, 40.0, cell_w())
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (3usize, ok)
}

// The combos as the v3 dialogs show them (ref/windows/dialogs: Options > Grids, Search for Card,
// the Conditional Formatting manager), each control at (4, 4) of a cell as large as the capture's
// crop (rectangle plus 4 px), so windows/<sheet>.png compares pixel for pixel with
// ref/windows/<sheet>.png (scripts/looks_refs_d.py). `combo_box.exe dialog`: two at rest, 389 wide;
// `edit`: the focused editable combo (Search for Card); `pick`: a focused list-style combo.
fn build_dialog_set(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, which: usize) -> (usize, err) {
    let colors = [4]str{ "Against Card Color", "Mono", "Rarity", "Frame" }
    let sizes = [3]str{ "Small", "Medium", "Large" }
    var n = 2usize
    var across: f32 = 397.0
    if which == 1usize { across = 297.0 }
    if which == 2usize { across = 151.0 }
    if which != 0usize { n = 1usize }
    var i = 0usize
    while i < n {
        var options = control.field_options()
        options.width = 389.0
        var value = "Against Card Color"
        var choices: []const str = colors[0usize..4usize]
        var drive = looks.Drive.None
        let high: f32 = 29.0
        options.edge_y = 71.0
        options.edge_x = 321.0
        if i == 1usize {
            value = "Medium"
            choices = sizes[0usize..3usize]
            options.edge_y = 159.0
        }
        if which == 1usize {
            options.width = 289.0
            value = ""
            drive = .Focus
        }
        if which == 2usize {
            options.width = 143.0
            options.read_only = true
            options.edge_y = 41.0
            options.edge_x = 149.0
            value = "All"
            choices = colors[0usize..4usize]
            drive = .Focus
        }
        let (node, node_error) = one(a, t, u64(i + 1usize) * 100u64, value, choices, 0usize, false, options, 4.0, 4.0, high, across)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: "", node: node, drive: drive }
        i += 1usize
    }
    ret (n, ok)
}

fn build_dialog(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (made, made_error) = build_dialog_set(ctx, a, t, cells, 0usize)
    ret (made, made_error)
}

fn build_edit(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (made, made_error) = build_dialog_set(ctx, a, t, cells, 1usize)
    ret (made, made_error)
}

fn build_pick(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (made, made_error) = build_dialog_set(ctx, a, t, cells, 2usize)
    ret (made, made_error)
}

// The open drop-down as the v3 grabs show it (ref/windows/states/combo-box-open-*): a list-style combo
// at (4, 4) of a one-cell sheet with its popup right under it. `combo_box.exe o<n>`: 1 Row Color
// (chosen row 1), 2 Row Color (row 2 lit), 3 Font Size, 4 Font Size (row 4), 5 Show rules (scrolling,
// 21 rows), 6 the same with row 2. The 21 rows of the scrolling list are fillers after the 8 captured.
type Open = struct { name: str, width: f32, high: f32, edge_x: f32, edge_y: f32, active: usize, rows: usize, set: usize }

fn open_spec(n: usize) -> Open {
    if n == 1usize { ret Open { name: "combo_box_open_color", width: 389.0, high: 41.0, edge_x: 10321.0, edge_y: 71.0, active: 1usize, rows: 3usize, set: 0usize } }
    if n == 2usize { ret Open { name: "combo_box_open_color2", width: 389.0, high: 41.0, edge_x: 321.0, edge_y: 71.0, active: 2usize, rows: 3usize, set: 0usize } }
    if n == 3usize { ret Open { name: "combo_box_open_size", width: 389.0, high: 54.0, edge_x: 10321.0, edge_y: 159.0, active: 1usize, rows: 4usize, set: 1usize } }
    if n == 4usize { ret Open { name: "combo_box_open_size2", width: 389.0, high: 54.0, edge_x: 321.0, edge_y: 159.0, active: 3usize, rows: 4usize, set: 1usize } }
    if n == 5usize { ret Open { name: "combo_box_open_show", width: 143.0, high: 106.0, edge_x: 149.0, edge_y: 41.0, active: 1usize, rows: 21usize, set: 2usize } }
    ret Open { name: "combo_box_open_show2", width: 143.0, high: 106.0, edge_x: 149.0, edge_y: 41.0, active: 2usize, rows: 21usize, set: 2usize }
}

fn build_open_n(a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, n: usize) -> (usize, err) {
    let o = open_spec(n)
    let colors = [3]str{ "Not Colored", "Against Card Color", "Against Card Rarity" }
    let sizes = [4]str{ "Small", "Medium", "Large", "Extra Large" }
    let shows = [21]str{ "Current Selection", "All", "Favorite", "ES", "Name", "Legal", "Edition", "Color", "Rarity", "Type", "Cost", "Power", "Toughness", "Artist", "Block", "Set", "Price", "Quantity", "Foil", "Note", "Tag" }
    var choices: []const str = colors[0usize..3usize]
    if o.set == 1usize { choices = sizes[0usize..4usize] }
    if o.set == 2usize { choices = shows[0usize..21usize] }
    var options = control.field_options()
    options.width = o.width
    options.read_only = true
    options.edge_x = o.edge_x
    options.edge_y = o.edge_y
    let (node, node_error) = one(a, t, 100u64, choices[1usize], choices, o.active, true, options, 4.0, 4.0, 4.0 + 21.0 + o.high + 4.0, o.width + 8.0)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "", node: node, drive: .None }
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
    var build: looks.Build = build_o1
    if n == 2usize { build = build_o2 }
    if n == 3usize { build = build_o3 }
    if n == 4usize { build = build_o4 }
    if n == 5usize { build = build_o5 }
    if n == 6usize { build = build_o6 }
    let sheet = looks.Sheet { name: o.name, cells: 1usize, columns: 1usize, cell_w: o.width + 8.0, cell_h: 4.0 + 21.0 + o.high + 4.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}

// The closed combo held down on its drop button (`h`) and with the keyboard focus (`f`), list style, as
// ref/windows/states/combo-box-drop-button-pressed-options-row-color and ...-focused-options-row-color
// show them. The cell is wide so that the harness's pointer, at its centre, lands on the drop button.
fn build_held(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let colors = [3]str{ "Not Colored", "Against Card Color", "Against Card Rarity" }
    var options = control.field_options()
    options.width = 389.0
    options.read_only = true
    options.edge_x = 321.0
    options.edge_y = 71.0
    let (node, node_error) = one(a, t, 100u64, "Against Card Color", colors[0usize..3usize], 1usize, false, options, 4.0, 4.0, 29.0, 762.0)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "", node: node, drive: .Press }
    ret (1usize, ok)
}

fn build_focus(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let colors = [3]str{ "Not Colored", "Against Card Color", "Against Card Rarity" }
    var options = control.field_options()
    options.width = 389.0
    options.read_only = true
    options.edge_x = 321.0
    options.edge_y = 71.0
    let (node, node_error) = one(a, t, 100u64, "Against Card Color", colors[0usize..3usize], 1usize, false, options, 4.0, 4.0, 29.0, 397.0)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "", node: node, drive: .Focus }
    ret (1usize, ok)
}

// The editable combo of the Search window with its drop button held (`s`), as
// ref/windows/states/combo-box-drop-button-pressed-search: a wide cell so that the pointer, at its centre,
// lands on the drop button.
fn build_search_held(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let colors = [3]str{ "Black Lotus", "Mox Pearl", "Sol Ring" }
    var options = control.field_options()
    options.width = 289.0
    let (node, node_error) = one(a, t, 100u64, "", colors[0usize..3usize], 0usize, false, options, 4.0, 4.0, 29.0, 570.0)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "", node: node, drive: .Press }
    ret (1usize, ok)
}

// The popup windows of the captures on their own (ref/windows/states/combo-box-open-list-*), one cell the size of
// the window: `combo_box.exe L<n>`: 1 Row Color (row 1 lit), 2 Row Color (row 2), 3 Font Size (1), 4 Font Size (3),
// 5 Show rules (1), 6 Show rules (2). The heads are the sheets above (combo_box_open_*).
type Listed = struct { name: str, width: f32, high: f32, active: usize, set: usize }

fn listed_spec(n: usize) -> Listed {
    if n == 1usize { ret Listed { name: "combo_box_list_color", width: 389.0, high: 41.0, active: 1usize, set: 0usize } }
    if n == 2usize { ret Listed { name: "combo_box_list_color2", width: 389.0, high: 41.0, active: 2usize, set: 0usize } }
    if n == 3usize { ret Listed { name: "combo_box_list_size", width: 389.0, high: 54.0, active: 1usize, set: 1usize } }
    if n == 4usize { ret Listed { name: "combo_box_list_size2", width: 389.0, high: 54.0, active: 3usize, set: 1usize } }
    if n == 5usize { ret Listed { name: "combo_box_list_show", width: 143.0, high: 106.0, active: 1usize, set: 2usize } }
    ret Listed { name: "combo_box_list_show2", width: 143.0, high: 106.0, active: 2usize, set: 2usize }
}

fn build_listed_n(a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, n: usize) -> (usize, err) {
    let o = listed_spec(n)
    let colors = [3]str{ "Not Colored", "Against Card Color", "Against Card Rarity" }
    let sizes = [4]str{ "Small", "Medium", "Large", "Extra Large" }
    let shows = [21]str{ "Current Selection", "All", "Favorite", "ES", "Name", "Legal", "Edition", "Color", "Rarity", "Type", "Cost", "Power", "Toughness", "Artist", "Block", "Set", "Price", "Quantity", "Foil", "Note", "Tag" }
    var choices: []const str = colors[0usize..3usize]
    if o.set == 1usize { choices = sizes[0usize..4usize] }
    if o.set == 2usize { choices = shows[0usize..21usize] }
    let (picks, picks_error) = pick_actions(a, choices.len)
    if picks_error != ok { ret (0usize, picks_error) }
    var none: []const widget.Node = zero
    let (node, node_error) = control.win_list_standalone(a, 100u64, t, "List", choices, none, o.active, picks, o.width, 13.0, 8usize, 0u32)
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

fn run_listed(a: *mem.Arena, n: usize) -> err {
    let o = listed_spec(n)
    var build: looks.Build = build_l1
    if n == 2usize { build = build_l2 }
    if n == 3usize { build = build_l3 }
    if n == 4usize { build = build_l4 }
    if n == 5usize { build = build_l5 }
    if n == 6usize { build = build_l6 }
    let sheet = looks.Sheet { name: o.name, cells: 1usize, columns: 1usize, cell_w: o.width, cell_h: o.high, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}

// The open heads of the captures on their own (exact crops of ref/windows/states/combo-box-open-dialog-*, the
// control's rectangle plus its bleed row and column): `combo_box.exe E<n>` as `o<n>`, written <open name>_head.
fn build_head_n(a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, n: usize) -> (usize, err) {
    let o = open_spec(n)
    let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
    if buffer_error != ok { ret (0usize, buffer_error) }
    let value = "Against Card Color"
    var shown = value
    if n >= 3usize && n <= 4usize { shown = "Medium" }
    if n >= 5usize { shown = "All" }
    let len = control.copy_text(buffer, shown)
    var options = control.field_options()
    options.width = o.width
    options.read_only = true
    options.edge_x = o.edge_x
    options.edge_y = o.edge_y
    let (toggle, toggle_error) = pick_actions(a, 1usize)
    if toggle_error != ok { ret (0usize, toggle_error) }
    let (frame, frame_error) = control.win_edit_frame(a, 100u64, t, "Head", buffer, len, zero, true, &toggle[0usize], options)
    if frame_error != ok { ret (0usize, frame_error) }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (0usize, held_error) }
    held[0usize] = frame
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
    var build: looks.Build = build_e1
    if n == 2usize { build = build_e2 }
    if n == 3usize { build = build_e3 }
    if n == 4usize { build = build_e4 }
    if n == 5usize { build = build_e5 }
    if n == 6usize { build = build_e6 }
    var name = "combo_box_open_color_head"
    if n == 2usize { name = "combo_box_open_color2_head" }
    if n == 3usize { name = "combo_box_open_size_head" }
    if n == 4usize { name = "combo_box_open_size2_head" }
    if n == 5usize { name = "combo_box_open_show_head" }
    if n == 6usize { name = "combo_box_open_show2_head" }
    let sheet = looks.Sheet { name: name, cells: 1usize, columns: 1usize, cell_w: o.width + 1.0, cell_h: 22.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len == 2usize {
        let first = args[1usize][0usize]
        if first == 115u8 {
            let held = looks.Sheet { name: "combo_box_search_held", cells: 1usize, columns: 1usize, cell_w: 570.0, cell_h: 29.0, ctx: zero, build: build_search_held }
            ret looks.run_all(a, &held)
        }
        if first == 104u8 {
            let held = looks.Sheet { name: "combo_box_held", cells: 1usize, columns: 1usize, cell_w: 762.0, cell_h: 29.0, ctx: zero, build: build_held }
            ret looks.run_all(a, &held)
        }
        if first == 102u8 {
            let focus = looks.Sheet { name: "combo_box_focus", cells: 1usize, columns: 1usize, cell_w: 397.0, cell_h: 29.0, ctx: zero, build: build_focus }
            ret looks.run_all(a, &focus)
        }
        if first == 111u8 { ret run_open(a, usize(args[1usize][1usize]) - 48usize) }
        if first == 70u8 {
            // `F1` Mode under the pointer, `F2` the card name combo, `F3` that one under the pointer.
            let kind = usize(args[1usize][1usize]) - 48usize
            if kind == 1usize {
                let sheet = looks.Sheet { name: "combo_box_flat_hover", cells: 1usize, columns: 1usize, cell_w: 356.0, cell_h: 28.0, ctx: zero, build: build_flat_hot }
                ret looks.run_all(a, &sheet)
            }
            if kind == 2usize {
                let sheet = looks.Sheet { name: "combo_box_flat_card", cells: 1usize, columns: 1usize, cell_w: 186.0, cell_h: 28.0, ctx: zero, build: build_flat_card }
                ret looks.run_all(a, &sheet)
            }
            let sheet = looks.Sheet { name: "combo_box_flat_card_hover", cells: 1usize, columns: 1usize, cell_w: 294.0, cell_h: 28.0, ctx: zero, build: build_flat_card_hot }
            ret looks.run_all(a, &sheet)
        }
        if first == 69u8 { ret run_head(a, usize(args[1usize][1usize]) - 48usize) }
        if first == 76u8 { ret run_listed(a, usize(args[1usize][1usize]) - 48usize) }
        if first == 100u8 {
            let dialog = looks.Sheet { name: "combo_box_dialog", cells: 2usize, columns: 2usize, cell_w: 397.0, cell_h: 29.0, ctx: zero, build: build_dialog }
            ret looks.run_all(a, &dialog)
        }
        if first == 101u8 {
            let edit = looks.Sheet { name: "combo_box_edit", cells: 1usize, columns: 1usize, cell_w: 297.0, cell_h: 29.0, ctx: zero, build: build_edit }
            ret looks.run_all(a, &edit)
        }
        if first == 112u8 {
            let pick = looks.Sheet { name: "combo_box_pick", cells: 1usize, columns: 1usize, cell_w: 151.0, cell_h: 29.0, ctx: zero, build: build_pick }
            ret looks.run_all(a, &pick)
        }
    }
    if args.len > 3usize {
        let states = looks.Sheet { name: "combo_box_flat_states", cells: 3usize, columns: 3usize, cell_w: 170.0, cell_h: 50.0, ctx: zero, build: build_flat_states }
        ret looks.run_all(a, &states)
    }
    if args.len > 2usize {
        let flat = looks.Sheet { name: "combo_box_flat", cells: 1usize, columns: 1usize, cell_w: 188.0, cell_h: 28.0, ctx: zero, build: build_flat }
        ret looks.run_all(a, &flat)
    }
    let (passes, passes_error) = mem.alloc[Pass](a, 1usize)
    if passes_error != ok { ret passes_error }
    passes[0usize] = Pass { call: 0usize }
    if args.len > 1usize {
        let lists = looks.Sheet { name: "combo_box_lists", cells: 4usize, columns: 4usize, cell_w: cell_w(), cell_h: cell_h(), ctx: mem.cast[*void](&passes[0usize]), build: build_lists }
        ret looks.run_all(a, &lists)
    }
    let states = looks.Sheet { name: "combo_box", cells: 8usize, columns: 4usize, cell_w: cell_w(), cell_h: 70.0, ctx: mem.cast[*void](&passes[0usize]), build: build_states }
    ret looks.run_all(a, &states)
}
