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
    coll_view: view.View,
    coll_group: grp.Grouping,
    scratch: mem.Arena,
    store: mem.Arena,
    coll_grid: dg.Grid
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

fn coll_specs(a: *mem.Arena) -> ([]dg.ColumnSpec, err) {
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
    let (cv, cv_error) = view.create(a, &m.coll)
    if cv_error != ok { ret cv_error }
    m.coll_view = cv
    let (cg, cg_error) = grp.create(a, &m.coll_view, 8usize)
    if cg_error != ok { ret cg_error }
    m.coll_group = cg
    var none: [1]grp.GroupLevel = zero
    var order: [1]view.Key = zero
    order[0usize] = view.column_key(CC_QTY, false, true)
    try grp.group_by(&m.coll_group, none[0usize..0usize], order[0usize..0usize], &m.scratch)
    var sums: [3]grp.SummarySpec = zero
    sums[0usize] = grp.SummarySpec { column: CC_QTY }
    sums[1usize] = grp.SummarySpec { column: CC_USED }
    sums[2usize] = grp.SummarySpec { column: CC_BUY }
    try grp.apply_summaries(&m.coll_group, sums[0usize..3usize], &m.store)
    let (cs, cs_error) = coll_specs(a)
    if cs_error != ok { ret cs_error }
    var events = dg.no_events()
    events.custom_cell = coll_cell
    let (g2, g2_error) = dg.create(a, &m.coll, &m.coll_group, cs, events, 20000u64)
    if g2_error != ok { ret g2_error }
    m.coll_grid = g2
    var look = gl.v3()
    look.footer_band = gl.rgb(0xC0DCC0u32)
    look.ring_top_o = gl.rgb(0xBABDC1u32)
    look.ring_top_i = gl.rgb(0xBFC2C6u32)
    look.ring_left_o = gl.rgb(0x878B93u32)
    look.ring_left_i = gl.rgb(0xEAEAECu32)
    look.ring_bottom = gl.rgb(0xCACCCFu32)
    dg.set_look(&m.coll_grid, look)
    dg.set_row_ink(&m.coll_grid, mem.cast[*void](m), coll_ink)
    dg.set_footer_label(&m.coll_grid, "Rows")
    dg.set_grid_lines(&m.coll_grid, dg.GridLines.Both)
    dg.set_immediate_edit(&m.coll_grid, true)
    dg.show_navigator(&m.coll_grid, true)
    dg.set_pane_hint(&m.coll_grid, 573.0)
    dg.show_sort(&m.coll_grid, 1usize, true)
    m.coll_grid.aligns[3usize] = 2u8
    m.coll_grid.aligns[4usize] = 2u8
    m.coll_grid.aligns[5usize] = 2u8
    // the third row (Tangle) is current and selected, the grid has the focus
    m.coll_grid.has_selection = true
    m.coll_grid.selected_row = 2usize
    m.coll_grid.has_position = true
    m.coll_grid.position = 2usize
    dg.set_forced_focus(&m.coll_grid, true)
    ret ok
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let m = mem.cast[*Bottom](ctx)
    if m.ready && m.windows != (t.tokens.profile == .Windows) { m.ready = false }
    if !m.ready {
        m.windows = t.tokens.profile == .Windows
        try setup(m)
        m.ready = true
    }
    let (body, body_error) = dg.build(a, &m.coll_grid, t, 267.0)
    if body_error != ok { ret (0usize, body_error) }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (0usize, held_error) }
    held[0usize] = body
    var face = looks.size_style(576.0, 242.0)
    face.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    cells[0usize] = looks.Cell { caption: "Collection grid: Tangle selected, grid focused", node: widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, face, held[0usize..1usize]), drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (bottoms, bottoms_error) = mem.alloc[Bottom](a, 1usize)
    if bottoms_error != ok { ret bottoms_error }
    var seed: Bottom = zero
    seed.a = a
    bottoms[0usize] = seed
    let sheet = looks.Sheet { name: "data_grid_bottom", cells: 1usize, columns: 1usize, cell_w: 576.0, cell_h: 242.0, ctx: mem.cast[*void](&bottoms[0usize]), build: build }
    ret looks.run_all(a, &sheet)
}
