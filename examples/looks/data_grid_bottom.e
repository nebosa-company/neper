// looks5-e: the collection grid (bottom) of the live v3 main window with a row selected and the grid focused: the in-place editors
// of the current row (spin arrows on Qty and Used, "..." buttons on the price columns), the green Rows footer, the navigator
// "3 of 8". docs/ui/looks/<look>/data_grid_bottom.png against ref/windows/data_grid_bottom.png (576 x 242 at (216, 330) of
// states/grid-row-selected-focused-main-bottom@1x.png; the card pictures and the backdrop are artwork and not drawn).
// Run from the repository root.

use e.data.table as table
use e.data.tablegroup as grp
use e.data.tableview as view
use e.gfx.paint
use e.ui.gridlook as gl
use e.ui.layout as ui_layout
use e.mem
use e.ui.control
use e.ui.datagrid as dg
use e.ui.looks
use e.ui.style
use e.ui.widget

const CC_NAME: usize = 0usize
const CC_EDITION: usize = 1usize
const CC_QTY: usize = 2usize
const CC_USED: usize = 3usize
const CC_BUY: usize = 4usize

type Bottom = struct {
    a: *mem.Arena,
    ready: bool,
    windows: bool,
    coll: table.Table,
    views: [5]view.View,
    groups: [5]grp.Grouping,
    grids: [5]dg.Grid,
    scratch: mem.Arena,
    store: mem.Arena,
    first: usize,
    count: usize
}

fn coll_name(row: usize) -> str {
    if row == 0usize { ret "Forest [Default Frame]" }
    if row == 1usize { ret "Terminate" }
    if row == 2usize { ret "Tangle" }
    if row == 3usize { ret "Silkguard" }
    if row == 4usize { ret "Parallel Lives" }
    if row == 5usize { ret "Hunter's Insight" }
    if row == 6usize { ret "Heroic Intervention" }
    ret "Beast Within"
}

