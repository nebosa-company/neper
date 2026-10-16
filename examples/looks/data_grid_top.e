// looks5-e: the top grid of the live v3 main window in every captured interaction state, one cell per state:
// docs/ui/looks/<look>/data_grid_top.png, compared with ref/windows/data_grid_top.png (the 576 x 215 crops of
// states/grid-*-main@1x.png at (216, 108), laid out as this sheet is). The card pool as plain rows (Swiftfoot Boots, the
// fourth row, current), the navigator with its first, previous, next and last record buttons and the horizontal thumb.
// States: header pressed (Name), navigator at rest, first, next and last button pressed, row selected with the grid
// focused, row selected with the grid not focused. Run from the repository root.

use e.data.table as table
use e.data.tablegroup as grp
use e.data.tableview as view
use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.datagrid as dg
use e.ui.gridlook as gl
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

const ROWS: usize = 120283usize
const CELLS: usize = 10usize
const C_NAME: usize = 0usize
const C_ED: usize = 1usize
const C_COLOR: usize = 2usize
const C_TYPE: usize = 3usize
const C_RARITY: usize = 4usize
const C_FAV: usize = 5usize

type App = struct {
    a: *mem.Arena,
    ready: bool,
    windows: bool,
    tbl: table.Table,
    views: [CELLS]view.View,
    groups: [CELLS]grp.Grouping,
    grids: [CELLS]dg.Grid,
    scratch: mem.Arena,
    first: usize,
    count: usize
}

fn name_of(row: usize) -> str {
    if row == 9usize { ret "Dust to Dust" }
    if row == 10usize { ret "Euru, Acorn Scrounger" }
    let k = row % 9usize
    if k == 0usize { ret "Path of Ancestry" }
    if k == 1usize { ret "Exotic Orchard" }
    if k == 2usize { ret "Thought Vessel" }
    if k == 3usize { ret "Swiftfoot Boots" }
    if k == 4usize { ret "Mind Stone" }
    if k == 5usize { ret "Jeweled Amulet" }
    if k == 6usize { ret "Fellwar Stone" }
    if k == 7usize { ret "Chromatic Lantern" }
    ret "Chaos Warp"
}

fn type_of(row: usize) -> str {
    if row == 9usize { ret "Sorcery" }
    if row == 10usize { ret "Legendary Creature — Squirrel" }
    let k = row % 9usize
    if k == 0usize || k == 1usize { ret "Land" }
    if k == 3usize { ret "Artifact — Equipment" }
    if k == 8usize { ret "Instant" }
    ret "Artifact"
}

fn rarity_of(row: usize) -> str {
    if row == 9usize || row == 10usize { ret "U" }
    let k = row % 9usize
    if k == 0usize { ret "C" }
    if k == 1usize || k == 7usize || k == 8usize { ret "R" }
    ret "U"
}

fn color_of(row: usize) -> str {
    if row == 9usize { ret "W" }
    if row == 10usize { ret "M" }
    if row % 9usize == 8usize { ret "R" }
    ret "N"
}

fn load(a: *mem.Arena, app: *App) -> err {
    var spec: [6]table.Spec = zero
    spec[C_FAV] = table.Spec { name: "Fav", kind: table.Kind.Bool, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_NAME] = table.Spec { name: "Name", kind: table.Kind.Dict, heap_bytes: 1024usize, dict_cap: 16usize }
    spec[C_ED] = table.Spec { name: "Edition", kind: table.Kind.Dict, heap_bytes: 64usize, dict_cap: 4usize }
    spec[C_COLOR] = table.Spec { name: "Color", kind: table.Kind.Dict, heap_bytes: 64usize, dict_cap: 4usize }
    spec[C_TYPE] = table.Spec { name: "Type", kind: table.Kind.Dict, heap_bytes: 256usize, dict_cap: 8usize }
    spec[C_RARITY] = table.Spec { name: "Rarity", kind: table.Kind.Dict, heap_bytes: 64usize, dict_cap: 4usize }
    let (made, made_error) = table.create(a, spec[0..], ROWS)
    if made_error != ok { ret made_error }
    app.tbl = made
    table.begin_load(&app.tbl)
    var row = 0usize
    while row < ROWS {
        let (got, append_error) = table.append_row(&app.tbl)
        if append_error != ok { ret append_error }
        try table.set_str(&app.tbl, C_NAME, got, name_of(row))
        try table.set_str(&app.tbl, C_ED, got, "MBC")
        try table.set_str(&app.tbl, C_COLOR, got, color_of(row))
        try table.set_str(&app.tbl, C_TYPE, got, type_of(row))
        try table.set_str(&app.tbl, C_RARITY, got, rarity_of(row))
        table.set_bool(&app.tbl, C_FAV, got, false)
        row += 1usize
    }
    table.end_load(&app.tbl)
    ret ok
}

