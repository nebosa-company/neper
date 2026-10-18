// The Android look's combo box: an exposed dropdown menu (M3), a text field with a trailing arrow and the menu below it.
// `material_combo_box.exe` writes material/combo_box.png (the states), `material_combo_box.exe lists` combo_box_lists.png.
// Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.gfx.paint
use e.ui.style
use e.ui.widget
use e.ui.layout as ui_layout

fn noop_submit(ctx: *void) -> err { ret ok }

fn cell_w() -> f32 { ret 440.0 }
fn cell_h() -> f32 { ret 380.0 }

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
    let (combo, combo_error) = control.combo_box(a, key, t, "Label", buffer, n, zero, choices, active, open, picks, zero, &toggle[0usize], options)
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
    options.width = 200.0
    var s = Spec { caption: "Enabled", drive: .None, value: "Against Card Color", open: false, rows: 4usize, active: 0usize, above: 12.0, left: 10.0, high: 84.0, options: options }
    if sheet_no == 0usize {
        // the states sheet: a 240 dp field centred in its cell, the value the reference's
        s.options.width = 240.0
        s.value = "Apple"
        s.above = 20.0
        s.left = 15.0
        s.high = 96.0
        if i == 1usize {
            s.caption = "Hovered"
            s.drive = .Hover
        }
        if i == 2usize {
            s.caption = "Focused"
            s.drive = .Focus
        }
        if i == 3usize {
            s.caption = "Disabled"
            s.options.enabled = false
        }
        if i == 4usize {
            s.caption = "Error"
            s.options.invalid = true
        }
        if i == 5usize {
            s.caption = "Filled"
            s.options.filled = true
        }
        if i == 6usize {
            s.caption = "Filled, hovered"
            s.options.filled = true
            s.drive = .Hover
        }
        if i == 7usize {
            s.caption = "Filled, focused"
            s.options.filled = true
            s.drive = .Focus
        }
        if i == 8usize {
            s.caption = "Filled, disabled"
            s.options.filled = true
            s.options.enabled = false
        }
        if i == 9usize {
            s.caption = "Filled, error"
            s.options.filled = true
            s.options.invalid = true
        }
        // Cells 10 to 19: no value yet (the label rests inside), outlined then filled: enabled, hovered, focused, disabled, error.
        if i >= 10usize {
            let k = (i - 10usize) % 5usize
            s.value = ""
            s.options.filled = i >= 15usize
            if k == 0usize { s.caption = "Empty" }
            if k == 1usize {
                s.caption = "Empty, hovered"
                s.drive = .Hover
            }
            if k == 2usize {
                s.caption = "Empty, focused"
                s.drive = .Focus
            }
            if k == 3usize {
                s.caption = "Empty, disabled"
                s.options.enabled = false
            }
            if k == 4usize {
                s.caption = "Empty, error"
                s.options.invalid = true
            }
        }
    } else {
        s.high = cell_h()
        s.above = 12.0
        s.drive = .Hover
        s.options.read_only = true
        if i == 0usize {
            s.caption = "Open"
            s.open = true
            s.above = 12.0
        }
        if i == 1usize {
            s.caption = "Open, row hovered"
            s.open = true
            s.above = 12.0
            s.left = 120.0
        }
        if i == 2usize {
            s.caption = "Open, selected, filled"
            s.options.filled = true
            s.active = 1usize
            s.value = "Mono"
            s.open = true
            s.above = 12.0
        }
    }
    ret s
}

fn across_of(sheet_no: usize) -> f32 {
    if sheet_no == 0usize { ret 270.0 }
    ret cell_w()
}

fn count_of(sheet_no: usize) -> usize {
    if sheet_no == 0usize { ret 20usize }
    ret 3usize
}

fn build_set(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, sheet_no: usize) -> (usize, err) {
    let colors = [4]str{ "Against Card Color", "Mono", "Rarity", "Frame" }
    let numbers = [22]str{ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20", "21" }
    let n = count_of(sheet_no)
    var drives: [20]looks.Drive = zero
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
        let (node, node_error) = one(a, t, u64(i + 1usize) * 100u64, s.value, choices, s.active, s.open && now == i, s.options, s.above, s.left, s.high, across_of(sheet_no))
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

fn main(a: *mem.Arena, args: []str) -> err {
    let (passes, passes_error) = mem.alloc[Pass](a, 1usize)
    if passes_error != ok { ret passes_error }
    passes[0usize] = Pass { call: 0usize }
    if args.len > 1usize {
        let lists = looks.Sheet { name: "combo_box_lists", cells: 3usize, columns: 3usize, cell_w: cell_w(), cell_h: cell_h(), ctx: mem.cast[*void](&passes[0usize]), build: build_lists }
        ret looks.run_material(a, &lists)
    }
    let states = looks.Sheet { name: "combo_box", cells: 20usize, columns: 3usize, cell_w: 270.0, cell_h: 96.0, ctx: mem.cast[*void](&passes[0usize]), build: build_states }
    ret looks.run_material(a, &states)
}
