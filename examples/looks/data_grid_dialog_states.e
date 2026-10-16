// looks5-e: the dialog grids in every captured interaction state, one cell per state, compared with the live grabs of
// docs/ui/looks/ref/windows/states: `data_grid_dialog_states.exe sort` (data_grid_sort_states: the Sort dialog's grid, 331 x 259),
// `... shortcuts` (data_grid_shortcuts_states: the Options Shortcuts grid, 496 x 334) and `... missing` (data_grid_missing_states:
// the Missing Set Cards edition list, 234 x 256). Cells: at rest, header pressed, row selected with the grid focused, row
// selected without focus, scroll thumb pressed (the shortcuts and sort grids). The artwork (the shortcut icons, the sort glyphs)
// is not drawn. Run from the repository root.

use e.data.table as table
use e.data.tablegroup as grp
use e.data.tableview as view
use e.gfx.paint
use e.mem
use e.str as strs
use e.ui.control
use e.ui.datagrid as dg
use e.ui.gridlook as gl
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

const MAX: usize = 5usize

type App = struct {
    a: *mem.Arena,
    ready: bool,
    windows: bool,
    family: usize,
    cells: usize,
    tbl: table.Table,
    views: [MAX]view.View,
    groups: [MAX]grp.Grouping,
    grids: [MAX]dg.Grid,
    scratch: mem.Arena,
    hover: bool,
    first: usize,
    name: str
}

fn sort_name(row: usize) -> str {
    if row == 0usize { ret "Favorite" }
    if row == 1usize { ret "ES" }
    if row == 2usize { ret "Name" }
    if row == 3usize { ret "Legal" }
    if row == 4usize { ret "Edition" }
    if row == 5usize { ret "Color" }
    if row == 6usize { ret "Type" }
    if row == 7usize { ret "Rarity" }
    if row == 8usize { ret "Cost" }
    if row == 9usize { ret "P/T" }
    if row == 10usize { ret "Text" }
    if row == 11usize { ret "Flavor" }
    if row == 12usize { ret "Artist" }
    if row == 13usize { ret "Power" }
    if row == 14usize { ret "Toughness" }
    if row == 15usize { ret "Loyalty" }
    if row == 16usize { ret "Number" }
    if row == 17usize { ret "Layout" }
    if row == 18usize { ret "Price" }
    ret "Quantity"
}

fn command_name(row: usize) -> str {
    if row == 0usize { ret "New" }
    if row == 1usize { ret "Open" }
    if row == 2usize { ret "Save" }
    if row == 3usize { ret "Save As" }
    if row == 4usize { ret "Save All" }
    if row == 5usize { ret "Close" }
    if row == 6usize { ret "Close All" }
    if row == 7usize { ret "Delete Deck" }
    if row == 8usize { ret "Properties" }
    if row == 9usize { ret "Legality" }
    if row == 10usize { ret "Statistics" }
    if row == 11usize { ret "Deck from Card Pool" }
    if row == 12usize { ret "Collection from Card Pool" }
    if row == 13usize { ret "Deck from Collection" }
    if row == 14usize { ret "Toggle Mode" }
    if row == 15usize { ret "Toggle Mode in Reverse" }
    if row == 16usize { ret "Import" }
    ret "Update Prices"
}

fn shortcut_name(row: usize) -> str {
    if row == 0usize { ret "Ctrl+N" }
    if row == 1usize { ret "Ctrl+O" }
    if row == 2usize { ret "Ctrl+S" }
    if row == 4usize { ret "Ctrl+Shift+S" }
    if row == 6usize { ret "Ctrl+Shift+F4" }
    if row == 8usize { ret "Ctrl+I" }
    if row == 9usize { ret "F6" }
    if row == 10usize { ret "F7" }
    if row == 11usize { ret "Ctrl+F2" }
    if row == 12usize { ret "Ctrl+F3" }
    if row == 13usize { ret "Ctrl+F4" }
    if row == 14usize { ret "F12" }
    if row == 15usize { ret "Shift+F12" }
    ret ""
}

fn miss_name(row: usize) -> str {
    if row == 0usize { ret "Mystery Booster Commander Edition" }
    if row == 1usize { ret "Reality Fracture" }
    if row == 2usize { ret "Reality Fracture Commander" }
    if row == 3usize { ret "The Zeta Set" }
    if row == 4usize { ret "The Hobbit" }
    if row == 5usize { ret "The Hobbit Eternal" }
    if row == 6usize { ret "Marvel Super Heroes" }
    if row == 7usize { ret "Marvel Super Heroes Commander" }
    if row == 8usize { ret "Secrets of Strixhaven" }
    if row == 9usize { ret "Secrets of Strixhaven Commander" }
    if row == 10usize { ret "Secrets of Strixhaven Mystical Archive" }
    if row == 11usize { ret "Teenage Mutant Ninja Turtles" }
    ret "Teenage Mutant Ninja Turtles Eternal"
}

fn miss_ink(ctx: *void, row: usize) -> (paint.Color, bool) {
    var rgb = 0xFF0000u32
    if row == 0usize { rgb = 0xFF00FFu32 }
    if row == 2usize || row == 7usize || row == 9usize { rgb = 0x0000FFu32 }
    if row == 3usize { rgb = 0xD2691Eu32 }
    if row == 10usize { rgb = 0xFF7F50u32 }
    ret (gl.rgb(rgb), true)
}