// every card of the capture is colourless (grey) but Chaos Warp (red)
fn ink(ctx: *void, row: usize) -> (paint.Color, bool) {
    if row == 9usize {
        let (white, has_white) = gl.card_ink(87u8)
        ret (white, has_white)
    }
    if row == 10usize {
        let (multi, has_multi) = gl.card_ink(77u8)
        ret (multi, has_multi)
    }
    if row % 9usize == 8usize {
        let (red, has_red) = gl.card_ink(82u8)
        ret (red, has_red)
    }
    let (grey, has_grey) = gl.card_ink(78u8)
    ret (grey, has_grey)
}

fn specs_of(a: *mem.Arena) -> ([]dg.ColumnSpec, err) {
    let (specs, specs_error) = mem.alloc[dg.ColumnSpec](a, 10usize)
    if specs_error != ok { ret (zero, specs_error) }
    let sk = grp.SummaryKind.Rows
    specs[0usize] = dg.ColumnSpec { title: "", width: 12.0, column: C_NAME, kind: dg.CellKind.Indicator, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[1usize] = dg.ColumnSpec { title: "Favorite", width: 23.0, column: C_FAV, kind: dg.CellKind.Star, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[2usize] = dg.ColumnSpec { title: "", width: 21.0, column: C_NAME, kind: dg.CellKind.Picture, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[3usize] = dg.ColumnSpec { title: "Name", width: 150.0, column: C_NAME, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[4usize] = dg.ColumnSpec { title: "Edition", width: 70.0, column: C_ED, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[5usize] = dg.ColumnSpec { title: "Color", width: 60.0, column: C_COLOR, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[6usize] = dg.ColumnSpec { title: "Type", width: 150.0, column: C_TYPE, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[7usize] = dg.ColumnSpec { title: "Rarity", width: 50.0, column: C_RARITY, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[8usize] = dg.ColumnSpec { title: "", width: 24.0, column: C_NAME, kind: dg.CellKind.Picture, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    // the columns beyond the pane: the navigator's thumb says the content is wider
    specs[9usize] = dg.ColumnSpec { title: "Power", width: 500.0, column: C_NAME, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    ret (specs, ok)
}

fn setup(app: *App) -> err {
    let a = app.a
    try load(a, app)
    let (scratch_bytes, scratch_error) = mem.alloc[u8](a, 16777216usize)
    if scratch_error != ok { ret scratch_error }
    app.scratch = mem.arena_from(scratch_bytes)
    var order: [1]view.Key = zero
    order[0usize] = view.column_key(C_NAME, false, true)
    var none: [1]grp.GroupLevel = zero
    var k = app.first
    while k < app.first + app.count {
        let (v, v_error) = view.create(a, &app.tbl)
        if v_error != ok { ret v_error }
        app.views[k] = v
        let (g, g_error) = grp.create(a, &app.views[k], 8usize)
        if g_error != ok { ret g_error }
        app.groups[k] = g
        // the rows stay in load order: no key
        try grp.group_by(&app.groups[k], none[0usize..0usize], order[0usize..0usize], &app.scratch)
        let (specs, specs_error) = specs_of(a)
        if specs_error != ok { ret specs_error }
        let (made, made_error) = dg.create(a, &app.tbl, &app.groups[k], specs, dg.no_events(), u64(1000000 + k * 1000000))
        if made_error != ok { ret made_error }
        app.grids[k] = made
        var look = gl.v3()
        look.header_height = 22.0
        // the live capture's frame: white header, so a lighter inner top line
        look.ring_top_i = gl.rgb(0xD0D2D5u32)
        look.ring_left_o = gl.rgb(0x90949Cu32)
        look.ring_left_i = gl.rgb(0xEFF0F1u32)
        look.foot_set = true
        look.foot_g1 = gl.rgb(0xE5E5E5u32)
        look.foot_g2 = gl.rgb(0xF0F0F0u32)
        look.foot_w1 = gl.rgb(0xEBEBEBu32)
        look.foot_w2 = gl.rgb(0xE7E7E7u32)
        dg.set_look(&app.grids[k], look)
        dg.set_row_ink(&app.grids[k], zero, ink)
        dg.set_grid_lines(&app.grids[k], dg.GridLines.Horizontal)
        dg.show_navigator(&app.grids[k], true)
        dg.set_pane_hint(&app.grids[k], 573.0)
        app.grids[k].aligns[4usize] = 2u8
        app.grids[k].aligns[5usize] = 2u8
        app.grids[k].aligns[7usize] = 2u8
        app.grids[k].has_position = true
        app.grids[k].position = 3usize
        app.grids[k].has_selection = true
        app.grids[k].selected_row = 3usize
        // focused: the cells 0 to 5 (the capture's grid had the focus: dotted row rectangle); the last one is not
        dg.set_forced_focus(&app.grids[k], k != 6usize)
        if k == 0usize { dg.show_sort(&app.grids[k], 3usize, false) }
        // the lower arrow held down scrolls the rows (the capture shows two rows gone)
        if k == 9usize { app.grids[k].offset = 38.0 }
        k += 1usize
    }
    ret ok
}

fn cell_of(a: *mem.Arena, t: *const control.Theme, grid: *dg.Grid) -> (widget.Node, err) {
    let (body, body_error) = dg.build(a, grid, t, 239.0)
    if body_error != ok { ret (zero, body_error) }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = body
    var face = looks.size_style(576.0, 213.0)
    face.padding = style.EdgeLengths { left: style.Length { Px: 0.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    face.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, face, held[0usize..1usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let app = mem.cast[*App](ctx)
    if app.ready && app.windows != (t.tokens.profile == .Windows) { app.ready = false }
    if !app.ready {
        app.windows = t.tokens.profile == .Windows
        try setup(app)
        app.ready = true
    }
    let captions = [CELLS]str{ "Header pressed (Name)", "Navigator at rest", "First pressed", "Next pressed", "Last pressed", "Row selected, grid focused", "Row selected, grid not focused", "Vertical thumb pressed", "Horizontal thumb pressed", "Lower arrow pressed" }
    var i = app.first
    while i < app.first + app.count {
        let (node, node_error) = cell_of(a, t, &app.grids[i])
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        // the pointer goes to the control that is pressed: the Name header, the first, next or last record button
        if i == 0usize {
            drive = .Press
            looks.aim(i - app.first, 100.0 - 288.0, 12.0 - 106.5)
        }
        if i == 2usize {
            drive = .Press
            looks.aim(i - app.first, 12.0 - 288.0, 199.0 - 106.5)
        }
        if i == 3usize {
            drive = .Press
            looks.aim(i - app.first, 146.0 - 288.0, 199.0 - 106.5)
        }
        if i == 4usize {
            drive = .Press
            looks.aim(i - app.first, 192.0 - 288.0, 199.0 - 106.5)
        }
        if i == 7usize {
            drive = .Press
            looks.aim(i - app.first, 783.0 - 216.0 - 288.0, 135.0 - 109.0 - 106.5)
        }
        if i == 8usize {
            drive = .Press
            looks.aim(i - app.first, 323.0 - 288.0, 201.0 - 106.5)
        }
        if i == 9usize {
            drive = .Press
            looks.aim(i - app.first, 783.0 - 216.0 - 288.0, 187.0 - 106.5)
        }
        cells[i - app.first] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (app.count, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (apps, apps_error) = mem.alloc[App](a, 1usize)
    if apps_error != ok { ret apps_error }
    var seed: App = zero
    seed.a = a
    // the sheet is run in parts (the rig holds a limited number of nodes): `data_grid_top.exe 1` is cells 0 to 2 ...
    var name = "data_grid_top"
    seed.first = 0usize
    seed.count = 2usize
    if args.len > 1usize {
        let part = usize(args[1usize][0usize] - 48u8)
        seed.first = part * 2usize
        seed.count = 2usize
        if seed.first + 2usize > CELLS { seed.count = CELLS - seed.first }
        if part == 1usize { name = "data_grid_top2" }
        if part == 2usize { name = "data_grid_top3" }
        if part == 3usize { name = "data_grid_top4" }
        if part == 4usize { name = "data_grid_top5" }
    }
    apps[0usize] = seed
    let sheet = looks.Sheet { name: name, cells: seed.count, columns: 2usize, cell_w: 576.0, cell_h: 213.0, ctx: mem.cast[*void](&apps[0usize]), build: build }
    ret looks.run_all(a, &sheet)
}