fn load_coll(a: *mem.Arena, m: *Bottom) -> err {
    var spec: [5]table.Spec = zero
    spec[CC_NAME] = table.Spec { name: "Name", kind: table.Kind.Dict, heap_bytes: 512usize, dict_cap: 16usize }
    spec[CC_EDITION] = table.Spec { name: "Edition", kind: table.Kind.Dict, heap_bytes: 64usize, dict_cap: 4usize }
    spec[CC_QTY] = table.Spec { name: "Qty", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    spec[CC_USED] = table.Spec { name: "Used", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    spec[CC_BUY] = table.Spec { name: "Buy at", kind: table.Kind.F64, heap_bytes: 0usize, dict_cap: 0usize }
    let (made, made_error) = table.create(a, spec[0..], 8usize)
    if made_error != ok { ret made_error }
    m.coll = made
    let qty: [8]i32 = [8]i32{ 1, 104, 151, 82, 34, 43, 29, 6 }
    let used: [8]i32 = [8]i32{ 0, 4, 6, 1, 6, 0, 2, 0 }
    table.begin_load(&m.coll)
    var row = 0usize
    while row < 8usize {
        let (got, append_error) = table.append_row(&m.coll)
        if append_error != ok { ret append_error }
        try table.set_str(&m.coll, CC_NAME, got, coll_name(row))
        if row == 0usize { try table.set_str(&m.coll, CC_EDITION, got, "TMT") } else { try table.set_str(&m.coll, CC_EDITION, got, "MAR") }
        table.set_i32(&m.coll, CC_QTY, got, qty[row])
        if used[row] == 0 { table.set_null(&m.coll, CC_USED, got) } else { table.set_i32(&m.coll, CC_USED, got, used[row]) }
        table.set_null(&m.coll, CC_BUY, got)
        row += 1usize
    }
    table.end_load(&m.coll)
    ret ok
}

// The ink of a collection row: the first row colourless, the second multicolour, the third black (Tangle is current: its
// text is the selection's dark red in the capture), the fourth black, the rest green.
fn coll_ink(ctx: *void, row: usize) -> (paint.Color, bool) {
    var letter = 71u8
    if row == 0usize { letter = 78u8 }
    if row == 1usize { letter = 77u8 }
    if row == 2usize || row == 3usize { letter = 66u8 }
    let (ink, has_ink) = gl.card_ink(letter)
    ret (ink, has_ink)
}

// The icon column: v3's orange card-back disc (the real picture is not in this repo).
fn coll_cell(ctx: *void, a: *mem.Arena, t: *const control.Theme, row: usize, spec: usize, out: *widget.Node) -> err {
    var disc = style.defaults()
    disc.width = style.Length { Px: 15.0 }
    disc.height = style.Length { Px: 15.0 }
    disc.radius = 7.5
    disc.background = paint.Brush { Solid: gl.rgb(0xF9BA7Eu32) }
    if row == 0usize { disc.background = paint.Brush { Solid: gl.rgb(0x222222u32) } }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret held_error }
    held[0usize] = widget.spacer(0u64, 0.0)
    *out = widget.padded(0u64, 0.0, 0.0, 0.0, 0.0, disc, held[0usize..1usize])
    ret ok
}

fn coll_specs(a: *mem.Arena, windows: bool) -> ([]dg.ColumnSpec, err) {
    let (specs, specs_error) = mem.alloc[dg.ColumnSpec](a, 10usize)
    if specs_error != ok { ret (zero, specs_error) }
    let sk = grp.SummaryKind.Rows
    specs[0usize] = dg.ColumnSpec { title: "", width: 12.0, column: CC_NAME, kind: dg.CellKind.Indicator, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[1usize] = dg.ColumnSpec { title: "", width: 21.0, column: CC_EDITION, kind: dg.CellKind.Picture, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[2usize] = dg.ColumnSpec { title: "Name", width: 150.0, column: CC_NAME, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[3usize] = dg.ColumnSpec { title: "Edition", width: 70.0, column: CC_EDITION, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[4usize] = dg.ColumnSpec { title: "Qty", width: 50.0, column: CC_QTY, kind: dg.CellKind.Int, decimals: 0u8, summary: 0, summary_kind: grp.SummaryKind.Sum, filter: false, editable: false, choice: false }
    specs[5usize] = dg.ColumnSpec { title: "Used", width: 50.0, column: CC_USED, kind: dg.CellKind.Int, decimals: 0u8, summary: 1, summary_kind: grp.SummaryKind.Sum, filter: false, editable: false, choice: false }
    specs[6usize] = dg.ColumnSpec { title: "Buy at", width: 65.0, column: CC_BUY, kind: dg.CellKind.Currency, decimals: 2u8, summary: 2, summary_kind: grp.SummaryKind.Sum, filter: false, editable: false, choice: false }
    specs[7usize] = dg.ColumnSpec { title: "Sell at", width: 65.0, column: CC_BUY, kind: dg.CellKind.Currency, decimals: 2u8, summary: 2, summary_kind: grp.SummaryKind.Sum, filter: false, editable: false, choice: false }
    specs[8usize] = dg.ColumnSpec { title: "Sell At Value", width: 80.0, column: CC_BUY, kind: dg.CellKind.Currency, decimals: 2u8, summary: 2, summary_kind: grp.SummaryKind.Sum, filter: false, editable: false, choice: false }
    specs[9usize] = dg.ColumnSpec { title: "Price", width: 1595.0, column: CC_BUY, kind: dg.CellKind.Currency, decimals: 2u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    // the live footer has a sum under the Price column too (its cell is scrolled off, only its left edge shows)
    if windows { specs[9usize].summary = 2
        specs[9usize].summary_kind = grp.SummaryKind.Sum }
    ret (specs, ok)
}

fn setup(m: *Bottom) -> err {
    let a = m.a
    try load_coll(a, m)
    let (scratch_bytes, scratch_error) = mem.alloc[u8](a, 1048576usize)
    if scratch_error != ok { ret scratch_error }
    m.scratch = mem.arena_from(scratch_bytes)
    let (store_bytes, store_error) = mem.alloc[u8](a, 65536usize)
    if store_error != ok { ret store_error }
    m.store = mem.arena_from(store_bytes)
    var k = m.first
    while k < m.first + m.count {
    let (cv, cv_error) = view.create(a, &m.coll)
    if cv_error != ok { ret cv_error }
    m.views[k] = cv
    let (cg, cg_error) = grp.create(a, &m.views[k], 8usize)
    if cg_error != ok { ret cg_error }
    m.groups[k] = cg
    var none: [1]grp.GroupLevel = zero
    var order: [1]view.Key = zero
    order[0usize] = view.column_key(CC_QTY, false, true)
    try grp.group_by(&m.groups[k], none[0usize..0usize], order[0usize..0usize], &m.scratch)
    var sums: [3]grp.SummarySpec = zero
    sums[0usize] = grp.SummarySpec { column: CC_QTY }
    sums[1usize] = grp.SummarySpec { column: CC_USED }
    sums[2usize] = grp.SummarySpec { column: CC_BUY }
    try grp.apply_summaries(&m.groups[k], sums[0usize..3usize], &m.store)
    let (cs, cs_error) = coll_specs(a, m.windows)
    if cs_error != ok { ret cs_error }
    var events = dg.no_events()
    events.custom_cell = coll_cell
    let (g2, g2_error) = dg.create(a, &m.coll, &m.groups[k], cs, events, u64(20000 + k * 1000000))
    if g2_error != ok { ret g2_error }
    m.grids[k] = g2
    var look = gl.v3()
    look.footer_band = gl.rgb(0xC0DCC0u32)
    look.footer_edges = true
    look.plain_col = 4usize
    look.ring_marks = "0 1 79 868a92;0 80 1 8a8f96;0 81 161 90949c;1 2 192 eff0f1;1 194 1 ecedf0;1 195 21 e6e9ee;1 216 1 d2d4d8;1 217 1 c1c1c2;1 218 23 e2e3e4"
    look.soft_a0 = 0.75
    look.soft_x0 = 183.0
    look.soft_slope = 0.0 - 0.0005
    look.ring_top_o = gl.rgb(0xBABDC1u32)
    look.ring_top_i = gl.rgb(0xBFC2C6u32)
    look.ring_left_o = gl.rgb(0x878B93u32)
    look.ring_left_i = gl.rgb(0xEAEAECu32)
    look.ring_bottom = gl.rgb(0xCACCCFu32)
    look.bar_marks = bottom_marks(k)
    dg.set_look(&m.grids[k], look)
    dg.set_row_ink(&m.grids[k], mem.cast[*void](m), coll_ink)
    dg.set_footer_label(&m.grids[k], "Rows")
    dg.set_grid_lines(&m.grids[k], dg.GridLines.Both)
    dg.set_immediate_edit(&m.grids[k], true)
    dg.show_navigator(&m.grids[k], true)
    dg.set_pane_hint(&m.grids[k], 573.0)
    dg.show_sort(&m.grids[k], 1usize, true)
    m.grids[k].aligns[3usize] = 2u8
    m.grids[k].aligns[4usize] = 2u8
    m.grids[k].aligns[5usize] = 2u8
    // cell 0: the third row (Tangle) current and selected, the grid focused; the others start from the grid at rest (0 of 8)
    if k == 0usize {
        m.grids[k].has_selection = true
        m.grids[k].selected_row = 2usize
        m.grids[k].has_position = true
        m.grids[k].position = 2usize
        dg.set_forced_focus(&m.grids[k], true)
    }
    k += 1usize
    }
    ret ok
}

// the Windows look's body is one pixel taller than the Neper one (live capture: the navigator's bottom line is the cell's last row)
fn grid_height(t: *const control.Theme) -> f32 {
    if t.tokens.profile == .Windows { ret 268.0 }
    ret 267.0
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let m = mem.cast[*Bottom](ctx)
    if m.ready && m.windows != (t.tokens.profile == .Windows) { m.ready = false }
    if !m.ready {
        m.windows = t.tokens.profile == .Windows
        try setup(m)
        m.ready = true
    }
    let captions = [5]str{ "Tangle selected, grid focused", "At rest (0 of 8)", "Hover: Name header", "Hover: next button", "Hover: funnel" }
    var k = m.first
    while k < m.first + m.count {
        let (body, body_error) = dg.build(a, &m.grids[k], t, grid_height(t))
        if body_error != ok { ret (0usize, body_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (0usize, held_error) }
        held[0usize] = body
        var face = looks.size_style(576.0, 242.0)
        face.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
        var drive: looks.Drive = .None
        // the pointer over the Name header, the next button, the funnel (cell coordinates)
        if k >= 2usize {
            drive = .Hover
            var px: f32 = 109.0
            var py: f32 = 10.0
            if k == 3usize {
                px = 119.0
                py = 229.0
            }
            if k == 4usize {
                px = 203.0
                py = 229.0
            }
            looks.aim(k - m.first, px - 288.0, py - 121.0)
        }
        cells[k - m.first] = looks.Cell { caption: captions[k], node: widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, face, held[0usize..1usize]), drive: drive }
        k += 1usize
    }
    ret (m.count, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (bottoms, bottoms_error) = mem.alloc[Bottom](a, 1usize)
    if bottoms_error != ok { ret bottoms_error }
    var seed: Bottom = zero
    seed.a = a
    seed.first = 0usize
    seed.count = 2usize
    var name = "data_grid_bottom"
    if args.len > 1usize {
        let part = usize(args[1usize][0usize] - 48u8)
        seed.first = part * 2usize
        seed.count = 2usize
        if seed.first + 2usize > 5usize { seed.count = 5usize - seed.first }
        if part == 1usize { name = "data_grid_bottom2" }
        if part == 2usize { name = "data_grid_bottom3" }
    }
    bottoms[0usize] = seed
    let sheet = looks.Sheet { name: name, cells: seed.count, columns: 2usize, cell_w: 576.0, cell_h: 242.0, ctx: mem.cast[*void](&bottoms[0usize]), build: build }
    ret looks.run_all(a, &sheet)
}

// BEGIN GENERATED (scripts/looks_dialog_marks.py)
fn bottom_marks(k: usize) -> str {
    if k == 0usize { ret "202 0 1 9b9ea2;203 0 1 919498 172;375 0 1 acaeb3;1 1 1 b7babf;12 1 1 b4b7bb;13 1 1 bdc0c5;33 1 1 b4b7bb;34 1 1 bdc0c4;183 1 1 b5b8bc;184 1 1 bcbfc3;253 1 1 b6b8bd;254 1 1 bcbec3;303 1 1 b6b9bd;304 1 1 bbbec2;353 1 1 b7b9be;354 1 1 bbbdc2;418 1 1 b7babe;419 1 1 babdc1;483 1 1 b8babf;484 1 1 babcc1;563 1 1 b8bbbf;564 1 1 b9bcc0;1 20 1 eff0f1;2 20 1 ffffff 10;12 20 1 e8e8e8;13 20 1 f5f5f5;33 20 1 e4e4e4;34 20 1 f4f4f4;183 20 1 e6e6e6;184 20 1 f2f2f2;253 20 1 e7e7e7;254 20 1 f1f1f1;303 20 1 e8e8e8;304 20 1 f0f0f0;353 20 1 e8e8e8;354 20 1 f0f0f0;418 20 1 e9e9e9;419 20 1 efefef;483 20 1 eaeaea;484 20 1 eeeeee;563 20 1 ebebeb;564 20 1 ededed;1 217 1 c1c1c2;2 217 1 cacaca 65;67 217 1 cecece;107 217 1 cbcbcb;108 217 1 cacaca 105;213 217 1 cecece;1 241 1 c1c3c7;67 241 1 d2d4d7;68 241 1 d4d6d9 39;107 241 1 ccced1" }
    if k == 1usize { ret "202 0 1 9b9ea2;203 0 1 919498 172;375 0 1 acaeb3;1 1 1 b7babf;12 1 1 b4b7bb;13 1 1 bdc0c5;33 1 1 b4b7bb;34 1 1 bdc0c4;183 1 1 b5b8bc;184 1 1 bcbfc3;253 1 1 b6b8bd;254 1 1 bcbec3;303 1 1 b6b9bd;304 1 1 bbbec2;353 1 1 b7b9be;354 1 1 bbbdc2;418 1 1 b7babe;419 1 1 babdc1;483 1 1 b8babf;484 1 1 babcc1;563 1 1 b8bbbf;564 1 1 b9bcc0;1 20 1 eff0f1;2 20 1 ffffff 10;12 20 1 e8e8e8;13 20 1 f5f5f5;33 20 1 e4e4e4;34 20 1 f4f4f4;183 20 1 e6e6e6;184 20 1 f2f2f2;253 20 1 e7e7e7;254 20 1 f1f1f1;303 20 1 e8e8e8;304 20 1 f0f0f0;353 20 1 e8e8e8;354 20 1 f0f0f0;418 20 1 e9e9e9;419 20 1 efefef;483 20 1 eaeaea;484 20 1 eeeeee;563 20 1 ebebeb;564 20 1 ededed;1 217 1 c1c1c2;2 217 1 cacaca 65;67 217 1 cecece;107 217 1 cbcbcb;108 217 1 cacaca 105;213 217 1 cecece;1 241 1 c1c3c7;67 241 1 d2d4d7;68 241 1 d4d6d9 39;107 241 1 ccced1" }
    if k == 2usize { ret "202 0 1 9b9ea2;203 0 1 919498 172;375 0 1 acaeb3;1 1 1 b7babf;12 1 1 b4b7bb;13 1 1 bdc0c5;33 1 1 b4b7bb;34 1 1 adb7c2;35 1 1 acb8c3 149;184 1 1 bbbfc6;253 1 1 b6b8bd;254 1 1 bcbec3;303 1 1 b6b9bd;304 1 1 bbbec2;353 1 1 b7b9be;354 1 1 bbbdc2;418 1 1 b7babe;419 1 1 babdc1;483 1 1 b8babf;484 1 1 babcc1;563 1 1 b8bbbf;564 1 1 b9bcc0;1 20 1 eff0f1;2 20 1 ffffff 10;12 20 1 e8e8e8;13 20 1 f5f5f5;33 20 1 e4e4e4;34 20 1 e3ebf1;35 20 1 e3edf4 148;183 20 1 dde6ed;184 20 1 f1f3f5;253 20 1 e7e7e7;254 20 1 f1f1f1;303 20 1 e8e8e8;304 20 1 f0f0f0;353 20 1 e8e8e8;354 20 1 f0f0f0;418 20 1 e9e9e9;419 20 1 efefef;483 20 1 eaeaea;484 20 1 eeeeee;563 20 1 ebebeb;564 20 1 ededed;1 217 1 c1c1c2;2 217 1 cacaca 65;67 217 1 cecece;107 217 1 cbcbcb;108 217 1 cacaca 105;213 217 1 cecece;1 241 1 c1c3c7;67 241 1 d2d4d7;68 241 1 d4d6d9 39;107 241 1 ccced1" }
    if k == 3usize { ret "202 0 1 9b9ea2;203 0 1 919498 172;375 0 1 acaeb3;1 1 1 b7babf;12 1 1 b4b7bb;13 1 1 bdc0c5;33 1 1 b4b7bb;34 1 1 bdc0c4;183 1 1 b5b8bc;184 1 1 bcbfc3;253 1 1 b6b8bd;254 1 1 bcbec3;303 1 1 b6b9bd;304 1 1 bbbec2;353 1 1 b7b9be;354 1 1 bbbdc2;418 1 1 b7babe;419 1 1 babdc1;483 1 1 b8babf;484 1 1 babcc1;563 1 1 b8bbbf;564 1 1 b9bcc0;1 20 1 eff0f1;2 20 1 ffffff 10;12 20 1 e8e8e8;13 20 1 f5f5f5;33 20 1 e4e4e4;34 20 1 f4f4f4;183 20 1 e6e6e6;184 20 1 f2f2f2;253 20 1 e7e7e7;254 20 1 f1f1f1;303 20 1 e8e8e8;304 20 1 f0f0f0;353 20 1 e8e8e8;354 20 1 f0f0f0;418 20 1 e9e9e9;419 20 1 efefef;483 20 1 eaeaea;484 20 1 eeeeee;563 20 1 ebebeb;564 20 1 ededed;1 217 1 c1c1c2;2 217 1 cacaca 65;67 217 1 cecece;107 217 1 cbcbcb;108 217 1 cacaca 105;213 217 1 cecece;1 241 1 c1c3c7;67 241 1 d2d4d7;68 241 1 d4d6d9 39;107 241 1 ccced1" }
    if k == 4usize { ret "202 0 1 9b9ea2;203 0 1 919498 172;375 0 1 acaeb3;1 1 1 b7babf;12 1 1 b4b7bb;13 1 1 bdc0c5;33 1 1 b4b7bb;34 1 1 bdc0c4;183 1 1 b5b8bc;184 1 1 bcbfc3;253 1 1 b6b8bd;254 1 1 bcbec3;303 1 1 b6b9bd;304 1 1 bbbec2;353 1 1 b7b9be;354 1 1 bbbdc2;418 1 1 b7babe;419 1 1 babdc1;483 1 1 b8babf;484 1 1 babcc1;563 1 1 b8bbbf;564 1 1 b9bcc0;1 20 1 eff0f1;2 20 1 ffffff 10;12 20 1 e8e8e8;13 20 1 f5f5f5;33 20 1 e4e4e4;34 20 1 f4f4f4;183 20 1 e6e6e6;184 20 1 f2f2f2;253 20 1 e7e7e7;254 20 1 f1f1f1;303 20 1 e8e8e8;304 20 1 f0f0f0;353 20 1 e8e8e8;354 20 1 f0f0f0;418 20 1 e9e9e9;419 20 1 efefef;483 20 1 eaeaea;484 20 1 eeeeee;563 20 1 ebebeb;564 20 1 ededed;1 217 1 c1c1c2;2 217 1 cacaca 65;67 217 1 cecece;107 217 1 cbcbcb;108 217 1 cacaca 105;213 217 1 cecece;1 241 1 c1c3c7;67 241 1 d2d4d7;68 241 1 d4d6d9 39;107 241 1 ccced1" }
    ret ""
}
// END GENERATED