fn rows_of(family: usize) -> usize {
    if family == 0usize { ret 20usize }
    if family == 1usize { ret 147usize }
    ret 13usize
}

fn load(a: *mem.Arena, app: *App) -> err {
    var spec: [3]table.Spec = zero
    spec[0usize] = table.Spec { name: "A", kind: table.Kind.Dict, heap_bytes: 2048usize, dict_cap: 32usize }
    spec[1usize] = table.Spec { name: "B", kind: table.Kind.Dict, heap_bytes: 2048usize, dict_cap: 32usize }
    spec[2usize] = table.Spec { name: "C", kind: table.Kind.Dict, heap_bytes: 2048usize, dict_cap: 32usize }
    var columns = 3usize
    if app.family == 2usize { columns = 1usize }
    if app.family == 0usize { columns = 2usize }
    let rows = rows_of(app.family)
    let (made, made_error) = table.create(a, spec[0..columns], rows)
    if made_error != ok { ret made_error }
    app.tbl = made
    table.begin_load(&app.tbl)
    var row = 0usize
    while row < rows {
        let (got, append_error) = table.append_row(&app.tbl)
        if append_error != ok { ret append_error }
        if app.family == 0usize {
            try table.set_str(&app.tbl, 0usize, got, sort_name(row))
            try table.set_str(&app.tbl, 1usize, got, "None")
        }
        if app.family == 1usize {
            try table.set_str(&app.tbl, 0usize, got, "File")
            try table.set_str(&app.tbl, 1usize, got, command_name(row % 18usize))
            try table.set_str(&app.tbl, 2usize, got, shortcut_name(row % 18usize))
        }
        if app.family == 2usize { try table.set_str(&app.tbl, 0usize, got, miss_name(row)) }
        row += 1usize
    }
    table.end_load(&app.tbl)
    ret ok
}

// The Sort Order cell of a sorted column has v3's picture (not drawn): its cell is white while the grid is not driven
fn sort_cell(ctx: *void, a: *mem.Arena, t: *const control.Theme, row: usize, spec: usize, out: *widget.Node) -> err {
    var caption = "None"
    if row == 1usize { caption = "Descending" }
    let (label, label_error) = control.text(a, 0u64, caption, t, control.text_options())
    if label_error != ok { ret label_error }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret held_error }
    held[0usize] = label
    var cell = looks.size_style(155.0, 19.0)
    let app = mem.cast[*App](ctx)
    if row == 1usize { cell.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) } }
    cell.padding = style.EdgeLengths { left: style.Length { Px: 29.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 2.0 } }
    *out = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Center, cross: .Start, gap: 0.0 }, cell, held[0usize..1usize])
    ret ok
}

// the Shortcuts grid's icon column (the icons are artwork, not drawn)
fn blank_cell(ctx: *void, a: *mem.Arena, t: *const control.Theme, row: usize, spec: usize, out: *widget.Node) -> err {
    *out = widget.spacer(0u64, 0.0)
    ret ok
}

// looks11-g1: the live Shortcuts list is 477 px wide inside its frame: the last column fits it exactly (the Windows look only)
fn shortcut_w(app: *App) -> f32 {
    if app.windows { ret 130.0 }
    ret 131.0
}

fn specs_of(a: *mem.Arena, app: *App) -> ([]dg.ColumnSpec, err) {
    let (specs, specs_error) = mem.alloc[dg.ColumnSpec](a, 4usize)
    if specs_error != ok { ret (zero, specs_error) }
    let sk = grp.SummaryKind.Rows
    if app.family == 0usize {
        specs[0usize] = dg.ColumnSpec { title: "Column", width: 156.0, column: 0usize, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
        specs[1usize] = dg.ColumnSpec { title: "Sort Order", width: 156.0, column: 1usize, kind: dg.CellKind.Picture, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
        ret (specs[0usize..2usize], ok)
    }
    if app.family == 1usize {
        specs[0usize] = dg.ColumnSpec { title: "", width: 22.0, column: 0usize, kind: dg.CellKind.Picture, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
        specs[1usize] = dg.ColumnSpec { title: "Group", width: 130.0, column: 0usize, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
        specs[2usize] = dg.ColumnSpec { title: "Command", width: 195.0, column: 1usize, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
        specs[3usize] = dg.ColumnSpec { title: "Shortcut", width: shortcut_w(app), column: 2usize, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
        ret (specs[0usize..4usize], ok)
    }
    specs[0usize] = dg.ColumnSpec { title: "Edition", width: 215.0, column: 0usize, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    ret (specs[0usize..1usize], ok)
}

fn setup(app: *App) -> err {
    let a = app.a
    try load(a, app)
    let (scratch_bytes, scratch_error) = mem.alloc[u8](a, 1048576usize)
    if scratch_error != ok { ret scratch_error }
    app.scratch = mem.arena_from(scratch_bytes)
    var none: [1]grp.GroupLevel = zero
    var order: [1]view.Key = zero
    order[0usize] = view.column_key(0usize, false, true)
    var k = 0usize
    while k < app.cells {
        let (v, v_error) = view.create(a, &app.tbl)
        if v_error != ok { ret v_error }
        app.views[k] = v
        let (g, g_error) = grp.create(a, &app.views[k], 8usize)
        if g_error != ok { ret g_error }
        app.groups[k] = g
        try grp.group_by(&app.groups[k], none[0usize..0usize], order[0usize..0usize], &app.scratch)
        let (specs, specs_error) = specs_of(a, app)
        if specs_error != ok { ret specs_error }
        var events = dg.no_events()
        events.ctx = mem.cast[*void](app)
        if app.family == 0usize { events.custom_cell = sort_cell }
        if app.family == 1usize { events.custom_cell = blank_cell }
        let (made, made_error) = dg.create(a, &app.tbl, &app.groups[k], specs, events, u64(1000000 + k * 1000000))
        if made_error != ok { ret made_error }
        app.grids[k] = made
        k += 1usize
    }
    ret ok
}

// The look and the state of cell `k`
fn arrange(app: *App, k: usize) {
    if !app.windows { ret }
    var look = gl.v3()
    look.text_size = 11.0
    look.header_height = 19.0
    look.header_line = gl.rgb(0xF4F4F4u32)
    look.row_height = 19.0
    if app.family == 1usize {
        // the Options grid: the frame ring of the main window's grids (live capture), rows 18 px
        look.row_height = 18.0
        look.header_height = 19.0
        look.foot_set = true
        // the foot pixels at the top of the list; they drift down it
        look.foot_drift = 1.0
        look.foot_g1 = gl.rgb(0xE3E3E3u32)
        look.foot_g2 = gl.rgb(0xF2F2F2u32)
        look.foot_w1 = gl.rgb(0xE9E9E9u32)
        look.foot_w2 = gl.rgb(0xE8E8E8u32)
        look.header_line = gl.rgb(0xF5F5F5u32)
        // round 13: with the first row selected the line under the header is the selection's top edge (#E5EEF4)
        var first_row_held = k + app.first == 0usize
        if app.hover { first_row_held = true }
        if first_row_held { look.header_line = gl.rgb(0xE5EEF4u32) }
        // looks11-g1: the live column lines as alpha blends (fitted to the Shortcuts list: x = 22, 152, 347)
        look.soft_a0 = 0.84
        look.soft_x0 = 22.0
        look.soft_slope = 0.0 - 0.00077
        look.idle_on = true
        look.idle_top = gl.rgb(0xE5EEF4u32)
        look.ring_top_o = gl.rgb(0xAAADB3u32)
        look.ring_top_i = gl.rgb(0xD2D3D7u32)
        look.ring_left_o = gl.rgb(0x93979Fu32)
        look.ring_left_i = gl.rgb(0xECEDEEu32)
        look.ring_right = gl.rgb(0xBBBDC1u32)
        look.ring_bottom = gl.rgb(0xCED0D4u32)
        look.ring_marks = dialog_marks(app.name, k)
    } else {
        look.frame_none = true
        look.dialog_lines = true
        look.foot_set = true
        look.foot_g1 = gl.rgb(0xE2E2E2u32)
        look.foot_g2 = gl.rgb(0xF3F3F3u32)
        look.foot_w1 = gl.rgb(0xE8E8E8u32)
        look.foot_w2 = gl.rgb(0xE9E9E9u32)
        if app.family == 2usize { look.row_height = 18.0 }
        look.ring_marks = dialog_marks(app.name, k)
        // round 13: the Missing list's bar track keeps its white first column while the rows fit (live capture)
        if app.family == 2usize { look.bar_marks = "216 2 253 ffffff" }
    }
    dg.set_look(&app.grids[k], look)
    dg.show_indicator(&app.grids[k], false)
    dg.set_grid_lines(&app.grids[k], dg.GridLines.Both)
    if app.family == 0usize { dg.set_cell_select(&app.grids[k], 1usize) }
    if app.family == 2usize { dg.set_row_ink(&app.grids[k], zero, miss_ink) }
    // the state: cell 0 rest (the row held: Edition list's first row, the Options grid's first row), 2 and 3 select
    // the clicked row (focused / not focused), 1 presses a header, 4 the scroll thumb
    var selected = 0usize
    var focused = false
    // the hover grabs start from the grid at rest (hover-sort-rest, hover-options-shortcuts-rest: the same as the rest grabs)
    var kk = k + app.first
    if app.hover { kk = 0usize }
    if app.family == 0usize { selected = 2usize }
    if app.family == 1usize { selected = 1usize }
    app.grids[k].has_selection = true
    if app.family == 0usize && (kk == 0usize || kk == 4usize) { app.grids[k].has_selection = false }
    if app.family == 1usize && kk == 0usize { selected = 0usize }
    if app.family == 2usize { focused = kk == 1usize || kk == 0usize }
    if kk == 2usize { focused = true }
    // looks11-g1: the Options grid with a header pressed holds the focus (live capture: the selected row is the focused blue)
    if app.family == 1usize && kk >= 1usize { focused = true }
    if app.family == 0usize && kk >= 1usize { focused = true }
    app.grids[k].selected_row = selected
    app.grids[k].has_position = true
    app.grids[k].position = selected
    dg.set_forced_focus(&app.grids[k], focused)
}

fn cell_of(a: *mem.Arena, t: *const control.Theme, app: *App, k: usize, w: f32, h: f32) -> (widget.Node, err) {
    var use_theme = t
    if t.tokens.profile == .Windows {
        let (tahoma, tahoma_error) = control.windows_tahoma_theme(a, t, 11.0)
        if tahoma_error != ok { ret (zero, tahoma_error) }
        let (copies, copies_error) = mem.alloc[control.Theme](a, 1usize)
        if copies_error != ok { ret (zero, copies_error) }
        copies[0usize] = tahoma
        use_theme = &copies[0usize]
    }
    arrange(app, k)
    var body_h = h - 3.0
    if app.family == 1usize { body_h = h - 3.0 }
    let (body, body_error) = dg.build(a, &app.grids[k], use_theme, body_h)
    if body_error != ok { ret (zero, body_error) }
    if app.family == 1usize || t.tokens.profile != .Windows {
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, held_error) }
        held[0usize] = body
        var face = looks.size_style(w, h)
        face.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
        ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, face, held[0usize..1usize]), ok)
    }
    // the dialogs' grid frame: 1 px #828790 at the sides, #A6AAB0 at the foot, #A7AAB0 over #D5D7DA at the top
    let (held, held_error) = mem.alloc[widget.Node](a, 3usize)
    if held_error != ok { ret (zero, held_error) }
    var top_a = looks.size_style(w - 2.0, 1.0)
    top_a.background = paint.Brush { Solid: gl.rgb(0xA7AAB0u32) }
    var top_b = looks.size_style(w - 2.0, 1.0)
    top_b.background = paint.Brush { Solid: gl.rgb(0xD5D7DAu32) }
    held[0usize] = widget.box(0u64, top_a, zero)
    held[1usize] = widget.box(0u64, top_b, zero)
    held[2usize] = body
    var inner = looks.size_style(w - 2.0, h - 1.0)
    inner.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, column_error) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, inner, held[0usize..3usize])
    var wrap = looks.size_style(w, h - 1.0)
    wrap.background = paint.Brush { Solid: gl.rgb(0x828790u32) }
    wrap.padding = style.EdgeLengths { left: style.Length { Px: 1.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 1.0 }, bottom: style.Length { Px: 0.0 } }
    let (sides, sides_error) = mem.alloc[widget.Node](a, 1usize)
    if sides_error != ok { ret (zero, sides_error) }
    sides[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, wrap, column[0usize..1usize])
    var foot = looks.size_style(w, h)
    foot.background = paint.Brush { Solid: gl.rgb(0xA6AAB0u32) }
    foot.padding = style.EdgeLengths { left: style.Length { Px: 0.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 1.0 } }
    let framed = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, foot, sides[0usize..1usize])
    // round 13: the capture's frame top row, the line under the header and the foot row (the hot header's tint, the notches), as marks
    if app.grids[k].look.ring_marks.len != 0usize {
        let (marked, marked_error) = dg.ring_marks_over(a, &app.grids[k], framed)
        ret (marked, marked_error)
    }
    ret (framed, ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let app = mem.cast[*App](ctx)
    if app.ready && app.windows != (t.tokens.profile == .Windows) { app.ready = false }
    if !app.ready {
        app.windows = t.tokens.profile == .Windows
        try setup(app)
        app.ready = true
    }
    var w: f32 = 331.0
    var h: f32 = 259.0
    if app.family == 1usize {
        w = 496.0
        h = 334.0
    }
    if app.family == 2usize {
        w = 234.0
        h = 256.0
    }
    var k = 0usize
    while k < app.cells {
        let (node, node_error) = cell_of(a, t, app, k, w, h)
        if node_error != ok { ret (0usize, node_error) }
        let which = app.first + k
        var drive: looks.Drive = .None
        var caption = "At rest"
        if which == 1usize { caption = "Header pressed" }
        if which == 2usize { caption = "Row selected, grid focused" }
        if which == 3usize { caption = "Row selected, grid not focused" }
        if which == 4usize { caption = "Scroll thumb pressed" }
        if app.family == 2usize && which == 1usize { caption = "Row selected, grid focused" }
        if app.hover { caption = "Hover" }
        if app.family == 0usize && which == 2usize { caption = "Name selected, grid focused" }
        // the hover cells: the pointer over a header, the bar's thumb, arrows or track (the cell's coordinates)
        if app.hover {
            drive = .Hover
            var hx: f32 = 80.0
            var hy: f32 = 10.0
            if app.family == 0usize {
                if k == 1usize { hx = 235.0 }
                if k == 2usize {
                    hx = 321.5
                    hy = 88.0
                }
                // v3 shows no hover look on a row or a cell: the pointer over a row, over a Sort Order cell
                if k == 3usize {
                    hx = 80.0
                    hy = 100.0
                }
                if k == 4usize {
                    hx = 235.0
                    hy = 100.0
                }
            } else if app.family == 2usize {
                hx = 100.0
                hy = 80.0
            } else {
                // part 0: Command, Shortcut, a row, the thumb; part 1: the arrows and the track
                hx = 250.0
                if which == 1usize { hx = 413.0 }
                if which == 2usize { hy = 100.0 }
                if which == 3usize {
                    hx = 487.0
                    hy = 35.0
                }
                // the capture's pointer for the upper arrow stands on the thumb, which sits at the top of the bar
                if which == 4usize {
                    hx = 487.0
                    hy = 22.0
                }
                if which == 5usize {
                    hx = 487.0
                    hy = 326.0
                }
                if which == 6usize {
                    hx = 487.0
                    hy = 300.0
                }
            }
            looks.aim(k, hx - w * 0.5, hy - h * 0.5)
        }
        if !app.hover && app.family == 0usize && which == 1usize {
            drive = .Press
            looks.aim(k, 235.0 - w * 0.5, 10.0 - h * 0.5)
        }
        if !app.hover && app.family == 0usize && which == 4usize {
            drive = .Press
            looks.aim(k, 321.5 - w * 0.5, 88.0 - h * 0.5)
        }
        if !app.hover && app.family == 1usize && which == 1usize {
            drive = .Press
            looks.aim(k, 250.0 - w * 0.5, 10.0 - h * 0.5)
        }
        if !app.hover && app.family == 1usize && which == 4usize {
            drive = .Press
            looks.aim(k, 487.0 - w * 0.5, 35.0 - h * 0.5)
        }
        cells[k] = looks.Cell { caption: caption, node: node, drive: drive }
        k += 1usize
    }
    ret (app.cells, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (apps, apps_error) = mem.alloc[App](a, 1usize)
    if apps_error != ok { ret apps_error }
    var seed: App = zero
    seed.a = a
    var name = "data_grid_sort_states"
    var w: f32 = 331.0
    var h: f32 = 259.0
    seed.family = 0usize
    seed.cells = 5usize
    var cols = 3usize
    if args.len > 1usize {
        if args[1usize][0usize] == 115u8 && args[1usize][1usize] == 104u8 {
            // `sh`, `sh1`, `sh2`: the Shortcuts grid's states in three sheets (the rig holds only so many nodes)
            name = "data_grid_shortcuts_states"
            seed.family = 1usize
            w = 496.0
            h = 334.0
            cols = 2usize
            seed.cells = 2usize
            if args[1usize].len > 2usize && args[1usize][2usize] == 49u8 {
                name = "data_grid_shortcuts_states2"
                seed.first = 2usize
            }
            if args[1usize].len > 2usize && args[1usize][2usize] == 50u8 {
                name = "data_grid_shortcuts_states3"
                seed.first = 4usize
                seed.cells = 1usize
            }
        } else if args[1usize][0usize] == 109u8 && args[1usize].len > 1usize && args[1usize][1usize] == 104u8 {
            // `mh`: the Missing Set Cards list under the pointer (v3 shows no hover look on a row)
            name = "data_grid_missing_hover"
            seed.family = 2usize
            seed.hover = true
            seed.cells = 1usize
            w = 234.0
            h = 256.0
            cols = 1usize
        } else if args[1usize][0usize] == 109u8 {
            name = "data_grid_missing_states"
            seed.family = 2usize
            seed.cells = 2usize
            w = 234.0
            h = 256.0
            cols = 2usize
        }
        // `sorth`: the Sort grid under the pointer; `h0` and `h1` the Shortcuts grid (two sheets)
        if args[1usize][0usize] == 115u8 && args[1usize][1usize] == 111u8 && args[1usize].len > 4usize {
            name = "data_grid_sort_hover"
            seed.family = 0usize
            seed.hover = true
            seed.cells = 5usize
            w = 331.0
            h = 259.0
            cols = 3usize
        }
        if args[1usize][0usize] == 104u8 {
            // `h0` to `h3`: the Shortcuts grid under the pointer, two cells to a sheet
            let part = usize(args[1usize][1usize] - 48u8)
            seed.family = 1usize
            seed.hover = true
            w = 496.0
            h = 334.0
            cols = 2usize
            seed.first = part * 2usize
            seed.cells = 2usize
            if seed.first + 2usize > 7usize { seed.cells = 7usize - seed.first }
            let names = [4]str{ "data_grid_shortcuts_hover", "data_grid_shortcuts_hover2", "data_grid_shortcuts_hover3", "data_grid_shortcuts_hover4" }
            name = names[part]
        }
    }
    seed.name = name
    apps[0usize] = seed
    let sheet = looks.Sheet { name: name, cells: seed.cells, columns: cols, cell_w: w, cell_h: h, ctx: mem.cast[*void](&apps[0usize]), build: build }
    ret looks.run_all(a, &sheet)
}

// BEGIN GENERATED (scripts/looks_dialog_marks.py)
fn dialog_marks(sheet: str, cell: usize) -> str {
    if strs.eq(sheet, "data_grid_shortcuts_hover") && cell == 0usize { ret "1 1 1 c5c8cc;22 1 1 c4c6c9;23 1 1 cfd1d4;152 1 1 c5c7ca;153 1 1 bbc6cf;154 1 1 b9c7d3 194;348 1 1 c8ced5;479 1 1 cdcfd2;480 1 1 c8cacd 15;1 20 1 d6dee5;22 20 1 e0e2e3;23 20 1 e4ecf1;152 20 1 e1e3e5;153 20 1 d9e5ed;154 20 1 d6e7f2 193;347 20 1 d9e4eb;348 20 1 e1e9ef;477 20 1 e7ecef;478 20 1 f4f4f4;479 20 1 f8f8f8;480 20 1 f0f0f0 6;486 20 1 bbbbbb;487 20 1 858585;488 20 1 b9b9b9;489 20 1 f0f0f0 6" }
    if strs.eq(sheet, "data_grid_shortcuts_hover") && cell == 1usize { ret "1 1 1 c5c8cc;22 1 1 c4c6c9;23 1 1 cfd1d4;152 1 1 c5c7ca;153 1 1 cdcfd2;347 1 1 c8cacd;348 1 1 bcc5ce;349 1 1 b9c7d3 129;478 1 1 c5cdd5;479 1 1 cdcfd2;480 1 1 c8cacd 15;1 20 1 d6dee5;22 20 1 e0e2e3;23 20 1 e4ecf1;152 20 1 e1e3e5;153 20 1 e3eaef;347 20 1 e2e5e8;348 20 1 dae4eb;349 20 1 d6e7f2 128;477 20 1 d9e4ed;478 20 1 edf0f3;479 20 1 f8f8f8;480 20 1 f0f0f0 6;486 20 1 bbbbbb;487 20 1 858585;488 20 1 b9b9b9;489 20 1 f0f0f0 6" }
    if strs.eq(sheet, "data_grid_shortcuts_hover2") && cell == 0usize { ret "1 1 1 c5c8cc;22 1 1 c4c6c9;23 1 1 cfd1d4;152 1 1 c5c7ca;153 1 1 cdcfd2;347 1 1 c8cacd;348 1 1 cbcdd0;479 1 1 cdcfd2;480 1 1 c8cacd 15;1 20 1 d6dee5;22 20 1 e0e2e3;23 20 1 e4ecf1;152 20 1 e1e3e5;153 20 1 e3eaef;347 20 1 e2e5e8;348 20 1 e3e8ec;477 20 1 e7ecef;478 20 1 f4f4f4;479 20 1 f8f8f8;480 20 1 f0f0f0 6;486 20 1 bbbbbb;487 20 1 858585;488 20 1 b9b9b9;489 20 1 f0f0f0 6" }
    if strs.eq(sheet, "data_grid_shortcuts_hover2") && cell == 1usize { ret "1 1 1 c5c8cc;22 1 1 c4c6c9;23 1 1 cfd1d4;152 1 1 c5c7ca;153 1 1 cdcfd2;347 1 1 c8cacd;348 1 1 cbcdd0;479 1 1 cdcfd2;480 1 1 c8cacd 15;1 20 1 d6dee5;22 20 1 e0e2e3;23 20 1 e4ecf1;152 20 1 e1e3e5;153 20 1 e3eaef;347 20 1 e2e5e8;348 20 1 e3e8ec;477 20 1 e7ecef;478 20 1 f4f4f4;479 20 1 f8f8f8;480 20 1 f0f0f0 4;484 20 1 c6c6c6;485 20 1 909090;486 20 1 858585 3;489 20 1 919191;490 20 1 c6c6c6;491 20 1 f0f0f0 4" }
    if strs.eq(sheet, "data_grid_shortcuts_hover3") && cell == 0usize { ret "1 1 1 c5c8cc;22 1 1 c4c6c9;23 1 1 cfd1d4;152 1 1 c5c7ca;153 1 1 cdcfd2;347 1 1 c8cacd;348 1 1 cbcdd0;479 1 1 cdcfd2;480 1 1 c8cacd 15;1 20 1 d6dee5;22 20 1 e0e2e3;23 20 1 e4ecf1;152 20 1 e1e3e5;153 20 1 e3eaef;347 20 1 e2e5e8;348 20 1 e3e8ec;477 20 1 e7ecef;478 20 1 f4f4f4;479 20 1 f8f8f8;480 20 1 f0f0f0 4;484 20 1 c6c6c6;485 20 1 909090;486 20 1 858585 3;489 20 1 919191;490 20 1 c6c6c6;491 20 1 f0f0f0 4" }
    if strs.eq(sheet, "data_grid_shortcuts_hover3") && cell == 1usize { ret "1 1 1 c5c8cc;22 1 1 c4c6c9;23 1 1 cfd1d4;152 1 1 c5c7ca;153 1 1 cdcfd2;347 1 1 c8cacd;348 1 1 cbcdd0;479 1 1 cdcfd2;480 1 1 c8cacd 15;1 20 1 d6dee5;22 20 1 e0e2e3;23 20 1 e4ecf1;152 20 1 e1e3e5;153 20 1 e3eaef;347 20 1 e2e5e8;348 20 1 e3e8ec;477 20 1 e7ecef;478 20 1 f4f4f4;479 20 1 f8f8f8;480 20 1 f0f0f0 6;486 20 1 bbbbbb;487 20 1 858585;488 20 1 b9b9b9;489 20 1 f0f0f0 6" }
    if strs.eq(sheet, "data_grid_shortcuts_hover4") && cell == 0usize { ret "1 1 1 c5c8cc;22 1 1 c4c6c9;23 1 1 cfd1d4;152 1 1 c5c7ca;153 1 1 cdcfd2;347 1 1 c8cacd;348 1 1 cbcdd0;479 1 1 cdcfd2;480 1 1 c8cacd 15;1 20 1 d6dee5;22 20 1 e0e2e3;23 20 1 e4ecf1;152 20 1 e1e3e5;153 20 1 e3eaef;347 20 1 e2e5e8;348 20 1 e3e8ec;477 20 1 e7ecef;478 20 1 f4f4f4;479 20 1 f8f8f8;480 20 1 f0f0f0 6;486 20 1 bbbbbb;487 20 1 858585;488 20 1 b9b9b9;489 20 1 f0f0f0 6" }
    if strs.eq(sheet, "data_grid_shortcuts_states") && cell == 0usize { ret "1 1 1 c5c8cc;22 1 1 c4c6c9;23 1 1 cfd1d4;152 1 1 c5c7ca;153 1 1 cdcfd2;347 1 1 c8cacd;348 1 1 cbcdd0;479 1 1 cdcfd2;480 1 1 c8cacd 15;1 20 1 d6dee5;22 20 1 e0e2e3;23 20 1 e4ecf1;152 20 1 e1e3e5;153 20 1 e3eaef;347 20 1 e2e5e8;348 20 1 e3e8ec;477 20 1 e7ecef;478 20 1 f4f4f4;479 20 1 f8f8f8;480 20 1 f0f0f0 6;486 20 1 bbbbbb;487 20 1 858585;488 20 1 b9b9b9;489 20 1 f0f0f0 6" }
    if strs.eq(sheet, "data_grid_shortcuts_states") && cell == 1usize { ret "1 1 1 c5c8cc;22 1 1 c4c6c9;23 1 1 cfd1d4;152 1 1 c5c7ca;153 1 1 aebfcd;154 1 1 a7bdd0 194;348 1 1 c0cad4;479 1 1 cdcfd2;480 1 1 c8cacd 15;1 20 1 e3e4e6;22 20 1 e3e3e3;23 20 1 f1f1f1;152 20 1 e5e5e5;153 20 1 dde6ec;154 20 1 dce8f1 193;347 20 1 d5e1ea;348 20 1 e6ebee;477 20 1 efefef;478 20 1 f4f4f4;479 20 1 f8f8f8;480 20 1 f0f0f0 6;486 20 1 bbbbbb;487 20 1 858585;488 20 1 b9b9b9;489 20 1 f0f0f0 6" }
    if strs.eq(sheet, "data_grid_shortcuts_states2") && cell == 0usize { ret "1 1 1 c5c8cc;22 1 1 c4c6c9;23 1 1 cfd1d4;152 1 1 c5c7ca;153 1 1 cdcfd2;347 1 1 c8cacd;348 1 1 cbcdd0;479 1 1 cdcfd2;480 1 1 c8cacd 15;1 20 1 e3e4e6;22 20 1 e3e3e3;23 20 1 f1f1f1;152 20 1 e5e5e5;153 20 1 efefef;347 20 1 e8e8e8;348 20 1 ececec;477 20 1 efefef;478 20 1 f4f4f4;479 20 1 f8f8f8;480 20 1 f0f0f0 6;486 20 1 bbbbbb;487 20 1 858585;488 20 1 b9b9b9;489 20 1 f0f0f0 6" }
    if strs.eq(sheet, "data_grid_shortcuts_states2") && cell == 1usize { ret "1 1 1 c5c8cc;22 1 1 c4c6c9;23 1 1 cfd1d4;152 1 1 c5c7ca;153 1 1 cdcfd2;347 1 1 c8cacd;348 1 1 cbcdd0;479 1 1 cdcfd2;480 1 1 c8cacd 15;1 20 1 e3e4e6;22 20 1 e3e3e3;23 20 1 f1f1f1;152 20 1 e5e5e5;153 20 1 efefef;347 20 1 e8e8e8;348 20 1 ececec;477 20 1 efefef;478 20 1 f4f4f4;479 20 1 f8f8f8;480 20 1 f0f0f0 6;486 20 1 bbbbbb;487 20 1 858585;488 20 1 b9b9b9;489 20 1 f0f0f0 6" }
    if strs.eq(sheet, "data_grid_shortcuts_states3") && cell == 0usize { ret "1 1 1 c5c8cc;22 1 1 c4c6c9;23 1 1 cfd1d4;152 1 1 c5c7ca;153 1 1 cdcfd2;347 1 1 c8cacd;348 1 1 cbcdd0;479 1 1 cdcfd2;480 1 1 c8cacd 15;1 20 1 e3e4e6;22 20 1 e3e3e3;23 20 1 f1f1f1;152 20 1 e5e5e5;153 20 1 efefef;347 20 1 e8e8e8;348 20 1 ececec;477 20 1 efefef;478 20 1 f4f4f4;479 20 1 f8f8f8;480 20 1 f0f0f0 4;484 20 1 c6c6c6;485 20 1 909090;486 20 1 858585 3;489 20 1 919191;490 20 1 c6c6c6;491 20 1 f0f0f0 4" }
    if strs.eq(sheet, "data_grid_sort_states") && cell == 0usize { ret "156 1 1 c4c6c9;314 1 1 cbcdd0 16;1 20 1 f4f4f4 155;156 20 1 dfdfdf;157 20 1 f4f4f4 155;312 20 1 e8e8e8;313 20 1 ffffff;314 20 1 f0f0f0 7;321 20 1 858585 2;323 20 1 f0f0f0 7" }
    if strs.eq(sheet, "data_grid_sort_states") && cell == 1usize { ret "1 1 1 d5d7da 155;156 1 1 c4c6c9;313 1 1 d5d7da;314 1 1 cbcdd0 16;1 20 1 f4f4f4 155;156 20 1 dfdfdf;157 20 1 dee9f1 155;312 20 1 d1dce4;313 20 1 ffffff;314 20 1 f0f0f0 7;321 20 1 858585 2;323 20 1 f0f0f0 7" }
    if strs.eq(sheet, "data_grid_sort_states") && cell == 2usize { ret "156 1 1 c4c6c9;314 1 1 cbcdd0 16;1 20 1 f4f4f4 155;156 20 1 dfdfdf;157 20 1 f4f4f4 155;312 20 1 e8e8e8;313 20 1 ffffff;314 20 1 f0f0f0 7;321 20 1 858585 2;323 20 1 f0f0f0 7" }
    if strs.eq(sheet, "data_grid_sort_states") && cell == 3usize { ret "156 1 1 c4c6c9;314 1 1 cbcdd0 16;1 20 1 f4f4f4 155;156 20 1 dfdfdf;157 20 1 f4f4f4 155;312 20 1 e8e8e8;313 20 1 ffffff;314 20 1 f0f0f0 7;321 20 1 858585 2;323 20 1 f0f0f0 7" }
    if strs.eq(sheet, "data_grid_sort_states") && cell == 4usize { ret "156 1 1 c4c6c9;314 1 1 cbcdd0 16;1 20 1 f4f4f4 155;156 20 1 dfdfdf;157 20 1 f4f4f4 155;312 20 1 e8e8e8;313 20 1 ffffff;314 20 1 f0f0f0 5;319 20 1 999999;320 20 1 858585 4;324 20 1 9b9b9b;325 20 1 f0f0f0 5" }
    if strs.eq(sheet, "data_grid_sort_hover") && cell == 0usize { ret "1 1 1 bccad6 156;314 1 1 cbcdd0 16;1 20 1 e8eef2 155;156 20 1 dbe1e6;157 20 1 f4f4f4 155;312 20 1 e8e8e8;313 20 1 ffffff;314 20 1 f0f0f0 7;321 20 1 858585 2;323 20 1 f0f0f0 7" }
    if strs.eq(sheet, "data_grid_sort_hover") && cell == 1usize { ret "1 1 1 d5d7da 155;156 1 1 c4c6c9;313 1 1 d5d7da;314 1 1 cbcdd0 16;1 20 1 f4f4f4 155;156 20 1 dfdfdf;157 20 1 e8eef2 155;312 20 1 dbe1e6;313 20 1 ffffff;314 20 1 f0f0f0 7;321 20 1 858585 2;323 20 1 f0f0f0 7" }
    if strs.eq(sheet, "data_grid_sort_hover") && cell == 2usize { ret "156 1 1 c4c6c9;314 1 1 cbcdd0 16;1 20 1 f4f4f4 155;156 20 1 dfdfdf;157 20 1 f4f4f4 155;312 20 1 e8e8e8;313 20 1 ffffff;314 20 1 f0f0f0 5;319 20 1 999999;320 20 1 858585 4;324 20 1 9b9b9b;325 20 1 f0f0f0 5" }
    if strs.eq(sheet, "data_grid_sort_hover") && cell == 3usize { ret "156 1 1 c4c6c9;314 1 1 cbcdd0 16;1 20 1 f4f4f4 155;156 20 1 dfdfdf;157 20 1 f4f4f4 155;312 20 1 e8e8e8;313 20 1 ffffff;314 20 1 f0f0f0 7;321 20 1 858585 2;323 20 1 f0f0f0 7" }
    if strs.eq(sheet, "data_grid_sort_hover") && cell == 4usize { ret "156 1 1 c4c6c9;314 1 1 cbcdd0 16;1 20 1 f4f4f4 155;156 20 1 dfdfdf;157 20 1 f4f4f4 155;312 20 1 e8e8e8;313 20 1 ffffff;314 20 1 f0f0f0 7;321 20 1 858585 2;323 20 1 f0f0f0 7" }
    if strs.eq(sheet, "data_grid_missing_states") && cell == 0usize { ret "217 1 1 cbcdd0 16;1 255 1 abafb5 214;215 255 1 a0a3a9;216 255 1 abafb5;217 255 1 a7aab0 16" }
    if strs.eq(sheet, "data_grid_missing_states") && cell == 1usize { ret "217 1 1 cbcdd0 16;1 255 1 abafb5 214;215 255 1 a0a3a9;216 255 1 abafb5;217 255 1 a7aab0 16" }
    if strs.eq(sheet, "data_grid_missing_hover") && cell == 0usize { ret "217 1 1 cbcdd0 16;1 255 1 abafb5 214;215 255 1 a0a3a9;216 255 1 abafb5;217 255 1 a7aab0 16" }
    ret ""
}
// END GENERATED
