// A data grid view over an `e.data.table` and its `e.data.tablegroup` (docs/grid.md 5.5):
// column header with sort indicator, a virtual body that builds only the visible rows,
// group rows (expand or collapse on a tap, with the group's summaries under their columns),
// a footer of summaries, and a no-data text. It has no sorting, filtering or grouping logic
// of its own: a header tap is reported as an event and the application sorts or groups
// through `e.data.tableview` / `e.data.tablegroup`, then builds the grid again.
//
// Cells are drawn from typed values by kind (text, integer, real, currency, boolean) with a
// text node per visible cell; nothing is created for rows out of view.
//
// Keys. The grid owns the widget keys from `key` to `key + 4096 + rows + groups + 1`: the table
// is `key` (its header cells use the keys just above it), a data row is `key + 4096 + storage
// row`, a group row `key + 4096 + row capacity + group`, the footer `key + 4096 + row capacity +
// group capacity`.
//
// Custom cells. A column of kind `Custom` asks the application for the cell's node (a mana
// cost, a legality badge, a foil mark: boxes and text composed there), and `row_role` colours
// the text of a row (colour by rarity). Filter row: a row of small text fields, one per
// column that asks for one, above the header; each change is the `filter_changed` event (the
// application builds and applies the filter, as for a sort).
//
// Bands. `set_bands` puts a row of titled spans above the filter row and the header, each over a
// run of columns (non-interactive). Row indicator: a column of kind `Indicator` shows `>` at the
// grid's current row. Navigator: `show_navigator` adds First / Prev / Next / Last buttons and
// "Row n of m" under the footer; they move the current data row (groups are skipped) and scroll
// it into view; `navigate` is the same from code.
//
// Editing. A column with `editable` set can be edited in place: a tap on the already current row
// (or `begin_edit`) replaces that cell by a text field holding the cell's text; Enter commits
// (parsed by the column's kind, written to the table through its typed setters, an empty text
// is a null, a text that does not parse keeps the editor open and marked invalid), and the
// application hears `cell_edited` (storage row, spec) to re-sort, re-filter or re-group.
// Layout. Column widths follow a header resize; `save_layout` / `load_layout` keep the widths,
// the sort indicator, the filter row, the navigator and the filter texts as small text.
//
// Preview row. `show_preview(spec)` turns on a disclosure at the start of each data row; opening
// it adds, under the record, the text of one column wrapped over several lines (a card's rules
// text). Up to 32 previews are open at once.
//
// Kinds of editor. A boolean cell has no editor: a tap on the current row (or `begin_edit`) flips
// it. A column with `choice` set and a small dictionary edits through a select of the
// dictionary's values; the others edit as text. `can_edit` locks cells (a row, a column), and
// `value_changed` carries the old and the new text; between `begin_batch` and `end_batch` the
// events are held back and one `batch_done` (with the number of cells) is raised at the end.
//
// Tab. While a cell is edited, Tab commits and edits the next editable cell of the row (Shift+Tab
// the previous one); past the last one it goes to the first editable cell of the next data row.
// Escape cancels the edit.
//
// Columns. `set_hidden` and `move_column` (and a header drag) change which columns show and in
// which order; every spec index the application sees (events, `begin_edit`, `show_sort`, widths,
// filter texts, layout) is the index in the list given to `create`, never a display position.
//
// Conditional formatting. `set_rules` attaches an `e.ui.gridrules` rule set: each data cell asks
// it for a look (ink role, fill, bold, a data bar behind the text, an icon glyph before it) by
// the column's table column and the storage row. The application calls `rules.refresh` after
// the table changes. A rule's ink replaces `row_role`'s for that cell.
//
// ponytail: one level of header and the filter row sits above it (the table owns the header).

use e.mem
use e.str
use e.time
use e.data.table as table
use e.data.tablegroup as grp
use e.ui.collection
use e.fmt.xlsx as xlsx
use e.fmt.xlsx.book as book
use e.fmt.pdf.write as pdfw
use e.ui.control
use e.ui.gridrules as rules
use e.ui.gridlook as gl
use e.ui.input
use e.gfx.paint
use e.gfx.geometry
use e.gfx.scene
use e.ui.layout as ui_layout
use e.ui.overlay
use e.ui.style
use e.ui.widget

const FILTER_TEXT: usize = 40usize
const FILTER_KEY: u64 = 2048u64
const EDIT_KEY: u64 = 3000u64
const EDIT_TEXT: usize = 64usize
const KEYBOARD_KEY: u64 = 3200u64
// keys far from every row, header and filter key (rows run to 4096 + the table's capacity)
const GROUP_BOX_KEY: u64 = 1073741824u64

type CellKind = enum u8 { Text, Int, Real, Currency, Bool, Custom, Indicator, Star, Picture }

// A titled span over `count` columns from spec `first`.
type Band = struct { title: str, first: usize, count: usize }

// v3's Show Grid Lines: the lines between cells (vertical), between rows (horizontal), both or none.
type GridLines = enum u8 { Vertical, Horizontal, Both, None }

type Nav = enum u8 { First, Prev, Next, Last, PrevPage, NextPage }

// One grid column: the table column it shows and how, and which applied group summary it
// shows on group rows and in the footer (`summary` < 0: none); `filter` asks for a field in the
// filter row.
type ColumnSpec = struct { title: str, width: f32, column: usize, kind: CellKind, decimals: u8, summary: i32, summary_kind: grp.SummaryKind, filter: bool, editable: bool, choice: bool }

type Events = struct {
    ctx: *void,
    sort_changed: fn(*void, usize, bool) -> err,
    row_picked: fn(*void, usize) -> err,
    filter_changed: fn(*void, usize, str) -> err,
    cell_edited: fn(*void, usize, usize) -> err,
    value_changed: fn(*void, usize, usize, str, str) -> err,
    can_edit: fn(*void, usize, usize) -> bool,
    batch_done: fn(*void, usize) -> err,
    custom_cell: fn(*void, *mem.Arena, *const control.Theme, usize, usize, *widget.Node) -> err,
    row_role: fn(*void, usize) -> style.ColorRole
}

type Grid = struct {
    t: *table.Table,
    g: *grp.Grouping,
    specs: []const ColumnSpec,
    columns: []collection.Column,
    all: []const ColumnSpec,
    display: []ColumnSpec,
    column_store: []collection.Column,
    origin: []usize,
    order: []usize,
    hidden: []bool,
    widths: []f32,
    events: Events,
    key: widget.Key,
    empty_text: str,
    sort_column: usize,
    descending: bool,
    extra_sort: [4]usize,
    extra_desc: [4]bool,
    extra_count: usize,
    sort_dialog_open: bool,
    win_x: [4]f32,
    win_y: [4]f32,
    win_gx: [4]f32,
    win_gy: [4]f32,
    win_placed: [4]bool,
    win_rank: [4]u8,
    win_top: u8,
    has_row_drop: bool,
    row_drop_ctx: *void,
    row_drop_fn: fn(*void, usize) -> err,
    rules_dialog_open: bool,
    wiz_open: bool,
fmt_open: bool,
print_open: bool,
chooser_bands: bool,
band_tabs: bool,
filter_off: bool,
pv_design: bool,
dz_tab: u8,
sw_open: u8,
sw_tab: u8,
sw_page: u8,
dz_checks: u64,
dz_ready: bool,
dz_style: u8,
dz_dirty: bool,
dz_dlg: u8,
dz_title: [48]u8,
dz_title_len: usize,
dz_title_set: bool,
dz_foot: [48]u8,
dz_foot_len: usize,
dz_pick_color: u32,
dz_custom: [16]u32,
dz_custom_n: usize,
dz_style_rgb: [13]u32,
dz_style_has: u16,
dz_modes: [2]u8,
pv_tenths: [6]u8,
pv_hund: [6]u8,
pv_wide: u8,
pv_tall: u8,
pv_cell: [144]u8,
pv_cell_len: [6]u8,
pv_cell_touched: u8,
pv_page: usize,
pv_zoom: u8,
pv_setup: bool,
pv_tab: u8,
pv_center: u8,
pv_fit: bool,
pv_percent: u8,
pv_reverse: bool,
pv_paper: u8,
pv_orient: u8,
pv_order: u8,
band_names: []const str,
wiz_pos_color: u8,
wiz_neg_color: u8,
wiz_axis_color: u8,
fmt_pick: u8,
cust_rgb: u32,
    rules_changed: bool,
    wiz_bar_only: bool,
    wiz_min_number: bool,
    wiz_select_open: bool,
    wiz_palette: u8,
    wiz_bar_style: u8,
    wiz_target: usize,
    has_wiz_target: bool,
    wiz_max_number: bool,
    wiz_min_pct: bool,
    wiz_max_pct: bool,
    wiz_min_ptile: bool,
    wiz_max_ptile: bool,
    wiz_min_text: [16]u8,
    wiz_min_len: usize,
    wiz_max_text: [16]u8,
    wiz_max_len: usize,
    base_look: gl.Look,
    wiz_edit: bool,
    wiz_column: usize,
    has_wiz_column: bool,
    head_spec: usize,
    wiz_type: u8,
    rules_arena: *mem.Arena,
    crit_open: bool,
    crit_pop: bool,
    crit_io: u8,
    crit_pop_kind: u8,
    crit_pop_row: usize,
    crit_pending: bool,
    crit_group: u8,
    crit_sub: [6]bool,
    crit_sub_group: u8,
    crit_count: usize,
    crit_spec: [6]usize,
    crit_op: [6]u8,
    crit_len: [6]usize,
    crit_text: [192]u8,
    rules_selected: usize,
    sort_marks: [24]u8,
    hint_key: widget.Key,
    hint_since: i64,
    also_marks: []u8,
    has_selection: bool,
    selected_row: usize,
    offset: f32,
    row_height: f32,
    footer_visible: bool,
    filter_visible: bool,
    bands: []const Band,
    navigator_visible: bool,
    group_box_visible: bool,
    immediate_edit: bool,
    enter_action: u8,
    focus_column: usize,
    edit_focus_pending: bool,
    multi: bool,
    quick_sorted: bool,
    flat_left: f32,
    flat_top: f32,
    flat_width: f32,
    aligns: []u8,
    right_flags: []bool,
    center_flags: []bool,
    menu_cursor: usize,
    menu_count: usize,
    menu_enabled: [40]bool,
    menu_actions: [40]widget.Submit,
    app_menu: []const overlay.MenuCommand,
    app_menu_x: f32,
    app_menu_y: f32,
    hints: []const str,
    footer_label: str,
    quick_x: f32,
    quick_y: f32,
    header_icons: [9]scene.TextureId,
    has_header_icons: bool,
    align_icons: [3]scene.TextureId,
    parent_drawn: bool,
    has_align_icons: bool,
    filter_op_icons: [12]scene.TextureId,
    has_filter_op_icons: bool,
    hoff: f32,
    bar_shift: f32,
    hgrab: f32,
    hon: bool,
    hcontent: f32,
    hpane: f32,
    pane_hint: f32,
    count_spec: usize,
    force_focus: bool,
    cell_select: usize,
    bar_on: bool,
    nav_icons: [7]scene.TextureId,
    nav_disabled: [6]scene.TextureId,
    has_nav_icons: bool,
    cell_menu: []const overlay.MenuCommand,
    menu_open: bool,
    menu_kind: u8,
    menu_spec: usize,
    command: u8,
    command_spec: usize,
    chooser_open: bool,
    chooser_x: f32,
    chooser_y: f32,
    chooser_placed: bool,
    chooser_active: bool,
    chooser_grab_x: f32,
    chooser_grab_y: f32,
    fit_all_pending: bool,
    search_spec: usize,
    has_search: bool,
    search_within: bool,
    search_buf: []u8,
    search_len: usize,
    bookmark_row: usize,
    has_bookmark: bool,
    lines: GridLines,
    header_off: bool,
    auto_width: bool,
    auto_total: f32,
    group_drop_spec: usize,
    group_drop_pending: bool,
    editors: []u8,
    button_row: usize,
    button_spec: usize,
    button_clicked: bool,
    button_action: widget.Submit,
    has_button_action: bool,
    marks: []u8,
    marked: usize,
    anchor: usize,
    has_anchor: bool,
    edit_caret_frames: usize,
    edit_click_x: f32,
    rest_row: usize,
    rest_spec: usize,
    rest_pending: bool,
    ink_ctx: *void,
    ink_of: fn(*void, usize) -> (paint.Color, bool),
    has_ink: bool,
    fit_spec: usize,
    fit_pending: bool,
    page_rows: usize,
    filter_action: widget.Submit,
    has_filter_action: bool,
    has_position: bool,
    position: usize,
    read_only: bool,
    preview_on: bool,
    preview_spec: usize,
    preview_open: [32]u64,
    preview_count: usize,
    editing: bool,
    edit_row: usize,
    edit_spec: usize,
    edit_text: [64]u8,
    edit_scratch: [160]u8,
    edit_len: usize,
    edit_invalid: bool,
    edit_old: [64]u8,
    edit_old_len: usize,
    select_open: bool,
    batch_depth: usize,
    batch_count: usize,
    look: gl.Look,
    rule_set: *rules.Rules,
    has_rules: bool,
    filter_text: []u8,
    filter_lens: []usize,
    filter_ops: []u8,
    filter_pop: usize,
    theme: *const control.Theme
}

error TooManyColumns
error NotEditable
error Locked
error BadLayout

fn ignore_sort(ctx: *void, column: usize, descending: bool) -> err { ret ok }

fn ignore_row(ctx: *void, row: usize) -> err { ret ok }

fn ignore_filter(ctx: *void, spec: usize, text: str) -> err { ret ok }

fn ignore_edit(ctx: *void, row: usize, spec: usize) -> err { ret ok }

fn ignore_value(ctx: *void, row: usize, spec: usize, old: str, new: str) -> err { ret ok }

fn allow_edit(ctx: *void, row: usize, spec: usize) -> bool { ret true }

fn ignore_batch(ctx: *void, count: usize) -> err { ret ok }

fn no_custom_cell(ctx: *void, a: *mem.Arena, t: *const control.Theme, row: usize, spec: usize, out: *widget.Node) -> err { ret ok }

fn plain_role(ctx: *void, row: usize) -> style.ColorRole { ret .Text }

// Events that do nothing, for a grid that only displays.
fn no_events() -> Events {
    ret Events { ctx: nil, sort_changed: ignore_sort, row_picked: ignore_row, filter_changed: ignore_filter, cell_edited: ignore_edit, value_changed: ignore_value, can_edit: allow_edit, batch_done: ignore_batch, custom_cell: no_custom_cell, row_role: plain_role }
}

fn create(a: *mem.Arena, t: *table.Table, g: *grp.Grouping, specs: []const ColumnSpec, events: Events, key: widget.Key) -> (Grid, err) {
    var grid: Grid = zero
    grid.t = t
    grid.g = g
    grid.all = specs
    grid.events = events
    grid.key = key
    grid.empty_text = "No data to display"
    grid.sort_column = specs.len
    grid.row_height = 28.0
    grid.footer_visible = true
    if specs.len != 0usize {
        let (display, display_error) = mem.alloc[ColumnSpec](a, specs.len)
        if display_error != ok { ret (grid, display_error) }
        grid.display = display
        let (store, store_error) = mem.alloc[collection.Column](a, specs.len)
        if store_error != ok { ret (grid, store_error) }
        grid.column_store = store
        let (origin, origin_error) = mem.alloc[usize](a, specs.len)
        if origin_error != ok { ret (grid, origin_error) }
        grid.origin = origin
        let (order, order_error) = mem.alloc[usize](a, specs.len)
        if order_error != ok { ret (grid, order_error) }
        grid.order = order
        let (hidden, hidden_error) = mem.alloc[bool](a, specs.len)
        if hidden_error != ok { ret (grid, hidden_error) }
        grid.hidden = hidden
        let (widths, widths_error) = mem.alloc[f32](a, specs.len)
        if widths_error != ok { ret (grid, widths_error) }
        grid.widths = widths
        let (text, text_error) = mem.alloc[u8](a, specs.len * FILTER_TEXT)
        if text_error != ok { ret (grid, text_error) }
        grid.filter_text = text
        let (lens, lens_error) = mem.alloc[usize](a, specs.len)
        if lens_error != ok { ret (grid, lens_error) }
        var at = 0usize
        while at < specs.len {
            grid.order[at] = at
            grid.hidden[at] = false
            grid.widths[at] = specs[at].width
            lens[at] = 0usize
            at += 1usize
        }
        grid.filter_lens = lens
        let (ops, ops_error) = mem.alloc[u8](a, specs.len)
        if ops_error != ok { ret (grid, ops_error) }
        var op_at = 0usize
        while op_at < specs.len {
            ops[op_at] = 0u8
            op_at += 1usize
        }
        grid.filter_ops = ops
    }
    let (marks, marks_error) = mem.alloc[u8](a, (table.capacity(t) + 7usize) / 8usize)
    if marks_error != ok { ret (zero, marks_error) }
    var cleared = 0usize
    while cleared < marks.len {
        marks[cleared] = 0u8
        cleared += 1usize
    }
    grid.marks = marks
    let (search_buf, search_buf_error) = mem.alloc[u8](a, 64usize)
    if search_buf_error != ok { ret (zero, search_buf_error) }
    grid.search_buf = search_buf
    let (aligns, aligns_error) = mem.alloc[u8](a, specs.len + 1usize)
    if aligns_error != ok { ret (zero, aligns_error) }
    let (rights, rights_error) = mem.alloc[bool](a, specs.len + 1usize)
    if rights_error != ok { ret (zero, rights_error) }
    let (centers, centers_error) = mem.alloc[bool](a, specs.len + 1usize)
    if centers_error != ok { ret (zero, centers_error) }
    var align_at = 0usize
    while align_at < aligns.len {
        aligns[align_at] = 0u8
        rights[align_at] = false
        centers[align_at] = false
        align_at += 1usize
    }
    grid.aligns = aligns
    grid.right_flags = rights
    let (also_buf, also_error) = mem.alloc[u8](a, specs.len + 1usize)
    if also_error != ok { ret (zero, also_error) }
    var mark_at = 0usize
    while mark_at < also_buf.len {
        also_buf[mark_at] = 0u8
        mark_at += 1usize
    }
    grid.also_marks = also_buf
    grid.center_flags = centers
    let (editors, editors_error) = mem.alloc[u8](a, specs.len + 1usize)
    if editors_error != ok { ret (zero, editors_error) }
    var edit_at = 0usize
    while edit_at < editors.len {
        editors[edit_at] = 0u8
        edit_at += 1usize
    }
    grid.editors = editors
    relayout(&grid)
    ret (grid, ok)
}

// Rebuilds the displayed columns (specs, widths, headers) from the order, the hidden flags and
// the widths. An edit in progress is cancelled: its column may have moved.
fn relayout(grid: *Grid) {
    var n = 0usize
    var k = 0usize
    while k < grid.order.len {
        let o = grid.order[k]
        if !grid.hidden[o] {
            grid.display[n] = grid.all[o]
            grid.origin[n] = o
            grid.column_store[n] = collection.Column { title: grid.all[o].title, width: grid.widths[o] }
            n += 1usize
        }
        k += 1usize
    }
    // the disclosure of a preview leads the first cell and needs room
    if grid.preview_on && n > 0usize && grid.column_store[0usize].width < 64.0 { grid.column_store[0usize].width = 64.0 }
    if grid.auto_width && grid.auto_total > 0.0 && n > 0usize {
        var sum: f32 = 0.0
        var s = 0usize
        while s < n {
            sum += grid.column_store[s].width
            s += 1usize
        }
        if sum > 0.0 {
            let factor = grid.auto_total / sum
            s = 0usize
            while s < n {
                var scaled = grid.column_store[s].width * factor
                if scaled < 24.0 { scaled = 24.0 }
                grid.column_store[s].width = scaled
                s += 1usize
            }
        }
    }
    grid.specs = grid.display[0usize..n]
    grid.columns = grid.column_store[0usize..n]
    grid.editing = false
    grid.edit_invalid = false
}

// The display position of spec `spec` (its index in the list given to `create`), if it shows.
fn display_of(grid: *const Grid, spec: usize) -> (usize, bool) {
    var at = 0usize
    while at < grid.specs.len {
        if grid.origin[at] == spec { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// Shows or hides a column.
// Attaches (or with `nil` detaches) a conditional formatting rule set.
fn set_rules(grid: *Grid, set: *rules.Rules) {
    grid.rule_set = set
    grid.has_rules = true
}

fn clear_rules(grid: *Grid) { grid.has_rules = false }

// The look of the grid (`e.ui.gridlook`): row and header heights, text size, colours; the
// theme's own look when `look.on` is false.
fn set_look(grid: *Grid, look: gl.Look) {
    grid.look = look
    grid.base_look = look
    if look.on { grid.row_height = look.row_height }
}

// Options > Grids > Font Size of v3 (Small 7, Medium 8, Large 10, Extra Large 12 points): the text
// size and the heights of the measured look follow, from the Medium (8 point) look given to `set_look`.
fn set_font_size(grid: *Grid, points: f32) {
    if !grid.base_look.on { ret }
    // measured in v3 (FS1-font-size-xl-v3.png): at Extra Large (12 pt) the cells and footers use
    // 1.5 times the text, a row is 40.5 px against 28.5, the headers and their height stay
    let factor = points / 8.0
    var look = grid.base_look
    look.text_size = grid.base_look.text_size * factor
    look.row_height = grid.base_look.row_height + 3.0 * (points - 8.0)
    grid.look = look
    grid.row_height = look.row_height
    relayout(grid)
}

// The group box above the header: a chip for each grouping level (the field and its sort
// triangle), as in v3.
// The ink of a row's text as a colour (v3 draws a card's row in the card's own colour): `ink` answers
// the storage row's colour, and false for the theme's text.
fn set_row_ink(grid: *Grid, ctx: *void, ink: fn(*void, usize) -> (paint.Color, bool)) {
    grid.ink_ctx = ctx
    grid.ink_of = ink
    grid.has_ink = true
}

// v3's collection grid edits at once: a click on a row makes it current and opens its first
// editable cell (without this the second tap on the current row does).
fn set_immediate_edit(grid: *Grid, on: bool) { grid.immediate_edit = on }

// looks4-e: the width the horizontal scroll bar's pane has before the first frame measured it (the looks sheets draw one frame).
fn set_pane_hint(grid: *Grid, width: f32) { grid.pane_hint = width }

// looks4-e: the column whose footer cell holds the count (v3 lets the grid's designer choose; the default is the first text column).
fn set_count_column(grid: *Grid, spec: usize) { grid.count_spec = spec + 1usize }

// looks4-e: draw the selected row as a focused grid's (the looks sheets cannot put the keyboard focus on a chosen row).
fn set_forced_focus(grid: *Grid, on: bool) { grid.force_focus = on }

// looks4-e: select cells, not rows: only column `spec`'s cell of the selected row is filled and framed (v3's Sort dialog).
fn set_cell_select(grid: *Grid, spec: usize) { grid.cell_select = spec + 1usize }

fn show_group_box(grid: *Grid, on: bool) { grid.group_box_visible = on }

// v3's View > Show Summary Footer.
fn show_footer(grid: *Grid, on: bool) { grid.footer_visible = on }

// v3's View > Full Expand and Full Collapse: every group open or closed.
fn set_all_groups(grid: *Grid, open: bool) {
    var group = 0usize
    while group < grp.group_len(grid.g) {
        let changed = grp.set_expanded(grid.g, group, open)
        group += 1usize
    }
}

// v3's View > Best Fit (all columns).
fn best_fit_all(a: *mem.Arena, grid: *Grid) -> err {
    var spec = 0usize
    while spec < grid.all.len {
        try best_fit(a, grid, spec)
        spec += 1usize
    }
    ret ok
}

// The navigator's funnel button calls `action` (v3 opens its filter dialog from it).
fn set_filter_action(grid: *Grid, action: widget.Submit) {
    grid.filter_action = action
    grid.has_filter_action = true
}

fn set_hidden(grid: *Grid, spec: usize, hide: bool) {
    if spec >= grid.all.len { ret }
    grid.hidden[spec] = hide
    relayout(grid)
}

fn is_hidden(grid: *const Grid, spec: usize) -> bool { ret spec >= grid.all.len || grid.hidden[spec] }

// Moves column `spec` so that it stands where display position `to` is now (at the end when
// `to` is past the last column).
fn move_column(grid: *Grid, spec: usize, to: usize) {
    if spec >= grid.all.len { ret }
    var before = grid.all.len
    var have_before = false
    if to < grid.specs.len {
        before = grid.origin[to]
        have_before = true
    }
    if have_before && before == spec { ret }
    // take the column out of the order
    var k = 0usize
    while k < grid.order.len && grid.order[k] != spec { k += 1usize }
    if k >= grid.order.len { ret }
    while k + 1usize < grid.order.len {
        grid.order[k] = grid.order[k + 1usize]
        k += 1usize
    }
    // and put it back in front of `before`
    var at = 0usize
    if have_before {
        while at + 1usize < grid.order.len && grid.order[at] != before { at += 1usize }
    } else {
        at = grid.order.len - 1usize
    }
    var j = grid.order.len - 1usize
    while j > at {
        grid.order[j] = grid.order[j - 1usize]
        j -= 1usize
    }
    grid.order[at] = spec
    relayout(grid)
}

// The header's sort indicator (not the sort itself): a spec index, or `specs.len` for none.
fn show_sort(grid: *Grid, spec: usize, descending: bool) {
    grid.sort_column = spec
    grid.descending = descending
}

// v3's View > Clear Sort Order: the marks go and the application hears the command
// (`take_command`, CMD_CLEAR_SORT) to restore its order.
fn clear_sort(grid: *Grid) {
    grid.sort_column = grid.all.len
    grid.extra_count = 0usize
    grid.command = CMD_CLEAR_SORT
    grid.command_spec = 0usize
}

// A column's in-cell editor (v3's cxSpinEdit and cxButtonEdit): the text field, a spin editor
// with a step arrow either side of the number, or a field with a three-dots button at its end.
const EDITOR_TEXT: u8 = 0u8
const EDITOR_SPIN: u8 = 1u8
const EDITOR_BUTTON: u8 = 2u8

fn set_editor(grid: *Grid, spec: usize, kind: u8) {
    if spec < grid.editors.len { grid.editors[spec] = kind }
}

// What the application runs when the three-dots button of a cell is pressed; `button_cell` then
// tells which cell (once).
fn set_button_action(grid: *Grid, action: widget.Submit) {
    grid.button_action = action
    grid.has_button_action = true
}

fn button_cell(grid: *Grid) -> (usize, usize, bool) {
    if !grid.button_clicked { ret (0usize, 0usize, false) }
    grid.button_clicked = false
    ret (grid.button_row, grid.button_spec, true)
}

fn on_cell_button(ctx: *void) -> err {
    let grid = mem.cast[*Grid](ctx)
    if !grid.editing { ret ok }
    grid.button_row = grid.edit_row
    grid.button_spec = grid.origin[grid.edit_spec]
    grid.button_clicked = true
    if grid.has_button_action { ret grid.button_action.invoke(grid.button_action.ctx) }
    ret ok
}

// The spin editor's arrows step the number being edited by one.
fn spin_by(grid: *Grid, delta: i64) {
    var value: i64 = 0
    var at = 0usize
    var negative = false
    if grid.edit_len > 0usize && grid.edit_text[0usize] == 45u8 {
        negative = true
        at = 1usize
    }
    while at < grid.edit_len {
        let c = grid.edit_text[at]
        if c >= 48u8 && c <= 57u8 { value = value * 10 + i64(c - 48u8) }
        at += 1usize
    }
    if negative { value = 0 - value }
    value += delta
    if value < 0 { value = 0 }
    var digits: [24]u8 = zero
    var n = 0usize
    var rest = value
    if rest == 0 {
        digits[0usize] = 48u8
        n = 1usize
    }
    while rest > 0 {
        digits[n] = 48u8 + u8(rest % 10)
        rest = rest / 10
        n += 1usize
    }
    var k = 0usize
    while k < n {
        grid.edit_text[k] = digits[n - 1usize - k]
        k += 1usize
    }
    grid.edit_len = n
}

fn on_spin_down(ctx: *void) -> err {
    spin_by(mem.cast[*Grid](ctx), -1)
    ret ok
}

fn on_spin_up(ctx: *void) -> err {
    spin_by(mem.cast[*Grid](ctx), 1)
    ret ok
}

// The three dots of a button editor: a flat 18 px cell button.
fn dots_button(a: *mem.Arena, grid: *Grid, key: widget.Key, action: *const widget.Submit) -> (widget.Node, err) {
    let (dots, dots_error) = mem.alloc[widget.Node](a, 1usize)
    if dots_error != ok { ret (zero, dots_error) }
    let mark_error = text_node(a, grid, "...", true, .Text, &dots[0usize])
    if mark_error != ok { ret (zero, mark_error) }
    let state = control.control_state(grid.theme, key, true, false)
    var look = style.resolve(grid.theme.tokens, .Plain, state)
    look.background = paint.rgba(0.0, 0.0, 0.0, 0.0)
    look.border_width = 1.0
    look.border = grid.look.selected_line
    look.opacity = 1.0
    look.radius = 0.0
    look.custom_padding = true
    look.padding = 1.0
    look.padding_y = 0.0
    look.min_width = 18.0
    look.min_height = 16.0
    let (node, node_error) = control.pressable_states(a, key, grid.theme, 3u8, "Choose", look, true, false, 0u32, 0u32, 0u64, action, dots[0usize])
    ret (node, node_error)
}

// A small flat step arrow of the spin editor.
fn spin_arrow(a: *mem.Arena, grid: *Grid, key: widget.Key, shape: gl.Shape, label: str, action: *const widget.Submit) -> (widget.Node, err) {
    let ink = gl.rgb(0x000000u32)
    let (mark, mark_error) = gl.mark(a, shape, ink, ink, 6.0, 9.0)
    if mark_error != ok { ret (zero, mark_error) }
    let state = control.control_state(grid.theme, key, true, false)
    var look = style.resolve(grid.theme.tokens, .Plain, state)
    look.background = paint.rgba(0.0, 0.0, 0.0, 0.0)
    look.border_width = 0.0
    look.opacity = 1.0
    look.radius = 0.0
    look.custom_padding = true
    look.padding = 2.0
    look.padding_y = 1.0
    look.min_width = 12.0
    look.min_height = 12.0
    let (node, node_error) = control.pressable_states(a, key, grid.theme, 3u8, label, look, true, false, 0u32, 0u32, 0u64, action, mark)
    ret (node, node_error)
}

// ---- incremental search and the bookmark (v3's search toolbar, Search > Next / Previous / Bookmark) ----

// Typing in the grid searches `spec`'s text: from the start of the cell (begins-with) or anywhere in
// it (`within`), case-insensitively. The current row moves to the first match from itself on and
// the view scrolls it to the top; Ctrl+Down and Ctrl+Up go to the next and the previous match
// (wrapping), Backspace shortens the text and Escape ends the search.
fn set_search_column(grid: *Grid, spec: usize, within: bool) {
    grid.search_spec = spec
    grid.has_search = spec < grid.all.len
    grid.search_within = within
    grid.search_len = 0usize
}

fn search_query(grid: *const Grid) -> str { ret grid.search_buf[0usize..grid.search_len] }

fn cancel_search(grid: *Grid) { grid.search_len = 0usize }

fn lower_ascii(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

// Whether a data row's cell text of the search column matches the typed text.
fn search_matches(grid: *const Grid, row: usize) -> bool {
    if !grid.has_search || grid.search_len == 0usize { ret false }
    let column = grid.all[grid.search_spec].column
    let kind = table.column_kind(grid.t, column)
    if kind != table.Kind.Str && kind != table.Kind.Dict { ret false }
    let text = table.get_str(grid.t, column, row)
    let n = grid.search_len
    if text.len < n { ret false }
    var start = 0usize
    while start + n <= text.len {
        var k = 0usize
        while k < n && lower_ascii(text[start + k]) == lower_ascii(grid.search_buf[k]) { k += 1usize }
        if k == n { ret true }
        if !grid.search_within { ret false }
        start += 1usize
    }
    ret false
}

// The visible position of the next (or previous) match from `from`, wrapping; `inclusive` also
// tests `from` itself.
fn search_find(grid: *const Grid, from: usize, forward: bool, inclusive: bool) -> (usize, bool) {
    let n = grp.visible_len(grid.g)
    if n == 0usize { ret (0usize, false) }
    var step = 0usize
    while step < n {
        var at = 0usize
        var offset = step
        if !inclusive { offset = step + 1usize }
        if forward {
            at = (from + offset) % n
        } else {
            at = (from + n - (offset % n)) % n
        }
        if !grp.visible_is_group(grid.g, at) && search_matches(grid, grp.visible_row(grid.g, at)) { ret (at, true) }
        step += 1usize
    }
    ret (0usize, false)
}

// Makes the match current with the view scrolled to put it at the top (v3's `TopRecordIndex`).
fn search_go(grid: *Grid, at: usize) -> err {
    let moved = go_to(grid, at)
    grid.offset = entry_top(grid, at)
    // the row the keyboard was on may have scrolled away: the keyboard follows the match
    grid.rest_row = grid.selected_row
    grid.rest_pending = true
    ret moved
}

fn search_next(grid: *Grid, forward: bool) -> err {
    var from = 0usize
    if grid.has_position { from = grid.position }
    let (at, found) = search_find(grid, from, forward, false)
    if !found { ret ok }
    ret search_go(grid, at)
}

fn on_search_next(ctx: *void) -> err { ret search_next(mem.cast[*Grid](ctx), true) }
fn on_search_prev(ctx: *void) -> err { ret search_next(mem.cast[*Grid](ctx), false) }

// A typed character (or Backspace, 8) of the search: a shortcut per key, because a scope that takes
// raw keys would take the navigation keys too.
type SearchKey = struct { grid: *Grid, ch: u8 }

fn on_search_char(ctx: *void) -> err {
    let key = mem.cast[*SearchKey](ctx)
    let grid = key.grid
    if !grid.has_search || grid.editing { ret ok }
    // a letter typed into the filter row's editor is its own, not a search
    if mem.address_of(grid.theme) != 0usize && mem.address_of(grid.theme.runtime) != 0usize {
        let (held, has_held) = widget.focused_key(grid.theme.runtime)
        if has_held && held >= grid.key + FILTER_KEY && held < grid.key + FILTER_KEY + 1024u64 { ret ok }
    }
    if key.ch == 8u8 {
        if grid.search_len > 0usize { grid.search_len -= 1usize }
        ret ok
    }
    if grid.search_len >= grid.search_buf.len { ret ok }
    grid.search_buf[grid.search_len] = key.ch
    grid.search_len += 1usize
    var from = 0usize
    if grid.has_position { from = grid.position }
    let (at, found) = search_find(grid, from, true, true)
    if !found {
        // v3 ignores a letter that matches nothing: the buffer keeps what it had
        grid.search_len -= 1usize
        ret ok
    }
    ret search_go(grid, at)
}

fn on_search_cancel(ctx: *void) -> err {
    cancel_search(mem.cast[*Grid](ctx))
    ret ok
}

// One bookmark per view, kept on the row so it survives a sort or a filter.
fn toggle_bookmark(grid: *Grid) {
    if grid.has_bookmark && grid.has_selection && grid.bookmark_row == grid.selected_row {
        grid.has_bookmark = false
        ret
    }
    if !grid.has_selection { ret }
    grid.bookmark_row = grid.selected_row
    grid.has_bookmark = true
}

fn goto_bookmark(grid: *Grid) -> (bool, err) {
    if !grid.has_bookmark { ret (false, ok) }
    let visible = grp.visible_len(grid.g)
    var at = 0usize
    while at < visible && (grp.visible_is_group(grid.g, at) || grp.visible_row(grid.g, at) != grid.bookmark_row) { at += 1usize }
    if at >= visible { ret (false, ok) }
    let moved = go_to(grid, at)
    ret (true, moved)
}

fn on_bookmark_toggle(ctx: *void) -> err {
    toggle_bookmark(mem.cast[*Grid](ctx))
    ret ok
}

fn on_bookmark_goto(ctx: *void) -> err {
    let (found, moved) = goto_bookmark(mem.cast[*Grid](ctx))
    let _ = found
    ret moved
}

// ---- context menus and the field chooser (v3's pmCards / header popup / group box popup / Customization) ----

const MENU_KEY: u64 = 1073742000u64
const CHOOSER_KEY: u64 = 1073742100u64

// What a menu command does (MenuPick.id).
const CMD_SORT_ASC: u8 = 1u8
const CMD_SORT_DESC: u8 = 2u8
const CMD_CLEAR_SORT: u8 = 3u8
const CMD_GROUP_FIELD: u8 = 4u8
const CMD_GROUP_BOX: u8 = 5u8
const CMD_FOOTER: u8 = 6u8
const CMD_REMOVE_COLUMN: u8 = 7u8
const CMD_CHOOSER: u8 = 8u8
const CMD_BEST_FIT: u8 = 9u8
const CMD_BEST_FIT_ALL: u8 = 10u8
const CMD_EXPAND_ALL: u8 = 11u8
const CMD_COLLAPSE_ALL: u8 = 12u8
const CMD_CLEAR_GROUPING: u8 = 13u8
const CMD_ALIGN_MENU: u8 = 14u8
const CMD_ALIGN_LEFT: u8 = 15u8
const CMD_ALIGN_CENTER: u8 = 16u8
const CMD_ALIGN_RIGHT: u8 = 17u8
const CMD_GROUP_SWAP: u8 = 18u8
const CMD_GROUP_FOOTERS: u8 = 19u8
const FOOTER_KEY_OFFSET: u64 = 1048576u64
const CHIP_TAG: u64 = 4398046511104u64

// Which menu: the application's cell menu, a header's, the group box's.
const MENU_CELL: u8 = 1u8
const MENU_HEADER: u8 = 2u8
const MENU_GROUP: u8 = 3u8
const MENU_QUICK: u8 = 4u8
const MENU_ALIGN: u8 = 5u8
const MENU_APP: u8 = 6u8

type MenuPick = struct { grid: *Grid, id: u8, spec: usize }

// The application's commands for the cell menu (a row under the pointer); the grid adds Show
// Columns... after them. `commands` must outlive the grid's builds.
// The pictures of the header popup, in order: sort ascending, descending, clear, group by field,
// group by box, footer, group footers, field chooser, best fit.
// The pictures of the Alignment submenu: Align Left, Align Right, Align Center.
fn set_align_menu_icons(grid: *Grid, icons: [3]scene.TextureId) {
    grid.align_icons = icons
    grid.has_align_icons = true
}

fn set_header_menu_icons(grid: *Grid, icons: [9]scene.TextureId) {
    grid.header_icons = icons
    grid.has_header_icons = true
}

// The pictures of the filter row's twelve operators (v3's list order: Equals, Does not equal, ...,
// Begins with, Ends with), about 26 by 20; without them the list shows signs in text.
fn set_filter_operator_icons(grid: *Grid, icons: [12]scene.TextureId) {
    grid.filter_op_icons = icons
    grid.has_filter_op_icons = true
}

// v3's navigator pictures: the enabled First, Previous page, Previous, Next, Next page, Last and the
// funnel, and the disabled First .. Last (each 28 by 32, with the button's own bevel).
fn set_navigator_icons(grid: *Grid, enabled: [7]scene.TextureId, disabled: [6]scene.TextureId) {
    grid.nav_icons = enabled
    grid.nav_disabled = disabled
    grid.has_nav_icons = true
}

fn set_backdrop(grid: *Grid, texture: scene.TextureId) {
    backdrop_texture = texture
    backdrop_set = true
}

// The body as the pane shows it: shifted by the horizontal scroll, over v3's background picture. A
// function of its own: `build_parts` has no room for more locals (the compiler build silently
// corrupts the rule wizard's styles past it, D2524).
fn shown_in_pane(a: *mem.Arena, grid: *Grid, body: widget.Node, body_height: f32) -> (widget.Node, err) {
    var shown = body
    if grid.hon {
        let (shifted, shifted_error) = hshift(a, grid, body, grid.hcontent, body_height)
        if shifted_error != ok { ret (zero, shifted_error) }
        shown = shifted
    }
    if backdrop_set && grid.look.on {
        let (picture, picture_error) = control.image(a, grid.key + 3950u64, backdrop_texture, 233.0, 168.0, .Contain, "")
        if picture_error != ok { ret (zero, picture_error) }
        let (flow, flow_error) = mem.alloc[widget.Node](a, 2usize)
        if flow_error != ok { ret (zero, control.TooLarge) }
        let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
        if layers_error != ok { ret (zero, control.TooLarge) }
        var spacer_h = body_height - 168.0
        if !(spacer_h > 0.0) { spacer_h = 0.0 }
        flow[0usize] = widget.box(grid.key + 3951u64, control.sized_style(1.0, spacer_h), zero)
        flow[1usize] = picture
        layers[0usize] = widget.flex(grid.key + 3952u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), flow[0usize..2usize])
        layers[1usize] = shown
        shown = widget.stack(grid.key + 3953u64, style.defaults(), layers[0usize..2usize])
    }
    ret (shown, ok)
}

// The word before the count in the footer (v3: "Count" in the pool, "Rows" in the collection).
fn set_footer_label(grid: *Grid, label: str) { grid.footer_label = label }

// The message of an empty grid (v3's NoDataToDisplayInfoText: "<No cards in card pool>" and so on).
fn set_empty_text(grid: *Grid, text: str) { grid.empty_text = text }

// v3's group footers are 29 px in rows of 19: this much taller than a row.
fn footer_extra() -> f32 { ret 10.0 }

// Card Rules (v3's preview): every data row carries its rules text under it, this much taller.
fn preview_extra() -> f32 { ret 18.0 }

fn preview_detail_height(grid: *const Grid) -> f32 {
    if grid.preview_on { ret preview_extra() }
    ret 0.0
}

// How much taller than a row visible entry `at` is: a group footer, or a data row with its preview.
fn extra_of(grid: *const Grid, at: usize) -> f32 {
    if grid.g.group_footers && grp.visible_is_footer(grid.g, at) { ret footer_extra() }
    // looks4-e: a group row is 18 px tall in the live capture, a data row 19
    if grid.look.on && grid.look.group_flat && grp.visible_is_group(grid.g, at) && !grp.visible_is_footer(grid.g, at) {
        // looks5-e: directly under the header (no filter row) the first group row is 16 tall (live capture)
        if at == 0usize && !grid.filter_visible { ret -3.0 }
        ret -1.0
    }
    if grid.preview_on && grid.look.on && !grp.visible_is_group(grid.g, at) { ret preview_extra() }
    ret 0.0
}

fn has_extras(grid: *const Grid) -> bool { ret grid.g.group_footers || (grid.preview_on && grid.look.on) || (grid.look.on && grid.look.group_flat) }

// The scroll offset of the top of visible entry `index`: a row each, a group footer or a preview taller.
fn entry_top(grid: *const Grid, index: usize) -> f32 {
    var top = f32(index) * grid.row_height
    if has_extras(grid) {
        var at = 0usize
        let n = grp.visible_len(grid.g)
        while at < index && at < n {
            top += extra_of(grid, at)
            at += 1usize
        }
    }
    ret top
}

// The visible entry at scroll offset `offset`.
fn entry_at(grid: *const Grid, offset: f32) -> usize {
    if !has_extras(grid) { ret usize(offset / grid.row_height) }
    var top: f32 = 0.0
    var at = 0usize
    let n = grp.visible_len(grid.g)
    while at < n {
        let h = grid.row_height + extra_of(grid, at)
        if top + h > offset { ret at }
        top += h
        at += 1usize
    }
    ret n
}

// Cards dragged between grids (v3): `set_row_drop` makes the grid a drop target; `fn` hears the row
// (of the source grid's table) that was dropped on one of this grid's rows.
fn set_row_drop(grid: *Grid, ctx: *void, f: fn(*void, usize) -> err) {
    grid.has_row_drop = true
    grid.row_drop_ctx = ctx
    grid.row_drop_fn = f
}

// The table row a dragged row key stands for in this grid (`found` false for another grid's).
fn row_of_key(grid: *const Grid, key: u64) -> (usize, bool) {
    let base = grid.key + KEY_BASE
    if key < base || key >= base + u64(table.capacity(grid.t)) { ret (0usize, false) }
    ret (usize(key - base), true)
}

fn on_row_drop(ctx: *void, key: u64) -> err {
    let grid = mem.cast[*Grid](ctx)
    if !grid.has_row_drop { ret ok }
    // another grid's row: its key, less this grid's own
    let (own_row, own) = row_of_key(grid, key)
    if own { ret ok }
    ret grid.row_drop_fn(grid.row_drop_ctx, usize(key))
}

// ---- export and copy as text (v3: Cards > Export ▸ HTML, PDF, Excel, CSV, Plain Text, Xml; Copy as Text ▸ Copy Card Name, Copy Selected, Copy All) ----

const EXPORT_CSV: u8 = 0u8
const EXPORT_TEXT: u8 = 1u8
const EXPORT_XML: u8 = 2u8
const EXPORT_HTML: u8 = 3u8

fn export_escape(sb: *str.Builder, text: str, format: u8) -> err {
    var at = 0usize
    while at < text.len {
        let c = text[at]
        if format == EXPORT_CSV && c == 34u8 {
            if str.push(sb, "\"\"") != ok { ret control.TooLarge }
        } else if (format == EXPORT_XML || format == EXPORT_HTML) && c == 60u8 {
            if str.push(sb, "&lt;") != ok { ret control.TooLarge }
        } else if (format == EXPORT_XML || format == EXPORT_HTML) && c == 62u8 {
            if str.push(sb, "&gt;") != ok { ret control.TooLarge }
        } else if (format == EXPORT_XML || format == EXPORT_HTML) && c == 38u8 {
            if str.push(sb, "&amp;") != ok { ret control.TooLarge }
        } else if format == EXPORT_TEXT && (c == 9u8 || c == 10u8 || c == 13u8) {
            if str.push(sb, " ") != ok { ret control.TooLarge }
        } else {
            if str.push_byte(sb, c) != ok { ret control.TooLarge }
        }
        at += 1usize
    }
    ret ok
}

// The grid's shown columns and data rows (in the order and under the filter on screen; group rows
// and footers are left out) as one text of the chosen format. `selected_only` keeps the selected
// (multi-select) rows, or the current one.
fn export_string(a: *mem.Arena, grid: *Grid, format: u8, selected_only: bool, limit: usize) -> (str, err) {
    var cap = 4096usize
    var rows_wanted = 0usize
    let visible = grp.visible_len(grid.g)
    var at = 0usize
    while at < visible {
        if !grp.visible_is_group(grid.g, at) { rows_wanted += 1usize }
        at += 1usize
    }
    if rows_wanted > limit { rows_wanted = limit }
    cap += (rows_wanted + 2usize) * (grid.specs.len * 24usize + 64usize)
    let (b, b_error) = str.builder(a, cap)
    if b_error != ok { ret ("", b_error) }
    var sb = b
    if format == EXPORT_XML { if str.push(&sb, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<cards>\n") != ok { ret ("", control.TooLarge) } }
    if format == EXPORT_HTML { if str.push(&sb, "<html><body><table border=\"1\">\n") != ok { ret ("", control.TooLarge) } }
    // the header
    var col = 0usize
    var first = true
    if format == EXPORT_HTML { if str.push(&sb, "<tr>") != ok { ret ("", control.TooLarge) } }
    while col < grid.specs.len {
        let s = grid.specs[col]
        if s.kind != CellKind.Indicator && s.title.len != 0usize && format != EXPORT_XML {
            if format == EXPORT_HTML {
                if str.push(&sb, "<th>") != ok { ret ("", control.TooLarge) }
            } else if !first {
                if format == EXPORT_CSV { if str.push(&sb, ",") != ok { ret ("", control.TooLarge) } } else { if str.push(&sb, "\t") != ok { ret ("", control.TooLarge) } }
            }
            if format == EXPORT_CSV { if str.push(&sb, "\"") != ok { ret ("", control.TooLarge) } }
            if export_escape(&sb, s.title, format) != ok { ret ("", control.TooLarge) }
            if format == EXPORT_CSV { if str.push(&sb, "\"") != ok { ret ("", control.TooLarge) } }
            if format == EXPORT_HTML { if str.push(&sb, "</th>") != ok { ret ("", control.TooLarge) } }
            first = false
        }
        col += 1usize
    }
    if format == EXPORT_HTML { if str.push(&sb, "</tr>\n") != ok { ret ("", control.TooLarge) } } else if format != EXPORT_XML { if str.push(&sb, "\n") != ok { ret ("", control.TooLarge) } }
    // the rows
    var written = 0usize
    var cell_store: [256]u8 = zero
    var cell_scratch = mem.arena_from(cell_store[0usize..256usize])
    at = 0usize
    while at < visible && written < limit {
        if !grp.visible_is_group(grid.g, at) {
            let row = grp.visible_row(grid.g, at)
            var keep = true
            if selected_only {
                keep = false
                if grid.multi && is_marked(grid, row) { keep = true }
                if !grid.multi && grid.has_selection && grid.selected_row == row { keep = true }
            }
            if keep {
                if format == EXPORT_XML { if str.push(&sb, "  <card>") != ok { ret ("", control.TooLarge) } }
                if format == EXPORT_HTML { if str.push(&sb, "<tr>") != ok { ret ("", control.TooLarge) } }
                first = true
                col = 0usize
                while col < grid.specs.len {
                    let s = grid.specs[col]
                    if s.kind != CellKind.Indicator && s.title.len != 0usize {
                        // a cell that draws a picture has no text of its own: an empty field
                        var text = ""
                        if s.kind == CellKind.Star {
                            if !table.is_null(grid.t, s.column, row) && table.get_bool(grid.t, s.column, row) { text = "Yes" }
                        } else if s.kind != CellKind.Custom && s.kind != CellKind.Picture {
                            // the text of a number is built in a scratch of its own: the output builder
                            // grows in place and nothing else may be allocated from its arena meanwhile
                            mem.reset(&cell_scratch, 0usize)
                            let (shown_text, text_error) = cell_text_of(&cell_scratch, grid, s, row)
                            if text_error == ok { text = shown_text }
                        }
                        if format == EXPORT_XML {
                            if str.push(&sb, "<field name=\"") != ok { ret ("", control.TooLarge) }
                            if export_escape(&sb, s.title, format) != ok { ret ("", control.TooLarge) }
                            if str.push(&sb, "\">") != ok { ret ("", control.TooLarge) }
                            if export_escape(&sb, text, format) != ok { ret ("", control.TooLarge) }
                            if str.push(&sb, "</field>") != ok { ret ("", control.TooLarge) }
                        } else {
                            if format == EXPORT_HTML {
                                if str.push(&sb, "<td>") != ok { ret ("", control.TooLarge) }
                            } else if !first {
                                if format == EXPORT_CSV { if str.push(&sb, ",") != ok { ret ("", control.TooLarge) } } else { if str.push(&sb, "\t") != ok { ret ("", control.TooLarge) } }
                            }
                            if format == EXPORT_CSV { if str.push(&sb, "\"") != ok { ret ("", control.TooLarge) } }
                            if export_escape(&sb, text, format) != ok { ret ("", control.TooLarge) }
                            if format == EXPORT_CSV { if str.push(&sb, "\"") != ok { ret ("", control.TooLarge) } }
                            if format == EXPORT_HTML { if str.push(&sb, "</td>") != ok { ret ("", control.TooLarge) } }
                        }
                        first = false
                    }
                    col += 1usize
                }
                var row_end = "\n"
                if format == EXPORT_XML { row_end = "</card>\n" }
                if format == EXPORT_HTML { row_end = "</tr>\n" }
                if str.push(&sb, row_end) != ok { ret ("", control.TooLarge) }
                written += 1usize
            }
        }
        at += 1usize
    }
    if format == EXPORT_XML { if str.push(&sb, "</cards>\n") != ok { ret ("", control.TooLarge) } }
    if format == EXPORT_HTML { if str.push(&sb, "</table></body></html>\n") != ok { ret ("", control.TooLarge) } }
    ret (str.done(&sb), ok)
}

// `text` with the control characters XML cannot hold (all below a space but tab and the line breaks)
// replaced by spaces; the text itself when it has none (the Excel package refuses the rest).
fn xml_clean(a: *mem.Arena, text: str) -> (str, err) {
    var bad = false
    var i = 0usize
    while i < text.len && !bad {
        let c = text[i]
        if c < 32u8 && c != 9u8 && c != 10u8 && c != 13u8 { bad = true }
        i += 1usize
    }
    if !bad { ret (text, ok) }
    let (out, out_error) = mem.alloc[u8](a, text.len)
    if out_error != ok { ret ("", out_error) }
    i = 0usize
    while i < text.len {
        var c = text[i]
        if c < 32u8 && c != 9u8 && c != 10u8 && c != 13u8 { c = 32u8 }
        out[i] = c
        i += 1usize
    }
    ret (out[0usize..text.len], ok)
}

// `text` with every byte outside printable ASCII replaced by a question mark (the PDF's WinAnsi
// fonts print nothing else here).
fn ascii_text(a: *mem.Arena, text: str) -> (str, err) {
    var n = text.len
    if n > 48usize { n = 48usize }
    let (out, out_error) = mem.alloc[u8](a, n)
    if out_error != ok { ret ("", out_error) }
    var i = 0usize
    while i < n {
        var c = text[i]
        if c < 32u8 || c > 126u8 { c = 63u8 }
        out[i] = c
        i += 1usize
    }
    ret (out[0usize..n], ok)
}

// The listed columns' titles and the shown data rows as arrays of text, the header first (the
// source of the Excel and PDF exports: v3 sends the same view through DevExpress's exporters).
fn export_rows(a: *mem.Arena, grid: *Grid, limit: usize, ascii: bool) -> ([]const []const str, usize, err) {
    var wide = 0usize
    var c = 0usize
    while c < grid.specs.len {
        if grid.specs[c].kind != CellKind.Indicator && grid.specs[c].title.len != 0usize { wide += 1usize }
        c += 1usize
    }
    let visible = grp.visible_len(grid.g)
    var rows_wanted = 0usize
    var at = 0usize
    while at < visible && rows_wanted < limit {
        if !grp.visible_is_group(grid.g, at) && !grp.visible_is_footer(grid.g, at) { rows_wanted += 1usize }
        at += 1usize
    }
    let (rows, rows_error) = mem.alloc[[]const str](a, rows_wanted + 1usize)
    if rows_error != ok { ret (zero, 0usize, rows_error) }
    var written = 0usize
    var line = 0usize
    while line <= rows_wanted {
        let (cells, cells_error) = mem.alloc[str](a, wide)
        if cells_error != ok { ret (zero, 0usize, cells_error) }
        var out = 0usize
        var row = 0usize
        var drawn = line == 0usize
        if line != 0usize {
            // the next data row in view order
            var seen = 0usize
            var scan = 0usize
            while scan < visible && !drawn {
                if !grp.visible_is_group(grid.g, scan) && !grp.visible_is_footer(grid.g, scan) {
                    seen += 1usize
                    if seen == line {
                        row = grp.visible_row(grid.g, scan)
                        drawn = true
                    }
                }
                scan += 1usize
            }
        }
        c = 0usize
        while c < grid.specs.len && drawn {
            let s = grid.specs[c]
            if s.kind != CellKind.Indicator && s.title.len != 0usize {
                var text = s.title
                if line != 0usize {
                    text = ""
                    if s.kind == CellKind.Star {
                        if !table.is_null(grid.t, s.column, row) && table.get_bool(grid.t, s.column, row) { text = "Yes" }
                    } else if s.kind != CellKind.Custom && s.kind != CellKind.Picture {
                        let (shown_text, text_error) = cell_text_of(a, grid, s, row)
                        if text_error == ok { text = shown_text }
                    }
                }
                if ascii {
                    let (plain, plain_error) = ascii_text(a, text)
                    if plain_error != ok { ret (zero, 0usize, plain_error) }
                    text = plain
                } else {
                    let (clean, clean_error) = xml_clean(a, text)
                    if clean_error != ok { ret (zero, 0usize, clean_error) }
                    text = clean
                }
                cells[out] = text
                out += 1usize
            }
            c += 1usize
        }
        rows[line] = cells[0usize..wide]
        written += 1usize
        line += 1usize
    }
    ret (rows[0usize..written], wide, ok)
}

// Export > Excel (v3 ExportGridToXLSX): one sheet, the header row bold, numbers as numbers.
fn export_xlsx(a: *mem.Arena, grid: *Grid, limit: usize) -> ([]u8, err) {
    let (rows, wide, rows_error) = export_rows(a, grid, limit, false)
    if rows_error != ok { ret (zero, rows_error) }
    let (grid_cells, grid_error) = mem.alloc[[]const xlsx.Cell](a, rows.len)
    if grid_error != ok { ret (zero, grid_error) }
    var r = 0usize
    while r < rows.len {
        let (cells, cells_error) = mem.alloc[xlsx.Cell](a, wide)
        if cells_error != ok { ret (zero, cells_error) }
        var k = 0usize
        while k < wide {
            cells[k] = xlsx.text_cell(rows[r][k])
            if r != 0usize && rows[r][k].len != 0usize {
                let (number, number_error) = str.parse_f64(rows[r][k])
                if number_error == ok { cells[k] = xlsx.number_cell(number) }
            }
            k += 1usize
        }
        grid_cells[r] = cells[0usize..wide]
        r += 1usize
    }
    let (sheets, sheets_error) = mem.alloc[xlsx.Sheet](a, 1usize)
    if sheets_error != ok { ret (zero, sheets_error) }
    sheets[0usize] = xlsx.Sheet { name: "Cards", grid: grid_cells[0usize..rows.len] }
    let (layouts, layouts_error) = mem.alloc[book.Layout](a, 1usize)
    if layouts_error != ok { ret (zero, layouts_error) }
    var layout = book.no_layout()
    layout.bold_header = true
    layouts[0usize] = layout
    let (package, package_error) = book.encode(a, sheets[0usize..1usize], layouts[0usize..1usize])
    ret (package, package_error)
}

// Export > PDF: the shown rows as a ruled table over A4 pages (595 x 842 pt), columns of equal width.
fn export_pdf(a: *mem.Arena, grid: *Grid, limit: usize) -> (str, err) {
    let (rows, wide, rows_error) = export_rows(a, grid, limit, true)
    if rows_error != ok { ret ("", rows_error) }
    if wide == 0usize { ret ("", control.TooLarge) }
    let per_page = 44usize
    let pages = (rows.len + per_page - 1usize) / per_page
    let (d, d_error) = pdfw.document(a, pages + 1usize, 4194304usize, 595.0, 842.0, "MTG Studio")
    if d_error != ok { ret ("", d_error) }
    var doc = d
    let (widths, widths_error) = mem.alloc[f64](a, wide)
    if widths_error != ok { ret ("", widths_error) }
    // the grid's column widths, scaled to the 510 pt between the margins
    var total: f64 = 0.0
    var w = 0usize
    var shown = 0usize
    while w < grid.specs.len {
        if grid.specs[w].kind != CellKind.Indicator && grid.specs[w].title.len != 0usize && shown < wide {
            widths[shown] = f64(grid.specs[w].width) + 8.0
            total += widths[shown]
            shown += 1usize
        }
        w += 1usize
    }
    w = 0usize
    while w < wide {
        widths[w] = widths[w] * 510.0 / total
        w += 1usize
    }
    var from = 0usize
    while from < rows.len {
        var to = from + per_page
        if to > rows.len { to = rows.len }
        if pdfw.begin_page(&doc) != ok { ret ("", control.TooLarge) }
        let (_bottom, table_error) = pdfw.put_table(&doc, 42.0, 42.0, widths[0usize..wide], rows[from..to], 7.0, 12.0, 2.0, true, pdfw.black(), pdfw.rgb(160u8, 160u8, 160u8))
        if table_error != ok { ret ("", table_error) }
        if pdfw.end_page(&doc) != ok { ret ("", control.TooLarge) }
        from = to
    }
    let (document, document_error) = pdfw.finish(a, &doc)
    ret (document, document_error)
}

// Copy Card Name (v3's Ctrl+F9): the search column text of the current row, empty with none.
fn card_name(a: *mem.Arena, grid: *const Grid) -> (str, err) {
    if !grid.has_selection || !grid.has_search || grid.search_spec >= grid.all.len { ret ("", ok) }
    let (name_text, name_error) = cell_text_of(a, grid, grid.all[grid.search_spec], grid.selected_row)
    ret (name_text, name_error)
}

// A hint per column (by the column's index in the specs given to `create`), shown after the pointer
// rests on its header (v3's HeaderHint: "Name - the card's name appears in the upper left corner.").
fn set_header_hints(grid: *Grid, hints: []const str) { grid.hints = hints }

fn set_cell_menu(grid: *Grid, commands: []const overlay.MenuCommand) {
    grid.cell_menu = commands
}

// A command the application must carry out (Clear Sorting, Clear Grouping): taken once.
fn take_command(grid: *Grid) -> (u8, usize, bool) {
    if grid.command == 0u8 { ret (0u8, 0usize, false) }
    let id = grid.command
    grid.command = 0u8
    ret (id, grid.command_spec, true)
}

fn show_chooser(grid: *Grid, on: bool) { grid.chooser_open = on }

fn on_menu_show(ctx: *void) -> err {
    let grid = mem.cast[*Grid](ctx)
    grid.menu_cursor = 100usize
    grid.chooser_active = false
    grid.menu_open = true
    grid.menu_kind = MENU_CELL
    grid.menu_spec = 0usize
    if mem.address_of(grid.theme) == 0usize || mem.address_of(grid.theme.runtime) == 0usize { ret ok }
    let (at, pointed) = widget.context_point(grid.theme.runtime)
    if !pointed { ret ok }
    // the group box, then the header band (from the first header cell), else a cell
    let (box_rect, has_box) = control.keyed_bounds(grid.theme.runtime, grid.key + GROUP_BOX_KEY)
    if grid.group_box_visible && has_box && at.y >= box_rect.y && at.y < box_rect.y + box_rect.height {
        grid.menu_kind = MENU_GROUP
        ret ok
    }
    // a right-click on a card makes it current (and the only selected one unless it is selected)
    var look_at = entry_at(grid, grid.offset)
    let look_end = look_at + grid.page_rows + 4usize
    while look_at < grp.visible_len(grid.g) && look_at < look_end {
        if !grp.visible_is_group(grid.g, look_at) {
            let row = grp.visible_row(grid.g, look_at)
            let (row_rect, has_row) = control.keyed_bounds(grid.theme.runtime, row_key(grid, row))
            if has_row && at.y >= row_rect.y && at.y < row_rect.y + row_rect.height && at.x >= row_rect.x && at.x < row_rect.x + row_rect.width {
                grid.has_selection = true
                grid.selected_row = row
                grid.has_position = true
                grid.position = look_at
                if grid.multi && !is_marked(grid, row) {
                    clear_marks(grid)
                    set_mark(grid, row, true)
                    grid.anchor = look_at
                    grid.has_anchor = true
                }
                let picked = grid.events.row_picked(grid.events.ctx, row)
                let _ = picked
                ret ok
            }
        }
        look_at += 1usize
    }
    // not a card: a header cell (its semantics name row 0 and the column)
    let (cell_row, cell_column, has_cell) = widget.cell_at(grid.theme.runtime, at)
    if has_cell && cell_row == 0u32 && cell_column >= 1u32 && usize(cell_column) <= grid.specs.len {
        grid.menu_kind = MENU_HEADER
        grid.menu_spec = usize(cell_column) - 1usize
    }
    ret ok
}

// The application's own menu (v3's View menu) as a popup at the window point (x, y): the grid draws
// it in its flat look, with section headings from `head` of the commands.
fn show_app_menu(grid: *Grid, commands: []const overlay.MenuCommand, x: f32, y: f32) {
    grid.app_menu = commands
    grid.app_menu_x = x
    grid.app_menu_y = y
    grid.menu_kind = MENU_APP
    grid.menu_open = true
    grid.menu_cursor = 0usize
}

fn on_menu_dismiss(ctx: *void) -> err {
    let grid = mem.cast[*Grid](ctx)
    grid.menu_open = false
    ret ok
}

fn on_menu_pick(ctx: *void) -> err {
    let pick = mem.cast[*MenuPick](ctx)
    let grid = pick.grid
    grid.menu_open = pick.id == CMD_ALIGN_MENU
    let shown = pick.spec
    if pick.id == CMD_SORT_ASC || pick.id == CMD_SORT_DESC {
        if shown >= grid.specs.len { ret ok }
        let spec = grid.origin[shown]
        grid.sort_column = spec
        grid.descending = pick.id == CMD_SORT_DESC
        ret grid.events.sort_changed(grid.events.ctx, spec, grid.descending)
    }
    if pick.id == CMD_CLEAR_SORT || pick.id == CMD_CLEAR_GROUPING {
        if pick.id == CMD_CLEAR_SORT {
            grid.sort_column = grid.all.len
            grid.extra_count = 0usize
        }
        grid.command = pick.id
        grid.command_spec = shown
        ret ok
    }
    if pick.id == CMD_GROUP_FIELD {
        if shown >= grid.specs.len { ret ok }
        grid.group_drop_spec = grid.specs[shown].column
        grid.group_drop_pending = true
        grid.group_box_visible = true
        ret ok
    }
    if pick.id == CMD_GROUP_BOX {
        grid.group_box_visible = !grid.group_box_visible
        ret ok
    }
    if pick.id == CMD_FOOTER {
        grid.footer_visible = !grid.footer_visible
        ret ok
    }
    if pick.id == CMD_GROUP_FOOTERS {
        grp.set_group_footers(grid.g, !grid.g.group_footers)
        ret ok
    }
    if pick.id == CMD_REMOVE_COLUMN {
        if shown >= grid.specs.len { ret ok }
        grid.hidden[grid.origin[shown]] = true
        relayout(grid)
        ret ok
    }
    if pick.id == CMD_CHOOSER {
        grid.chooser_open = true
        grid.chooser_active = true
        ret ok
    }
    if pick.id == CMD_ALIGN_MENU {
        // the Alignment submenu stands beside the popup, for the same column
        grid.menu_open = true
        grid.menu_kind = MENU_ALIGN
        grid.menu_spec = shown
        ret ok
    }
    if pick.id == CMD_ALIGN_LEFT || pick.id == CMD_ALIGN_CENTER || pick.id == CMD_ALIGN_RIGHT {
        if shown < grid.specs.len {
            let spec = grid.origin[shown]
            var kind = 1u8
            if pick.id == CMD_ALIGN_CENTER { kind = 2u8 }
            if pick.id == CMD_ALIGN_RIGHT { kind = 3u8 }
            grid.aligns[spec] = kind
        }
        ret ok
    }
    if pick.id == CMD_BEST_FIT {
        if shown >= grid.specs.len { ret ok }
        grid.fit_spec = grid.origin[shown]
        grid.fit_pending = true
        ret ok
    }
    if pick.id == CMD_BEST_FIT_ALL {
        grid.fit_all_pending = true
        ret ok
    }
    if pick.id == CMD_EXPAND_ALL || pick.id == CMD_COLLAPSE_ALL {
        var group = 0usize
        while group < grp.group_len(grid.g) {
            let changed = grp.set_expanded(grid.g, group, pick.id == CMD_EXPAND_ALL)
            if changed != ok { ret changed }
            group += 1usize
        }
        ret ok
    }
    ret ok
}

fn menu_item(label: str, action: widget.Submit, enabled: bool, separated: bool, shortcut: str) -> overlay.MenuCommand {
    var c = overlay.menu_command(label, action)
    c.enabled = enabled
    c.separated = separated
    c.shortcut = shortcut
    ret c
}

// The commands of the open menu.
fn menu_commands(a: *mem.Arena, grid: *Grid) -> ([]overlay.MenuCommand, err) {
    let (picks, picks_error) = mem.alloc[MenuPick](a, 16usize)
    if picks_error != ok { ret (zero, control.TooLarge) }
    let (commands, commands_error) = mem.alloc[overlay.MenuCommand](a, 16usize + grid.cell_menu.len + grid.app_menu.len)
    if commands_error != ok { ret (zero, control.TooLarge) }
    var n = 0usize
    var p = 0usize
    let me = mem.cast[*void](grid)
    if grid.menu_kind == MENU_APP {
        var ai = 0usize
        while ai < grid.app_menu.len {
            commands[n] = grid.app_menu[ai]
            n += 1usize
            ai += 1usize
        }
        ret (commands[0usize..n], ok)
    }
    if grid.menu_kind == MENU_CELL {
        var i = 0usize
        while i < grid.cell_menu.len {
            commands[n] = grid.cell_menu[i]
            n += 1usize
            i += 1usize
        }
        ret (commands[0usize..n], ok)
    }
    if grid.menu_kind == MENU_ALIGN {
        let kinds: [3]u8 = [3]u8{ CMD_ALIGN_LEFT, CMD_ALIGN_RIGHT, CMD_ALIGN_CENTER }
        let words: [3]str = [3]str{ "Align Left", "Align Right", "Align Center" }
        var current = 1u8
        if grid.menu_spec < grid.specs.len && grid.aligns[grid.origin[grid.menu_spec]] != 0u8 { current = grid.aligns[grid.origin[grid.menu_spec]] }
        var q = 0usize
        while q < 3usize {
            picks[q] = MenuPick { grid: grid, id: kinds[q], spec: grid.menu_spec }
            commands[q] = menu_item(words[q], widget.Submit { ctx: mem.cast[*void](&picks[q]), invoke: on_menu_pick }, true, false, "")
            var slot_value = u8(q + 1usize)
            if q == 1usize { slot_value = 3u8 }
            if q == 2usize { slot_value = 2u8 }
            commands[q].checked = slot_value == current
            if grid.has_align_icons {
                commands[q].has_picture = true
                commands[q].picture = grid.align_icons[q]
            }
            q += 1usize
        }
        ret (commands[0usize..3usize], ok)
    }
    if grid.menu_kind == MENU_GROUP {
        picks[0usize] = MenuPick { grid: grid, id: CMD_EXPAND_ALL, spec: 0usize }
        picks[1usize] = MenuPick { grid: grid, id: CMD_COLLAPSE_ALL, spec: 0usize }
        picks[2usize] = MenuPick { grid: grid, id: CMD_CLEAR_GROUPING, spec: 0usize }
        picks[3usize] = MenuPick { grid: grid, id: CMD_GROUP_BOX, spec: 0usize }
        commands[0usize] = menu_item("Full Expand", widget.Submit { ctx: mem.cast[*void](&picks[0usize]), invoke: on_menu_pick }, true, false, "")
        commands[1usize] = menu_item("Full Collapse", widget.Submit { ctx: mem.cast[*void](&picks[1usize]), invoke: on_menu_pick }, true, false, "")
        commands[2usize] = menu_item("Clear Grouping", widget.Submit { ctx: mem.cast[*void](&picks[2usize]), invoke: on_menu_pick }, true, true, "")
        commands[3usize] = menu_item("Hide Group By Box", widget.Submit { ctx: mem.cast[*void](&picks[3usize]), invoke: on_menu_pick }, true, false, "")
        ret (commands[0usize..4usize], ok)
    }
    // a header: v3's column popup
    let shown = grid.menu_spec
    let labels: [13]str = [13]str{ "Sort Ascending", "Sort Descending", "Clear Sorting", "Group By This Field", "Group By Box", "Footer", "Group Footers", "Remove This Column", "Field Chooser", "Alignment", "Best Fit", "Best Fit (all columns)", "" }
    let ids: [13]u8 = [13]u8{ CMD_SORT_ASC, CMD_SORT_DESC, CMD_CLEAR_SORT, CMD_GROUP_FIELD, CMD_GROUP_BOX, CMD_FOOTER, CMD_GROUP_FOOTERS, CMD_REMOVE_COLUMN, CMD_CHOOSER, CMD_ALIGN_MENU, CMD_BEST_FIT, CMD_BEST_FIT_ALL, 0u8 }
    var k = 0usize
    while k < 12usize {
        picks[k] = MenuPick { grid: grid, id: ids[k], spec: shown }
        let separated = k == 3usize || k == 5usize || k == 7usize || k == 9usize || k == 11usize
        var enabled = ids[k] != 0u8
        if ids[k] == CMD_REMOVE_COLUMN && grid.specs.len < 2usize { enabled = false }
        if ids[k] == CMD_GROUP_FOOTERS && grid.g.level_count == 0usize { enabled = false }
        commands[n] = menu_item(labels[k], widget.Submit { ctx: mem.cast[*void](&picks[k]), invoke: on_menu_pick }, enabled, separated, "")
        if ids[k] == CMD_ALIGN_MENU { commands[n].supporting = ">" }
        if ids[k] == CMD_FOOTER {
            commands[n].checkable = true
            commands[n].checked = grid.footer_visible
        }
        if ids[k] == CMD_GROUP_FOOTERS {
            commands[n].checkable = true
            commands[n].checked = grid.g.group_footers
        }
        if ids[k] == CMD_GROUP_BOX {
            commands[n].checkable = true
            commands[n].checked = grid.group_box_visible
        }
        if grid.has_header_icons {
            // (a ticked entry with a picture shows the picture in a pale blue box)
            // icon slots: 0 asc, 1 desc, 2 clear, 3 group field, 4 group box, 5 footer, 6 group footers, 8 chooser, 10 best fit
            var slot: usize = 99usize
            if k == 0usize { slot = 0usize }
            if k == 1usize { slot = 1usize }
            if k == 2usize { slot = 2usize }
            if k == 3usize { slot = 3usize }
            if k == 4usize { slot = 4usize }
            if k == 5usize { slot = 5usize }
            if k == 6usize { slot = 6usize }
            if k == 8usize { slot = 7usize }
            if k == 10usize { slot = 8usize }
            if slot < 9usize {
                commands[n].has_picture = true
                commands[n].picture = grid.header_icons[slot]
            }
        }
        n += 1usize
        k += 1usize
    }
    let _ = me
    ret (commands[0usize..n], ok)
}

// A hidden column of the field chooser: a tap shows it again.
type ChooserPick = struct { grid: *Grid, spec: usize }

fn on_chooser_pick(ctx: *void) -> err {
    let pick = mem.cast[*ChooserPick](ctx)
    pick.grid.hidden[pick.spec] = false
    relayout(pick.grid)
    ret ok
}

fn on_open_chooser(ctx: *void) -> err {
    let grid = mem.cast[*Grid](ctx)
    grid.chooser_open = true
    grid.chooser_active = true
    ret ok
}

// The Bands / Columns tabs of a band grid's Customization window.
fn on_chooser_tab_bands(ctx: *void, g: widget.Gesture) -> err {
    switch g {
    case .Tap as at:
        mem.cast[*Grid](ctx).chooser_bands = true
        ret ok
    default:
        ret ok
    }
}

fn on_chooser_tab_columns(ctx: *void, g: widget.Gesture) -> err {
    switch g {
    case .Tap as at:
        mem.cast[*Grid](ctx).chooser_bands = false
        ret ok
    default:
        ret ok
    }
}

fn on_chooser_close(ctx: *void) -> err {
    mem.cast[*Grid](ctx).chooser_open = false
    ret ok
}

// One hidden column of the chooser: a tap shows it, a drag takes it to the header.
type ChooserItem = struct { grid: *Grid, spec: usize }

fn on_chooser_item(ctx: *void, g: widget.Gesture) -> err {
    let item = mem.cast[*ChooserItem](ctx)
    let grid = item.grid
    switch g {
    case .Tap as at:
        grid.chooser_active = true
        grid.hidden[item.spec] = false
        relayout(grid)
        ret ok
    case .DragStart as at:
        grid.chooser_active = true
        // the payload carries the grid (its key, 16 bits) and the column
        ret widget.begin_drag(grid.theme.runtime, collection.chooser_payload_tag() + ((grid.key & 65535u64) << 13u64) + u64(item.spec) + 1u64)
    default:
        ret ok
    }
}

// The chooser is a window of its own: its title moves it, and it is active (its close mark red)
// until something in the grid is used.
fn on_chooser_title(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        grid.chooser_active = true
        ret ok
    case .DragStart as at:
        grid.chooser_active = true
        grid.chooser_grab_x = at.x - grid.chooser_x
        grid.chooser_grab_y = at.y - grid.chooser_y
        ret ok
    case .DragMove as d:
        grid.chooser_x = d.position.x - grid.chooser_grab_x
        grid.chooser_y = d.position.y - grid.chooser_grab_y
        ret ok
    default:
        ret ok
    }
}

// A header dropped on the chooser takes its column out of the grid.
fn on_chooser_drop(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Drop as d:
        let tag = collection.header_payload_tag()
        if d.payload <= tag || d.payload > tag + 4096u64 { ret ok }
        let shown = usize(d.payload - tag - 1u64)
        if shown >= grid.specs.len || grid.specs.len < 2usize { ret ok }
        grid.hidden[grid.origin[shown]] = true
        grid.chooser_active = true
        relayout(grid)
        ret ok
    default:
        ret ok
    }
}

// The hidden columns in a window called Column: drag one to the header, or a header to the window.
// ---- secondary windows: a title bar to drag them by and a close box (the chooser's concept) ----

type WinDrag = struct { grid: *Grid, which: u8 }

// 0 the Sort dialog, 1 the rules manager, 2 the rule wizard, 3 the Advanced Filter.
fn on_window_title(ctx: *void, g: widget.Gesture) -> err {
    let w = mem.cast[*WinDrag](ctx)
    let i = usize(w.which)
    switch g {
    case .Tap as at:
        raise_window(w.grid, w.which)
        ret ok
    case .DragStart as at:
        raise_window(w.grid, w.which)
        w.grid.win_gx[i] = at.x - w.grid.win_x[i]
        w.grid.win_gy[i] = at.y - w.grid.win_y[i]
        ret ok
    case .DragMove as d:
        w.grid.win_x[i] = d.position.x - w.grid.win_gx[i]
        w.grid.win_y[i] = d.position.y - w.grid.win_gy[i]
        ret ok
    default:
        ret ok
    }
}

fn raise_window(grid: *Grid, which: u8) {
    if grid.win_top == 255u8 {
        // the ranks start over, keeping their order
        var k = 0usize
        while k < 4usize {
            grid.win_rank[k] = 0u8
            k += 1usize
        }
        grid.win_top = 0u8
    }
    grid.win_top += 1u8
    grid.win_rank[usize(which)] = grid.win_top
}

// The body of a window: a tap on its empty parts raises it above the others.
fn window_body(a: *mem.Arena, grid: *Grid, which: u8, body: style.Style, inner: []widget.Node) -> (widget.Node, err) {
    let (drags, drags_error) = mem.alloc[WinDrag](a, 1usize)
    if drags_error != ok { ret (zero, control.TooLarge) }
    drags[0usize] = WinDrag { grid: grid, which: which }
    ret (widget.region(grid.key + MENU_KEY + 899900u64 + u64(which), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&drags[0usize]), invoke: on_window_title }, gestures: 1u8, enabled: true, focusable: false }, body, inner), ok)
}

fn on_window_close(ctx: *void, g: widget.Gesture) -> err {
    let w = mem.cast[*WinDrag](ctx)
    switch g {
    case .Tap as at:
        if w.which == 0u8 { w.grid.sort_dialog_open = false }
        if w.which == 1u8 { w.grid.rules_dialog_open = false }
        if w.which == 2u8 { w.grid.wiz_open = false
            w.grid.sw_open = 0u8
            w.grid.fmt_open = false
            w.grid.print_open = false
        }
        if w.which == 3u8 { w.grid.crit_open = false }
        ret ok
    default:
        ret ok
    }
}

// Where window `which` stands: where the user left it, else centred at `y`.
fn window_place(grid: *Grid, which: u8, width: f32, y: f32, surface: f32) {
    let i = usize(which)
    if grid.win_placed[i] { ret }
    var x = (surface - width) * 0.5
    if x < 0.0 { x = 0.0 }
    grid.win_x[i] = x
    grid.win_y[i] = y
    grid.win_placed[i] = true
}

// The title bar of a window: its text, dragged to move it, and a close box (pale red, darker under
// the pointer) at the right end.
fn window_title(a: *mem.Arena, grid: *Grid, which: u8, text: str, width: f32, height: f32, dark: bool) -> (widget.Node, err) {
    let (drags, drags_error) = mem.alloc[WinDrag](a, 1usize)
    if drags_error != ok { ret (zero, control.TooLarge) }
    drags[0usize] = WinDrag { grid: grid, which: which }
    var ink = gl.rgb(0x000000u32)
    if dark { ink = gl.rgb(0xFFFFFFu32) }
    let (label, label_error) = flat_text(a, grid, text, ink)
    if label_error != ok { ret (zero, label_error) }
    var bar = control.sized_style(width - 44.0, height)
    if dark { bar.background = paint.Brush { Solid: gl.rgb(0x202020u32) } } else { bar.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) } }
    let bar_key = grid.key + MENU_KEY + 899800u64 + u64(which) * 2u64
    let title_region = widget.region(bar_key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&drags[0usize]), invoke: on_window_title }, gestures: 3u8, enabled: true, focusable: false }, bar, one(a, widget.padded(0u64, 14.0, height * 0.28, 0.0, 0.0, style.defaults(), one(a, label))))
    let close_key = bar_key + 1u64
    let close_state = control.control_state(grid.theme, close_key, true, false)
    var close_style = control.sized_style(44.0, height)
    close_style.background = paint.Brush { Solid: gl.rgb(0xC75050u32) }
    if close_state.hovered { close_style.background = paint.Brush { Solid: gl.rgb(0xE04343u32) } }
    let (cross, cross_error) = flat_text(a, grid, "x", gl.rgb(0xFFFFFFu32))
    if cross_error != ok { ret (zero, cross_error) }
    let close_region = widget.region(close_key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&drags[0usize]), invoke: on_window_close }, gestures: 1u8 | 4u8, enabled: true, focusable: false }, close_style, one(a, widget.padded(0u64, 16.0, height * 0.22, 0.0, 0.0, style.defaults(), one(a, cross))))
    let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
    if pair_error != ok { ret (zero, control.TooLarge) }
    pair[0usize] = title_region
    pair[1usize] = close_region
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), pair[0usize..2usize]), ok)
}

// ---- the Sort dialog (v3's View > Sort...: every column with None / Ascending / Descending) ----

type SortRow = struct { grid: *Grid, spec: usize }
type SortAct = struct { grid: *Grid, kind: u8 }

fn sort_row_listed(grid: *const Grid, spec: usize) -> bool {
    ret grid.all[spec].kind != CellKind.Indicator && grid.all[spec].title.len != 0usize
}

// Opens the dialog with the grid's current sort (the primary, then the Shift+click ones).
fn open_sort_dialog(grid: *Grid) {
    raise_window(grid, 0u8)
    var at = 0usize
    while at < 24usize {
        grid.sort_marks[at] = 0u8
        at += 1usize
    }
    if grid.sort_column < grid.all.len && grid.sort_column < 24usize {
        grid.sort_marks[grid.sort_column] = 1u8
        if grid.descending { grid.sort_marks[grid.sort_column] = 2u8 }
    }
    var extra = 0usize
    while extra < grid.extra_count {
        let spec = grid.extra_sort[extra]
        if spec < 24usize {
            grid.sort_marks[spec] = 1u8
            if grid.extra_desc[extra] { grid.sort_marks[spec] = 2u8 }
        }
        extra += 1usize
    }
    grid.sort_dialog_open = true
}

fn on_sort_row(ctx: *void, g: widget.Gesture) -> err {
    let row = mem.cast[*SortRow](ctx)
    switch g {
    case .Tap as at:
        if row.spec < 24usize {
            row.grid.sort_marks[row.spec] = (row.grid.sort_marks[row.spec] + 1u8) % 3u8
        }
        ret ok
    default:
        ret ok
    }
}

// Clear (kind 0) empties the list, OK (1) applies it, Cancel (2) closes it.
fn on_sort_act(ctx: *void, g: widget.Gesture) -> err {
    let act = mem.cast[*SortAct](ctx)
    let grid = act.grid
    switch g {
    case .Tap as at:
        if act.kind == 0u8 {
            var at_mark = 0usize
            while at_mark < 24usize {
                grid.sort_marks[at_mark] = 0u8
                at_mark += 1usize
            }
            ret ok
        }
        grid.sort_dialog_open = false
        if act.kind == 2u8 { ret ok }
        // OK: the marked columns top to bottom, the first is the primary sort
        var found = 0usize
        var spec = 0usize
        grid.extra_count = 0usize
        var primary = grid.all.len
        var primary_desc = false
        while spec < grid.all.len && spec < 24usize {
            if grid.sort_marks[spec] != 0u8 && sort_row_listed(grid, spec) {
                if found == 0usize {
                    primary = spec
                    primary_desc = grid.sort_marks[spec] == 2u8
                } else if grid.extra_count < 4usize {
                    grid.extra_sort[grid.extra_count] = spec
                    grid.extra_desc[grid.extra_count] = grid.sort_marks[spec] == 2u8
                    grid.extra_count += 1usize
                }
                found += 1usize
            }
            spec += 1usize
        }
        if found == 0usize {
            grid.sort_column = grid.all.len
            grid.command = CMD_CLEAR_SORT
            grid.command_spec = 0usize
            ret ok
        }
        grid.sort_column = primary
        grid.descending = primary_desc
        ret grid.events.sort_changed(grid.events.ctx, primary, primary_desc)
    default:
        ret ok
    }
}

fn sort_button(a: *mem.Arena, grid: *Grid, key: widget.Key, label_text: str, act: *SortAct, default_button: bool) -> (widget.Node, err) {
    let (label, label_error) = flat_text(a, grid, label_text, gl.rgb(0x000000u32))
    if label_error != ok { ret (zero, label_error) }
    var box = control.sized_style(100.0, 27.0)
    box.background = paint.Brush { Solid: gl.rgb(0xFDFDFDu32) }
    box.radius = 4.0
    var edge = gl.rgb(0xADADADu32)
    var edge_width: f32 = 1.0
    if default_button {
        edge = gl.rgb(0x0078D7u32)
        edge_width = 2.0
    }
    box.border = style.Border { width: edge_width, color: edge }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, control.TooLarge) }
    var centred = style.defaults()
    centred.width = style.Length { Percent: 100.0 }
    centred.height = style.Length { Percent: 100.0 }
    held[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Center, cross: .Center, gap: 0.0 }, centred, one(a, label))
    ret (widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](act), invoke: on_sort_act }, gestures: 1u8, enabled: true, focusable: false }, box, held[0usize..1usize]), ok)
}

fn sort_dialog_panel(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let width: f32 = 528.0
    let (rows, rows_error) = mem.alloc[widget.Node](a, grid.all.len + 4usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    let (picks, picks_error) = mem.alloc[SortRow](a, grid.all.len + 1usize)
    if picks_error != ok { ret (zero, control.TooLarge) }
    let (acts, acts_error) = mem.alloc[SortAct](a, 3usize)
    if acts_error != ok { ret (zero, control.TooLarge) }
    var n = 0usize
    // the title bar
    let (title_row, title_error) = window_title(a, grid, 0u8, "Sort [Card Pool]", width, 44.0, true)
    if title_error != ok { ret (zero, title_error) }
    rows[n] = title_row
    n += 1usize
    // the column header
    let (head_a, head_a_error) = flat_text(a, grid, "Column", gl.rgb(0x000000u32))
    if head_a_error != ok { ret (zero, head_a_error) }
    let (head_b, head_b_error) = flat_text(a, grid, "Sort Order", gl.rgb(0x000000u32))
    if head_b_error != ok { ret (zero, head_b_error) }
    let (head_cells, head_cells_error) = mem.alloc[widget.Node](a, 2usize)
    if head_cells_error != ok { ret (zero, control.TooLarge) }
    head_cells[0usize] = widget.padded(0u64, 4.0, 4.0, 0.0, 0.0, control.sized_style(236.0, 26.0), one(a, head_a))
    head_cells[1usize] = widget.padded(0u64, 4.0, 4.0, 0.0, 0.0, control.sized_style(230.0, 26.0), one(a, head_b))
    var head_style = control.sized_style(width - 16.0, 26.0)
    head_style.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    head_style.margin = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: style.Length { Px: 8.0 }, right: style.Length { Px: 8.0 }, bottom: style.Length { Px: 0.0 } }
    rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, head_style, head_cells[0usize..2usize])
    n += 1usize
    var listed = 0usize
    var spec = 0usize
    while spec < grid.all.len {
        if sort_row_listed(grid, spec) {
            var mark = 0u8
            if spec < 24usize { mark = grid.sort_marks[spec] }
            picks[spec] = SortRow { grid: grid, spec: spec }
            var words = "None"
            if mark == 1u8 { words = "Ascending" }
            if mark == 2u8 { words = "Descending" }
            let (name_node, name_error) = flat_text(a, grid, grid.all[spec].title, gl.rgb(0x000000u32))
            if name_error != ok { ret (zero, name_error) }
            let (order_node, order_error) = flat_text(a, grid, words, gl.rgb(0x000000u32))
            if order_error != ok { ret (zero, order_error) }
            let (cells, cells_error) = mem.alloc[widget.Node](a, 3usize)
            if cells_error != ok { ret (zero, control.TooLarge) }
            cells[0usize] = widget.padded(0u64, 4.0, 6.0, 0.0, 0.0, control.sized_style(236.0, 28.0), one(a, name_node))
            var icon_text = ""
            if mark == 1u8 { icon_text = "a-z" }
            if mark == 2u8 { icon_text = "z-a" }
            var glyph_style = control.sized_style(30.0, 18.0)
            if mark != 0u8 {
                glyph_style.border = style.Border { width: 1.0, color: gl.rgb(0xA0A0A0u32) }
                glyph_style.radius = 4.0
            }
            let (glyph_text, glyph_error) = flat_text(a, grid, icon_text, gl.rgb(0x555555u32))
            if glyph_error != ok { ret (zero, glyph_error) }
            cells[1usize] = widget.aligned(0u64, .Center, .Center, glyph_style, one(a, glyph_text))
            cells[2usize] = widget.padded(0u64, 6.0, 6.0, 0.0, 0.0, control.sized_style(200.0, 28.0), one(a, order_node))
            var row_style = control.sized_style(width - 16.0, 28.0)
            var zebra = gl.rgb(0xFFFFFFu32)
            if listed % 2usize == 0usize { zebra = gl.rgb(0xF0F0F0u32) }
            row_style.background = paint.Brush { Solid: zebra }
            row_style.margin = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 8.0 }, bottom: style.Length { Px: 0.0 } }
            let (row_line, row_line_error) = mem.alloc[widget.Node](a, 1usize)
            if row_line_error != ok { ret (zero, control.TooLarge) }
            row_line[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), cells[0usize..3usize])
            rows[n] = widget.region(grid.key + MENU_KEY + 700000u64 + u64(spec), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&picks[spec]), invoke: on_sort_row }, gestures: 1u8, enabled: true, focusable: false }, row_style, row_line[0usize..1usize])
            n += 1usize
            listed += 1usize
        }
        spec += 1usize
    }
    // Clear, OK, Cancel
    acts[0usize] = SortAct { grid: grid, kind: 0u8 }
    acts[1usize] = SortAct { grid: grid, kind: 1u8 }
    acts[2usize] = SortAct { grid: grid, kind: 2u8 }
    let (clear_button, clear_error) = sort_button(a, grid, grid.key + MENU_KEY + 699990u64, "Clear", &acts[0usize], false)
    if clear_error != ok { ret (zero, clear_error) }
    let (ok_button, ok_error) = sort_button(a, grid, grid.key + MENU_KEY + 699991u64, "OK", &acts[1usize], true)
    if ok_error != ok { ret (zero, ok_error) }
    let (cancel_button, cancel_error) = sort_button(a, grid, grid.key + MENU_KEY + 699992u64, "Cancel", &acts[2usize], false)
    if cancel_error != ok { ret (zero, cancel_error) }
    let (buttons, buttons_error) = mem.alloc[widget.Node](a, 3usize)
    if buttons_error != ok { ret (zero, control.TooLarge) }
    buttons[0usize] = clear_button
    buttons[1usize] = ok_button
    buttons[2usize] = cancel_button
    var button_row = control.sized_style(width - 16.0, 46.0)
    button_row.margin = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: style.Length { Px: 8.0 }, right: style.Length { Px: 8.0 }, bottom: style.Length { Px: 0.0 } }
    rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .SpaceBetween, cross: .Center, gap: 8.0 }, button_row, buttons[0usize..3usize])
    n += 1usize
    var body_style = control.sized_style(width, 44.0 + 34.0 + f32(listed) * 28.0 + 54.0 + 8.0)
    body_style.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    body_style.border = style.Border { width: 1.0, color: gl.rgb(0x6D6D6Du32) }
    body_style.radius = 8.0
    body_style.overflow = .Clip
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, control.TooLarge) }
    inner[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), rows[0usize..n])
    let (framed_body, framed_body_error) = window_body(a, grid, 0u8, body_style, inner[0usize..1usize])
    ret (framed_body, framed_body_error)
}

// ---- the Conditional Formatting Rules Manager (v3's View > Conditional Formatting...) ----

type RuleRow = struct { grid: *Grid, index: usize }
type RuleAct = struct { grid: *Grid, kind: u8 }

fn rule_words(r: *const rules.Rule) -> str {
    if r.kind == rules.Kind.CellIs { ret "Cell Value" }
    if r.kind == rules.Kind.Text { ret "Specific Text" }
    if r.kind == rules.Kind.Blank { ret "Blanks" }
    if r.kind == rules.Kind.Above { ret "Above Average" }
    if r.kind == rules.Kind.Below { ret "Below Average" }
    if r.kind == rules.Kind.Top { ret "Top Values" }
    if r.kind == rules.Kind.Bottom { ret "Bottom Values" }
    if r.kind == rules.Kind.Duplicate { ret "Duplicate Values" }
    if r.kind == rules.Kind.Unique { ret "Unique Values" }
    if r.kind == rules.Kind.Scale { ret "Color Scale" }
    if r.kind == rules.Kind.Bar { ret "Data Bar" }
    ret "Icon Set"
}

fn on_rule_row(ctx: *void, g: widget.Gesture) -> err {
    let row = mem.cast[*RuleRow](ctx)
    switch g {
    case .Tap as at:
        row.grid.rules_selected = row.index
        // a tap in the Stop If True column flips it
        if mem.address_of(row.grid.rule_set) != 0usize && row.index < row.grid.rule_set.total && mem.address_of(row.grid.theme) != 0usize && mem.address_of(row.grid.theme.runtime) != 0usize {
            let (row_box, has_row) = control.keyed_bounds(row.grid.theme.runtime, row.grid.key + MENU_KEY + 800000u64 + u64(row.index))
            if has_row && at.x >= row_box.x + 520.0 {
                row.grid.rule_set.rules[row.index].stop = !row.grid.rule_set.rules[row.index].stop
            }
        }
        ret ok
    default:
        ret ok
    }
}

// 0 Delete, 1 Up, 2 Down, 3 OK / Apply, 4 Cancel.
fn on_rule_act(ctx: *void, g: widget.Gesture) -> err {
    let act = mem.cast[*RuleAct](ctx)
    let grid = act.grid
    switch g {
    case .Tap as at:
        if act.kind == 3u8 || act.kind == 4u8 {
            grid.rules_dialog_open = false
            ret ok
        }
        if act.kind == 5u8 || act.kind == 6u8 {
            grid.wiz_open = true
            grid.fmt_open = false
            raise_window(grid, 2u8)
            grid.wiz_type = 0u8
            grid.has_wiz_target = false
            grid.wiz_edit = act.kind == 6u8
            if act.kind == 6u8 && mem.address_of(grid.rule_set) != 0usize && grid.rules_selected < grid.rule_set.total {
                let edited = grid.rule_set.rules[grid.rules_selected].kind
                if edited == rules.Kind.Bar { grid.wiz_type = 0u8 }
                if edited == rules.Kind.Icons { grid.wiz_type = 1u8 }
                if edited == rules.Kind.Scale { grid.wiz_type = 2u8 }
                if edited == rules.Kind.Blank { grid.wiz_type = 4u8 }
                if edited == rules.Kind.Duplicate { grid.wiz_type = 5u8 }
                if edited == rules.Kind.Top || edited == rules.Kind.Bottom { grid.wiz_type = 6u8 }
                if edited == rules.Kind.Unique { grid.wiz_type = 7u8 }
                if edited == rules.Kind.Above || edited == rules.Kind.Below { grid.wiz_type = 8u8 }
            }
            ret ok
        }
        if mem.address_of(grid.rule_set) == 0usize { ret ok }
        let at_rule = grid.rules_selected
        if at_rule >= grid.rule_set.total { ret ok }
        if act.kind == 0u8 {
            rules.remove(grid.rule_set, at_rule)
            if grid.rules_selected >= grid.rule_set.total && grid.rule_set.total > 0usize { grid.rules_selected = grid.rule_set.total - 1usize }
            ret ok
        }
        if act.kind == 1u8 && at_rule > 0usize {
            rules.swap(grid.rule_set, at_rule, at_rule - 1usize)
            grid.rules_selected = at_rule - 1usize
        }
        if act.kind == 2u8 && at_rule + 1usize < grid.rule_set.total {
            rules.swap(grid.rule_set, at_rule, at_rule + 1usize)
            grid.rules_selected = at_rule + 1usize
        }
        ret ok
    default:
        ret ok
    }
}

fn rules_button(a: *mem.Arena, grid: *Grid, key: widget.Key, label_text: str, w: f32, act: *RuleAct, enabled: bool, default_button: bool) -> (widget.Node, err) {
    var ink = gl.rgb(0x000000u32)
    if !enabled { ink = gl.rgb(0xA0A0A0u32) }
    let (label, label_error) = flat_text(a, grid, label_text, ink)
    if label_error != ok { ret (zero, label_error) }
    var box = control.sized_style(w, 27.0)
    box.background = paint.Brush { Solid: gl.rgb(0xFDFDFDu32) }
    box.radius = 4.0
    var edge = gl.rgb(0xADADADu32)
    var edge_width: f32 = 1.0
    if default_button {
        edge = gl.rgb(0x0078D7u32)
        edge_width = 2.0
    }
    if !enabled { edge = gl.rgb(0xD0D0D0u32) }
    box.border = style.Border { width: edge_width, color: edge }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, control.TooLarge) }
    var centred = style.defaults()
    centred.width = style.Length { Percent: 100.0 }
    centred.height = style.Length { Percent: 100.0 }
    held[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Center, cross: .Center, gap: 0.0 }, centred, one(a, label))
    if !enabled { ret (widget.box(0u64, box, held[0usize..1usize]), ok) }
    ret (widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](act), invoke: on_rule_act }, gestures: 1u8, enabled: true, focusable: false }, box, held[0usize..1usize]), ok)
}

fn rules_dialog_panel(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let width: f32 = 640.0
    var count = 0usize
    if mem.address_of(grid.rule_set) != 0usize { count = grid.rule_set.total }
    let (rows, rows_error) = mem.alloc[widget.Node](a, count + 8usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    let (picks, picks_error) = mem.alloc[RuleRow](a, count + 1usize)
    if picks_error != ok { ret (zero, control.TooLarge) }
    let (acts, acts_error) = mem.alloc[RuleAct](a, 7usize)
    if acts_error != ok { ret (zero, control.TooLarge) }
    var k = 0usize
    while k < 7usize {
        acts[k] = RuleAct { grid: grid, kind: u8(k) }
        k += 1usize
    }
    var n = 0usize
    // the title
    let (title_row, title_error) = window_title(a, grid, 1u8, "Conditional Formatting Rules Manager", width, 40.0, false)
    if title_error != ok { ret (zero, title_error) }
    rows[n] = title_row
    n += 1usize
    // Show formatting rules for: All
    let (show_label, show_label_error) = flat_text(a, grid, "Show formatting rules for:   All", gl.rgb(0x000000u32))
    if show_label_error != ok { ret (zero, show_label_error) }
    var show_style = control.sized_style(width - 24.0, 34.0)
    show_style.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 6.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
    rows[n] = widget.padded(0u64, 0.0, 8.0, 0.0, 0.0, show_style, one(a, show_label))
    n += 1usize
    // New Rule..., Edit Rule..., Delete Rule, Up, Down
    var has_selection = count > 0usize && grid.rules_selected < count
    let (b_new, e_new) = rules_button(a, grid, grid.key + MENU_KEY + 799980u64, "New Rule...", 130.0, &acts[5usize], true, false)
    if e_new != ok { ret (zero, e_new) }
    let (b_edit, e_edit) = rules_button(a, grid, grid.key + MENU_KEY + 799981u64, "Edit Rule...", 130.0, &acts[6usize], has_selection, false)
    if e_edit != ok { ret (zero, e_edit) }
    let (b_delete, e_delete) = rules_button(a, grid, grid.key + MENU_KEY + 799982u64, "Delete Rule", 130.0, &acts[0usize], has_selection, false)
    if e_delete != ok { ret (zero, e_delete) }
    let (b_up, e_up) = rules_button(a, grid, grid.key + MENU_KEY + 799983u64, "Up", 40.0, &acts[1usize], has_selection && grid.rules_selected > 0usize, false)
    if e_up != ok { ret (zero, e_up) }
    let (b_down, e_down) = rules_button(a, grid, grid.key + MENU_KEY + 799984u64, "Down", 56.0, &acts[2usize], has_selection && grid.rules_selected + 1usize < count, false)
    if e_down != ok { ret (zero, e_down) }
    let (tools, tools_error) = mem.alloc[widget.Node](a, 5usize)
    if tools_error != ok { ret (zero, control.TooLarge) }
    tools[0usize] = b_new
    tools[1usize] = b_edit
    tools[2usize] = b_delete
    tools[3usize] = b_up
    tools[4usize] = b_down
    var tools_style = control.sized_style(width - 24.0, 40.0)
    tools_style.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 6.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
    rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, tools_style, tools[0usize..5usize])
    n += 1usize
    // the list header
    let heads: [5]str = [5]str{ "Rule (applied in order shown)", "Format", "Applies to", "Apply to the record", "Stop If True" }
    let head_widths: [5]f32 = [5]f32{ 190.0, 90.0, 110.0, 130.0, 80.0 }
    let (head_cells, head_cells_error) = mem.alloc[widget.Node](a, 5usize)
    if head_cells_error != ok { ret (zero, control.TooLarge) }
    var h = 0usize
    while h < 5usize {
        let (head_text, head_error) = flat_text(a, grid, heads[h], gl.rgb(0x000000u32))
        if head_error != ok { ret (zero, head_error) }
        head_cells[h] = widget.padded(0u64, 4.0, 5.0, 0.0, 0.0, control.sized_style(head_widths[h], 26.0), one(a, head_text))
        h += 1usize
    }
    var head_style = control.sized_style(width - 24.0, 26.0)
    head_style.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    head_style.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 8.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
    rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, head_style, head_cells[0usize..5usize])
    n += 1usize
    // one row per rule
    var at_rule = 0usize
    var list_rows = 0usize
    while at_rule < count {
        let r = grid.rule_set.rules[at_rule]
        picks[at_rule] = RuleRow { grid: grid, index: at_rule }
        var applies = ""
        if r.column < table.column_count(grid.t) { applies = table.column_name(grid.t, r.column) }
        var selected = false
        if has_selection && grid.rules_selected == at_rule { selected = true }
        var ink = gl.rgb(0x000000u32)
        if selected { ink = gl.rgb(0xFFFFFFu32) }
        let (c0, e0) = flat_text(a, grid, rule_words(&r), ink)
        if e0 != ok { ret (zero, e0) }
        let (c2, e2) = flat_text(a, grid, applies, ink)
        if e2 != ok { ret (zero, e2) }
        var whole = "No"
        if r.whole_row { whole = "Yes" }
        let (c3, e3) = flat_text(a, grid, whole, ink)
        if e3 != ok { ret (zero, e3) }
        var stop_words = "No"
        if r.stop { stop_words = "Yes" }
        let (c4, e4) = flat_text(a, grid, stop_words, ink)
        if e4 != ok { ret (zero, e4) }
        // the format sample: the rule's fill and ink behind "AaBbCc"
        var sample_ink = gl.rgb(0x000000u32)
        if r.has_ink { sample_ink = gl.rgb(0xC00000u32) }
        let (sample_text, sample_error) = flat_text(a, grid, "AaBbCc", sample_ink)
        if sample_error != ok { ret (zero, sample_error) }
        var sample_style = control.sized_style(70.0, 18.0)
        if r.has_fill { sample_style.background = paint.Brush { Solid: r.fill } }
        if r.kind == rules.Kind.Bar { sample_style.background = paint.Brush { Solid: gl.rgb(0x9CC2E5u32) } }
        let (cells, cells_error) = mem.alloc[widget.Node](a, 5usize)
        if cells_error != ok { ret (zero, control.TooLarge) }
        cells[0usize] = widget.padded(0u64, 4.0, 5.0, 0.0, 0.0, control.sized_style(190.0, 26.0), one(a, c0))
        cells[1usize] = widget.aligned(0u64, .Start, .Center, control.sized_style(90.0, 26.0), one(a, widget.aligned(0u64, .Center, .Center, sample_style, one(a, sample_text))))
        cells[2usize] = widget.padded(0u64, 4.0, 5.0, 0.0, 0.0, control.sized_style(110.0, 26.0), one(a, c2))
        cells[3usize] = widget.padded(0u64, 4.0, 5.0, 0.0, 0.0, control.sized_style(130.0, 26.0), one(a, c3))
        cells[4usize] = widget.padded(0u64, 4.0, 5.0, 0.0, 0.0, control.sized_style(80.0, 26.0), one(a, c4))
        var row_style = control.sized_style(width - 24.0, 26.0)
        row_style.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
        if selected { row_style.background = paint.Brush { Solid: gl.rgb(0x0078D7u32) } }
        row_style.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
        let (line, line_error) = mem.alloc[widget.Node](a, 1usize)
        if line_error != ok { ret (zero, control.TooLarge) }
        line[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), cells[0usize..5usize])
        rows[n] = widget.region(grid.key + MENU_KEY + 800000u64 + u64(at_rule), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&picks[at_rule]), invoke: on_rule_row }, gestures: 1u8, enabled: true, focusable: false }, row_style, line[0usize..1usize])
        n += 1usize
        list_rows += 1usize
        at_rule += 1usize
    }
    // the white list area under the rows, then OK, Cancel, Apply
    var filler = control.sized_style(width - 24.0, 330.0 - f32(list_rows) * 26.0)
    filler.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    filler.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
    rows[n] = widget.box(0u64, filler, zero)
    n += 1usize
    let (b_ok, e_ok) = rules_button(a, grid, grid.key + MENU_KEY + 799990u64, "OK", 120.0, &acts[3usize], true, true)
    if e_ok != ok { ret (zero, e_ok) }
    let (b_cancel, e_cancel) = rules_button(a, grid, grid.key + MENU_KEY + 799991u64, "Cancel", 120.0, &acts[4usize], true, false)
    if e_cancel != ok { ret (zero, e_cancel) }
    let (b_apply, e_apply) = rules_button(a, grid, grid.key + MENU_KEY + 799992u64, "Apply", 120.0, &acts[3usize], false, false)
    if e_apply != ok { ret (zero, e_apply) }
    let (finish, finish_error) = mem.alloc[widget.Node](a, 3usize)
    if finish_error != ok { ret (zero, control.TooLarge) }
    finish[0usize] = b_ok
    finish[1usize] = b_cancel
    finish[2usize] = b_apply
    var finish_style = control.sized_style(width - 24.0, 46.0)
    finish_style.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 6.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
    rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .End, cross: .Center, gap: 8.0 }, finish_style, finish[0usize..3usize])
    n += 1usize
    var body_style = control.sized_style(width, 600.0)
    body_style.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    body_style.border = style.Border { width: 1.0, color: gl.rgb(0x6D6D6Du32) }
    body_style.radius = 8.0
    body_style.overflow = .Clip
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, control.TooLarge) }
    inner[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), rows[0usize..n])
    let (framed_body, framed_body_error) = window_body(a, grid, 1u8, body_style, inner[0usize..1usize])
    ret (framed_body, framed_body_error)
}

// Opens the manager.
// Whether rules were added or edited since the last call (the application then refreshes its rule set).
fn take_rules_changed(grid: *Grid) -> bool {
    let was = grid.rules_changed
    grid.rules_changed = false
    ret was
}

fn open_rules_manager(grid: *Grid) {
    raise_window(grid, 1u8)
    grid.rules_selected = 0usize
    grid.rules_dialog_open = true
}

// ---- the Advanced Filter (v3's Search > Advanced Filter...: And / Or over column conditions) ----

type CritRow = struct { grid: *Grid, index: usize, part: u8 }
type CritAct = struct { grid: *Grid, kind: u8 }
type CritValue = struct { grid: *Grid, index: usize }

const CRIT_MAX: usize = 6usize
const CRIT_TEXT: usize = 32usize

fn crit_op_words(op: u8) -> str {
    if op == 0u8 { ret "Equals" }
    if op == 1u8 { ret "Does not equal" }
    if op == 2u8 { ret "Is less than" }
    if op == 3u8 { ret "Is greater than" }
    if op == 4u8 { ret "Contains" }
    if op == 5u8 { ret "Does not contain" }
    if op == 6u8 { ret "Begins with" }
    if op == 8u8 { ret "Is blank" }
    if op == 9u8 { ret "Is not blank" }
    if op == 10u8 { ret "Is any of" }
    if op == 11u8 { ret "Is none of" }
    ret "Ends with"
}

fn crit_group_words(kind: u8) -> str {
    if kind == 0u8 { ret "And" }
    if kind == 1u8 { ret "Or" }
    if kind == 2u8 { ret "Not And" }
    ret "Not Or"
}

fn crit_next_listed(grid: *const Grid, from: usize) -> usize {
    var step = 1usize
    while step <= grid.all.len {
        let at = (from + step) % grid.all.len
        if sort_row_listed(grid, at) { ret at }
        step += 1usize
    }
    ret from
}

// Whether `word` is one of the comma separated entries of condition `index`s value.
fn crit_has_value(grid: *const Grid, index: usize, word: str) -> bool {
    let text = grid.crit_text[index * CRIT_TEXT..index * CRIT_TEXT + grid.crit_len[index]]
    var start = 0usize
    var at = 0usize
    while at <= text.len {
        if at == text.len || text[at] == 44u8 {
            var from = start
            var to = at
            while from < to && text[from] == 32u8 { from += 1usize }
            while to > from && text[to - 1usize] == 32u8 { to -= 1usize }
            if same_text(text[from..to], word) { ret true }
            start = at + 1usize
        }
        at += 1usize
    }
    ret false
}

// Adds the dictionary entry `id` of the condition column to its value list, or takes it out.
fn crit_toggle_value(grid: *Grid, index: usize, id: usize) {
    let column = grid.all[grid.crit_spec[index]].column
    if id >= table.dict_len(grid.t, column) { ret }
    let word = table.dict_str(grid.t, column, u32(id))
    let had = crit_has_value(grid, index, word)
    var buf: [32]u8 = zero
    var len = 0usize
    let text = grid.crit_text[index * CRIT_TEXT..index * CRIT_TEXT + grid.crit_len[index]]
    var start = 0usize
    var at = 0usize
    while at <= text.len {
        if at == text.len || text[at] == 44u8 {
            var from = start
            var to = at
            while from < to && text[from] == 32u8 { from += 1usize }
            while to > from && text[to - 1usize] == 32u8 { to -= 1usize }
            if to > from && !(had && same_text(text[from..to], word)) {
                if len != 0usize && len < 31usize {
                    buf[len] = 44u8
                    len += 1usize
                }
                var c = from
                while c < to && len < 32usize {
                    buf[len] = text[c]
                    len += 1usize
                    c += 1usize
                }
            }
            start = at + 1usize
        }
        at += 1usize
    }
    if !had {
        if len != 0usize && len < 31usize {
            buf[len] = 44u8
            len += 1usize
        }
        var w = 0usize
        while w < word.len && len < 32usize {
            buf[len] = word[w]
            len += 1usize
            w += 1usize
        }
    }
    var k = 0usize
    while k < len {
        grid.crit_text[index * CRIT_TEXT + k] = buf[k]
        k += 1usize
    }
    grid.crit_len[index] = len
}

fn on_crit_tap(ctx: *void, g: widget.Gesture) -> err {
    let row = mem.cast[*CritRow](ctx)
    let grid = row.grid
    switch g {
    case .Tap as at:
        if row.part == 9u8 {
            // v3 opens a list of the four group operators under the word
            grid.crit_pop = !grid.crit_pop
            grid.crit_pop_kind = 0u8
            ret ok
        }
        if row.part == 20u8 || row.part == 21u8 || row.part == 22u8 || row.part == 23u8 {
            grid.crit_group = row.part - 20u8
            grid.crit_pop = false
            ret ok
        }
        if row.part == 12u8 {
            grid.crit_pop = !grid.crit_pop
            grid.crit_pop_kind = 3u8
            grid.crit_pop_row = row.index
            ret ok
        }
        if row.part >= 100u8 && grid.crit_pop_row < grid.crit_count {
            crit_toggle_value(grid, grid.crit_pop_row, usize(row.part - 100u8))
            ret ok
        }
        if row.part >= 40u8 && row.part < 40u8 + 12u8 && grid.crit_pop_row < grid.crit_count {
            grid.crit_op[grid.crit_pop_row] = row.part - 40u8
            grid.crit_pop = false
            ret ok
        }
        if row.part >= 60u8 && row.part < 60u8 + 40u8 && grid.crit_pop_row < grid.crit_count {
            grid.crit_spec[grid.crit_pop_row] = usize(row.part - 60u8)
            grid.crit_pop = false
            ret ok
        }
        if row.index >= grid.crit_count { ret ok }
        if row.part == 0u8 {
            // the "..." button: takes the condition out
            var i = row.index
            while i + 1usize < grid.crit_count {
                grid.crit_spec[i] = grid.crit_spec[i + 1usize]
                grid.crit_op[i] = grid.crit_op[i + 1usize]
                grid.crit_len[i] = grid.crit_len[i + 1usize]
                var c = 0usize
                while c < CRIT_TEXT {
                    grid.crit_text[i * CRIT_TEXT + c] = grid.crit_text[(i + 1usize) * CRIT_TEXT + c]
                    c += 1usize
                }
                i += 1usize
            }
            grid.crit_count -= 1usize
        }
        if row.part == 1u8 || row.part == 2u8 {
            // v3 opens a list under the column or the operator word
            grid.crit_pop = !grid.crit_pop
            grid.crit_pop_kind = row.part
            grid.crit_pop_row = row.index
        }
        ret ok
    default:
        ret ok
    }
}

fn on_crit_value(ctx: *void, value: str) -> err {
    let pick = mem.cast[*CritValue](ctx)
    let grid = pick.grid
    if pick.index >= grid.crit_count { ret ok }
    var n = value.len
    if n > CRIT_TEXT { n = CRIT_TEXT }
    var c = 0usize
    while c < n {
        grid.crit_text[pick.index * CRIT_TEXT + c] = value[c]
        c += 1usize
    }
    grid.crit_len[pick.index] = n
    ret ok
}

// 0 add a condition, 1 OK, 2 Cancel, 3 Apply.
fn on_crit_act(ctx: *void, g: widget.Gesture) -> err {
    let act = mem.cast[*CritAct](ctx)
    let grid = act.grid
    switch g {
    case .Tap as at:
        if act.kind == 0u8 {
            if grid.crit_count < CRIT_MAX {
                grid.crit_spec[grid.crit_count] = crit_next_listed(grid, grid.all.len - 1usize)
                grid.crit_op[grid.crit_count] = 0u8
                grid.crit_len[grid.crit_count] = 0usize
                grid.crit_count += 1usize
            }
            ret ok
        }
        if act.kind == 6u8 {
            // put the last condition into the nested group, or take it out again
            if grid.crit_count > 0usize {
                let last = grid.crit_count - 1usize
                grid.crit_sub[last] = !grid.crit_sub[last]
            }
            ret ok
        }
        if act.kind == 7u8 {
            grid.crit_sub_group = (grid.crit_sub_group + 1u8) % 4u8
            ret ok
        }
        if act.kind == 4u8 || act.kind == 5u8 {
            // Open... (4) and Save As... (5): the application reads or writes the text of the conditions
            grid.crit_io = act.kind - 3u8
            ret ok
        }
        if act.kind == 1u8 || act.kind == 3u8 { grid.crit_pending = true }
        if act.kind != 3u8 { grid.crit_open = false }
        ret ok
    default:
        ret ok
    }
}

fn open_criteria_editor(grid: *Grid) {
    raise_window(grid, 3u8)
    grid.crit_open = true
}

// 0 none, 1 the user asked to open a saved filter, 2 to save the conditions; taken once.
fn take_criteria_io(grid: *Grid) -> u8 {
    let kind = grid.crit_io
    grid.crit_io = 0u8
    ret kind
}

// The conditions as text: the group operator, then one line `column-index operator-index value`.
fn criteria_text(a: *mem.Arena, grid: *const Grid) -> (str, err) {
    let (b, b_error) = str.builder(a, 64usize + grid.crit_count * (CRIT_TEXT + 24usize))
    if b_error != ok { ret ("", b_error) }
    var sb = b
    if str.push(&sb, "filter 1\ngroup ") != ok || str.push_usize(&sb, usize(grid.crit_group)) != ok { ret ("", control.TooLarge) }
    if str.push(&sb, "\nsubgroup ") != ok || str.push_usize(&sb, usize(grid.crit_sub_group)) != ok { ret ("", control.TooLarge) }
    var i = 0usize
    while i < grid.crit_count {
        if grid.crit_sub[i] {
            if str.push(&sb, "\nsub ") != ok || str.push_usize(&sb, i) != ok { ret ("", control.TooLarge) }
        }
        if str.push(&sb, "\ncond ") != ok || str.push_usize(&sb, grid.crit_spec[i]) != ok || str.push(&sb, " ") != ok || str.push_usize(&sb, usize(grid.crit_op[i])) != ok || str.push(&sb, " ") != ok { ret ("", control.TooLarge) }
        if str.push(&sb, grid.crit_text[i * CRIT_TEXT..i * CRIT_TEXT + grid.crit_len[i]]) != ok { ret ("", control.TooLarge) }
        i += 1usize
    }
    if str.push(&sb, "\n") != ok { ret ("", control.TooLarge) }
    ret (str.done(&sb), ok)
}

// Takes conditions written by `criteria_text`; a text that is not one changes nothing.
fn load_criteria(grid: *Grid, text: str) -> bool {
    if text.len < 9usize { ret false }
    var rest = text
    var first = true
    var count = 0usize
    var group = grid.crit_group
    var sub_group: u8 = 0u8
    var subs: [6]bool = zero
    var specs: [6]usize = zero
    var ops: [6]u8 = zero
    var lens: [6]usize = zero
    var values: [192]u8 = zero
    while rest.len > 0usize {
        var end = 0usize
        while end < rest.len && rest[end] != 10u8 { end += 1usize }
        let line = rest[0usize..end]
        if end < rest.len { rest = rest[end + 1usize..] } else { rest = rest[rest.len..] }
        let (head, tail) = next_token(line)
        if first {
            if !same_text(head, "filter") { ret false }
            first = false
        } else if same_text(head, "group") {
            let (n, ok_n) = str.parse_u64(tail)
            if ok_n != ok || n > 3u64 { ret false }
            group = u8(n)
        } else if same_text(head, "subgroup") {
            let (sg, sg_ok) = str.parse_u64(tail)
            if sg_ok != ok || sg > 3u64 { ret false }
            sub_group = u8(sg)
        } else if same_text(head, "sub") {
            let (si, si_ok) = str.parse_u64(tail)
            if si_ok == ok && si < 6u64 { subs[usize(si)] = true }
        } else if same_text(head, "cond") && count < 6usize {
            let (spec_word, after_spec) = next_token(tail)
            let (op_word, value_text) = next_token(after_spec)
            let (spec_n, spec_ok) = str.parse_u64(spec_word)
            let (op_n, op_ok) = str.parse_u64(op_word)
            if spec_ok != ok || op_ok != ok || usize(spec_n) >= grid.all.len || op_n > 11u64 { ret false }
            specs[count] = usize(spec_n)
            ops[count] = u8(op_n)
            var m = value_text.len
            if m > CRIT_TEXT { m = CRIT_TEXT }
            var c = 0usize
            while c < m {
                values[count * CRIT_TEXT + c] = value_text[c]
                c += 1usize
            }
            lens[count] = m
            count += 1usize
        }
    }
    if first { ret false }
    grid.crit_group = group
    grid.crit_sub_group = sub_group
    grid.crit_count = count
    var sj = 0usize
    while sj < 6usize {
        grid.crit_sub[sj] = subs[sj] && sj < count
        sj += 1usize
    }
    var k = 0usize
    while k < count {
        grid.crit_spec[k] = specs[k]
        grid.crit_op[k] = ops[k]
        grid.crit_len[k] = lens[k]
        var c2 = 0usize
        while c2 < lens[k] {
            grid.crit_text[k * CRIT_TEXT + c2] = values[k * CRIT_TEXT + c2]
            c2 += 1usize
        }
        k += 1usize
    }
    ret true
}

// The application takes the conditions once after OK or Apply.
fn take_criteria(grid: *Grid) -> bool {
    if !grid.crit_pending { ret false }
    grid.crit_pending = false
    ret true
}

fn criteria_group(grid: *const Grid) -> u8 { ret grid.crit_group }
fn criteria_sub_group(grid: *const Grid) -> u8 { ret grid.crit_sub_group }
// Whether condition `index` stands in the nested group (v3 nests groups under the root).
fn criteria_in_sub(grid: *const Grid, index: usize) -> bool { ret index < 6usize && grid.crit_sub[index] }
fn criteria_len(grid: *const Grid) -> usize { ret grid.crit_count }
fn criteria_column(grid: *const Grid, index: usize) -> usize { ret grid.all[grid.crit_spec[index]].column }
fn criteria_op(grid: *const Grid, index: usize) -> u8 { ret grid.crit_op[index] }
fn criteria_value(grid: *const Grid, index: usize) -> str { ret grid.crit_text[index * CRIT_TEXT..index * CRIT_TEXT + grid.crit_len[index]] }

fn crit_word(a: *mem.Arena, grid: *Grid, key: widget.Key, text: str, ink: paint.Color, row: *CritRow) -> (widget.Node, err) {
    let (label, label_error) = flat_text(a, grid, text, ink)
    if label_error != ok { ret (zero, label_error) }
    let (underline, underline_error) = mem.alloc[widget.Node](a, 2usize)
    if underline_error != ok { ret (zero, control.TooLarge) }
    underline[0usize] = label
    var rule = control.sized_style(f32(text.len) * 6.6, 1.0)
    rule.background = paint.Brush { Solid: ink }
    underline[1usize] = widget.box(0u64, rule, zero)
    let stacked = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), underline[0usize..2usize])
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, control.TooLarge) }
    held[0usize] = stacked
    ret (widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](row), invoke: on_crit_tap }, gestures: 1u8, enabled: true, focusable: false }, style.defaults(), held[0usize..1usize]), ok)
}

fn crit_button(a: *mem.Arena, grid: *Grid, key: widget.Key, text: str, w: f32, act: *CritAct, default_button: bool) -> (widget.Node, err) {
    let (label, label_error) = flat_text(a, grid, text, gl.rgb(0x000000u32))
    if label_error != ok { ret (zero, label_error) }
    var box = control.sized_style(w, 27.0)
    box.background = paint.Brush { Solid: gl.rgb(0xFDFDFDu32) }
    box.radius = 4.0
    box.border = style.Border { width: 1.0, color: gl.rgb(0xADADADu32) }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, control.TooLarge) }
    var centred = style.defaults()
    centred.width = style.Length { Percent: 100.0 }
    centred.height = style.Length { Percent: 100.0 }
    held[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Center, cross: .Center, gap: 0.0 }, centred, one(a, label))
    ret (widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](act), invoke: on_crit_act }, gestures: 1u8, enabled: true, focusable: false }, box, held[0usize..1usize]), ok)
}

fn criteria_panel(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let width: f32 = 540.0
    let (rows, rows_error) = mem.alloc[widget.Node](a, CRIT_MAX + 8usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    let (parts, parts_error) = mem.alloc[CritRow](a, CRIT_MAX * 3usize + 2usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    let (values, values_error) = mem.alloc[CritValue](a, CRIT_MAX)
    if values_error != ok { ret (zero, control.TooLarge) }
    let (acts, acts_error) = mem.alloc[CritAct](a, 8usize)
    if acts_error != ok { ret (zero, control.TooLarge) }
    var k = 0usize
    while k < 8usize {
        acts[k] = CritAct { grid: grid, kind: u8(k) }
        k += 1usize
    }
    var n = 0usize
    let (title_row, title_error) = window_title(a, grid, 3u8, "Advanced Filter", width, 40.0, false)
    if title_error != ok { ret (zero, title_error) }
    rows[n] = title_row
    n += 1usize
    // Filter  And  <root>
    let (filter_label, filter_error) = flat_text(a, grid, "Filter", gl.rgb(0x000000u32))
    if filter_error != ok { ret (zero, filter_error) }
    parts[0usize] = CritRow { grid: grid, index: 0usize, part: 9u8 }
    let (group_word, group_error) = crit_word(a, grid, grid.key + MENU_KEY + 899900u64, crit_group_words(grid.crit_group), gl.rgb(0xFF0000u32), &parts[0usize])
    if group_error != ok { ret (zero, group_error) }
    let (root_label, root_error) = flat_text(a, grid, "<root>", gl.rgb(0x000000u32))
    if root_error != ok { ret (zero, root_error) }
    let (head, head_error) = mem.alloc[widget.Node](a, 3usize)
    if head_error != ok { ret (zero, control.TooLarge) }
    var filter_box = control.sized_style(44.0, 22.0)
    filter_box.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    filter_box.border = style.Border { width: 1.0, color: gl.rgb(0x9A9A9Au32) }
    filter_box.radius = 4.0
    head[0usize] = widget.aligned(0u64, .Center, .Center, filter_box, one(a, filter_label))
    head[1usize] = group_word
    head[2usize] = root_label
    var head_style = control.sized_style(width - 24.0, 30.0)
    head_style.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 6.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
    rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 12.0 }, head_style, head[0usize..3usize])
    n += 1usize
    var i = 0usize
    while i < grid.crit_count {
        parts[1usize + i * 3usize] = CritRow { grid: grid, index: i, part: 0u8 }
        parts[2usize + i * 3usize] = CritRow { grid: grid, index: i, part: 1u8 }
        parts[3usize + i * 3usize] = CritRow { grid: grid, index: i, part: 2u8 }
        values[i] = CritValue { grid: grid, index: i }
        let (dots_text, dots_error) = flat_text(a, grid, "...", gl.rgb(0x000000u32))
        if dots_error != ok { ret (zero, dots_error) }
        var dots_box = control.sized_style(24.0, 20.0)
        dots_box.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
        dots_box.border = style.Border { width: 1.0, color: gl.rgb(0x9A9A9Au32) }
        dots_box.radius = 4.0
        let (dots_held, dots_held_error) = mem.alloc[widget.Node](a, 1usize)
        if dots_held_error != ok { ret (zero, control.TooLarge) }
        dots_held[0usize] = widget.aligned(0u64, .Center, .Center, style.defaults(), one(a, dots_text))
        let dots = widget.region(grid.key + MENU_KEY + 899910u64 + u64(i) * 4u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&parts[1usize + i * 3usize]), invoke: on_crit_tap }, gestures: 1u8, enabled: true, focusable: false }, dots_box, dots_held[0usize..1usize])
        let (column_word, column_error) = crit_word(a, grid, grid.key + MENU_KEY + 899911u64 + u64(i) * 4u64, grid.all[grid.crit_spec[i]].title, gl.rgb(0x008000u32), &parts[2usize + i * 3usize])
        if column_error != ok { ret (zero, column_error) }
        let (op_word, op_error) = crit_word(a, grid, grid.key + MENU_KEY + 899912u64 + u64(i) * 4u64, crit_op_words(grid.crit_op[i]), gl.rgb(0x8B0000u32), &parts[3usize + i * 3usize])
        if op_error != ok { ret (zero, op_error) }
        var options = control.field_options()
        let buffer = grid.crit_text[i * CRIT_TEXT..(i + 1usize) * CRIT_TEXT]
        let (field, field_error) = control.text_field(a, grid.key + MENU_KEY + 899913u64 + u64(i) * 4u64, grid.theme, "Value", buffer, grid.crit_len[i], widget.Change[str] { ctx: mem.cast[*void](&values[i]), invoke: on_crit_value }, zero, options)
        if field_error != ok { ret (zero, field_error) }
        var field_box = control.sized_style(180.0, 28.0)
        let (cells, cells_error) = mem.alloc[widget.Node](a, 4usize)
        if cells_error != ok { ret (zero, control.TooLarge) }
        cells[0usize] = dots
        cells[1usize] = column_word
        cells[2usize] = op_word
        cells[3usize] = widget.padded(0u64, 0.0, 0.0, 0.0, 0.0, field_box, one(a, field))
        var value_listed = false
        if (grid.crit_op[i] == 10u8 || grid.crit_op[i] == 11u8) && table.column_kind(grid.t, grid.all[grid.crit_spec[i]].column) == table.Kind.Dict && table.dict_len(grid.t, grid.all[grid.crit_spec[i]].column) <= 40usize { value_listed = true }
        if value_listed {
            // v3 offers the values of the column as a checked list
            let (list_cells, list_cells_error) = mem.alloc[widget.Node](a, 5usize)
            if list_cells_error != ok { ret (zero, list_cells_error) }
            var li = 0usize
            while li < 4usize {
                list_cells[li] = cells[li]
                li += 1usize
            }
            let (pick_text, pick_text_error) = flat_text(a, grid, "Values...", gl.rgb(0x000000u32))
            if pick_text_error != ok { ret (zero, pick_text_error) }
            var pick_box = control.sized_style(80.0, 26.0)
            pick_box.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
            pick_box.border = style.Border { width: 1.0, color: gl.rgb(0x9A9A9Au32) }
            pick_box.radius = 4.0
            let (value_picks, value_picks_error) = mem.alloc[CritRow](a, 1usize)
            if value_picks_error != ok { ret (zero, control.TooLarge) }
            value_picks[0usize] = CritRow { grid: grid, index: i, part: 12u8 }
            list_cells[4usize] = widget.region(grid.key + MENU_KEY + 899914u64 + u64(i) * 4u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&value_picks[0usize]), invoke: on_crit_tap }, gestures: 1u8, enabled: true, focusable: false }, pick_box, one(a, widget.padded(0u64, 6.0, 4.0, 0.0, 0.0, style.defaults(), one(a, pick_text))))
            var list_line = control.sized_style(width - 24.0, 30.0)
            list_line.margin = style.EdgeLengths { left: style.Length { Px: 32.0 }, top: style.Length { Px: 4.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
            rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, list_line, list_cells[0usize..5usize])
            n += 1usize
            i += 1usize
            continue
        }
        var line_style = control.sized_style(width - 24.0, 30.0)
        var line_left: f32 = 32.0
        if grid.crit_sub[i] { line_left = 64.0 }
        line_style.margin = style.EdgeLengths { left: style.Length { Px: line_left }, top: style.Length { Px: 4.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
        rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 12.0 }, line_style, cells[0usize..4usize])
        n += 1usize
        i += 1usize
    }
    // "press the button to add a new condition"
    let (add_button, add_error) = crit_button(a, grid, grid.key + MENU_KEY + 899990u64, "press the button to add a new condition", 280.0, &acts[0usize], false)
    if add_error != ok { ret (zero, add_error) }
    var add_style = control.sized_style(280.0, 27.0)
    add_style.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 6.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    let (add_held, add_held_error) = mem.alloc[widget.Node](a, 1usize)
    if add_held_error != ok { ret (zero, control.TooLarge) }
    add_held[0usize] = add_button
    rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, add_style, add_held[0usize..1usize])
    n += 1usize
    // the nested group: its operator and the button that moves the last condition into it
    var sub_words = "Nested group: "
    if true { sub_words = "Nested group" }
    let (group_button, group_button_error) = crit_button(a, grid, grid.key + MENU_KEY + 899996u64, "Move the last condition into / out of the nested group", 340.0, &acts[6usize], false)
    if group_button_error != ok { ret (zero, group_button_error) }
    let (sub_button, sub_button_error) = crit_button(a, grid, grid.key + MENU_KEY + 899997u64, crit_group_words(grid.crit_sub_group), 80.0, &acts[7usize], false)
    if sub_button_error != ok { ret (zero, sub_button_error) }
    let (sub_pair, sub_pair_error) = mem.alloc[widget.Node](a, 2usize)
    if sub_pair_error != ok { ret (zero, control.TooLarge) }
    sub_pair[0usize] = group_button
    sub_pair[1usize] = sub_button
    var sub_style = control.sized_style(width - 24.0, 27.0)
    sub_style.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 6.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, sub_style, sub_pair[0usize..2usize])
    n += 1usize
    var filler_height = 190.0 - f32(grid.crit_count) * 34.0 - 34.0
    if filler_height < 0.0 { filler_height = 0.0 }
    var filler = control.sized_style(width - 24.0, filler_height)
    filler.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
    rows[n] = widget.box(0u64, filler, zero)
    n += 1usize
    let (b_open, e_open) = crit_button(a, grid, grid.key + MENU_KEY + 899991u64, "Open...", 80.0, &acts[4usize], false)
    if e_open != ok { ret (zero, e_open) }
    let (b_save, e_save) = crit_button(a, grid, grid.key + MENU_KEY + 899992u64, "Save As...", 80.0, &acts[5usize], false)
    if e_save != ok { ret (zero, e_save) }
    let (b_ok, e_ok) = crit_button(a, grid, grid.key + MENU_KEY + 899993u64, "OK", 80.0, &acts[1usize], true)
    if e_ok != ok { ret (zero, e_ok) }
    let (b_cancel, e_cancel) = crit_button(a, grid, grid.key + MENU_KEY + 899994u64, "Cancel", 80.0, &acts[2usize], false)
    if e_cancel != ok { ret (zero, e_cancel) }
    let (b_apply, e_apply) = crit_button(a, grid, grid.key + MENU_KEY + 899995u64, "Apply", 80.0, &acts[3usize], false)
    if e_apply != ok { ret (zero, e_apply) }
    let (left_foot, left_foot_error) = mem.alloc[widget.Node](a, 2usize)
    if left_foot_error != ok { ret (zero, control.TooLarge) }
    left_foot[0usize] = b_open
    left_foot[1usize] = b_save
    let (right_foot, right_foot_error) = mem.alloc[widget.Node](a, 3usize)
    if right_foot_error != ok { ret (zero, control.TooLarge) }
    right_foot[0usize] = b_ok
    right_foot[1usize] = b_cancel
    right_foot[2usize] = b_apply
    let (foot, foot_error) = mem.alloc[widget.Node](a, 2usize)
    if foot_error != ok { ret (zero, control.TooLarge) }
    foot[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 6.0 }, style.defaults(), left_foot[0usize..2usize])
    foot[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 6.0 }, style.defaults(), right_foot[0usize..3usize])
    var foot_style = control.sized_style(width - 24.0, 46.0)
    foot_style.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 6.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
    rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .SpaceBetween, cross: .Center, gap: 8.0 }, foot_style, foot[0usize..2usize])
    n += 1usize
    var body_style = control.sized_style(width, 360.0)
    body_style.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    body_style.border = style.Border { width: 1.0, color: gl.rgb(0x6D6D6Du32) }
    body_style.radius = 8.0
    body_style.overflow = .Clip
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, control.TooLarge) }
    inner[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), rows[0usize..n])
    let (framed, framed_error) = window_body(a, grid, 3u8, body_style, inner[0usize..1usize])
    if framed_error != ok { ret (zero, framed_error) }
    if !grid.crit_pop { ret (framed, ok) }
    if grid.crit_pop_kind == 3u8 && grid.crit_pop_row < grid.crit_count {
        // the values of the column with a check before each chosen one
        let value_column = grid.all[grid.crit_spec[grid.crit_pop_row]].column
        var value_total = table.dict_len(grid.t, value_column)
        if value_total > 14usize { value_total = 14usize }
        let (value_rows, value_rows_error) = mem.alloc[widget.Node](a, value_total + 1usize)
        if value_rows_error != ok { ret (zero, control.TooLarge) }
        let (value_picks, value_picks_error) = mem.alloc[CritRow](a, value_total + 1usize)
        if value_picks_error != ok { ret (zero, control.TooLarge) }
        var vi = 0usize
        while vi < value_total {
            let entry_word = table.dict_str(grid.t, value_column, u32(vi))
            value_picks[vi] = CritRow { grid: grid, index: grid.crit_pop_row, part: u8(100usize + vi) }
            let chosen = crit_has_value(grid, grid.crit_pop_row, entry_word)
            let (entry_text, entry_text_error) = flat_text(a, grid, entry_word, gl.rgb(0x000000u32))
            if entry_text_error != ok { ret (zero, entry_text_error) }
            var mark_box = control.sized_style(14.0, 14.0)
            mark_box.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
            mark_box.border = style.Border { width: 1.0, color: gl.rgb(0x333333u32) }
            let (mark_held, mark_held_error) = mem.alloc[widget.Node](a, 1usize)
            if mark_held_error != ok { ret (zero, control.TooLarge) }
            if chosen {
                let (tick, tick_error) = gl.mark(a, .Check, gl.rgb(0x005FB8u32), gl.rgb(0x005FB8u32), 10.0, 10.0)
                if tick_error != ok { ret (zero, tick_error) }
                mark_held[0usize] = tick
            } else {
                mark_held[0usize] = widget.box(0u64, style.defaults(), zero)
            }
            let (entry_parts, entry_parts_error) = mem.alloc[widget.Node](a, 2usize)
            if entry_parts_error != ok { ret (zero, control.TooLarge) }
            entry_parts[0usize] = widget.aligned(0u64, .Center, .Center, mark_box, mark_held[0usize..1usize])
            entry_parts[1usize] = widget.padded(0u64, 8.0, 0.0, 0.0, 0.0, style.defaults(), one(a, entry_text))
            var entry_style = control.sized_style(150.0, 24.0)
            entry_style.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
            let entry_line = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), entry_parts[0usize..2usize])
            value_rows[vi] = widget.region(grid.key + MENU_KEY + 899940u64 + u64(vi), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&value_picks[vi]), invoke: on_crit_tap }, gestures: 1u8, enabled: true, focusable: false }, entry_style, one(a, widget.padded(0u64, 8.0, 5.0, 0.0, 0.0, style.defaults(), one(a, entry_line))))
            vi += 1usize
        }
        var value_list_style = style.defaults()
        value_list_style.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
        value_list_style.border = style.Border { width: 1.0, color: gl.rgb(0x8E9092u32) }
        let value_list = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, value_list_style, value_rows[0usize..value_total])
        let (value_held, value_held_error) = mem.alloc[widget.Node](a, 1usize)
        if value_held_error != ok { ret (zero, control.TooLarge) }
        value_held[0usize] = value_list
        let (value_layers, value_layers_error) = mem.alloc[widget.Node](a, 2usize)
        if value_layers_error != ok { ret (zero, control.TooLarge) }
        value_layers[0usize] = framed
        value_layers[1usize] = widget.positioned(0u64, 400.0, 84.0 + 34.0 * f32(grid.crit_pop_row) + 26.0, style.defaults(), value_held[0usize..1usize])
        ret (widget.stack(0u64, style.defaults(), value_layers[0usize..2usize]), ok)
    }
    if grid.crit_pop_kind == 1u8 || grid.crit_pop_kind == 2u8 {
        // the columns or the operators of a condition, as a plain list under its word
        var entries: [40]usize = zero
        var entry_count = 0usize
        var current_entry = 0usize
        if grid.crit_pop_kind == 2u8 {
            // v3's list depends on the column: an image combo or a flag offers equals and blank only
            var small_list = false
            if grid.crit_pop_row < grid.crit_count {
                let crit_col = grid.all[grid.crit_spec[grid.crit_pop_row]]
                if crit_col.kind == CellKind.Star || crit_col.kind == CellKind.Bool || crit_col.choice { small_list = true }
            }
            if small_list {
                entries[0usize] = 0usize
                entries[1usize] = 1usize
                entries[2usize] = 8usize
                entries[3usize] = 9usize
                entries[4usize] = 10usize
                entries[5usize] = 11usize
                entry_count = 6usize
            } else {
                var oi = 0usize
                while oi < 8usize {
                    entries[oi] = oi
                    oi += 1usize
                }
                entries[8usize] = 8usize
                entries[9usize] = 9usize
                entries[10usize] = 10usize
                entries[11usize] = 11usize
                entry_count = 12usize
            }
            if grid.crit_pop_row < grid.crit_count { current_entry = usize(grid.crit_op[grid.crit_pop_row]) }
        } else {
            var ci = 0usize
            while ci < grid.all.len && entry_count < 40usize {
                if sort_row_listed(grid, ci) {
                    entries[entry_count] = ci
                    entry_count += 1usize
                }
                ci += 1usize
            }
            if grid.crit_pop_row < grid.crit_count { current_entry = grid.crit_spec[grid.crit_pop_row] }
        }
        let (list_rows, list_rows_error) = mem.alloc[widget.Node](a, entry_count + 1usize)
        if list_rows_error != ok { ret (zero, control.TooLarge) }
        let (list_picks, list_picks_error) = mem.alloc[CritRow](a, entry_count + 1usize)
        if list_picks_error != ok { ret (zero, control.TooLarge) }
        var ei = 0usize
        while ei < entry_count {
            var part_code = 60u8 + u8(entries[ei])
            var label_text = grid.all[entries[ei]].title
            if grid.crit_pop_kind == 2u8 {
                part_code = 40u8 + u8(entries[ei])
                label_text = crit_op_words(u8(entries[ei]))
            }
            list_picks[ei] = CritRow { grid: grid, index: 0usize, part: part_code }
            let (entry_label, entry_label_error) = flat_text(a, grid, label_text, gl.rgb(0x000000u32))
            if entry_label_error != ok { ret (zero, entry_label_error) }
            var entry_box = control.sized_style(122.0, 22.0)
            entry_box.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
            if entries[ei] == current_entry { entry_box.background = paint.Brush { Solid: gl.rgb(0x99D1FFu32) } }
            // v3's icons of the operators: = and the not-equal sign, the blank discs, the pair of discs
            var icon: widget.Node = zero
            var has_icon = false
            if grid.crit_pop_kind == 2u8 {
                let code = entries[ei]
                var ink_icon = gl.rgb(0x2E9E2Eu32)
                if code == 11usize { ink_icon = gl.rgb(0xC62828u32) }
                if code == 0usize || code == 1usize {
                    var sign = "="
                    if code == 1usize { sign = "≠" }
                    let (sign_node, sign_error) = flat_text(a, grid, sign, gl.rgb(0x000000u32))
                    if sign_error != ok { ret (zero, sign_error) }
                    icon = sign_node
                    has_icon = true
                } else if code == 8usize || code == 9usize {
                    var disc = control.sized_style(11.0, 11.0)
                    disc.radius = 5.5
                    if code == 9usize { disc.background = paint.Brush { Solid: ink_icon } } else { disc.border = style.Border { width: 1.0, color: ink_icon } }
                    icon = widget.box(0u64, disc, zero)
                    has_icon = true
                } else if code == 10usize || code == 11usize {
                    var first_disc = control.sized_style(10.0, 10.0)
                    first_disc.radius = 5.0
                    first_disc.background = paint.Brush { Solid: ink_icon }
                    let (pair_nodes, pair_nodes_error) = mem.alloc[widget.Node](a, 2usize)
                    if pair_nodes_error != ok { ret (zero, control.TooLarge) }
                    pair_nodes[0usize] = widget.box(0u64, first_disc, zero)
                    pair_nodes[1usize] = widget.box(0u64, first_disc, zero)
                    icon = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), pair_nodes[0usize..2usize])
                    has_icon = true
                }
            }
            let (entry_parts, entry_parts_error) = mem.alloc[widget.Node](a, 2usize)
            if entry_parts_error != ok { ret (zero, control.TooLarge) }
            var gutter = control.sized_style(32.0, 22.0)
            if has_icon {
                entry_parts[0usize] = widget.aligned(0u64, .Center, .Center, gutter, one(a, icon))
            } else {
                entry_parts[0usize] = widget.box(0u64, gutter, zero)
            }
            entry_parts[1usize] = entry_label
            let entry_line = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), entry_parts[0usize..2usize])
            list_rows[ei] = widget.region(grid.key + MENU_KEY + 899930u64 + u64(ei), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&list_picks[ei]), invoke: on_crit_tap }, gestures: 1u8, enabled: true, focusable: false }, entry_box, one(a, entry_line))
            ei += 1usize
        }
        var list_style = style.defaults()
        list_style.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
        list_style.border = style.Border { width: 1.0, color: gl.rgb(0x8E9092u32) }
        // v3 shows twelve entries and a scroll bar; the list here shows the first twelve
        var visible_entries = entry_count
        if visible_entries > 12usize { visible_entries = 12usize }
        let word_list = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, list_style, list_rows[0usize..visible_entries])
        let (word_held, word_held_error) = mem.alloc[widget.Node](a, 1usize)
        if word_held_error != ok { ret (zero, control.TooLarge) }
        word_held[0usize] = word_list
        let (word_layers, word_layers_error) = mem.alloc[widget.Node](a, 2usize)
        if word_layers_error != ok { ret (zero, control.TooLarge) }
        word_layers[0usize] = framed
        var list_x: f32 = 96.0
        if grid.crit_pop_kind == 2u8 { list_x = 200.0 }
        word_layers[1usize] = widget.positioned(0u64, list_x, 84.0 + 34.0 * f32(grid.crit_pop_row) + 26.0, style.defaults(), word_held[0usize..1usize])
        ret (widget.stack(0u64, style.defaults(), word_layers[0usize..2usize]), ok)
    }
    // the group operators as v3's popup: a ring or a filled pair of circles, the name, the current one light blue
    let (pop_rows, pop_rows_error) = mem.alloc[widget.Node](a, 4usize)
    if pop_rows_error != ok { ret (zero, control.TooLarge) }
    let (pop_picks, pop_picks_error) = mem.alloc[CritRow](a, 4usize)
    if pop_picks_error != ok { ret (zero, control.TooLarge) }
    var pi = 0usize
    while pi < 4usize {
        pop_picks[pi] = CritRow { grid: grid, index: 0usize, part: u8(20usize + pi) }
        var glyph_ink = gl.rgb(0x555555u32)
        if pi == 1usize { glyph_ink = gl.rgb(0x2E9E2Eu32) }
        if pi == 2usize { glyph_ink = gl.rgb(0xC62828u32) }
        if pi == 3usize { glyph_ink = gl.rgb(0xC62828u32) }
        // a ring (And, Not And) or a filled disc (Or, Not Or), green or red when negated
        var disc = control.sized_style(12.0, 12.0)
        disc.radius = 6.0
        if pi == 1usize || pi == 3usize {
            disc.background = paint.Brush { Solid: glyph_ink }
        } else {
            disc.border = style.Border { width: 2.0, color: glyph_ink }
        }
        let glyph = widget.box(0u64, disc, zero)
        let (name, name_error) = flat_text(a, grid, crit_group_words(u8(pi)), gl.rgb(0x000000u32))
        if name_error != ok { ret (zero, name_error) }
        let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
        if pair_error != ok { ret (zero, control.TooLarge) }
        pair[0usize] = widget.padded(0u64, 8.0, 0.0, 8.0, 0.0, style.defaults(), one(a, glyph))
        pair[1usize] = name
        var entry = control.sized_style(104.0, 26.0)
        entry.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
        if grid.crit_group == u8(pi) { entry.background = paint.Brush { Solid: gl.rgb(0x99D1FFu32) } }
        pop_rows[pi] = widget.region(grid.key + MENU_KEY + 899960u64 + u64(pi), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&pop_picks[pi]), invoke: on_crit_tap }, gestures: 1u8, enabled: true, focusable: false }, entry, one(a, widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), pair[0usize..2usize])))
        pi += 1usize
    }
    var pop_style = style.defaults()
    pop_style.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    pop_style.border = style.Border { width: 1.0, color: gl.rgb(0x8E9092u32) }
    let pop = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, pop_style, pop_rows[0usize..4usize])
    let (pop_held, pop_held_error) = mem.alloc[widget.Node](a, 1usize)
    if pop_held_error != ok { ret (zero, control.TooLarge) }
    pop_held[0usize] = pop
    let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
    if layers_error != ok { ret (zero, control.TooLarge) }
    layers[0usize] = framed
    layers[1usize] = widget.positioned(0u64, 76.0, 84.0, style.defaults(), pop_held[0usize..1usize])
    ret (widget.stack(0u64, style.defaults(), layers[0usize..2usize]), ok)
}

// ---- the Conditional Formatting Rule wizard (New Rule... of the rules manager: ten rule types) ----

type WizRow = struct { grid: *Grid, index: u8 }
type WizText = struct { grid: *Grid, maximum: bool }

// The colours of the wizard's Format...: the low, middle and high colour of a scale, the bar colour.
fn wiz_low(palette: u8) -> paint.Color {
    if palette == 1u8 { ret paint.rgba(0.95, 0.60, 0.20, 1.0) }
    if palette == 2u8 { ret paint.rgba(0.99, 0.99, 0.99, 1.0) }
    if palette == 3u8 { ret paint.rgba(0.30, 0.55, 0.95, 1.0) }
    ret paint.rgba(0.99, 0.74, 0.74, 1.0)
}

fn wiz_high(palette: u8) -> paint.Color {
    if palette == 1u8 { ret paint.rgba(0.30, 0.65, 0.95, 1.0) }
    if palette == 2u8 { ret paint.rgba(0.30, 0.60, 0.25, 1.0) }
    if palette == 3u8 { ret paint.rgba(0.95, 0.30, 0.30, 1.0) }
    ret paint.rgba(0.70, 0.90, 0.70, 1.0)
}

fn on_wiz_format(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        // a data bar opens v3's Data Bar Rule Style Settings; the other types step through colour sets
        if grid.wiz_type == 0u8 {
            grid.fmt_open = true
            ret ok
        }
        grid.wiz_palette = (grid.wiz_palette + 1u8) % 4u8
        ret ok
    default:
        ret ok
    }
}

fn on_wiz_text(ctx: *void, value: str) -> err {
    let t = mem.cast[*WizText](ctx)
    var n = value.len
    if n > 16usize { n = 16usize }
    var i = 0usize
    while i < n {
        if t.maximum { t.grid.wiz_max_text[i] = value[i] } else { t.grid.wiz_min_text[i] = value[i] }
        i += 1usize
    }
    if t.maximum { t.grid.wiz_max_len = n } else { t.grid.wiz_min_len = n }
    ret ok
}

fn on_wiz_spin(ctx: *void, value: i64) -> err {
    let t = mem.cast[*WizText](ctx)
    var digits: [16]u8 = zero
    let written = control.write_i64(digits[0usize..16usize], value)
    var i = 0usize
    while i < written && i < 16usize {
        if t.maximum { t.grid.wiz_max_text[i] = digits[i] } else { t.grid.wiz_min_text[i] = digits[i] }
        i += 1usize
    }
    if t.maximum { t.grid.wiz_max_len = written } else { t.grid.wiz_min_len = written }
    ret ok
}

fn on_wiz_mode(ctx: *void, g: widget.Gesture) -> err {
    let t = mem.cast[*WizText](ctx)
    switch g {
    case .Tap as at:
        // Lowest/Highest Value -> Number -> Percent -> Percentile -> Lowest/Highest Value
        let wg = t.grid
        if t.maximum {
            if !wg.wiz_max_number {
                wg.wiz_max_number = true
            } else if !wg.wiz_max_pct && !wg.wiz_max_ptile {
                wg.wiz_max_pct = true
            } else if wg.wiz_max_pct {
                wg.wiz_max_pct = false
                wg.wiz_max_ptile = true
            } else {
                wg.wiz_max_number = false
                wg.wiz_max_ptile = false
            }
        } else {
            if !wg.wiz_min_number {
                wg.wiz_min_number = true
            } else if !wg.wiz_min_pct && !wg.wiz_min_ptile {
                wg.wiz_min_pct = true
            } else if wg.wiz_min_pct {
                wg.wiz_min_pct = false
                wg.wiz_min_ptile = true
            } else {
                wg.wiz_min_number = false
                wg.wiz_min_ptile = false
            }
        }
        ret ok
    default:
        ret ok
    }
}

fn wiz_words(i: u8) -> str {
    if i == 0u8 { ret "Format all cells based on their values via data bar" }
    if i == 1u8 { ret "Format all cells based on their values via icon set" }
    if i == 2u8 { ret "Format all cells based on their values via three color scale" }
    if i == 3u8 { ret "Format all cells based on their values via two color scale" }
    if i == 4u8 { ret "Format only cells that contain" }
    if i == 5u8 { ret "Format only duplicate values" }
    if i == 6u8 { ret "Format only top or bottom ranked values" }
    if i == 7u8 { ret "Format only unique values" }
    if i == 8u8 { ret "Format only values that are above or below average" }
    ret "Use a formula to determine which cells to format"
}

// The arena the rules statistics live in (the grid keeps none of its own).
fn set_rules_arena(grid: *Grid, a: *mem.Arena) { grid.rules_arena = a }

fn on_wiz_row(ctx: *void, g: widget.Gesture) -> err {
    let row = mem.cast[*WizRow](ctx)
    switch g {
    case .Tap as at:
        row.grid.wiz_type = row.index
        ret ok
    default:
        ret ok
    }
}

// OK adds a rule of the chosen type on the sorted column, or the search column.
fn on_wiz_ok(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        grid.wiz_open = false
        grid.fmt_open = false
        if mem.address_of(grid.rule_set) == 0usize || mem.address_of(grid.rules_arena) == 0usize { ret ok }
        // the sorted column when it holds numbers, else the first numeric one, else the search column
        var spec = grid.search_spec
        var found_numeric = false
        if grid.head_spec < grid.all.len {
            let hk = table.column_kind(grid.t, grid.all[grid.head_spec].column)
            if grid.all[grid.head_spec].kind != CellKind.Indicator && (hk == table.Kind.I32 || hk == table.Kind.I64 || hk == table.Kind.F64) {
                spec = grid.head_spec
                found_numeric = true
            }
        }
        if !found_numeric && grid.sort_column < grid.all.len {
            let sk = table.column_kind(grid.t, grid.all[grid.sort_column].column)
            if sk == table.Kind.I32 || sk == table.Kind.I64 || sk == table.Kind.F64 {
                spec = grid.sort_column
                found_numeric = true
            }
        }
        if grid.has_wiz_target && grid.wiz_target < grid.all.len {
            spec = grid.wiz_target
            found_numeric = true
        }
        var scan_spec = 0usize
        while !found_numeric && scan_spec < grid.all.len {
            let scan_kind = table.column_kind(grid.t, grid.all[scan_spec].column)
            if grid.all[scan_spec].kind != CellKind.Indicator && (scan_kind == table.Kind.I32 || scan_kind == table.Kind.I64 || scan_kind == table.Kind.F64) {
                spec = scan_spec
                found_numeric = true
            }
            scan_spec += 1usize
        }
        if spec >= grid.all.len { ret ok }
        let column = grid.all[spec].column
        var kind = rules.Kind.Bar
        let t = grid.wiz_type
        if t == 1u8 { kind = rules.Kind.Icons }
        if t == 2u8 || t == 3u8 { kind = rules.Kind.Scale }
        if t == 4u8 { kind = rules.Kind.Blank }
        if t == 5u8 { kind = rules.Kind.Duplicate }
        if t == 6u8 { kind = rules.Kind.Top }
        if t == 7u8 { kind = rules.Kind.Unique }
        if t == 8u8 { kind = rules.Kind.Above }
        var formula_op = rules.Op.Eq
        var formula_value: f64 = 0.0
        if t == 9u8 {
            // v3's "Use a formula": a comparison of the cell with a number, "=A1>5" or ">5" (the sample's
            // formulas have one cell and one operator; the rule model has no expression)
            kind = rules.Kind.CellIs
            var at_f = 0usize
            var found_op = false
            while at_f < grid.wiz_min_len && !found_op {
                let ch = grid.wiz_min_text[at_f]
                if ch == 60u8 || ch == 62u8 || (ch == 61u8 && at_f > 0usize) {
                    found_op = true
                } else {
                    at_f += 1usize
                }
            }
            if !found_op { ret ok }
            var op_end = at_f + 1usize
            let first = grid.wiz_min_text[at_f]
            var second: u8 = 0u8
            if op_end < grid.wiz_min_len { second = grid.wiz_min_text[op_end] }
            if first == 60u8 {
                formula_op = rules.Op.Lt
                if second == 61u8 {
                    formula_op = rules.Op.Le
                    op_end += 1usize
                } else if second == 62u8 {
                    formula_op = rules.Op.Ne
                    op_end += 1usize
                }
            } else if first == 62u8 {
                formula_op = rules.Op.Gt
                if second == 61u8 {
                    formula_op = rules.Op.Ge
                    op_end += 1usize
                }
            } else {
                formula_op = rules.Op.Eq
            }
            if op_end >= grid.wiz_min_len { ret ok }
            let (fv, fe) = str.parse_f64(grid.wiz_min_text[op_end..grid.wiz_min_len])
            if fe != ok { ret ok }
            formula_value = fv
        }
        var r = rules.rule(column, kind)
        if t == 9u8 {
            r.op = formula_op
            r.a = formula_value
        }
        r.fill = paint.rgba(0.55, 0.72, 0.95, 0.55)
        r.has_fill = true
        r.low = wiz_low(grid.wiz_palette)
        r.mid = paint.rgba(1.0, 1.0, 0.8, 1.0)
        r.high = wiz_high(grid.wiz_palette)
        if t == 0u8 { r.fill = picked_color(grid, grid.wiz_pos_color) }
        if t == 0u8 && grid.wiz_neg_color != 0u8 {
            r.has_neg = true
            r.neg = picked_color(grid, grid.wiz_neg_color - 1u8)
        }
        if t == 0u8 && grid.wiz_axis_color != 0u8 {
            r.show_axis = true
            r.axis = picked_color(grid, grid.wiz_axis_color - 1u8)
        }
        r.three = t == 2u8
        r.bar_only = t == 0u8 && grid.wiz_bar_only
        r.bar_solid = t == 0u8 && (grid.wiz_bar_style & 1u8) != 0u8
        r.bar_border = t == 0u8 && (grid.wiz_bar_style & 2u8) != 0u8
        r.bar_rtl = t == 0u8 && (grid.wiz_bar_style & 4u8) != 0u8
        if t == 0u8 { r.bar_axis = (grid.wiz_bar_style >> 3u8) & 3u8 }
        if t <= 3u8 {
            // Minimum and Maximum of the wizard: Lowest / Highest Value, or a number typed
            if grid.wiz_min_number && grid.wiz_min_len > 0usize {
                let (mv, me) = str.parse_f64(grid.wiz_min_text[0usize..grid.wiz_min_len])
                if me == ok {
                    r.has_min = true
                    r.min_pct = grid.wiz_min_pct
                    r.min_ptile = grid.wiz_min_ptile
                    r.min_value = mv
                }
            }
            if grid.wiz_max_number && grid.wiz_max_len > 0usize {
                let (xv, xe) = str.parse_f64(grid.wiz_max_text[0usize..grid.wiz_max_len])
                if xe == ok {
                    r.has_max = true
                    r.max_pct = grid.wiz_max_pct
                    r.max_ptile = grid.wiz_max_ptile
                    r.max_value = xv
                }
            }
        }
        if grid.wiz_edit && grid.rules_selected < grid.rule_set.total {
            // Edit Rule: the same column, the new type, in the same place
            r.column = grid.rule_set.rules[grid.rules_selected].column
            let at_edit = grid.rules_selected
            let (_added_edit, add_edit_error) = rules.add(grid.rules_arena, grid.rule_set, r)
            if add_edit_error == ok {
                let last = grid.rule_set.total - 1usize
                rules.swap(grid.rule_set, at_edit, last)
                rules.remove(grid.rule_set, last)
                grid.rules_changed = true
            }
            grid.wiz_edit = false
            ret ok
        }
        let (_added, add_error) = rules.add(grid.rules_arena, grid.rule_set, r)
        if add_error != ok { ret ok }
        // a scale, bar or icon rule needs its column's lowest and highest value before it is drawn:
        // the application refreshes the rule set with its own scratch (`take_rules_changed`)
        grid.rules_changed = true
        ret ok
    default:
        ret ok
    }
}

fn on_wiz_bar_only(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        grid.wiz_bar_only = !grid.wiz_bar_only
        ret ok
    default:
        ret ok
    }
}

// The column the new rule applies to: the next listed column on each tap.
fn on_wiz_target(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        var from = grid.search_spec
        if grid.has_wiz_target { from = grid.wiz_target }
        grid.wiz_target = crit_next_listed(grid, from)
        grid.has_wiz_target = true
        ret ok
    default:
        ret ok
    }
}

type WizPick = struct { grid: *Grid, spec: usize }

// The Applies to select of the wizard (the library's combo box): its toggle and its picks.
fn on_wiz_select_toggle(ctx: *void) -> err {
    let grid = mem.cast[*Grid](ctx)
    grid.wiz_select_open = !grid.wiz_select_open
    ret ok
}

fn on_wiz_pick(ctx: *void) -> err {
    let pick = mem.cast[*WizPick](ctx)
    pick.grid.wiz_target = pick.spec
    pick.grid.has_wiz_target = true
    pick.grid.wiz_select_open = false
    ret ok
}

fn on_wiz_cancel(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        grid.wiz_open = false
        grid.fmt_open = false
        ret ok
    default:
        ret ok
    }
}

// v3's Data Bar Rule Style Settings: Fill mode and Border style take effect on the rule; the
// direction, negative-bar and axis rows are drawn as v3 shows them with their default choice.
fn on_fmt_fill(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        grid.wiz_bar_style = grid.wiz_bar_style ^ 1u8
        ret ok
    default:
        ret ok
    }
}

fn on_fmt_border(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        grid.wiz_bar_style = grid.wiz_bar_style ^ 2u8
        ret ok
    default:
        ret ok
    }
}

fn on_fmt_direction(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        grid.wiz_bar_style = grid.wiz_bar_style ^ 4u8
        ret ok
    default:
        ret ok
    }
}

fn on_fmt_axis(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        let step = (((grid.wiz_bar_style >> 3u8) & 3u8) + 1u8) % 3u8
        grid.wiz_bar_style = (grid.wiz_bar_style & 7u8) | (step << 3u8)
        ret ok
    default:
        ret ok
    }
}

// The colour editor of the style window: a palette of 24 colours (v3 opens the DevExpress colour editor
// with the same kind of swatches); the first is v3's default bar blue.
fn palette_value(i: u8) -> u32 {
    if i == 0u8 { ret 0x008BEFu32 }
    // the rest: every mix of 0, 128 and 255 on the three channels (27 colours, 24 listed)
    let k = u32(i)
    let red = (k % 3u32) * 127u32 + (k % 3u32) / 2u32
    let green = ((k / 3u32) % 3u32) * 127u32 + ((k / 3u32) % 3u32) / 2u32
    let blue = ((k / 9u32) % 3u32) * 127u32 + ((k / 9u32) % 3u32) / 2u32
    ret (red << 16u32) | (green << 8u32) | blue
}

fn bar_palette(i: u8) -> paint.Color {
    let v = palette_value(i)
    ret paint.rgba(f32((v >> 16u32) & 255u32) / 255.0, f32((v >> 8u32) & 255u32) / 255.0, f32(v & 255u32) / 255.0, 1.0)
}

fn axis_palette(i: u8) -> paint.Color { ret bar_palette(i) }

// The colour a stored index stands for: 200 is the custom colour of the editor's R / G / B steppers.
fn picked_color(grid: *const Grid, i: u8) -> paint.Color {
    if i != 200u8 { ret bar_palette(i) }
    let v = grid.cust_rgb
    ret paint.rgba(f32((v >> 16u32) & 255u32) / 255.0, f32((v >> 8u32) & 255u32) / 255.0, f32(v & 255u32) / 255.0, 1.0)
}

// "R.G.B" of a palette colour, as v3's colour box writes it.
fn palette_text(a: *mem.Arena, grid: *const Grid, i: u8) -> (str, err) {
    var v = palette_value(i)
    if i == 200u8 { v = grid.cust_rgb }
    let (b, b_error) = str.builder(a, 16usize)
    if b_error != ok { ret ("", b_error) }
    var sb = b
    if str.push_u64(&sb, u64((v >> 16u32) & 255u32)) != ok || str.push(&sb, ".") != ok { ret ("", control.TooLarge) }
    if str.push_u64(&sb, u64((v >> 8u32) & 255u32)) != ok || str.push(&sb, ".") != ok { ret ("", control.TooLarge) }
    if str.push_u64(&sb, u64(v & 255u32)) != ok { ret ("", control.TooLarge) }
    ret (str.done(&sb), ok)
}

// Opens the editor for a row: 1 positive, 2 negative, 3 axis.
fn on_fmt_pos_color(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        grid.fmt_pick = 1u8
        ret ok
    default:
        ret ok
    }
}

fn on_fmt_neg_color(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        grid.fmt_pick = 2u8
        ret ok
    default:
        ret ok
    }
}

fn on_fmt_axis_color(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        grid.fmt_pick = 3u8
        ret ok
    default:
        ret ok
    }
}

type SwatchTap = struct { grid: *Grid, value: u8 }

// A swatch (value 0..23) or the none/same entry (255).
fn on_swatch(ctx: *void, g: widget.Gesture) -> err {
    let t = mem.cast[*SwatchTap](ctx)
    switch g {
    case .Tap as at:
        let grid = t.grid
        if t.value == 201u8 {
            // the row takes the custom colour, whose R, G and B are typed in the style window
            if grid.fmt_pick == 1u8 { grid.wiz_pos_color = 200u8 }
            if grid.fmt_pick == 2u8 { grid.wiz_neg_color = 201u8 }
            if grid.fmt_pick == 3u8 { grid.wiz_axis_color = 201u8 }
            grid.fmt_pick = 0u8
            ret ok
        }
        if grid.fmt_pick == 1u8 && t.value != 255u8 { grid.wiz_pos_color = t.value }
        if grid.fmt_pick == 2u8 {
            if t.value == 255u8 { grid.wiz_neg_color = 0u8 } else { grid.wiz_neg_color = t.value + 1u8 }
        }
        if grid.fmt_pick == 3u8 {
            if t.value == 255u8 { grid.wiz_axis_color = 0u8 } else { grid.wiz_axis_color = t.value + 1u8 }
        }
        grid.fmt_pick = 0u8
        ret ok
    default:
        ret ok
    }
}

// A channel of the custom colour set (0 red, 1 green, 2 blue); the row being edited takes the custom colour.
fn set_channel(grid: *Grid, channel: u8, value: i64) {
    var v = value
    if v < 0i64 { v = 0i64 }
    if v > 255i64 { v = 255i64 }
    var shift: u32 = 16u32
    if channel == 1u8 { shift = 8u32 }
    if channel == 2u8 { shift = 0u32 }
    grid.cust_rgb = (grid.cust_rgb & ~(255u32 << shift)) | (u32(v) << shift)
    if grid.fmt_pick == 1u8 { grid.wiz_pos_color = 200u8 }
    if grid.fmt_pick == 2u8 { grid.wiz_neg_color = 201u8 }
    if grid.fmt_pick == 3u8 { grid.wiz_axis_color = 201u8 }
}

fn on_rgb_spin(ctx: *void, value: i64) -> err {
    let t = mem.cast[*SwatchTap](ctx)
    set_channel(t.grid, t.value, value)
    ret ok
}

fn on_rgb_text(ctx: *void, value: str) -> err {
    let t = mem.cast[*SwatchTap](ctx)
    var v: i64 = 0i64
    var i = 0usize
    while i < value.len && i < 3usize {
        if value[i] >= 48u8 && value[i] <= 57u8 { v = v * 10i64 + i64(value[i] - 48u8) }
        i += 1usize
    }
    set_channel(t.grid, t.value, v)
    ret ok
}

// The three spin boxes under the swatches, 62 wide each.
fn rgb_spins(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, 3usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    let (ctxs, ctxs_error) = mem.alloc[SwatchTap](a, 3usize)
    if ctxs_error != ok { ret (zero, control.TooLarge) }
    let (buffers, buffers_error) = mem.alloc[u8](a, 12usize)
    if buffers_error != ok { ret (zero, control.TooLarge) }
    var k = 0usize
    while k < 3usize {
        ctxs[k] = SwatchTap { grid: grid, value: u8(k) }
        var shift: u32 = 16u32
        if k == 1usize { shift = 8u32 }
        if k == 2usize { shift = 0u32 }
        let channel = i64((grid.cust_rgb >> shift) & 255u32)
        let (field, field_error) = control.spin_box_sized(a, grid.key + MENU_KEY + 850840u64 + u64(k) * 8u64, grid.theme, "", buffers[k * 4usize..k * 4usize + 4usize], channel, 0i64, 255i64, 8i64, widget.Change[i64] { ctx: mem.cast[*void](&ctxs[k]), invoke: on_rgb_spin }, widget.Change[str] { ctx: mem.cast[*void](&ctxs[k]), invoke: on_rgb_text }, 60.0)
        if field_error != ok { ret (zero, field_error) }
        cells[k] = field
        k += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), cells[0usize..3usize]), ok)
}

// "Custom color:" and its typed R, G and B, under the axis settings of the style window.
fn fmt_custom_row(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, 2usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    let (cap, cap_error) = fmt_caption_cell(a, grid, "Custom color:", 0x000000u32)
    if cap_error != ok { ret (zero, cap_error) }
    cells[0usize] = cap
    let (spins, spins_error) = rgb_spins(a, grid)
    if spins_error != ok { ret (zero, spins_error) }
    cells[1usize] = spins
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), cells[0usize..2usize]), ok)
}

// The palette popup: six swatches across, four down, and None / Same as positive under them.
fn swatch_panel(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (taps, taps_error) = mem.alloc[SwatchTap](a, 40usize)
    if taps_error != ok { ret (zero, control.TooLarge) }
    let (lines, lines_error) = mem.alloc[widget.Node](a, 8usize)
    if lines_error != ok { ret (zero, control.TooLarge) }
    var row = 0usize
    while row < 4usize {
        let (cells, cells_error) = mem.alloc[widget.Node](a, 6usize)
        if cells_error != ok { ret (zero, control.TooLarge) }
        var col = 0usize
        while col < 6usize {
            let index = row * 6usize + col
            taps[index] = SwatchTap { grid: grid, value: u8(index) }
            var swatch = control.sized_style(26.0, 22.0)
            swatch.background = paint.Brush { Solid: bar_palette(u8(index)) }
            swatch.border = style.Border { width: 1.0, color: gl.rgb(0x606060u32) }
            swatch.margin = style.EdgeLengths { left: style.Length { Px: 3.0 }, top: style.Length { Px: 3.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
            cells[col] = widget.region(grid.key + MENU_KEY + 850500u64 + u64(index), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&taps[index]), invoke: on_swatch }, gestures: 1u8, enabled: true, focusable: false }, swatch, zero)
            col += 1usize
        }
        lines[row] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), cells[0usize..6usize])
        row += 1usize
    }
    taps[25usize] = SwatchTap { grid: grid, value: 201u8 }
    let (custom_label, custom_error) = flat_text(a, grid, "Custom color", gl.rgb(0x000000u32))
    if custom_error != ok { ret (zero, custom_error) }
    lines[4usize] = widget.region(grid.key + MENU_KEY + 850531u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&taps[25usize]), invoke: on_swatch }, gestures: 1u8, enabled: true, focusable: false }, control.sized_style(180.0, 24.0), one(a, widget.padded(0u64, 6.0, 4.0, 0.0, 0.0, style.defaults(), one(a, custom_label))))
    var count = 5usize
    let (hues, hues_error) = hue_strip(a, grid, taps[28usize..40usize])
    if hues_error != ok { ret (zero, hues_error) }
    lines[count] = hues
    count += 1usize
    if grid.fmt_pick != 1u8 {
        taps[24usize] = SwatchTap { grid: grid, value: 255u8 }
        var caption = "None"
        if grid.fmt_pick == 2u8 { caption = "Same as positive bar" }
        let (none_label, none_error) = flat_text(a, grid, caption, gl.rgb(0x000000u32))
        if none_error != ok { ret (zero, none_error) }
        lines[count] = widget.region(grid.key + MENU_KEY + 850530u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&taps[24usize]), invoke: on_swatch }, gestures: 1u8, enabled: true, focusable: false }, control.sized_style(180.0, 24.0), one(a, widget.padded(0u64, 6.0, 4.0, 0.0, 0.0, style.defaults(), one(a, none_label))))
        count += 1usize
    }
    var frame = control.sized_style(190.0, 0.0)
    frame.height = style.Length { Px: 164.0 }
    frame.height = style.Length { Px: 164.0 }
    if count == 7usize { frame.height = style.Length { Px: 190.0 } }
    frame.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    frame.border = style.Border { width: 1.0, color: gl.rgb(0x606060u32) }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, frame, lines[0usize..count]), ok)
}

fn on_fmt_close(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        grid.fmt_open = false
        grid.fmt_pick = 0u8
        ret ok
    default:
        ret ok
    }
}

fn fmt_caption(a: *mem.Arena, grid: *Grid, text: str, ink: u32, top: f32) -> (widget.Node, err) {
    let (label, label_error) = flat_text(a, grid, text, gl.rgb(ink))
    if label_error != ok { ret (zero, label_error) }
    ret (widget.padded(0u64, 14.0, top, 0.0, 0.0, style.defaults(), one(a, label)), ok)
}

// A caption and a value box (a drop-down in v3), tapped to step through the choices.
fn fmt_choice(a: *mem.Arena, grid: *Grid, caption: str, value: str, key: u64, invoke: fn(*void, widget.Gesture) -> err, live: bool) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, 2usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    let (cap, cap_error) = flat_text(a, grid, caption, gl.rgb(0x000000u32))
    if cap_error != ok { ret (zero, cap_error) }
    var cap_style = control.sized_style(110.0, 26.0)
    cap_style.margin = style.EdgeLengths { left: style.Length { Px: 14.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    cells[0usize] = widget.box(0u64, cap_style, one(a, widget.padded(0u64, 0.0, 5.0, 0.0, 0.0, style.defaults(), one(a, cap))))
    let (val, val_error) = flat_text(a, grid, value, gl.rgb(0x000000u32))
    if val_error != ok { ret (zero, val_error) }
    var box = control.sized_style(250.0, 26.0)
    box.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    box.border = style.Border { width: 1.0, color: gl.rgb(0xC8C8C8u32) }
    box.radius = 4.0
    let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
    if layers_error != ok { ret (zero, control.TooLarge) }
    layers[0usize] = widget.padded(0u64, 6.0, 5.0, 0.0, 0.0, style.defaults(), one(a, val))
    let (chevron, chevron_error) = flat_text(a, grid, "v", gl.rgb(0x404040u32))
    if chevron_error != ok { ret (zero, chevron_error) }
    layers[1usize] = widget.positioned(0u64, 228.0, 5.0, style.defaults(), one(a, chevron))
    let held = widget.stack(0u64, style.defaults(), layers[0usize..2usize])
    if live {
        cells[1usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](grid), invoke: invoke }, gestures: 1u8, enabled: true, focusable: false }, box, one(a, held))
    } else {
        cells[1usize] = widget.box(0u64, box, one(a, held))
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), cells[0usize..2usize]), ok)
}

fn fmt_button(a: *mem.Arena, grid: *Grid, text: str, key: u64) -> (widget.Node, err) {
    let (label, label_error) = flat_text(a, grid, text, gl.rgb(0x000000u32))
    if label_error != ok { ret (zero, label_error) }
    var box = control.sized_style(110.0, 30.0)
    box.background = paint.Brush { Solid: gl.rgb(0xFDFDFDu32) }
    box.border = style.Border { width: 1.0, color: gl.rgb(0xADADADu32) }
    box.radius = 4.0
    box.margin = style.EdgeLengths { left: style.Length { Px: 0.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 10.0 }, bottom: style.Length { Px: 0.0 } }
    ret (widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](grid), invoke: on_fmt_close }, gestures: 1u8, enabled: true, focusable: false }, box, one(a, widget.padded(0u64, 36.0, 6.0, 0.0, 0.0, style.defaults(), one(a, label)))), ok)
}

// The caption cell of a style-window row: 14 in, 110 wide, the text dimmed or not.
fn fmt_caption_cell(a: *mem.Arena, grid: *Grid, caption: str, ink_rgb: u32) -> (widget.Node, err) {
    let (cap, cap_error) = flat_text(a, grid, caption, gl.rgb(ink_rgb))
    if cap_error != ok { ret (zero, cap_error) }
    var cap_style = control.sized_style(110.0, 26.0)
    cap_style.margin = style.EdgeLengths { left: style.Length { Px: 14.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    ret (widget.box(0u64, cap_style, one(a, widget.padded(0u64, 0.0, 5.0, 0.0, 0.0, style.defaults(), one(a, cap)))), ok)
}

// The colour chip, at the left inside a box.
fn fmt_chip(a: *mem.Arena, rgb: u32) -> widget.Node {
    var swatch = control.sized_style(40.0, 18.0)
    swatch.background = paint.Brush { Solid: gl.rgb(rgb) }
    swatch.border = style.Border { width: 1.0, color: gl.rgb(0xA0A0A0u32) }
    ret widget.positioned(0u64, 6.0, 4.0, style.defaults(), one(a, widget.box(0u64, swatch, zero)))
}

// The inside of a colour box: the value past the chip, the chip, and a chevron.
fn fmt_colour_body(a: *mem.Arena, grid: *Grid, text: str, ink_rgb: u32, chip_rgb: u32) -> (widget.Node, err) {
    let (layers, layers_error) = mem.alloc[widget.Node](a, 3usize)
    if layers_error != ok { ret (zero, control.TooLarge) }
    let (val, val_error) = flat_text(a, grid, text, gl.rgb(ink_rgb))
    if val_error != ok { ret (zero, val_error) }
    layers[0usize] = widget.padded(0u64, 52.0, 5.0, 0.0, 0.0, style.defaults(), one(a, val))
    layers[1usize] = fmt_chip(a, chip_rgb)
    let (chevron, chevron_error) = flat_text(a, grid, "v", gl.rgb(0x404040u32))
    if chevron_error != ok { ret (zero, chevron_error) }
    layers[2usize] = widget.positioned(0u64, 194.0, 5.0, style.defaults(), one(a, chevron))
    ret (widget.stack(0u64, style.defaults(), layers[0usize..3usize]), ok)
}

// The drop-down box of a colour row; a tap opens the editor when the row is live.
fn fmt_colour_box(a: *mem.Arena, grid: *Grid, text: str, look: u64, invoke: fn(*void, widget.Gesture) -> err) -> (widget.Node, err) {
    var ink_rgb: u32 = 0x000000u32
    var ground: u32 = 0xFFFFFFu32
    if ((look >> 32u64) & 1u64) != 0u64 {
        ink_rgb = 0x9A9A9Au32
        ground = 0xF4F4F4u32
    }
    var field = control.sized_style(216.0, 26.0)
    field.background = paint.Brush { Solid: gl.rgb(ground) }
    field.border = style.Border { width: 1.0, color: gl.rgb(0xC8C8C8u32) }
    field.radius = 4.0
    let (held, held_error) = fmt_colour_body(a, grid, text, ink_rgb, u32(look & 16777215u64))
    if held_error != ok { ret (zero, held_error) }
    if (look >> 40u64) == 0u64 { ret (widget.box(0u64, field, one(a, held)), ok) }
    ret (widget.region(grid.key + MENU_KEY + (look >> 40u64), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](grid), invoke: invoke }, gestures: 1u8, enabled: true, focusable: false }, field, one(a, held)), ok)
}

// v3's "..." button beside a colour box.
fn fmt_dots(a: *mem.Arena, grid: *Grid, look: u64, invoke: fn(*void, widget.Gesture) -> err) -> (widget.Node, err) {
    var ink_rgb: u32 = 0x000000u32
    if ((look >> 32u64) & 1u64) != 0u64 { ink_rgb = 0x9A9A9Au32 }
    let (dots, dots_error) = flat_text(a, grid, "...", gl.rgb(ink_rgb))
    if dots_error != ok { ret (zero, dots_error) }
    var dots_box = control.sized_style(28.0, 26.0)
    dots_box.background = paint.Brush { Solid: gl.rgb(0xFDFDFDu32) }
    dots_box.border = style.Border { width: 1.0, color: gl.rgb(0xC8C8C8u32) }
    dots_box.radius = 4.0
    dots_box.margin = style.EdgeLengths { left: style.Length { Px: 6.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    let held = widget.padded(0u64, 6.0, 4.0, 0.0, 0.0, style.defaults(), one(a, dots))
    if (look >> 40u64) == 0u64 { ret (widget.box(0u64, dots_box, one(a, held)), ok) }
    ret (widget.region(grid.key + MENU_KEY + (look >> 40u64) + 1000u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](grid), invoke: invoke }, gestures: 1u8, enabled: true, focusable: false }, dots_box, one(a, held)), ok)
}

// A colour row: caption, a drop-down box with the colour chip, and the "..." button.
// `look`: bits 0..23 the chip's RGB, bit 32 dimmed, bits 40.. the key offset (0 = not live).
fn fmt_colour_field(a: *mem.Arena, grid: *Grid, caption: str, text: str, look: u64, invoke: fn(*void, widget.Gesture) -> err) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, 3usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    var ink_rgb: u32 = 0x000000u32
    if ((look >> 32u64) & 1u64) != 0u64 { ink_rgb = 0x9A9A9Au32 }
    let (cap, cap_error) = fmt_caption_cell(a, grid, caption, ink_rgb)
    if cap_error != ok { ret (zero, cap_error) }
    cells[0usize] = cap
    let (field, field_error) = fmt_colour_box(a, grid, text, look, invoke)
    if field_error != ok { ret (zero, field_error) }
    cells[1usize] = field
    let (dots, dots_error) = fmt_dots(a, grid, look, invoke)
    if dots_error != ok { ret (zero, dots_error) }
    cells[2usize] = dots
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), cells[0usize..3usize]), ok)
}

fn picked_rgb(grid: *const Grid, i: u8) -> u32 {
    if i != 200u8 { ret palette_value(i) }
    ret grid.cust_rgb
}

// The three colour rows of the style window, each its caption and the colour as v3 writes it.
fn fmt_pos_row(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (text, text_error) = palette_text(a, grid, grid.wiz_pos_color)
    if text_error != ok { ret (zero, text_error) }
    let (row, row_error) = fmt_colour_field(a, grid, "Color:", text, u64(picked_rgb(grid, grid.wiz_pos_color)) | (850366u64 << 40u64), on_fmt_pos_color)
    ret (row, row_error)
}

// A radio line of the style window: "(o) text" or "( ) text", a tap picks it (SwatchTap carries which).
fn fmt_radio(a: *mem.Arena, grid: *Grid, chosen: bool, text: str, tap: *SwatchTap, key: u64, invoke: fn(*void, widget.Gesture) -> err) -> (widget.Node, err) {
    let live = key != 0u64
    var mark = "( ) "
    if chosen { mark = "(o) " }
    let (b, b_error) = str.builder(a, 96usize)
    if b_error != ok { ret (zero, control.TooLarge) }
    var sb = b
    if str.push(&sb, mark) != ok || str.push(&sb, text) != ok { ret (zero, control.TooLarge) }
    var ink = gl.rgb(0x000000u32)
    if !live { ink = gl.rgb(0x9A9A9Au32) }
    let (label, label_error) = flat_text(a, grid, str.done(&sb), ink)
    if label_error != ok { ret (zero, label_error) }
    let line = widget.padded(0u64, 14.0, 4.0, 0.0, 4.0, style.defaults(), one(a, label))
    if !live { ret (line, ok) }
    ret (widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](tap), invoke: invoke }, gestures: 1u8, enabled: true, focusable: false }, control.sized_style(360.0, 26.0), one(a, line)), ok)
}

// The Negative radios (value 0 same fill, 1 own colour) and the Axis radios (value 0..2, the axis mode).
fn on_fmt_radio(ctx: *void, g: widget.Gesture) -> err {
    let t = mem.cast[*SwatchTap](ctx)
    switch g {
    case .Tap as at:
        let grid = t.grid
        if t.value == 0u8 { grid.wiz_neg_color = 0u8 }
        if t.value == 1u8 && grid.wiz_neg_color == 0u8 { grid.wiz_neg_color = grid.wiz_pos_color + 1u8 }
        if t.value >= 10u8 { grid.wiz_bar_style = (grid.wiz_bar_style & 7u8) | ((t.value - 10u8) << 3u8) }
        ret ok
    default:
        ret ok
    }
}



fn fmt_neg_row(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    var index = grid.wiz_pos_color
    var caption = "( ) Color:"
    var dimmed: u64 = 1u64 << 32u64
    if grid.wiz_neg_color != 0u8 {
        index = grid.wiz_neg_color - 1u8
        caption = "(o) Color:"
        dimmed = 0u64
    }
    let (text, text_error) = palette_text(a, grid, index)
    if text_error != ok { ret (zero, text_error) }
    let (row, row_error) = fmt_colour_field(a, grid, caption, text, u64(picked_rgb(grid, index)) | dimmed | (850367u64 << 40u64), on_fmt_neg_color)
    ret (row, row_error)
}

fn fmt_axis_row(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    var text = "Black"
    var chip: u32 = 0u32
    if grid.wiz_axis_color != 0u8 {
        let (named, named_error) = palette_text(a, grid, grid.wiz_axis_color - 1u8)
        if named_error != ok { ret (zero, named_error) }
        text = named
        chip = picked_rgb(grid, grid.wiz_axis_color - 1u8)
    }
    let (row, row_error) = fmt_colour_field(a, grid, "Axis color:", text, u64(chip) | (850368u64 << 40u64), on_fmt_axis_color)
    ret (row, row_error)
}

fn fmt_panel(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (rows, rows_error) = mem.alloc[widget.Node](a, 24usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    var n = 0usize
    var fill = "Gradient"
    if (grid.wiz_bar_style & 1u8) != 0u8 { fill = "Solid" }
    var border = "None"
    if (grid.wiz_bar_style & 2u8) != 0u8 { border = "Solid" }
    let (c0, e0) = fmt_caption(a, grid, "Data Bar Rule Style Settings", 0x606060u32, 10.0)
    if e0 != ok { ret (zero, e0) }
    let (c1, e1) = fmt_caption(a, grid, "Common", 0x000000u32, 12.0)
    if e1 != ok { ret (zero, e1) }
    let (c2, e2) = fmt_choice(a, grid, "Fill mode:", fill, grid.key + MENU_KEY + 850360u64, on_fmt_fill, true)
    if e2 != ok { ret (zero, e2) }
    let (c3, e3) = fmt_choice(a, grid, "Border style:", border, grid.key + MENU_KEY + 850361u64, on_fmt_border, true)
    if e3 != ok { ret (zero, e3) }
    var direction = "Context"
    if (grid.wiz_bar_style & 4u8) != 0u8 { direction = "Right To Left" }
    let (c4, e4) = fmt_choice(a, grid, "Bar direction:", direction, grid.key + MENU_KEY + 850364u64, on_fmt_direction, true)
    if e4 != ok { ret (zero, e4) }
    let (c5, e5) = fmt_caption(a, grid, "Positive Bar Appearance", 0x000000u32, 12.0)
    if e5 != ok { ret (zero, e5) }
    let (c6, e6) = fmt_pos_row(a, grid)
    if e6 != ok { ret (zero, e6) }
    let (c7, e7) = fmt_caption(a, grid, "Negative Bar Appearance", 0x000000u32, 12.0)
    if e7 != ok { ret (zero, e7) }
    let (c8, e8) = fmt_neg_row(a, grid)
    if e8 != ok { ret (zero, e8) }
    let (c9, e9) = fmt_caption(a, grid, "Axis Settings", 0x000000u32, 12.0)
    if e9 != ok { ret (zero, e9) }
    let (taps, taps_error) = mem.alloc[SwatchTap](a, 4usize)
    if taps_error != ok { ret (zero, control.TooLarge) }
    taps[0usize] = SwatchTap { grid: grid, value: 0u8 }
    taps[1usize] = SwatchTap { grid: grid, value: 10u8 }
    taps[2usize] = SwatchTap { grid: grid, value: 11u8 }
    taps[3usize] = SwatchTap { grid: grid, value: 12u8 }
    let (sf, sf_error) = fmt_radio(a, grid, grid.wiz_neg_color == 0u8, "Apply same fill color as positive bar", &taps[0usize], grid.key + MENU_KEY + 850701u64, on_fmt_radio)
    if sf_error != ok { ret (zero, sf_error) }
    let (r0, r0_error) = fmt_radio(a, grid, ((grid.wiz_bar_style >> 3u8) & 3u8) == 0u8, "Automatic (display at variable position based on negative values)", &taps[1usize], grid.key + MENU_KEY + 850702u64, on_fmt_radio)
    if r0_error != ok { ret (zero, r0_error) }
    let (r1, r1_error) = fmt_radio(a, grid, ((grid.wiz_bar_style >> 3u8) & 3u8) == 1u8, "Cell midpoint", &taps[2usize], grid.key + MENU_KEY + 850703u64, on_fmt_radio)
    if r1_error != ok { ret (zero, r1_error) }
    let (r2, r2_error) = fmt_radio(a, grid, ((grid.wiz_bar_style >> 3u8) & 3u8) == 2u8, "None (show negative value bars in same direction as positive)", &taps[3usize], grid.key + MENU_KEY + 850704u64, on_fmt_radio)
    if r2_error != ok { ret (zero, r2_error) }
    let (c11, e11) = fmt_axis_row(a, grid)
    if e11 != ok { ret (zero, e11) }
    rows[0usize] = c0
    rows[1usize] = c1
    rows[2usize] = c2
    rows[3usize] = c3
    rows[4usize] = c4
    rows[5usize] = c5
    let (pb, pb_error) = fmt_colour_field(a, grid, "Border color:", "255.255.255", 16777215u64 | (1u64 << 32u64), on_fmt_pos_color)
    if pb_error != ok { ret (zero, pb_error) }
    let (nb, nb_error) = fmt_colour_field(a, grid, "( ) Border color:", "255.255.255", 16777215u64 | (1u64 << 32u64), on_fmt_neg_color)
    if nb_error != ok { ret (zero, nb_error) }
    let (sb, sb_error) = fmt_radio(a, grid, true, "Apply same border color as positive bar", &taps[0usize], 0u64, on_fmt_radio)
    if sb_error != ok { ret (zero, sb_error) }
    rows[6usize] = c6
    rows[7usize] = pb
    rows[8usize] = c7
    rows[9usize] = c8
    rows[10usize] = sf
    rows[11usize] = nb
    rows[12usize] = sb
    rows[13usize] = c9
    rows[14usize] = r0
    rows[15usize] = r1
    rows[16usize] = r2
    rows[17usize] = c11
    let (cust, cust_error) = fmt_custom_row(a, grid)
    if cust_error != ok { ret (zero, cust_error) }
    rows[18usize] = cust
    n = 19usize
    let (buttons, buttons_error) = mem.alloc[widget.Node](a, 2usize)
    if buttons_error != ok { ret (zero, control.TooLarge) }
    let (ok_button, ok_button_error) = fmt_button(a, grid, "OK", grid.key + MENU_KEY + 850362u64)
    if ok_button_error != ok { ret (zero, ok_button_error) }
    let (cancel_button, cancel_button_error) = fmt_button(a, grid, "Cancel", grid.key + MENU_KEY + 850363u64)
    if cancel_button_error != ok { ret (zero, cancel_button_error) }
    buttons[0usize] = ok_button
    buttons[1usize] = cancel_button
    var button_style = control.sized_style(380.0, 40.0)
    button_style.margin = style.EdgeLengths { left: style.Length { Px: 150.0 }, top: style.Length { Px: 14.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, button_style, buttons[0usize..2usize])
    n += 1usize
    var panel = control.sized_style(380.0, 680.0)
    panel.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    panel.border = style.Border { width: 1.0, color: gl.rgb(0x8E9092u32) }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, panel, rows[0usize..n]), ok)
}

// The wizard, with the Data Bar Rule Style Settings window over it while that is open.
// ---- Print Preview (v3: Cards > Print > Print Preview..., the DevExpress preview window) --------------

// Opens the preview of the shown rows; it stands in the wizard's window slot.
// The preview window's toolbar picture (the command icons of v3's DevExpress window, cut from its screen).
fn set_print_toolbar(texture: scene.TextureId) {
    toolbar_texture = texture
    toolbar_set = true
}

// Opens v3's Page Setup dialog (it stands in the preview's slot; OK returns to the preview).
fn show_page_setup(grid: *Grid) {
    show_print_preview(grid)
    grid.pv_setup = true
}

fn show_print_preview(grid: *Grid) {
    grid.wiz_open = true
    grid.fmt_open = false
    grid.print_open = true
    grid.pv_design = false
    grid.pv_page = 0usize
    grid.win_x[2usize] = 30.0
    grid.win_y[2usize] = 20.0
    grid.win_placed[2usize] = true
    raise_window(grid, 2u8)
}

fn on_print_close(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        grid.print_open = false
        grid.wiz_open = false
        ret ok
    default:
        ret ok
    }
}

// ---- Page Setup (v3: Cards > Print > Page Setup..., DevExpress's "Page Setup: Standard Style") --------

type SetupTap = struct { grid: *Grid, kind: u8, value: u8 }

fn on_setup_tap(ctx: *void, g: widget.Gesture) -> err {
    let tap = mem.cast[*SetupTap](ctx)
    switch g {
    case .Tap as at:
        if tap.kind == 0u8 { tap.grid.pv_paper = tap.value }
        if tap.kind == 1u8 { tap.grid.pv_orient = tap.value }
        if tap.kind == 2u8 { tap.grid.pv_order = tap.value }
        if tap.kind == 3u8 { tap.grid.pv_setup = false }
        if tap.kind == 4u8 { tap.grid.pv_tab = tap.value }
        if tap.kind == 5u8 { tap.grid.pv_tenths[usize(tap.value)] = (tap.grid.pv_tenths[usize(tap.value)] + 1u8) % 10u8 }
        if tap.kind == 6u8 {
            var z = 0usize
            while z < 6usize {
                tap.grid.pv_tenths[z] = 0u8
                tap.grid.pv_hund[z] = 0u8
                z += 1usize
            }
        }
        if tap.kind == 7u8 { tap.grid.pv_center = tap.grid.pv_center ^ tap.value }
        if tap.kind == 8u8 { tap.grid.pv_reverse = !tap.grid.pv_reverse }
        if tap.kind == 9u8 { tap.grid.pv_fit = tap.value == 1u8 }
        if tap.kind == 10u8 { tap.grid.pv_percent = (tap.grid.pv_percent + 1u8) % 21u8 }
        ret ok
    default:
        ret ok
    }
}

fn paper_name(i: u8) -> str {
    if i == 0u8 { ret "Letter" }
    if i == 1u8 { ret "Tabloid" }
    if i == 2u8 { ret "Legal" }
    if i == 3u8 { ret "Statement" }
    if i == 4u8 { ret "Executive" }
    if i == 5u8 { ret "A3" }
    if i == 6u8 { ret "A4" }
    if i == 7u8 { ret "A5" }
    if i == 8u8 { ret "B4 (JIS)" }
    if i == 9u8 { ret "B5 (JIS)" }
    if i == 10u8 { ret "Envelope #9" }
    if i == 11u8 { ret "Envelope #10" }
    ret "C size sheet"
}

// A line of the dialog: an optional marker ("(o) ") and a text, chosen when `chosen` (blue for a list entry).
fn setup_line(a: *mem.Arena, grid: *Grid, taps: []SetupTap, at: usize, kind: u8, value: u8, text: str, chosen: bool, listed: bool, width: f32) -> (widget.Node, err) {
    taps[at] = SetupTap { grid: grid, kind: kind, value: value }
    var ink = gl.rgb(0x000000u32)
    var shown = text
    if !listed {
        let (b, b_error) = str.builder(a, text.len + 6usize)
        if b_error != ok { ret (zero, b_error) }
        var sb = b
        var mark = "( ) "
        if chosen { mark = "(o) " }
        if str.push(&sb, mark) != ok || str.push(&sb, text) != ok { ret (zero, control.TooLarge) }
        shown = str.done(&sb)
    }
    if listed && chosen { ink = gl.rgb(0xFFFFFFu32) }
    let (label, label_error) = flat_text(a, grid, shown, ink)
    if label_error != ok { ret (zero, label_error) }
    var line = control.sized_style(width, 24.0)
    if listed && chosen { line.background = paint.Brush { Solid: gl.rgb(0x0078D7u32) } }
    ret (widget.region(grid.key + MENU_KEY + 850400u64 + u64(at), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&taps[at]), invoke: on_setup_tap }, gestures: 1u8, enabled: true, focusable: false }, line, one(a, widget.padded(0u64, 6.0, 3.0, 0.0, 0.0, style.defaults(), one(a, label)))), ok)
}

// The Page tab of the dialog: the paper list, the orientation and the print order.
fn page_content(a: *mem.Arena, grid: *Grid, taps: []SetupTap) -> (widget.Node, err) {
    let (left, left_error) = mem.alloc[widget.Node](a, 14usize)
    if left_error != ok { ret (zero, control.TooLarge) }
    var at = 0usize
    var i = 0usize
    let (paper_head, paper_head_error) = flat_text(a, grid, "Paper", gl.rgb(0x000000u32))
    if paper_head_error != ok { ret (zero, paper_head_error) }
    left[0usize] = widget.padded(0u64, 4.0, 0.0, 0.0, 4.0, style.defaults(), one(a, paper_head))
    var l = 1usize
    while i < 13usize {
        let (line, line_error) = setup_line(a, grid, taps[0usize..40usize], at, 0u8, u8(i), paper_name(u8(i)), grid.pv_paper == u8(i), true, 260.0)
        if line_error != ok { ret (zero, line_error) }
        left[l] = line
        l += 1usize
        at += 1usize
        i += 1usize
    }
    var left_style = control.sized_style(280.0, 340.0)
    left_style.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    left_style.border = style.Border { width: 1.0, color: gl.rgb(0xABABABu32) }
    let (right_nodes, right_error) = mem.alloc[widget.Node](a, 8usize)
    if right_error != ok { ret (zero, control.TooLarge) }
    let (orient_head, orient_head_error) = flat_text(a, grid, "Orientation", gl.rgb(0x000000u32))
    if orient_head_error != ok { ret (zero, orient_head_error) }
    right_nodes[0usize] = widget.padded(0u64, 4.0, 0.0, 0.0, 4.0, style.defaults(), one(a, orient_head))
    var r = 1usize
    var k = 0usize
    while k < 3usize {
        var words = "Portrait"
        if k == 1usize { words = "Landscape" }
        if k == 2usize { words = "Auto" }
        // stored: 0 Landscape (v3's default), 1 Portrait, 2 Auto; listed as Portrait, Landscape, Auto
        var stored: u8 = 2u8
        if k < 2usize { stored = u8(k) ^ 1u8 }
        let (line, line_error) = setup_line(a, grid, taps[0usize..40usize], at, 1u8, stored, words, grid.pv_orient == stored, false, 200.0)
        if line_error != ok { ret (zero, line_error) }
        right_nodes[r] = line
        r += 1usize
        at += 1usize
        k += 1usize
    }
    let (order_head, order_head_error) = flat_text(a, grid, "Print Order", gl.rgb(0x000000u32))
    if order_head_error != ok { ret (zero, order_head_error) }
    right_nodes[r] = widget.padded(0u64, 4.0, 14.0, 0.0, 4.0, style.defaults(), one(a, order_head))
    r += 1usize
    k = 0usize
    while k < 2usize {
        var words = "Down, then over"
        if k == 1usize { words = "Over, then down" }
        // stored: 0 Over, then down (v3's default), 1 Down, then over
        let order_value = u8(k) ^ 1u8
        let (line, line_error) = setup_line(a, grid, taps[0usize..40usize], at, 2u8, order_value, words, grid.pv_order == order_value, false, 200.0)
        if line_error != ok { ret (zero, line_error) }
        right_nodes[r] = line
        r += 1usize
        at += 1usize
        k += 1usize
    }
    let (columns, columns_error) = mem.alloc[widget.Node](a, 2usize)
    if columns_error != ok { ret (zero, control.TooLarge) }
    columns[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, left_style, left[0usize..l])
    columns[1usize] = widget.padded(0u64, 20.0, 0.0, 0.0, 0.0, style.defaults(), one(a, widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), right_nodes[0usize..r])))
    ret (widget.padded(0u64, 14.0, 10.0, 0.0, 0.0, style.defaults(), one(a, widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), columns[0usize..2usize]))), ok)
}

// A labelled white box of the dialog (a font name, a header cell): `text` inside a bordered box.
fn setup_box(a: *mem.Arena, grid: *Grid, text: str, width: f32, height: f32, right_aligned: bool) -> (widget.Node, err) {
    let (label, label_error) = flat_text(a, grid, text, gl.rgb(0x000000u32))
    if label_error != ok { ret (zero, label_error) }
    var box = control.sized_style(width, height)
    box.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    box.border = style.Border { width: 1.0, color: gl.rgb(0xABABABu32) }
    var left_pad: f32 = 6.0
    if right_aligned { left_pad = width - 104.0 }
    ret (widget.box(0u64, box, one(a, widget.padded(0u64, left_pad, 4.0, 0.0, 0.0, style.defaults(), one(a, label)))), ok)
}

// The Header / Footer tab: Reverse on even pages, then Header and Footer each with its font, its
// background and three cells, and the vertical alignment and predefined functions row.
fn header_footer_content(a: *mem.Arena, grid: *Grid, taps: []SetupTap) -> (widget.Node, err) {
    let (rows, rows_error) = mem.alloc[widget.Node](a, 12usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    var n = 0usize
    var reverse = "[ ] Reverse on even pages"
    if grid.pv_reverse { reverse = "[x] Reverse on even pages" }
    let (reverse_line, reverse_error) = setup_line(a, grid, taps[0usize..40usize], 0usize, 8u8, 0u8, reverse, false, true, 240.0)
    if reverse_error != ok { ret (zero, reverse_error) }
    rows[n] = reverse_line
    n += 1usize
    var group = 0usize
    while group < 2usize {
        var heading = "Header"
        if group == 1usize { heading = "Footer" }
        let (head_label, head_error) = flat_text(a, grid, heading, gl.rgb(0x000000u32))
        if head_error != ok { ret (zero, head_error) }
        rows[n] = widget.padded(0u64, 6.0, 8.0, 0.0, 4.0, style.defaults(), one(a, head_label))
        n += 1usize
        let (top_parts, top_error) = mem.alloc[widget.Node](a, 3usize)
        if top_error != ok { ret (zero, control.TooLarge) }
        let (font_button, font_error) = setup_box(a, grid, "Font...", 80.0, 26.0, false)
        if font_error != ok { ret (zero, font_error) }
        let (font_name, font_name_error) = setup_box(a, grid, "8 pt. Tahoma", 190.0, 26.0, false)
        if font_name_error != ok { ret (zero, font_name_error) }
        let (background, background_error) = setup_box(a, grid, "Background  [No Fill]", 150.0, 26.0, false)
        if background_error != ok { ret (zero, background_error) }
        top_parts[0usize] = widget.padded(0u64, 6.0, 0.0, 0.0, 0.0, style.defaults(), one(a, font_button))
        top_parts[1usize] = widget.padded(0u64, 8.0, 0.0, 0.0, 0.0, style.defaults(), one(a, font_name))
        top_parts[2usize] = widget.padded(0u64, 20.0, 0.0, 0.0, 0.0, style.defaults(), one(a, background))
        rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), top_parts[0usize..3usize])
        n += 1usize
        let (cells, cells_error) = mem.alloc[widget.Node](a, 3usize)
        if cells_error != ok { ret (zero, control.TooLarge) }
        var c = 0usize
        while c < 3usize {
            var words = ""
            if group == 1usize && c == 1usize { words = "[Page #]" }
            if group == 1usize && c == 2usize { words = "[Date Printed]" }
            let slot = group * 3usize + c
            if grid.pv_cell_len[slot] == 0u8 && grid.pv_cell_touched & (1u8 << u8(slot)) == 0u8 {
                var w = 0usize
                while w < words.len && w < 24usize {
                    grid.pv_cell[slot * 24usize + w] = words[w]
                    w += 1usize
                }
                grid.pv_cell_len[slot] = u8(w)
                grid.pv_cell_touched = grid.pv_cell_touched | (1u8 << u8(slot))
            }
            let (cell_ctx, cell_ctx_error) = mem.alloc[MarginSpin](a, 1usize)
            if cell_ctx_error != ok { ret (zero, control.TooLarge) }
            cell_ctx[0usize] = MarginSpin { grid: grid, slot: u8(slot) }
            let (cell, cell_error) = control.text_field(a, grid.key + MENU_KEY + 850500u64 + u64(slot) * 8u64, grid.theme, "", grid.pv_cell[slot * 24usize..slot * 24usize + 24usize], usize(grid.pv_cell_len[slot]), widget.Change[str] { ctx: mem.cast[*void](&cell_ctx[0usize]), invoke: on_cell_text }, zero, cell_field_options())
            if cell_error != ok { ret (zero, cell_error) }
            cells[c] = widget.padded(0u64, 6.0, 0.0, 0.0, 0.0, style.defaults(), one(a, cell))
            c += 1usize
        }
        rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), cells[0usize..3usize])
        n += 1usize
        group += 1usize
    }
    let (foot_label, foot_error) = flat_text(a, grid, "Vertical Alignment      Predefined Functions   Insert AutoText", gl.rgb(0x808080u32))
    if foot_error != ok { ret (zero, foot_error) }
    rows[n] = widget.padded(0u64, 10.0, 12.0, 0.0, 0.0, style.defaults(), one(a, foot_label))
    n += 1usize
    ret (widget.padded(0u64, 8.0, 8.0, 0.0, 0.0, style.defaults(), one(a, widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), rows[0usize..n]))), ok)
}

// The Scaling tab: Adjust To a percent of normal size (a tap steps ten), or Fit To pages wide by tall.
fn scaling_content(a: *mem.Arena, grid: *Grid, taps: []SetupTap) -> (widget.Node, err) {
    let (rows, rows_error) = mem.alloc[widget.Node](a, 6usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    let (adjust, adjust_error) = setup_line(a, grid, taps[0usize..40usize], 0usize, 9u8, 0u8, "Adjust To:", !grid.pv_fit, false, 240.0)
    if adjust_error != ok { ret (zero, adjust_error) }
    rows[0usize] = adjust
    let (percent_builder, percent_builder_error) = str.builder(a, 32usize)
    if percent_builder_error != ok { ret (zero, control.TooLarge) }
    var pb = percent_builder
    var shown = u64(grid.pv_percent) * 10u64
    if shown == 0u64 { shown = 100u64 }
    if str.push_u64(&pb, shown) != ok || str.push(&pb, "  % normal size") != ok { ret (zero, control.TooLarge) }
    let (percent_line, percent_error) = setup_line(a, grid, taps[0usize..40usize], 1usize, 10u8, 0u8, str.done(&pb), false, true, 240.0)
    if percent_error != ok { ret (zero, percent_error) }
    rows[1usize] = widget.padded(0u64, 20.0, 0.0, 0.0, 14.0, style.defaults(), one(a, percent_line))
    let (fit, fit_error) = setup_line(a, grid, taps[0usize..40usize], 2usize, 9u8, 1u8, "Fit To:", grid.pv_fit, false, 240.0)
    if fit_error != ok { ret (zero, fit_error) }
    rows[2usize] = fit
    let (fit_parts, fit_parts_error) = mem.alloc[widget.Node](a, 4usize)
    if fit_parts_error != ok { ret (zero, control.TooLarge) }
    let (fit_ctx, fit_ctx_error) = mem.alloc[MarginSpin](a, 2usize)
    if fit_ctx_error != ok { ret (zero, control.TooLarge) }
    let (fit_buffers, fit_buffers_error) = mem.alloc[u8](a, 8usize)
    if fit_buffers_error != ok { ret (zero, control.TooLarge) }
    var f = 0usize
    while f < 2usize {
        fit_ctx[f] = MarginSpin { grid: grid, slot: u8(f) }
        var current = i64(grid.pv_tall)
        var low = 0i64
        if f == 0usize {
            current = i64(grid.pv_wide) + 1i64
            low = 1i64
        }
        let (box, box_error) = control.spin_box_sized(a, grid.key + MENU_KEY + 850560u64 + u64(f) * 8u64, grid.theme, "", fit_buffers[f * 4usize..f * 4usize + 4usize], current, low, 99i64, 1i64, widget.Change[i64] { ctx: mem.cast[*void](&fit_ctx[f]), invoke: on_fit_spin }, widget.Change[str] { ctx: mem.cast[*void](&fit_ctx[f]), invoke: on_fit_text }, 90.0)
        if box_error != ok { ret (zero, box_error) }
        fit_parts[f * 2usize + 1usize] = box
        var words = "page(s) wide by"
        if f == 1usize { words = "tall" }
        let (word, word_error) = flat_text(a, grid, words, gl.rgb(0x000000u32))
        if word_error != ok { ret (zero, word_error) }
        fit_parts[f * 2usize] = widget.padded(0u64, 8.0, 14.0, 6.0, 0.0, style.defaults(), one(a, word))
        f += 1usize
    }
    // order: wide box, "page(s) wide by", tall box, "tall"
    let (ordered, ordered_error) = mem.alloc[widget.Node](a, 4usize)
    if ordered_error != ok { ret (zero, control.TooLarge) }
    ordered[0usize] = fit_parts[1usize]
    ordered[1usize] = fit_parts[0usize]
    ordered[2usize] = fit_parts[3usize]
    ordered[3usize] = fit_parts[2usize]
    rows[3usize] = widget.padded(0u64, 30.0, 4.0, 0.0, 0.0, style.defaults(), one(a, widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(520.0, 58.0), ordered[0usize..4usize])))
    ret (widget.padded(0u64, 14.0, 12.0, 0.0, 0.0, style.defaults(), one(a, widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), rows[0usize..4usize]))), ok)
}

type MarginSpin = struct { grid: *Grid, slot: u8 }

// A margin in hundredths of an inch (slots: Left, Top, Right, Bottom, Header, Footer).
fn margin_hund(grid: *const Grid, slot: usize) -> i64 {
    var base: i64 = 5i64
    if slot >= 4usize { base = 2i64 }
    ret (i64(grid.pv_tenths[slot]) + base) * 10i64 + i64(grid.pv_hund[slot])
}

// The margin in sheet pixels: the sheet is the paper (11 in landscape, 8.5 in portrait) across.
fn margin_px(grid: *const Grid, slot: usize, sheet: f32) -> f32 {
    var paper: f32 = 11.0
    if grid.pv_orient == 1u8 { paper = 8.5 }
    ret sheet / paper * f32(margin_hund(grid, slot)) / 100.0
}

fn on_cell_text(ctx: *void, value: str) -> err {
    let m = mem.cast[*MarginSpin](ctx)
    var n = value.len
    if n > 24usize { n = 24usize }
    var i = 0usize
    while i < n {
        m.grid.pv_cell[usize(m.slot) * 24usize + i] = value[i]
        i += 1usize
    }
    m.grid.pv_cell_len[usize(m.slot)] = u8(n)
    ret ok
}

// Fit To: slot 0 pages wide (1..99), slot 1 pages tall (0..99, 0 = as many as needed).
fn on_fit_spin(ctx: *void, value: i64) -> err {
    let m = mem.cast[*MarginSpin](ctx)
    var v = value
    if v > 99i64 { v = 99i64 }
    if m.slot == 0u8 {
        if v < 1i64 { v = 1i64 }
        m.grid.pv_wide = u8(v - 1i64)
    } else {
        if v < 0i64 { v = 0i64 }
        m.grid.pv_tall = u8(v)
    }
    ret ok
}

fn on_fit_text(ctx: *void, value: str) -> err {
    var v: i64 = 0i64
    var i = 0usize
    while i < value.len && i < 3usize {
        if value[i] >= 48u8 && value[i] <= 57u8 { v = v * 10i64 + i64(value[i] - 48u8) }
        i += 1usize
    }
    ret on_fit_spin(ctx, v)
}

// A margin set in hundredths of an inch; pv_tenths holds the tenths over the base, pv_hund the last digit.
fn set_margin(grid: *Grid, slot: u8, hundredths: i64) {
    var base: i64 = 5i64
    if slot >= 4u8 { base = 2i64 }
    var h = hundredths
    if h < base * 10i64 { h = base * 10i64 }
    if h > 999i64 { h = 999i64 }
    grid.pv_tenths[usize(slot)] = u8(h / 10i64 - base)
    grid.pv_hund[usize(slot)] = u8(h % 10i64)
}

fn on_margin_spin(ctx: *void, value: i64) -> err {
    let m = mem.cast[*MarginSpin](ctx)
    set_margin(m.grid, m.slot, value)
    ret ok
}

fn on_margin_text(ctx: *void, value: str) -> err {
    let m = mem.cast[*MarginSpin](ctx)
    var h: i64 = 0i64
    var i = 0usize
    while i < value.len && i < 4usize {
        if value[i] >= 48u8 && value[i] <= 57u8 { h = h * 10i64 + i64(value[i] - 48u8) }
        i += 1usize
    }
    set_margin(m.grid, m.slot, h)
    ret ok
}

// The Margins tab: the six margins as typed spin boxes (hundredths of an inch) (a tap steps a tenth of an inch, as in the preview), the
// page drawn with its margin lines, Restore Original and Center on page.
fn margins_content(a: *mem.Arena, grid: *Grid, taps: []SetupTap) -> (widget.Node, err) {
    let (lines, lines_error) = mem.alloc[widget.Node](a, 10usize)
    if lines_error != ok { ret (zero, control.TooLarge) }
    var n = 0usize
    var k = 0usize
    while k < 6usize {
        // v3's order: Top, Bottom, Left, Right, Header, Footer
        var slot: usize = 1usize
        var name = "Top: "
        var base: u8 = 5u8
        if k == 1usize {
            slot = 3usize
            name = "Bottom: "
        }
        if k == 2usize {
            slot = 0usize
            name = "Left: "
        }
        if k == 3usize {
            slot = 2usize
            name = "Right: "
        }
        if k == 4usize {
            slot = 4usize
            name = "Header: "
            base = 2u8
        }
        if k == 5usize {
            slot = 5usize
            name = "Footer: "
            base = 2u8
        }
        let (label, label_error) = flat_text(a, grid, name, gl.rgb(0x000000u32))
        if label_error != ok { ret (zero, label_error) }
        let (buffer, buffer_error) = mem.alloc[u8](a, 12usize)
        if buffer_error != ok { ret (zero, control.TooLarge) }
        let (spins, spins_error) = mem.alloc[MarginSpin](a, 1usize)
        if spins_error != ok { ret (zero, control.TooLarge) }
        spins[0usize] = MarginSpin { grid: grid, slot: u8(slot) }
        let hundredths = i64(grid.pv_tenths[slot] + base) * 10i64 + i64(grid.pv_hund[slot])
        let (field, field_error) = control.spin_box_sized(a, grid.key + MENU_KEY + 850400u64 + u64(k) * 8u64, grid.theme, "1/100 in", buffer[0usize..12usize], hundredths, i64(base) * 10i64, 999i64, 5i64, widget.Change[i64] { ctx: mem.cast[*void](&spins[0usize]), invoke: on_margin_spin }, widget.Change[str] { ctx: mem.cast[*void](&spins[0usize]), invoke: on_margin_text }, 110.0)
        if field_error != ok { ret (zero, field_error) }
        let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
        if pair_error != ok { ret (zero, control.TooLarge) }
        pair[0usize] = widget.padded(0u64, 0.0, 20.0, 6.0, 0.0, style.defaults(), one(a, label))
        pair[1usize] = field
        let line = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(240.0, 58.0), pair[0usize..2usize])
        lines[n] = line
        n += 1usize
        k += 1usize
    }
    let (restore, restore_error) = setup_line(a, grid, taps[0usize..40usize], 6usize, 6u8, 0u8, "Restore Original", false, true, 240.0)
    if restore_error != ok { ret (zero, restore_error) }
    lines[n] = restore
    n += 1usize
    var mark_h = "( ) Center horizontally"
    if (grid.pv_center & 1u8) != 0u8 { mark_h = "(x) Center horizontally" }
    var mark_v = "( ) Center vertically"
    if (grid.pv_center & 2u8) != 0u8 { mark_v = "(x) Center vertically" }
    let (center_h, center_h_error) = setup_line(a, grid, taps[0usize..40usize], 7usize, 7u8, 1u8, mark_h, false, true, 240.0)
    if center_h_error != ok { ret (zero, center_h_error) }
    lines[n] = center_h
    n += 1usize
    let (center_v, center_v_error) = setup_line(a, grid, taps[0usize..40usize], 8usize, 7u8, 2u8, mark_v, false, true, 240.0)
    if center_v_error != ok { ret (zero, center_v_error) }
    lines[n] = center_v
    n += 1usize
    // the page, drawn as a sheet with a dashed inner frame
    var sheet = control.sized_style(300.0, 190.0)
    sheet.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    sheet.border = style.Border { width: 2.0, color: gl.rgb(0x000000u32) }
    sheet.margin = style.EdgeLengths { left: style.Length { Px: 0.0 }, top: style.Length { Px: 40.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    var inner = control.sized_style(260.0, 150.0)
    inner.border = style.Border { width: 1.0, color: gl.rgb(0x808080u32) }
    inner.margin = style.EdgeLengths { left: style.Length { Px: 18.0 }, top: style.Length { Px: 18.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    let (drawing, drawing_error) = mem.alloc[widget.Node](a, 1usize)
    if drawing_error != ok { ret (zero, control.TooLarge) }
    drawing[0usize] = widget.box(0u64, inner, zero)
    let (halves, halves_error) = mem.alloc[widget.Node](a, 2usize)
    if halves_error != ok { ret (zero, control.TooLarge) }
    halves[0usize] = widget.box(0u64, sheet, drawing[0usize..1usize])
    halves[1usize] = widget.padded(0u64, 24.0, 0.0, 0.0, 0.0, style.defaults(), one(a, widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), lines[0usize..n])))
    ret (widget.padded(0u64, 14.0, 16.0, 0.0, 0.0, style.defaults(), one(a, widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), halves[0usize..2usize]))), ok)
}

fn page_setup_panel(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let width: f32 = 560.0
    let (rows, rows_error) = mem.alloc[widget.Node](a, 12usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    var n = 0usize
    let (title, title_error) = window_title(a, grid, 2u8, "Page Setup: Standard Style", width, 32.0, false)
    if title_error != ok { ret (zero, title_error) }
    rows[n] = title
    n += 1usize
    let (taps, taps_error) = mem.alloc[SetupTap](a, 40usize)
    if taps_error != ok { ret (zero, control.TooLarge) }
    // the style name (grey, v3's standard style cannot be renamed)
    let (name_label, name_error) = flat_text(a, grid, "Style Name:   Standard Style", gl.rgb(0x808080u32))
    if name_error != ok { ret (zero, name_error) }
    rows[n] = widget.padded(0u64, 14.0, 10.0, 0.0, 6.0, style.defaults(), one(a, name_label))
    n += 1usize
    // the tabs: each a tap that chooses its page
    let (tab_cells, tab_error) = mem.alloc[widget.Node](a, 4usize)
    if tab_error != ok { ret (zero, control.TooLarge) }
    var tab_at = 0usize
    while tab_at < 4usize {
        var tab_words = "Page"
        if tab_at == 1usize { tab_words = "Margins" }
        if tab_at == 2usize { tab_words = "Header / Footer" }
        if tab_at == 3usize { tab_words = "Scaling" }
        let (tab_line, tab_line_error) = setup_line(a, grid, taps[0usize..40usize], 24usize + tab_at, 4u8, u8(tab_at), tab_words, grid.pv_tab == u8(tab_at), true, 110.0)
        if tab_line_error != ok { ret (zero, tab_line_error) }
        tab_cells[tab_at] = tab_line
        tab_at += 1usize
    }
    rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(width, 26.0), tab_cells[0usize..4usize])
    n += 1usize
    var content: widget.Node = zero
    if grid.pv_tab == 1u8 {
        let (margins_node, margins_error) = margins_content(a, grid, taps)
        if margins_error != ok { ret (zero, margins_error) }
        content = margins_node
    } else if grid.pv_tab == 0u8 {
        let (page_node, page_error) = page_content(a, grid, taps)
        if page_error != ok { ret (zero, page_error) }
        content = page_node
    } else if grid.pv_tab == 2u8 {
        let (hf_node, hf_error) = header_footer_content(a, grid, taps)
        if hf_error != ok { ret (zero, hf_error) }
        content = hf_node
    } else {
        let (scale_node, scale_error) = scaling_content(a, grid, taps)
        if scale_error != ok { ret (zero, scale_error) }
        content = scale_node
    }
    rows[n] = content
    n += 1usize
    // OK
    let (ok_line, ok_line_error) = setup_line(a, grid, taps[0usize..40usize], 28usize, 3u8, 0u8, "OK", false, true, 100.0)
    if ok_line_error != ok { ret (zero, ok_line_error) }
    rows[n] = widget.padded(0u64, 400.0, 10.0, 0.0, 10.0, style.defaults(), one(a, ok_line))
    n += 1usize
    var panel = control.sized_style(width, 0.0)
    panel.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    panel.border = style.Border { width: 1.0, color: gl.rgb(0x606060u32) }
    panel.height = style.Length { Px: 540.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, panel, rows[0usize..n]), ok)
}

// A tap in the preview: 0..5 step a margin by a tenth of an inch (back to its start after nine), 6 the
// zoom, 7 and 8 the previous and the next page.
type PrintTap = struct { grid: *Grid, index: u8 }

fn on_print_tap(ctx: *void, g: widget.Gesture) -> err {
    let tap = mem.cast[*PrintTap](ctx)
    switch g {
    case .Tap as at:
        let grid = tap.grid
        if tap.index < 6u8 {
            grid.pv_tenths[usize(tap.index)] = (grid.pv_tenths[usize(tap.index)] + 1u8) % 10u8
        } else if tap.index == 6u8 {
            grid.pv_zoom = (grid.pv_zoom + 1u8) % 4u8
        } else if tap.index == 7u8 {
            if grid.pv_page > 0usize { grid.pv_page -= 1usize }
        } else if tap.index == 9u8 {
            grid.pv_page = 0usize
        } else if tap.index == 10u8 {
            grid.pv_page = 1000000usize
        } else {
            grid.pv_page += 1usize
        }
        ret ok
    default:
        ret ok
    }
}

// "Left: 0.5 in": the label and the value of a margin, in the arena.
fn margin_text(a: *mem.Arena, name: str, base_tenths: u8, extra: u8, hund: u8, two: bool) -> (str, err) {
    let (b, b_error) = str.builder(a, 24usize)
    if b_error != ok { ret ("", b_error) }
    var sb = b
    let tenths = base_tenths + extra
    if str.push(&sb, name) != ok { ret ("", control.TooLarge) }
    if str.push_u64(&sb, u64(tenths / 10u8)) != ok { ret ("", control.TooLarge) }
    if str.push(&sb, ".") != ok { ret ("", control.TooLarge) }
    if str.push_u64(&sb, u64(tenths % 10u8)) != ok { ret ("", control.TooLarge) }
    if (two || hund != 0u8) && str.push_u64(&sb, u64(hund)) != ok { ret ("", control.TooLarge) }
    if str.push(&sb, " in") != ok { ret ("", control.TooLarge) }
    ret (str.done(&sb), ok)
}

fn atleast(v: f32, floor: f32) -> f32 {
    if v < floor { ret floor }
    ret v
}

// A header (first = 0) or footer (first = 3) band of the printed page: its three cells from Page Setup,
// "[Page #]" showing the page number, left, centred and right across the printable width.
fn print_band(a: *mem.Arena, grid: *Grid, first: usize, lp: f32, across: f32, top: f32) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, 3usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    var c = 0usize
    while c < 3usize {
        let slot = first + c
        let len = usize(grid.pv_cell_len[slot])
        let (b, b_error) = str.builder(a, 40usize)
        if b_error != ok { ret (zero, control.TooLarge) }
        var sb = b
        var text = str.done(&sb)
        let seeded = (grid.pv_cell_touched & (1u8 << u8(slot))) != 0u8
        if (!seeded && slot == 4usize) || (len >= 8usize && grid.pv_cell[slot * 24usize + 1usize] == 80u8 && grid.pv_cell[slot * 24usize + 2usize] == 97u8) {
            if str.push(&sb, "Page ") != ok || str.push_u64(&sb, u64(grid.pv_page + 1usize)) != ok { ret (zero, control.TooLarge) }
            text = str.done(&sb)
        } else if (!seeded && slot == 5usize) || (len >= 5usize && grid.pv_cell[slot * 24usize + 1usize] == 68u8 && grid.pv_cell[slot * 24usize + 2usize] == 97u8) {
            let (stamp, stamp_error) = time.now()
            if stamp_error != ok { ret (zero, stamp_error) }
            let day = time.to_date(stamp)
            if str.push_u64(&sb, u64(day.month)) != ok || str.push(&sb, "/") != ok || str.push_u64(&sb, u64(day.day)) != ok || str.push(&sb, "/") != ok || str.push_u64(&sb, u64(day.year)) != ok { ret (zero, control.TooLarge) }
            text = str.done(&sb)
        } else if len >= 3usize && grid.pv_cell[slot * 24usize + 1usize] == 84u8 && grid.pv_cell[slot * 24usize + 2usize] == 105u8 {
            let (clock, clock_error) = time.now()
            if clock_error != ok { ret (zero, clock_error) }
            let now_time = time.to_time(clock)
            if str.push_u64(&sb, u64(now_time.hour)) != ok || str.push(&sb, ":") != ok { ret (zero, control.TooLarge) }
            if now_time.minute < 10u8 && str.push(&sb, "0") != ok { ret (zero, control.TooLarge) }
            if str.push_u64(&sb, u64(now_time.minute)) != ok { ret (zero, control.TooLarge) }
            text = str.done(&sb)
        } else {
            var ch = 0usize
            while ch < len {
                if str.push_byte(&sb, grid.pv_cell[slot * 24usize + ch]) != ok { ret (zero, control.TooLarge) }
                ch += 1usize
            }
            text = str.done(&sb)
        }
        let (label, label_error) = flat_text(a, grid, text, gl.rgb(0x000000u32))
        if label_error != ok { ret (zero, label_error) }
        var cell = control.sized_style(across / 3.0, 18.0)
        if c == 0usize { cells[c] = widget.box(0u64, cell, one(a, label)) }
        if c == 1usize { cells[c] = widget.aligned(0u64, .Center, .Center, cell, one(a, label)) }
        if c == 2usize { cells[c] = widget.aligned(0u64, .End, .Center, cell, one(a, label)) }
        c += 1usize
    }
    var band = control.sized_style(across, 18.0)
    if first == 3usize && ((grid.dz_style_has >> 8u16) & 1u16) != 0u16 { band.background = paint.Brush { Solid: gl.rgb(grid.dz_style_rgb[8usize]) } }
    band.margin = style.EdgeLengths { left: style.Length { Px: lp }, top: style.Length { Px: top }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, band, cells[0usize..3usize]), ok)
}

// The toolbar picture with tap targets over its first, previous, next and last page icons.
fn print_toolbar_row(a: *mem.Arena, grid: *Grid, width: f32) -> (widget.Node, err) {
    var tool = control.sized_style(width, 34.0)
    tool.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    tool.border = style.Border { width: 1.0, color: gl.rgb(0xD0D0D0u32) }
    if !toolbar_set { ret (widget.box(0u64, tool, zero), ok) }
    let (strip, strip_error) = control.image(a, grid.key + 3970u64, toolbar_texture, width, 27.0, .Contain, "")
    if strip_error != ok { ret (zero, strip_error) }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 5usize)
    if layers_error != ok { ret (zero, control.TooLarge) }
    let (taps, taps_error) = mem.alloc[PrintTap](a, 4usize)
    if taps_error != ok { ret (zero, control.TooLarge) }
    layers[0usize] = widget.padded(0u64, 0.0, 3.0, 0.0, 0.0, style.defaults(), one(a, strip))
    var k = 0usize
    while k < 4usize {
        // first, previous, next, last
        var at: f32 = 611.0
        var index: u8 = 9u8
        if k == 1usize {
            at = 633.0
            index = 7u8
        }
        if k == 2usize {
            at = 727.0
            index = 8u8
        }
        if k == 3usize {
            at = 749.0
            index = 10u8
        }
        taps[k] = PrintTap { grid: grid, index: index }
        layers[k + 1usize] = widget.positioned(0u64, at, 3.0, style.defaults(), one(a, widget.region(grid.key + MENU_KEY + 850820u64 + u64(k), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&taps[k]), invoke: on_print_tap }, gestures: 1u8, enabled: true, focusable: false }, control.sized_style(22.0, 27.0), zero)))
        k += 1usize
    }
    ret (widget.stack(0u64, tool, layers[0usize..5usize]), ok)
}

// The margins rows: the zoom (a tap), then each margin as a typed spin box.
fn print_margins(a: *mem.Arena, grid: *Grid, width: f32) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, 2usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    let (zoom_tap, zoom_tap_error) = mem.alloc[PrintTap](a, 1usize)
    if zoom_tap_error != ok { ret (zero, control.TooLarge) }
    var text: str = "Zoom: 100%"
    if grid.pv_zoom == 1u8 { text = "Zoom: 75%" }
    if grid.pv_zoom == 2u8 { text = "Zoom: 50%" }
    if grid.pv_zoom == 3u8 { text = "Zoom: 125%" }
    let (zoom_label, zoom_label_error) = flat_text(a, grid, text, gl.rgb(0x000000u32))
    if zoom_label_error != ok { ret (zero, zoom_label_error) }
    zoom_tap[0usize] = PrintTap { grid: grid, index: 6u8 }
    let zoom_padded = widget.padded(0u64, 10.0, 6.0, 0.0, 0.0, style.defaults(), one(a, zoom_label))
    cells[0usize] = widget.region(grid.key + MENU_KEY + 850386u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&zoom_tap[0usize]), invoke: on_print_tap }, gestures: 1u8, enabled: true, focusable: false }, style.defaults(), one(a, zoom_padded))
    // the six margins as typed spin boxes (hundredths of an inch), in the order of the row they replace
    let (pairs, pairs_error) = mem.alloc[widget.Node](a, 12usize)
    if pairs_error != ok { ret (zero, control.TooLarge) }
    let (spins, spins_error) = mem.alloc[MarginSpin](a, 6usize)
    if spins_error != ok { ret (zero, control.TooLarge) }
    let (buffers, buffers_error) = mem.alloc[u8](a, 72usize)
    if buffers_error != ok { ret (zero, control.TooLarge) }
    var k = 0usize
    while k < 6usize {
        var name = "Left:"
        var base: u8 = 5u8
        if k == 1usize { name = "Top:" }
        if k == 2usize { name = "Right:" }
        if k == 3usize { name = "Bottom:" }
        if k == 4usize {
            name = "Header:"
            base = 2u8
        }
        if k == 5usize {
            name = "Footer:"
            base = 2u8
        }
        spins[k] = MarginSpin { grid: grid, slot: u8(k) }
        let hundredths = i64(grid.pv_tenths[k] + base) * 10i64 + i64(grid.pv_hund[k])
        let (field, field_error) = control.spin_box_sized(a, grid.key + MENU_KEY + 850600u64 + u64(k) * 8u64, grid.theme, "", buffers[k * 12usize..k * 12usize + 12usize], hundredths, i64(base) * 10i64, 999i64, 5i64, widget.Change[i64] { ctx: mem.cast[*void](&spins[k]), invoke: on_margin_spin }, widget.Change[str] { ctx: mem.cast[*void](&spins[k]), invoke: on_margin_text }, 80.0)
        if field_error != ok { ret (zero, field_error) }
        let (label, label_error) = flat_text(a, grid, name, gl.rgb(0x000000u32))
        if label_error != ok { ret (zero, label_error) }
        pairs[k * 2usize] = widget.padded(0u64, 8.0, 20.0, 4.0, 0.0, style.defaults(), one(a, label))
        pairs[k * 2usize + 1usize] = field
        k += 1usize
    }
    var top = control.sized_style(width, 28.0)
    top.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    var bottom = control.sized_style(width, 58.0)
    bottom.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    let (bars, bars_error) = mem.alloc[widget.Node](a, 2usize)
    if bars_error != ok { ret (zero, control.TooLarge) }
    bars[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, top, cells[0usize..1usize])
    bars[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, bottom, pairs[0usize..12usize])
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(width, 86.0), bars[0usize..2usize]), ok)
}

fn print_cell(a: *mem.Arena, grid: *Grid, text: str, width: f32, row: usize) -> (widget.Node, err) {
    let (label, label_error) = flat_text(a, grid, text, gl.rgb(0x000000u32))
    if label_error != ok { ret (zero, label_error) }
    var box = control.sized_style(width, 18.0)
    box.background = paint.Brush { Solid: gl.rgb(dz_row_fill(grid, row)) }
    if row == 0usize { box.background = paint.Brush { Solid: gl.rgb(print_header_fill(grid)) } }
    box.border = style.Border { width: 1.0, color: gl.rgb(0xE0E0E0u32) }
    ret (widget.box(0u64, box, one(a, widget.padded(0u64, 3.0, 1.0, 0.0, 0.0, style.defaults(), one(a, label)))), ok)
}

fn print_row(a: *mem.Arena, grid: *Grid, line: []const str, widths: []const f32, row: usize) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, line.len + 1usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    var k = 0usize
    while k < line.len {
        let (cell, cell_error) = print_cell(a, grid, line[k], widths[k], row)
        if cell_error != ok { ret (zero, cell_error) }
        cells[k] = cell
        k += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), cells[0usize..line.len]), ok)
}

// A bar of text labels (the menu row and the margins row of the preview window).
fn print_bar(a: *mem.Arena, grid: *Grid, labels: []const str, fill: u32, width: f32) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, labels.len)
    if cells_error != ok { ret (zero, control.TooLarge) }
    var k = 0usize
    while k < labels.len {
        let (label, label_error) = flat_text(a, grid, labels[k], gl.rgb(0x000000u32))
        if label_error != ok { ret (zero, label_error) }
        cells[k] = widget.padded(0u64, 10.0, 6.0, 0.0, 0.0, style.defaults(), one(a, label))
        k += 1usize
    }
    var bar = control.sized_style(width, 28.0)
    bar.background = paint.Brush { Solid: gl.rgb(fill) }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, bar, cells[0usize..labels.len]), ok)
}

// The window: title bar, menu, toolbar and margins rows, then the page (title, header and rows) and the
// filter strip, as the DevExpress preview shows the grid.
fn print_panel(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let width: f32 = 760.0
    let (rows, rows_error) = mem.alloc[widget.Node](a, 40usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    var n = 0usize
    let (title, title_error) = window_title(a, grid, 2u8, "Print Preview", width, 30.0, false)
    if title_error != ok { ret (zero, title_error) }
    rows[n] = title
    n += 1usize
    let (menu_labels, menu_error) = mem.alloc[str](a, 5usize)
    if menu_error != ok { ret (zero, control.TooLarge) }
    menu_labels[0usize] = "File"
    menu_labels[1usize] = "Explorer"
    menu_labels[2usize] = "View"
    menu_labels[3usize] = "Format"
    menu_labels[4usize] = "Go"
    let (menu_bar, menu_bar_error) = print_bar(a, grid, menu_labels[0usize..5usize], 0xFFFFFFu32, width)
    if menu_bar_error != ok { ret (zero, menu_bar_error) }
    rows[n] = menu_bar
    n += 1usize
    let (tool_row, tool_row_error) = print_toolbar_row(a, grid, width)
    if tool_row_error != ok { ret (zero, tool_row_error) }
    rows[n] = tool_row
    n += 1usize
    let (margin_bar, margin_bar_error) = print_margins(a, grid, width)
    if margin_bar_error != ok { ret (zero, margin_bar_error) }
    rows[n] = margin_bar
    n += 1usize
    // twelve rows a page: the page asked for, from the rows up to its end
    let per_page = page_rows(grid)
    var data_rows = 0usize
    var counted = 0usize
    while counted < grp.visible_len(grid.g) {
        if !grp.visible_is_group(grid.g, counted) && !grp.visible_is_footer(grid.g, counted) { data_rows += 1usize }
        counted += 1usize
    }
    var pages = (data_rows + per_page - 1usize) / per_page
    if pages == 0usize { pages = 1usize }
    if grid.pv_page >= pages { grid.pv_page = pages - 1usize }
    let (all_lines, wide, lines_error) = export_rows(a, grid, (grid.pv_page + 1usize) * per_page, false)
    if lines_error != ok { ret (zero, lines_error) }
    var from = 1usize + grid.pv_page * per_page
    if from > all_lines.len { from = all_lines.len }
    let (page_lines, page_lines_error) = mem.alloc[[]const str](a, all_lines.len - from + 1usize)
    if page_lines_error != ok { ret (zero, control.TooLarge) }
    if all_lines.len > 0usize { page_lines[0usize] = all_lines[0usize] }
    var take = from
    var put = 1usize
    while take < all_lines.len {
        page_lines[put] = all_lines[take]
        put += 1usize
        take += 1usize
    }
    let lines = page_lines[0usize..put]
    var zoom: f32 = 1.0
    // Portrait (Page Setup) narrows the sheet and its columns
    var across: f32 = 640.0
    var sheet_wide: f32 = 690.0
    var sheet_high: f32 = 400.0
    if grid.pv_orient == 1u8 {
        across = 400.0
        sheet_wide = 450.0
        sheet_high = 470.0
    }
    across = sheet_wide - margin_px(grid, 0usize, sheet_wide) - margin_px(grid, 2usize, sheet_wide) - 4.0
    if grid.pv_zoom == 1u8 { zoom = 0.75 }
    if grid.pv_zoom == 2u8 { zoom = 0.5 }
    if grid.pv_zoom == 3u8 { zoom = 1.25 }
    var shown = wide
    if shown > 9usize { shown = 9usize }
    let (widths, widths_error) = mem.alloc[f32](a, shown + 1usize)
    if widths_error != ok { ret (zero, control.TooLarge) }
    var k = 0usize
    while k < shown {
        widths[k] = across * zoom / f32(shown)
        k += 1usize
    }
    let (heading, heading_error) = preview_heading(a, grid)
    if heading_error != ok { ret (zero, heading_error) }
    let (page, page_error) = mem.alloc[widget.Node](a, 40usize)
    if page_error != ok { ret (zero, control.TooLarge) }
    var q = 0usize
    let (head_band, head_band_error) = print_band(a, grid, 0usize, margin_px(grid, 0usize, sheet_wide), across, atleast(margin_px(grid, 4usize, sheet_wide) - 6.0, 0.0))
    if head_band_error != ok { ret (zero, head_band_error) }
    page[q] = head_band
    q += 1usize
    page[q] = widget.padded(0u64, margin_px(grid, 0usize, sheet_wide) + across * 0.5 - 40.0, atleast(margin_px(grid, 1usize, sheet_wide) - margin_px(grid, 4usize, sheet_wide) - 12.0, 2.0), 0.0, 8.0, style.defaults(), one(a, widget.box(0u64, caption_look(grid), one(a, heading))))
    q += 1usize
    var r = 0usize
    while r < lines.len && q < 30usize && shown > 0usize {
        let (line_node, line_error) = print_row(a, grid, lines[r][0usize..shown], widths[0usize..shown], r)
        if line_error != ok { ret (zero, line_error) }
        page[q] = widget.padded(0u64, margin_px(grid, 0usize, sheet_wide), 0.0, 0.0, 0.0, style.defaults(), one(a, line_node))
        q += 1usize
        r += 1usize
    }
    let (filter_text, filter_error) = flat_text(a, grid, "<Filter is Empty>", gl.rgb(0xFFFFFFu32))
    if filter_error != ok { ret (zero, filter_error) }
    var strip = control.sized_style(across * zoom, 22.0)
    strip.background = paint.Brush { Solid: gl.rgb(dz_strip_rgb(grid, 7usize)) }
    strip.margin = style.EdgeLengths { left: style.Length { Px: margin_px(grid, 0usize, sheet_wide) }, top: style.Length { Px: 6.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    page[q] = widget.box(0u64, strip, one(a, widget.padded(0u64, 4.0, 2.0, 0.0, 0.0, style.defaults(), one(a, filter_text))))
    q += 1usize
    let (foot_band, foot_band_error) = print_band(a, grid, 3usize, margin_px(grid, 0usize, sheet_wide), across, atleast(margin_px(grid, 3usize, sheet_wide) - margin_px(grid, 5usize, sheet_wide) - 22.0, 0.0) + 8.0)
    if foot_band_error != ok { ret (zero, foot_band_error) }
    page[q] = foot_band
    q += 1usize
    page[q] = preview_footnote(a, grid, margin_px(grid, 0usize, sheet_wide))
    q += 1usize
    var sheet = control.sized_style(sheet_wide * zoom, sheet_high)
    sheet.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    sheet.border = style.Border { width: 1.0, color: gl.rgb(0x3C8CDCu32) }
    sheet.margin = style.EdgeLengths { left: style.Length { Px: 36.0 }, top: style.Length { Px: 12.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, sheet, page[0usize..q])
    n += 1usize
    // the page row: previous, "Page n of m", next
    let (foot, foot_error) = mem.alloc[widget.Node](a, 4usize)
    if foot_error != ok { ret (zero, control.TooLarge) }
    let (foot_taps, foot_taps_error) = mem.alloc[PrintTap](a, 2usize)
    if foot_taps_error != ok { ret (zero, control.TooLarge) }
    foot_taps[0usize] = PrintTap { grid: grid, index: 7u8 }
    foot_taps[1usize] = PrintTap { grid: grid, index: 8u8 }
    let (prev_label, prev_error) = flat_text(a, grid, "<", gl.rgb(0x000000u32))
    if prev_error != ok { ret (zero, prev_error) }
    let (next_label, next_error) = flat_text(a, grid, ">", gl.rgb(0x000000u32))
    if next_error != ok { ret (zero, next_error) }
    let (page_builder, page_builder_error) = str.builder(a, 24usize)
    if page_builder_error != ok { ret (zero, control.TooLarge) }
    var pb = page_builder
    if str.push(&pb, "Page ") != ok || str.push_u64(&pb, u64(grid.pv_page + 1usize)) != ok || str.push(&pb, " of ") != ok || str.push_u64(&pb, u64(pages)) != ok { ret (zero, control.TooLarge) }
    let (page_label, page_label_error) = flat_text(a, grid, str.done(&pb), gl.rgb(0x000000u32))
    if page_label_error != ok { ret (zero, page_label_error) }
    var tap_style = control.sized_style(30.0, 28.0)
    tap_style.background = paint.Brush { Solid: gl.rgb(0xFDFDFDu32) }
    tap_style.border = style.Border { width: 1.0, color: gl.rgb(0xADADADu32) }
    tap_style.margin = style.EdgeLengths { left: style.Length { Px: 36.0 }, top: style.Length { Px: 8.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 8.0 } }
    foot[0usize] = widget.region(grid.key + MENU_KEY + 850390u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&foot_taps[0usize]), invoke: on_print_tap }, gestures: 1u8, enabled: true, focusable: false }, tap_style, one(a, widget.padded(0u64, 10.0, 5.0, 0.0, 0.0, style.defaults(), one(a, prev_label))))
    foot[1usize] = widget.padded(0u64, 12.0, 14.0, 0.0, 0.0, style.defaults(), one(a, page_label))
    var tap_style_next = tap_style
    tap_style_next.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 8.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 8.0 } }
    foot[2usize] = widget.region(grid.key + MENU_KEY + 850391u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&foot_taps[1usize]), invoke: on_print_tap }, gestures: 1u8, enabled: true, focusable: false }, tap_style_next, one(a, widget.padded(0u64, 10.0, 5.0, 0.0, 0.0, style.defaults(), one(a, next_label))))
    let (close_label, close_error) = flat_text(a, grid, "Close", gl.rgb(0x000000u32))
    if close_error != ok { ret (zero, close_error) }
    var close_box = control.sized_style(100.0, 28.0)
    close_box.background = paint.Brush { Solid: gl.rgb(0xFDFDFDu32) }
    close_box.border = style.Border { width: 1.0, color: gl.rgb(0xADADADu32) }
    close_box.radius = 4.0
    close_box.margin = style.EdgeLengths { left: style.Length { Px: 380.0 }, top: style.Length { Px: 8.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 8.0 } }
    foot[3usize] = widget.region(grid.key + MENU_KEY + 850370u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](grid), invoke: on_print_close }, gestures: 1u8, enabled: true, focusable: false }, close_box, one(a, widget.padded(0u64, 28.0, 5.0, 0.0, 0.0, style.defaults(), one(a, close_label))))
    rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(width, 44.0), foot[0usize..4usize])
    n += 1usize
    var panel = control.sized_style(width, 520.0)
    panel.background = paint.Brush { Solid: gl.rgb(0xA0A0A0u32) }
    panel.border = style.Border { width: 1.0, color: gl.rgb(0x606060u32) }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, panel, rows[0usize..n]), ok)
}

// The style window over the wizard, and over it the colour editor of the row asked for.
fn fmt_layers(a: *mem.Arena, grid: *Grid, base: widget.Node) -> (widget.Node, err) {
    let (over, over_error) = fmt_panel(a, grid)
    if over_error != ok { ret (zero, over_error) }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 3usize)
    if layers_error != ok { ret (zero, control.TooLarge) }
    layers[0usize] = base
    layers[1usize] = widget.padded(0u64, 70.0, 20.0, 0.0, 0.0, style.defaults(), one(a, over))
    if grid.fmt_pick == 0u8 { ret (widget.stack(0u64, style.defaults(), layers[0usize..2usize]), ok) }
    // the colour editor of the row asked for, over the dialog
    let (swatches, swatches_error) = swatch_panel(a, grid)
    if swatches_error != ok { ret (zero, swatches_error) }
    var down: f32 = 205.0
    if grid.fmt_pick == 2u8 { down = 280.0 }
    if grid.fmt_pick == 3u8 { down = 305.0 }
    layers[2usize] = widget.padded(0u64, 196.0, down, 0.0, 0.0, style.defaults(), one(a, swatches))
    ret (widget.stack(0u64, style.defaults(), layers[0usize..3usize]), ok)
}

fn wiz_panel(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    if grid.sw_open != 0u8 {
        let (sw_node, sw_error) = sw_panel(a, grid)
        ret (sw_node, sw_error)
    }
    if grid.print_open && grid.pv_design {
        let (design_node, design_error) = designer_panel(a, grid)
        ret (design_node, design_error)
    }
    if grid.print_open && grid.pv_setup {
        let (setup_node, setup_error) = page_setup_panel(a, grid)
        ret (setup_node, setup_error)
    }
    if grid.print_open {
        let (print_node, print_error) = print_panel(a, grid)
        ret (print_node, print_error)
    }
    let (base, base_error) = wiz_panel_base(a, grid)
    if base_error != ok { ret (zero, base_error) }
    if !grid.fmt_open { ret (base, ok) }
    let (layered, layered_error) = fmt_layers(a, grid, base)
    ret (layered, layered_error)
}

fn wiz_panel_base(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let width: f32 = 520.0
    let (rows, rows_error) = mem.alloc[widget.Node](a, 24usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    let (picks, picks_error) = mem.alloc[WizRow](a, 10usize)
    if picks_error != ok { ret (zero, control.TooLarge) }
    var n = 0usize
    let (title_row, title_error) = window_title(a, grid, 2u8, "Conditional Formatting Rule", width, 40.0, false)
    if title_error != ok { ret (zero, title_error) }
    rows[n] = title_row
    n += 1usize
    let (head, head_error) = flat_text(a, grid, "Select a Rule Type:", gl.rgb(0x000000u32))
    if head_error != ok { ret (zero, head_error) }
    rows[n] = widget.padded(0u64, 12.0, 8.0, 0.0, 4.0, style.defaults(), one(a, head))
    n += 1usize
    var i = 0usize
    while i < 10usize {
        picks[i] = WizRow { grid: grid, index: u8(i) }
        var ink = gl.rgb(0x000000u32)
        if grid.wiz_type == u8(i) { ink = gl.rgb(0xFFFFFFu32) }
        let (label, label_error) = flat_text(a, grid, wiz_words(u8(i)), ink)
        if label_error != ok { ret (zero, label_error) }
        var row_style = control.sized_style(width - 24.0, 26.0)
        row_style.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
        if grid.wiz_type == u8(i) { row_style.background = paint.Brush { Solid: gl.rgb(0x0078D7u32) } }
        row_style.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, control.TooLarge) }
        held[0usize] = widget.padded(0u64, 4.0, 5.0, 0.0, 0.0, style.defaults(), one(a, label))
        rows[n] = widget.region(grid.key + MENU_KEY + 850000u64 + u64(i), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&picks[i]), invoke: on_wiz_row }, gestures: 1u8, enabled: true, focusable: false }, row_style, held[0usize..1usize])
        n += 1usize
        i += 1usize
    }
    let (ok_label, ok_error) = flat_text(a, grid, "OK", gl.rgb(0x000000u32))
    if ok_error != ok { ret (zero, ok_error) }
    let (cancel_label, cancel_error) = flat_text(a, grid, "Cancel", gl.rgb(0x000000u32))
    if cancel_error != ok { ret (zero, cancel_error) }
    var ok_box = control.sized_style(110.0, 27.0)
    ok_box.background = paint.Brush { Solid: gl.rgb(0xFDFDFDu32) }
    ok_box.border = style.Border { width: 2.0, color: gl.rgb(0x0078D7u32) }
    ok_box.radius = 4.0
    var cancel_box = control.sized_style(110.0, 27.0)
    cancel_box.background = paint.Brush { Solid: gl.rgb(0xFDFDFDu32) }
    cancel_box.border = style.Border { width: 1.0, color: gl.rgb(0xADADADu32) }
    cancel_box.radius = 4.0
    let (ok_held, ok_held_error) = mem.alloc[widget.Node](a, 1usize)
    if ok_held_error != ok { ret (zero, control.TooLarge) }
    ok_held[0usize] = widget.padded(0u64, 40.0, 5.0, 0.0, 0.0, style.defaults(), one(a, ok_label))
    let (cancel_held, cancel_held_error) = mem.alloc[widget.Node](a, 1usize)
    if cancel_held_error != ok { ret (zero, control.TooLarge) }
    cancel_held[0usize] = widget.padded(0u64, 30.0, 5.0, 0.0, 0.0, style.defaults(), one(a, cancel_label))
    let (buttons, buttons_error) = mem.alloc[widget.Node](a, 2usize)
    if buttons_error != ok { ret (zero, control.TooLarge) }
    buttons[0usize] = widget.region(grid.key + MENU_KEY + 850100u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](grid), invoke: on_wiz_ok }, gestures: 1u8, enabled: true, focusable: false }, ok_box, ok_held[0usize..1usize])
    buttons[1usize] = widget.region(grid.key + MENU_KEY + 850101u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](grid), invoke: on_wiz_cancel }, gestures: 1u8, enabled: true, focusable: false }, cancel_box, cancel_held[0usize..1usize])
    var foot = control.sized_style(width - 24.0, 46.0)
    foot.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 8.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
    // the Preview strip (v3: a gradient for the colour scales, a bar for the data bar, boxes for the icons)
    if grid.wiz_type <= 3u8 {
        var strip_cells: [8]widget.Node = zero
        var strip_count = 0usize
        if grid.wiz_type == 0u8 {
            var bar_back = control.sized_style(240.0, 20.0)
            bar_back.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
            bar_back.border = style.Border { width: 1.0, color: gl.rgb(0x8E9092u32) }
            var bar_fill = control.sized_style(160.0, 18.0)
            bar_fill.background = paint.Brush { Solid: wiz_high(grid.wiz_palette) }
            let (bar_held, bar_held_error) = mem.alloc[widget.Node](a, 1usize)
            if bar_held_error != ok { ret (zero, control.TooLarge) }
            bar_held[0usize] = widget.box(0u64, bar_fill, zero)
            strip_cells[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, bar_back, bar_held[0usize..1usize])
            strip_count = 1usize
        } else if grid.wiz_type == 1u8 {
            var icon_colors: [3]u32 = [3]u32{ 0xE05050u32, 0xE0C040u32, 0x50B050u32 }
            var ic = 0usize
            while ic < 3usize {
                var icon_box = control.sized_style(30.0, 20.0)
                icon_box.background = paint.Brush { Solid: gl.rgb(icon_colors[ic]) }
                icon_box.radius = 10.0
                strip_cells[ic] = widget.box(0u64, icon_box, zero)
                ic += 1usize
            }
            strip_count = 3usize
        } else {
            // a colour scale: one linear gradient from the low colour to the high one, through the middle
            // colour for three (a single node: eight boxes pushed the wizard over what a frame holds)
            let (stops, stops_error) = mem.alloc[paint.Stop](a, 3usize)
            if stops_error != ok { ret (zero, control.TooLarge) }
            var stop_count = 2usize
            stops[0usize] = paint.Stop { offset: 0.0, color: wiz_low(grid.wiz_palette) }
            if grid.wiz_type == 2u8 {
                stops[1usize] = paint.Stop { offset: 0.5, color: paint.rgba(1.0, 1.0, 0.8, 1.0) }
                stops[2usize] = paint.Stop { offset: 1.0, color: wiz_high(grid.wiz_palette) }
                stop_count = 3usize
            } else {
                stops[1usize] = paint.Stop { offset: 1.0, color: wiz_high(grid.wiz_palette) }
            }
            var gradient_box = control.sized_style(240.0, 20.0)
            gradient_box.background = paint.Brush { Linear: paint.LinearGradient { start: geometry.Point { x: 0.0, y: 0.0 }, end: geometry.Point { x: 240.0, y: 0.0 }, stops: stops[0usize..stop_count] } }
            strip_cells[0usize] = widget.box(0u64, gradient_box, zero)
            strip_count = 1usize
        }
        var strip_style = control.sized_style(width - 24.0, 24.0)
        strip_style.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 6.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
        rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, strip_style, strip_cells[0usize..strip_count])
        n += 1usize
        // Format...: steps through four colour sets (v3 opens its cell format dialog)
        let (format_label, format_label_error) = flat_text(a, grid, "Format...", gl.rgb(0x000000u32))
        if format_label_error != ok { ret (zero, format_label_error) }
        var format_box = control.sized_style(100.0, 26.0)
        format_box.background = paint.Brush { Solid: gl.rgb(0xFDFDFDu32) }
        format_box.border = style.Border { width: 1.0, color: gl.rgb(0xADADADu32) }
        format_box.radius = 4.0
        format_box.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 6.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
        let (format_held, format_held_error) = mem.alloc[widget.Node](a, 1usize)
        if format_held_error != ok { ret (zero, control.TooLarge) }
        format_held[0usize] = widget.padded(0u64, 20.0, 4.0, 0.0, 0.0, style.defaults(), one(a, format_label))
        rows[n] = widget.region(grid.key + MENU_KEY + 850330u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](grid), invoke: on_wiz_format }, gestures: 1u8, enabled: true, focusable: false }, format_box, format_held[0usize..1usize])
        n += 1usize
    }
    // the column the rule applies to (the manager shows it in Applies to): the library's select
    if !grid.has_wiz_target {
        // a new rule starts on the first numeric column, which is what OK would pick
        var default_at = 0usize
        while default_at < grid.all.len {
            let default_kind = grid.all[default_at].kind
            if sort_row_listed(grid, default_at) && (default_kind == CellKind.Int || default_kind == CellKind.Real || default_kind == CellKind.Currency) {
                grid.wiz_target = default_at
                grid.has_wiz_target = true
                default_at = grid.all.len
            } else {
                default_at += 1usize
            }
        }
    }
    let (target_names, target_names_error) = mem.alloc[str](a, grid.all.len + 1usize)
    if target_names_error != ok { ret (zero, control.TooLarge) }
    let (target_picks, target_picks_error) = mem.alloc[WizPick](a, grid.all.len + 1usize)
    if target_picks_error != ok { ret (zero, control.TooLarge) }
    let (target_submits, target_submits_error) = mem.alloc[widget.Submit](a, grid.all.len + 1usize)
    if target_submits_error != ok { ret (zero, control.TooLarge) }
    var target_count = 0usize
    var target_current = 0usize
    var listed_at = 0usize
    while listed_at < grid.all.len {
        if sort_row_listed(grid, listed_at) {
            target_names[target_count] = grid.all[listed_at].title
            target_picks[target_count] = WizPick { grid: grid, spec: listed_at }
            target_submits[target_count] = widget.Submit { ctx: mem.cast[*void](&target_picks[target_count]), invoke: on_wiz_pick }
            if grid.has_wiz_target && grid.wiz_target == listed_at { target_current = target_count }
            target_count += 1usize
        }
        listed_at += 1usize
    }
    let (target_toggle, target_toggle_error) = mem.alloc[widget.Submit](a, 1usize)
    if target_toggle_error != ok { ret (zero, control.TooLarge) }
    target_toggle[0usize] = widget.Submit { ctx: mem.cast[*void](grid), invoke: on_wiz_select_toggle }
    let (target_select, target_select_error) = control.select(a, grid.key + MENU_KEY + 850320u64, grid.theme, "Applies to", target_names[0usize..target_count], target_current, grid.wiz_select_open, &target_toggle[0usize], target_submits[0usize..target_count])
    if target_select_error != ok { ret (zero, target_select_error) }
    var target_row = control.sized_style(300.0, 56.0)
    target_row.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 6.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
    rows[n] = widget.box(0u64, target_row, one(a, target_select))
    n += 1usize
    // the formula (v3's last rule type): one text field, the comparison to apply
    if grid.wiz_type == 9u8 {
        let (formula_texts, formula_texts_error) = mem.alloc[WizText](a, 1usize)
        if formula_texts_error != ok { ret (zero, control.TooLarge) }
        formula_texts[0usize] = WizText { grid: grid, maximum: false }
        var formula_options = control.field_options()
        formula_options.placeholder = "=A1>5"
        formula_options.width = width - 48.0
        formula_options.height = 44.0
        let (formula_field, formula_error) = control.text_field(a, grid.key + MENU_KEY + 850340u64, grid.theme, "Format values where this formula is true", grid.wiz_min_text[0usize..16usize], grid.wiz_min_len, widget.Change[str] { ctx: mem.cast[*void](&formula_texts[0usize]), invoke: on_wiz_text }, zero, formula_options)
        if formula_error != ok { ret (zero, formula_error) }
        var formula_row = control.sized_style(width - 24.0, 56.0)
        formula_row.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 6.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
        rows[n] = widget.box(0u64, formula_row, one(a, formula_field))
        n += 1usize
    }
    // Minimum and Maximum (v3: a Lowest / Highest Value choice and a value field, for the range types)
    if grid.wiz_type <= 3u8 {
        let (texts, texts_error) = mem.alloc[WizText](a, 2usize)
        if texts_error != ok { ret (zero, control.TooLarge) }
        texts[0usize] = WizText { grid: grid, maximum: false }
        texts[1usize] = WizText { grid: grid, maximum: true }
        var side = 0usize
        let (pair_cells, pair_cells_error) = mem.alloc[widget.Node](a, 2usize)
        if pair_cells_error != ok { ret (zero, control.TooLarge) }
        while side < 2usize {
            var is_number = grid.wiz_min_number
            var caption = "Minimum: Lowest Value"
            if side == 1usize {
                is_number = grid.wiz_max_number
                caption = "Maximum: Highest Value"
            }
            if is_number {
                caption = "Minimum: Number"
                if side == 1usize { caption = "Maximum: Number" }
                if (side == 0usize && grid.wiz_min_pct) || (side == 1usize && grid.wiz_max_pct) {
                    caption = "Minimum: Percent"
                    if side == 1usize { caption = "Maximum: Percent" }
                }
                if (side == 0usize && grid.wiz_min_ptile) || (side == 1usize && grid.wiz_max_ptile) {
                    caption = "Minimum: Percentile"
                    if side == 1usize { caption = "Maximum: Percentile" }
                }
            }
            let (mode_label, mode_error) = flat_text(a, grid, caption, gl.rgb(0x000000u32))
            if mode_error != ok { ret (zero, mode_error) }
            var mode_box = control.sized_style(180.0, 26.0)
            mode_box.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
            mode_box.border = style.Border { width: 1.0, color: gl.rgb(0x8E9092u32) }
            let (mode_held, mode_held_error) = mem.alloc[widget.Node](a, 1usize)
            if mode_held_error != ok { ret (zero, control.TooLarge) }
            mode_held[0usize] = widget.padded(0u64, 6.0, 4.0, 0.0, 0.0, style.defaults(), one(a, mode_label))
            let mode_node = widget.region(grid.key + MENU_KEY + 850300u64 + u64(side), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&texts[side]), invoke: on_wiz_mode }, gestures: 1u8, enabled: true, focusable: false }, mode_box, mode_held[0usize..1usize])
            let (column_nodes, column_nodes_error) = mem.alloc[widget.Node](a, 2usize)
            if column_nodes_error != ok { ret (zero, control.TooLarge) }
            column_nodes[0usize] = mode_node
            var column_count = 1usize
            if is_number {
                var buffer = grid.wiz_min_text[0usize..16usize]
                var length = grid.wiz_min_len
                if side == 1usize {
                    buffer = grid.wiz_max_text[0usize..16usize]
                    length = grid.wiz_max_len
                }
                // the library's spin box: arrows and typing, for the number of the Minimum or Maximum
                var spun: i64 = 0i64
                if length > 0usize {
                    let (parsed, parse_error) = str.parse_f64(buffer[0usize..length])
                    if parse_error == ok { spun = i64(parsed) }
                }
                let (field, field_error) = control.spin_box_sized(a, grid.key + MENU_KEY + 850310u64 + u64(side), grid.theme, "Value", buffer, spun, -1000000i64, 1000000i64, 1i64, widget.Change[i64] { ctx: mem.cast[*void](&texts[side]), invoke: on_wiz_spin }, widget.Change[str] { ctx: mem.cast[*void](&texts[side]), invoke: on_wiz_text }, 180.0)
                if field_error != ok { ret (zero, field_error) }
                column_nodes[1usize] = field
                column_count = 2usize
            }
            pair_cells[side] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, style.defaults(), column_nodes[0usize..column_count])
            side += 1usize
        }
        var pair_style = control.sized_style(width - 24.0, 70.0)
        pair_style.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 6.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
        rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 24.0 }, pair_style, pair_cells[0usize..2usize])
        n += 1usize
    }
    // the data bar's own option (v3: Show Bar Only), a check box under the list
    if grid.wiz_type == 0u8 {
        var box_ink = gl.rgb(0x000000u32)
        let (bar_label, bar_label_error) = flat_text(a, grid, "Show Bar Only", box_ink)
        if bar_label_error != ok { ret (zero, bar_label_error) }
        var check_style = control.sized_style(14.0, 14.0)
        check_style.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
        check_style.border = style.Border { width: 1.0, color: gl.rgb(0x333333u32) }
        check_style.radius = 2.0
        let (check_held, check_held_error) = mem.alloc[widget.Node](a, 1usize)
        if check_held_error != ok { ret (zero, control.TooLarge) }
        if grid.wiz_bar_only {
            let (tick, tick_error) = gl.mark(a, .Check, gl.rgb(0x005FB8u32), gl.rgb(0x005FB8u32), 10.0, 10.0)
            if tick_error != ok { ret (zero, tick_error) }
            check_held[0usize] = tick
        } else {
            check_held[0usize] = widget.box(0u64, style.defaults(), zero)
        }
        let (bar_parts, bar_parts_error) = mem.alloc[widget.Node](a, 2usize)
        if bar_parts_error != ok { ret (zero, control.TooLarge) }
        bar_parts[0usize] = widget.aligned(0u64, .Center, .Center, check_style, check_held[0usize..1usize])
        bar_parts[1usize] = bar_label
        var bar_row = control.sized_style(width - 24.0, 24.0)
        bar_row.margin = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 6.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
        rows[n] = widget.region(grid.key + MENU_KEY + 850200u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](grid), invoke: on_wiz_bar_only }, gestures: 1u8, enabled: true, focusable: false }, bar_row, one(a, widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, style.defaults(), bar_parts[0usize..2usize])))
        n += 1usize
    }
    rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .End, cross: .Center, gap: 8.0 }, foot, buttons[0usize..2usize])
    n += 1usize
    var body = control.sized_style(width, 40.0 + 30.0 + 260.0 + 62.0 + 30.0 + 80.0 + 32.0 + 30.0 + 32.0)
    body.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    body.border = style.Border { width: 1.0, color: gl.rgb(0x6D6D6Du32) }
    body.radius = 8.0
    body.overflow = .Clip
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, control.TooLarge) }
    inner[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), rows[0usize..n])
    let (framed_body, framed_body_error) = window_body(a, grid, 2u8, body, inner[0usize..1usize])
    ret (framed_body, framed_body_error)
}

fn chooser_panel(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let me = mem.cast[*void](grid)
    let (items, items_error) = mem.alloc[widget.Node](a, grid.all.len + 2usize)
    if items_error != ok { ret (zero, control.TooLarge) }
    let (picks, picks_error) = mem.alloc[ChooserItem](a, grid.all.len + 1usize)
    if picks_error != ok { ret (zero, control.TooLarge) }
    // the title bar: the name, and a close mark that is grey, red when the window is active, deeper red hovered
    var title_words = control.text_options()
    title_words.wrap = .None
    title_words.size = grid.look.text_size
    var title_ink = gl.rgb(0xA0A0A0u32)
    if grid.chooser_active { title_ink = gl.rgb(0x000000u32) }
    var title_caption = "Column"
    if grid.band_names.len > 0usize || grid.band_tabs { title_caption = "Customization" }
    let (title, title_error) = control.colored_text(a, 0u64, title_caption, grid.theme, title_words, title_ink)
    if title_error != ok { ret (zero, title_error) }
    var title_style = style.defaults()
    title_style.width = style.Length { Px: 130.0 }
    title_style.height = style.Length { Px: 22.0 }
    title_style.padding = style.EdgeLengths { left: style.Length { Px: 4.0 }, top: style.Length { Px: 4.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    let (title_nodes, title_nodes_error) = mem.alloc[widget.Node](a, 1usize)
    if title_nodes_error != ok { ret (zero, control.TooLarge) }
    title_nodes[0usize] = title
    let title_region = widget.region(grid.key + CHOOSER_KEY + 2u64, widget.Region { gesture: widget.GestureAction { ctx: me, invoke: on_chooser_title }, gestures: 3u8, enabled: true, focusable: false }, title_style, title_nodes[0usize..1usize])
    let (close_act, close_error) = mem.alloc[widget.Submit](a, 1usize)
    if close_error != ok { ret (zero, control.TooLarge) }
    close_act[0usize] = widget.Submit { ctx: me, invoke: on_chooser_close }
    var closer: widget.Node = zero
    var closer_words = control.text_options()
    closer_words.wrap = .None
    closer_words.size = grid.look.text_size
    let (closer_text, closer_error) = control.colored_text(a, 0u64, "x", grid.theme, closer_words, gl.rgb(0xFFFFFFu32))
    if closer_error != ok { ret (zero, closer_error) }
    closer = closer_text
    let close_state = control.control_state(grid.theme, grid.key + CHOOSER_KEY + 1u64, true, false)
    var close_look = style.resolve(grid.theme.tokens, .Plain, close_state)
    var close_fill = gl.rgb(0xDADADAu32)
    if grid.chooser_active { close_fill = gl.rgb(0xC75050u32) }
    if close_state.hovered { close_fill = gl.rgb(0xE04343u32) }
    close_look.background = close_fill
    close_look.border_width = 0.0
    close_look.radius = 0.0
    close_look.custom_padding = true
    close_look.padding = 6.0
    close_look.padding_y = 0.0
    close_look.min_width = 24.0
    close_look.min_height = 20.0
    let (close_button, close_button_error) = control.pressable_states(a, grid.key + CHOOSER_KEY + 1u64, grid.theme, 3u8, "Close", close_look, true, false, 0u32, 0u32, 0u64, &close_act[0usize], closer)
    if close_button_error != ok { ret (zero, close_button_error) }
    let (bar, bar_error) = mem.alloc[widget.Node](a, 2usize)
    if bar_error != ok { ret (zero, control.TooLarge) }
    bar[0usize] = title_region
    bar[1usize] = close_button
    var bar_style = style.defaults()
    bar_style.background = paint.Brush { Solid: gl.rgb(0xF3F3F3u32) }
    var n = 0usize
    items[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .SpaceBetween, cross: .Center, gap: 0.0 }, bar_style, bar[0usize..2usize])
    n += 1usize
    if grid.band_names.len > 0usize || grid.band_tabs {
        let (tabs, tabs_error) = chooser_tabs(a, grid)
        if tabs_error != ok { ret (zero, tabs_error) }
        items[n] = tabs
        n += 1usize
    }
    // the list: white, the hidden columns by name in the order of their titles
    let (rows, rows_error) = mem.alloc[widget.Node](a, grid.all.len + grid.band_names.len + 1usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    var listed = 0usize
    var o = 0usize
    while o < grid.band_names.len && grid.chooser_bands {
        // the Bands tab names the bands
        var band_label: widget.Node = zero
        let band_error = text_node(a, grid, grid.band_names[o], false, .Text, &band_label)
        if band_error != ok { ret (zero, band_error) }
        var band_style = style.defaults()
        band_style.width = style.Length { Percent: 100.0 }
        band_style.height = style.Length { Px: 19.0 }
        band_style.padding = style.EdgeLengths { left: style.Length { Px: 3.0 }, top: style.Length { Px: 1.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
        rows[listed] = widget.box(0u64, band_style, one(a, band_label))
        listed += 1usize
        o += 1usize
    }
    o = 0usize
    while o < grid.all.len {
        if !grid.chooser_bands && grid.hidden[o] && grid.all[o].kind != CellKind.Indicator && grid.all[o].title.len != 0usize {
            picks[listed] = ChooserItem { grid: grid, spec: o }
            var label: widget.Node = zero
            let label_error = text_node(a, grid, grid.all[o].title, false, .Text, &label)
            if label_error != ok { ret (zero, label_error) }
            let item_key = grid.key + CHOOSER_KEY + 8u64 + u64(o)
            let item_state = control.control_state(grid.theme, item_key, true, false)
            var item_style = style.defaults()
            item_style.width = style.Length { Percent: 100.0 }
            item_style.height = style.Length { Px: 19.0 }
            item_style.padding = style.EdgeLengths { left: style.Length { Px: 3.0 }, top: style.Length { Px: 1.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
            if item_state.hovered { item_style.background = paint.Brush { Solid: gl.rgb(0xD9EBF9u32) } }
            let (label_nodes, label_nodes_error) = mem.alloc[widget.Node](a, 1usize)
            if label_nodes_error != ok { ret (zero, control.TooLarge) }
            label_nodes[0usize] = label
            rows[listed] = widget.region(item_key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&picks[listed]), invoke: on_chooser_item }, gestures: 7u8, enabled: true, focusable: false }, item_style, label_nodes[0usize..1usize])
            listed += 1usize
        }
        o += 1usize
    }
    var list_style = style.defaults()
    list_style.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    list_style.border = style.Border { width: 1.0, color: gl.rgb(0xABABABu32) }
    list_style.width = style.Length { Percent: 100.0 }
    list_style.min_height = style.Length { Px: 120.0 }
    // v3's Customization window is 436 px tall
    if grid.band_names.len > 0usize || grid.band_tabs { list_style.min_height = style.Length { Px: 232.0 } }
    items[n] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, list_style, rows[0usize..listed])
    n += 1usize
    let inner = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 3.0 }, style.defaults(), items[0usize..n])
    var window = style.defaults()
    window.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    window.border = style.Border { width: 1.0, color: gl.rgb(0xBABABAu32) }
    window.width = style.Length { Px: 170.0 }
    let padded_window = widget.padded(0u64, 3.0, 0.0, 3.0, 4.0, window, one(a, inner))
    // the whole window takes a dropped header
    let (window_nodes, window_nodes_error) = mem.alloc[widget.Node](a, 1usize)
    if window_nodes_error != ok { ret (zero, control.TooLarge) }
    window_nodes[0usize] = padded_window
    let dropping = widget.region(grid.key + CHOOSER_KEY + 3u64, widget.Region { gesture: widget.GestureAction { ctx: me, invoke: on_chooser_drop }, gestures: widget.GESTURE_DROP, enabled: true, focusable: false }, style.defaults(), window_nodes[0usize..1usize])
    ret (dropping, ok)
}

// The tab row under the title bar of a band grid's Customization window: Bands and Columns, the
// chosen one white over the rest.
fn chooser_tabs(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, 2usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    var k = 0usize
    while k < 2usize {
        var caption = "Bands"
        var on_tap = on_chooser_tab_bands
        var chosen = grid.chooser_bands
        if k == 1usize {
            caption = "Columns"
            on_tap = on_chooser_tab_columns
            chosen = !grid.chooser_bands
        }
        var label: widget.Node = zero
        let label_error = text_node(a, grid, caption, false, .Text, &label)
        if label_error != ok { ret (zero, label_error) }
        var tab = style.defaults()
        tab.width = style.Length { Px: 60.0 }
        tab.height = style.Length { Px: 22.0 }
        tab.padding = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: style.Length { Px: 4.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
        tab.border = style.Border { width: 1.0, color: gl.rgb(0xBABABAu32) }
        tab.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
        if chosen { tab.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) } }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, control.TooLarge) }
        held[0usize] = label
        cells[k] = widget.region(grid.key + CHOOSER_KEY + 6u64 + u64(k), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](grid), invoke: on_tap }, gestures: 1u8, enabled: true, focusable: false }, tab, held[0usize..1usize])
        k += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), cells[0usize..2usize]), ok)
}

// ---- the popup menu in v3's look (flat #F0F0F0 with a grey frame, 16 px pictures, hover #0078D7) ----

// The mnemonic of a caption: the character after the first '&' (0 when none).
fn mnemonic_of(label: str) -> u8 {
    var i = 0usize
    while i + 1usize < label.len {
        if label[i] == 38u8 { ret label[i + 1usize] }
        i += 1usize
    }
    ret 0u8
}

fn upper_ascii(c: u8) -> u8 {
    if c >= 97u8 && c <= 122u8 { ret c - 32u8 }
    ret c
}

// A caption in the arena without its '&', and where the mnemonic stands (len when none).
fn plain_caption(a: *mem.Arena, label: str) -> (str, usize, err) {
    let (buf, buf_error) = mem.alloc[u8](a, label.len + 1usize)
    if buf_error != ok { ret ("", 0usize, buf_error) }
    var n = 0usize
    var at = label.len
    var i = 0usize
    while i < label.len {
        if label[i] == 38u8 && i + 1usize < label.len && label[i + 1usize] == 38u8 {
            // && is a literal ampersand
            buf[n] = 38u8
            n += 1usize
            i += 2usize
        } else if label[i] == 38u8 && at == label.len && i + 1usize < label.len {
            at = n
            i += 1usize
        } else {
            buf[n] = label[i]
            n += 1usize
            i += 1usize
        }
    }
    ret (buf[0usize..n], at, ok)
}

// The caption as a node: the mnemonic underlined (v3 draws &Add to Deck as Add to Deck).
fn caption_node(a: *mem.Arena, grid: *Grid, label: str, ink: paint.Color) -> (widget.Node, err) {
    let (plain, at, plain_error) = plain_caption(a, label)
    if plain_error != ok { ret (zero, plain_error) }
    if at >= plain.len {
        let (whole, whole_error) = flat_text(a, grid, plain, ink)
        ret (whole, whole_error)
    }
    // a space before the mark is kept as room: the text layout trims a trailing space
    var before_end = at
    var gap: f32 = 0.0
    if before_end > 0usize && plain[before_end - 1usize] == 32u8 {
        before_end -= 1usize
        gap = 4.0
    }
    let (before, before_error) = flat_text(a, grid, plain[0usize..before_end], ink)
    if before_error != ok { ret (zero, before_error) }
    let (mark, mark_error) = flat_text(a, grid, plain[at..at + 1usize], ink)
    if mark_error != ok { ret (zero, mark_error) }
    let (after, after_error) = flat_text(a, grid, plain[at + 1usize..], ink)
    if after_error != ok { ret (zero, after_error) }
    var rule = control.sized_style(7.0, 1.0)
    rule.background = paint.Brush { Solid: ink }
    let (under, under_error) = mem.alloc[widget.Node](a, 2usize)
    if under_error != ok { ret (zero, control.TooLarge) }
    under[0usize] = mark
    under[1usize] = widget.box(0u64, rule, zero)
    let underlined = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), under[0usize..2usize])
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    var n = 0usize
    if before_end > 0usize {
        parts[n] = before
        n += 1usize
    }
    parts[n] = widget.padded(0u64, gap, 0.0, 0.0, 0.0, style.defaults(), one(a, underlined))
    n += 1usize
    if at + 1usize < plain.len {
        parts[n] = after
        n += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..n]), ok)
}

// A mnemonic letter runs its entry.
fn on_flat_key(ctx: *void) -> err {
    let pick = mem.cast[*FlatPick](ctx)
    if !pick.enabled { ret ok }
    pick.grid.menu_open = false
    if widget.submit_set(pick.action.invoke) { ret widget.fire_submit(pick.action) }
    ret ok
}

// The cursor of the popup moved by the keyboard: down or up to the next enabled entry.
fn on_flat_move(ctx: *void) -> err {
    let step = mem.cast[*FlatStep](ctx)
    let grid = step.grid
    let n = grid.menu_count
    if n == 0usize { ret ok }
    var at = grid.menu_cursor
    var tried = 0usize
    while tried < n {
        if step.down {
            at = (at + 1usize) % n
        } else {
            at = (at + n - 1usize) % n
        }
        if grid.menu_enabled[at] { break }
        tried += 1usize
    }
    grid.menu_cursor = at
    ret ok
}

type FlatStep = struct { grid: *Grid, down: bool }

// Enter runs the entry under the cursor.
fn on_flat_enter(ctx: *void) -> err {
    let grid = mem.cast[*Grid](ctx)
    if grid.menu_cursor >= grid.menu_count || !grid.menu_enabled[grid.menu_cursor] { ret ok }
    grid.menu_open = false
    let action = grid.menu_actions[grid.menu_cursor]
    if widget.submit_set(action.invoke) { ret widget.fire_submit(action) }
    ret ok
}

// A hover and a pick of one entry (a pointer over it lights it, a tap runs it).
type FlatPick = struct { grid: *Grid, action: widget.Submit, enabled: bool }

fn on_flat_tap(ctx: *void, g: widget.Gesture) -> err {
    let pick = mem.cast[*FlatPick](ctx)
    switch g {
    case .Tap as at:
        if !pick.enabled { ret ok }
        pick.grid.menu_open = false
        if widget.submit_set(pick.action.invoke) { ret widget.fire_submit(pick.action) }
        ret ok
    default:
        ret ok
    }
}

fn flat_text(a: *mem.Arena, grid: *Grid, text: str, ink: paint.Color) -> (widget.Node, err) {
    var words = control.text_options()
    words.wrap = .None
    words.size = grid.look.text_size
    let (node, node_error) = control.colored_text(a, 0u64, text, grid.theme, words, ink)
    ret (node, node_error)
}

// The commands as a popup at the window point (x, y): `row_h` tall entries, v3's colours.
fn flat_menu(a: *mem.Arena, grid: *Grid, commands: []const overlay.MenuCommand, x: f32, y: f32, row_h: f32) -> (widget.Node, err) {
    let (picks, picks_error) = mem.alloc[FlatPick](a, commands.len)
    if picks_error != ok { ret (zero, control.TooLarge) }
    let (rows, rows_error) = mem.alloc[widget.Node](a, commands.len * 4usize + 1usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    var n = 0usize
    var widest_label = 0usize
    var widest_hint = 0usize
    var widest_hint_label = 0usize
    var k = 0usize
    while k < commands.len {
        if commands[k].label.len > widest_label { widest_label = commands[k].label.len }
        if commands[k].shortcut.len > widest_hint { widest_hint = commands[k].shortcut.len }
        if commands[k].shortcut.len != 0usize && commands[k].label.len > widest_hint_label { widest_hint_label = commands[k].label.len }
        k += 1usize
    }
    // 6.4 logical px a character of the 10 pt face is near enough; the picture column is 27 wide
    grid.menu_count = commands.len
    if grid.menu_count > 40usize { grid.menu_count = 40usize }
    // the application's menus (v3's View) are set in a smaller face than the grid's popups
    var char_width: f32 = 4.0
    if grid.menu_kind == MENU_APP { char_width = 4.6 }
    var width = 27.0 + f32(widest_label) * char_width + 24.0 + 22.0
    if widest_hint != 0usize {
        let with_hint = 27.0 + f32(widest_hint_label) * char_width + 34.0 + f32(widest_hint) * char_width + 6.0 + 14.0
        if with_hint > width { width = with_hint }
    }
    if width < 120.0 { width = 120.0 }
    // v3's column popup is 251 px across, ours came out 240
    if grid.menu_kind == MENU_HEADER { width += 7.0 }
    var i = 0usize
    while i < commands.len {
        let c = commands[i]
        if c.separated && i != 0usize {
            var rule = control.sized_style(width - 2.0, 1.0)
            rule.background = paint.Brush { Solid: gl.rgb(0xBCBCBCu32) }
            rule.margin = style.EdgeLengths { left: style.Length { Px: 1.0 }, top: style.Length { Px: 4.0 }, right: style.Length { Px: 1.0 }, bottom: style.Length { Px: 5.0 } }
            rows[n] = widget.box(0u64, rule, zero)
            n += 1usize
        }
        if c.head.len != 0usize {
            // a section heading: bold words over a rule (v3's View menu)
            let (heading, heading_error) = flat_text(a, grid, c.head, gl.rgb(0x000000u32))
            if heading_error != ok { ret (zero, heading_error) }
            var head_style = control.sized_style(width - 2.0, row_h + 4.0)
            head_style.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
            let (bold_heading, bold_heading_error) = faux_bold(a, grid, c.head, heading)
            if bold_heading_error != ok { ret (zero, bold_heading_error) }
            rows[n] = widget.padded(0u64, 10.0, 6.0, 0.0, 0.0, head_style, one(a, bold_heading))
            n += 1usize
            var head_rule = control.sized_style(width - 2.0, 1.0)
            head_rule.background = paint.Brush { Solid: gl.rgb(0xBCBCBCu32) }
            rows[n] = widget.box(0u64, head_rule, zero)
            n += 1usize
        }
        let key = grid.key + MENU_KEY + 16u64 + u64(i)
        let state = control.control_state(grid.theme, key, c.enabled, false)
        if state.hovered && c.enabled { grid.menu_cursor = i }
        let lit = grid.menu_cursor == i && c.enabled
        var ink = gl.rgb(0x000000u32)
        if !c.enabled { ink = gl.rgb(0xA0A0A0u32) }
        if lit && !grid.parent_drawn { ink = gl.rgb(0xFFFFFFu32) }
        let (label, label_error) = caption_node(a, grid, c.label, ink)
        if label_error != ok { ret (zero, label_error) }
        if i < 40usize {
            grid.menu_enabled[i] = c.enabled
            grid.menu_actions[i] = c.action
        }
        var parts_n = 0usize
        let (cells, cells_error) = mem.alloc[widget.Node](a, 5usize)
        if cells_error != ok { ret (zero, control.TooLarge) }
        // the picture column: the picture, a check, or nothing
        var slot = control.sized_style(27.0, row_h)
        if c.has_picture {
            let (pic, pic_error) = control.image(a, 0u64, c.picture, 16.0, 16.0, .Contain, "")
            if pic_error != ok { ret (zero, pic_error) }
            let (pic_box, pic_box_error) = mem.alloc[widget.Node](a, 1usize)
            if pic_box_error != ok { ret (zero, control.TooLarge) }
            pic_box[0usize] = pic
            // v3 marks a ticked picture entry with a pale blue rounded box behind its picture
            if c.checkable && c.checked {
                var frame_style = control.sized_style(24.0, row_h - 2.0)
                frame_style.background = paint.Brush { Solid: gl.rgb(0xCCE8FFu32) }
                frame_style.border = style.Border { width: 1.0, color: gl.rgb(0x99D1FFu32) }
                frame_style.radius = 3.0
                let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
                if framed_error != ok { ret (zero, control.TooLarge) }
                framed[0usize] = widget.aligned(0u64, .Center, .Center, frame_style, pic_box[0usize..1usize])
                cells[parts_n] = widget.aligned(0u64, .Center, .Center, slot, framed[0usize..1usize])
            } else {
                cells[parts_n] = widget.aligned(0u64, .Center, .Center, slot, pic_box[0usize..1usize])
            }
        } else if c.checked {
            let (tick, tick_error) = gl.mark(a, .Check, ink, ink, 9.0, 9.0)
            if tick_error != ok { ret (zero, tick_error) }
            let (tick_box, tick_box_error) = mem.alloc[widget.Node](a, 1usize)
            if tick_box_error != ok { ret (zero, control.TooLarge) }
            tick_box[0usize] = tick
            cells[parts_n] = widget.aligned(0u64, .Center, .Center, slot, tick_box[0usize..1usize])
        } else {
            cells[parts_n] = widget.box(0u64, slot, zero)
        }
        parts_n += 1usize
        var label_style = control.sized_style(width - 27.0 - 6.0, row_h)
        if c.supporting.len == 1usize && c.supporting[0usize] == 62u8 { label_style = control.sized_style(width - 27.0 - 24.0, row_h) }
        if c.shortcut.len != 0usize { label_style = control.sized_style(f32(widest_hint_label) * char_width + 34.0, row_h) }
        let (label_box, label_box_error) = mem.alloc[widget.Node](a, 1usize)
        if label_box_error != ok { ret (zero, control.TooLarge) }
        label_box[0usize] = label
        cells[parts_n] = widget.aligned(0u64, .Start, .Center, label_style, label_box[0usize..1usize])
        parts_n += 1usize
        if c.shortcut.len != 0usize {
            let (hint, hint_error) = flat_text(a, grid, c.shortcut, ink)
            if hint_error != ok { ret (zero, hint_error) }
            let (hint_box, hint_box_error) = mem.alloc[widget.Node](a, 1usize)
            if hint_box_error != ok { ret (zero, control.TooLarge) }
            hint_box[0usize] = hint
            cells[parts_n] = widget.aligned(0u64, .Start, .Center, control.sized_style(f32(widest_hint) * char_width + 6.0, row_h), hint_box[0usize..1usize])
            parts_n += 1usize
        }
        var row_style = control.sized_style(width - 2.0, row_h)
        if lit && !grid.parent_drawn { row_style.background = paint.Brush { Solid: gl.rgb(0x0078D7u32) } }
        // the popup an open submenu came from keeps its entry in a light blue
        if lit && grid.parent_drawn { row_style.background = paint.Brush { Solid: gl.rgb(0xBDDCF7u32) } }
        if c.supporting.len == 1usize && c.supporting[0usize] == 62u8 {
            // an entry with a submenu ends in a small right arrow
            let (arrow, arrow_error) = gl.mark(a, .Right, ink, ink, 5.0, 9.0)
            if arrow_error != ok { ret (zero, arrow_error) }
            let (arrow_cell, arrow_cell_error) = mem.alloc[widget.Node](a, 1usize)
            if arrow_cell_error != ok { ret (zero, control.TooLarge) }
            arrow_cell[0usize] = arrow
            cells[parts_n] = widget.aligned(0u64, .Center, .Center, control.sized_style(18.0, row_h), arrow_cell[0usize..1usize])
            parts_n += 1usize
        }
        let (row_inner, row_inner_error) = mem.alloc[widget.Node](a, 1usize)
        if row_inner_error != ok { ret (zero, control.TooLarge) }
        row_inner[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), cells[0usize..parts_n])
        picks[i] = FlatPick { grid: grid, action: c.action, enabled: c.enabled }
        rows[n] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&picks[i]), invoke: on_flat_tap }, gestures: 1u8 | 4u8, enabled: true, focusable: false }, row_style, row_inner[0usize..1usize])
        n += 1usize
        i += 1usize
    }
    var frame = style.defaults()
    frame.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    frame.border = style.Border { width: 1.0, color: gl.rgb(0xA0A0A0u32) }
    frame.width = style.Length { Px: width }
    frame.shadow = style.Shadow { offset: geometry.Point { x: 2.0, y: 2.0 }, color: paint.rgba(0.0, 0.0, 0.0, 0.25) }
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, frame, rows[0usize..n])
    let (column_box, column_box_error) = mem.alloc[widget.Node](a, 1usize)
    if column_box_error != ok { ret (zero, control.TooLarge) }
    let (scoped_box, scoped_box_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_box_error != ok { ret (zero, control.TooLarge) }
    scoped_box[0usize] = widget.padded(0u64, 0.0, 3.0, 0.0, 3.0, frame, one(a, column))
    var no_submit: widget.Submit = zero
    // Down, Up, Enter, and a plain letter for each mnemonic
    let (keys, keys_error) = mem.alloc[widget.Shortcut](a, commands.len + 3usize)
    if keys_error != ok { ret (zero, control.TooLarge) }
    let (steps, steps_error) = mem.alloc[FlatStep](a, 2usize)
    if steps_error != ok { ret (zero, control.TooLarge) }
    steps[0usize] = FlatStep { grid: grid, down: true }
    steps[1usize] = FlatStep { grid: grid, down: false }
    var plain_keys: input.Modifiers = zero
    var key_n = 0usize
    keys[key_n] = widget.Shortcut { key: 40u32, modifiers: plain_keys, action: widget.Submit { ctx: mem.cast[*void](&steps[0usize]), invoke: on_flat_move } }
    key_n += 1usize
    keys[key_n] = widget.Shortcut { key: 38u32, modifiers: plain_keys, action: widget.Submit { ctx: mem.cast[*void](&steps[1usize]), invoke: on_flat_move } }
    key_n += 1usize
    keys[key_n] = widget.Shortcut { key: 13u32, modifiers: plain_keys, action: widget.Submit { ctx: mem.cast[*void](grid), invoke: on_flat_enter } }
    key_n += 1usize
    var mi = 0usize
    while mi < commands.len {
        let mnemonic = upper_ascii(mnemonic_of(commands[mi].label))
        if mnemonic != 0u8 && commands[mi].enabled {
            keys[key_n] = widget.Shortcut { key: u32(mnemonic), modifiers: plain_keys, action: widget.Submit { ctx: mem.cast[*void](&picks[mi]), invoke: on_flat_key } }
            key_n += 1usize
        }
        mi += 1usize
    }
    column_box[0usize] = widget.scope(grid.key + MENU_KEY + 2u64, widget.Scope { traps_focus: false, shortcuts: keys[0usize..key_n], default_action: no_submit, cancel_action: widget.Submit { ctx: mem.cast[*void](grid), invoke: on_menu_dismiss }, keys: zero }, style.defaults(), scoped_box[0usize..1usize])
    // keep it on the surface
    var left = x
    var top = y
    let size = widget.surface_size(grid.theme.runtime)
    if left + width > size.width { left = size.width - width }
    var tall: f32 = 6.0
    tall += f32(commands.len) * row_h
    var seps = 0usize
    var q = 1usize
    while q < commands.len {
        if commands[q].separated { seps += 1usize }
        q += 1usize
    }
    tall += f32(seps) * 10.0
    if top + tall > size.height { top = size.height - tall }
    if left < 0.0 { left = 0.0 }
    if top < 0.0 { top = 0.0 }
    if grid.menu_kind != MENU_ALIGN {
        // where the popup stands, for a submenu that opens beside it
        grid.flat_left = left
        grid.flat_top = top
        grid.flat_width = width
    }
    var overlay_key = grid.key + MENU_KEY + 1u64
    if grid.menu_kind == MENU_ALIGN { overlay_key = grid.key + MENU_KEY + 6u64 }
    ret (widget.overlay(overlay_key, widget.Overlay { anchor: 0u64, placement: .At, offset: geometry.Point { x: left, y: top }, modal: true, dismiss: widget.Submit { ctx: mem.cast[*void](grid), invoke: on_menu_dismiss } }, style.defaults(), column_box[0usize..1usize]), ok)
}

// ---- the quick column list under the row indicator's header (v3's column quick customization) ----

type QuickPick = struct { grid: *Grid, spec: usize, all: bool }

fn on_quick_tap(ctx: *void, g: widget.Gesture) -> err {
    let pick = mem.cast[*QuickPick](ctx)
    let grid = pick.grid
    switch g {
    case .Tap as at:
        if pick.all {
            var o = 0usize
            while o < grid.all.len {
                grid.hidden[o] = false
                o += 1usize
            }
        } else if pick.spec == 1000000usize {
            // (Sorted): the list in alphabetical order instead of the grid's
            grid.quick_sorted = !grid.quick_sorted
        } else if pick.spec < grid.all.len {
            // the last shown column stays
            if !grid.hidden[pick.spec] && grid.specs.len < 3usize { ret ok }
            grid.hidden[pick.spec] = !grid.hidden[pick.spec]
        }
        relayout(grid)
        ret ok
    default:
        ret ok
    }
}

// Whether `x` sorts before `y` (case-insensitive, by bytes).
fn str_less(x: str, y: str) -> bool {
    var i = 0usize
    while i < x.len && i < y.len {
        let cx = lower_ascii(x[i])
        let cy = lower_ascii(y[i])
        if cx != cy { ret cx < cy }
        i += 1usize
    }
    ret x.len < y.len
}

fn quick_check(a: *mem.Arena, grid: *Grid, on: bool, partial: bool) -> (widget.Node, err) {
    var box = control.sized_style(15.0, 15.0)
    box.radius = 3.0
    if on || partial {
        box.background = paint.Brush { Solid: gl.rgb(0x005FB8u32) }
    } else {
        box.background = paint.Brush { Solid: gl.rgb(0xF3F3F3u32) }
        box.border = style.Border { width: 1.0, color: gl.rgb(0x8A8A8Au32) }
    }
    var inner: widget.Node = zero
    if on {
        let (tick, tick_error) = gl.mark(a, .Check, gl.rgb(0xFFFFFFu32), gl.rgb(0xFFFFFFu32), 9.0, 9.0)
        if tick_error != ok { ret (zero, tick_error) }
        inner = tick
    } else if partial {
        let (dash, dash_error) = gl.mark(a, .Minus, gl.rgb(0xFFFFFFu32), gl.rgb(0xFFFFFFu32), 9.0, 9.0)
        if dash_error != ok { ret (zero, dash_error) }
        inner = dash
    } else {
        inner = widget.box(0u64, style.defaults(), zero)
    }
    let (inner_nodes, inner_nodes_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_nodes_error != ok { ret (zero, control.TooLarge) }
    inner_nodes[0usize] = inner
    ret (widget.aligned(0u64, .Center, .Center, box, inner_nodes[0usize..1usize]), ok)
}

// One row of the quick list: a check box and the name, lit blue under the pointer.
fn quick_row(a: *mem.Arena, grid: *Grid, key: widget.Key, label_text: str, on: bool, partial: bool, pick: *QuickPick, width: f32) -> (widget.Node, err) {
    let st = control.control_state(grid.theme, key, true, false)
    var ink = gl.rgb(0x000000u32)
    if st.hovered { ink = gl.rgb(0xFFFFFFu32) }
    let (check, check_error) = quick_check(a, grid, on, partial)
    if check_error != ok { ret (zero, check_error) }
    let (label, label_error) = flat_text(a, grid, label_text, ink)
    if label_error != ok { ret (zero, label_error) }
    let (cells, cells_error) = mem.alloc[widget.Node](a, 2usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    cells[0usize] = widget.padded(0u64, 3.0, 0.0, 6.0, 0.0, style.defaults(), one(a, check))
    cells[1usize] = label
    var row_style = control.sized_style(width - 2.0, 17.0)
    if st.hovered { row_style.background = paint.Brush { Solid: gl.rgb(0x0078D7u32) } }
    let (row_inner, row_inner_error) = mem.alloc[widget.Node](a, 1usize)
    if row_inner_error != ok { ret (zero, control.TooLarge) }
    row_inner[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), cells[0usize..2usize])
    ret (widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](pick), invoke: on_quick_tap }, gestures: 1u8 | 4u8, enabled: true, focusable: false }, row_style, row_inner[0usize..1usize]), ok)
}

fn quick_panel(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (rows, rows_error) = mem.alloc[widget.Node](a, grid.all.len + 4usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    let (picks, picks_error) = mem.alloc[QuickPick](a, grid.all.len + 3usize)
    if picks_error != ok { ret (zero, control.TooLarge) }
    var shown = 0usize
    var listed = 0usize
    var o = 0usize
    while o < grid.all.len {
        if grid.all[o].kind != CellKind.Indicator && grid.all[o].title.len != 0usize {
            listed += 1usize
            if !grid.hidden[o] { shown += 1usize }
        }
        o += 1usize
    }
    let width: f32 = 92.0
    var n = 0usize
    var item = 0usize
    // (All), then (Sorted), a rule, the columns
    picks[item] = QuickPick { grid: grid, spec: 0usize, all: true }
    let (all_row, all_error) = quick_row(a, grid, grid.key + MENU_KEY + 48u64, "(All)", shown == listed, shown != listed && shown != 0usize, &picks[item], width)
    if all_error != ok { ret (zero, all_error) }
    rows[n] = all_row
    n += 1usize
    item += 1usize
    picks[item] = QuickPick { grid: grid, spec: 1000000usize, all: false }
    let (sorted_row, sorted_error) = quick_row(a, grid, grid.key + MENU_KEY + 49u64, "(Sorted)", grid.quick_sorted, false, &picks[item], width)
    if sorted_error != ok { ret (zero, sorted_error) }
    rows[n] = sorted_row
    n += 1usize
    item += 1usize
    var rule = control.sized_style(width - 10.0, 1.0)
    rule.background = paint.Brush { Solid: gl.rgb(0x9F9F9Fu32) }
    rule.margin = style.EdgeLengths { left: style.Length { Px: 5.0 }, top: style.Length { Px: 3.0 }, right: style.Length { Px: 5.0 }, bottom: style.Length { Px: 3.0 } }
    rows[n] = widget.box(0u64, rule, zero)
    n += 1usize
    // the list's order: the grid's, or by title when (Sorted) is ticked
    let (listing, listing_error) = mem.alloc[usize](a, grid.order.len + 1usize)
    if listing_error != ok { ret (zero, control.TooLarge) }
    var li = 0usize
    while li < grid.order.len {
        listing[li] = grid.order[li]
        li += 1usize
    }
    if grid.quick_sorted {
        var si = 1usize
        while si < grid.order.len {
            let moving = listing[si]
            var sj = si
            while sj > 0usize && str_less(grid.all[moving].title, grid.all[listing[sj - 1usize]].title) {
                listing[sj] = listing[sj - 1usize]
                sj -= 1usize
            }
            listing[sj] = moving
            si += 1usize
        }
    }
    var order_at = 0usize
    while order_at < grid.order.len {
        o = listing[order_at]
        order_at += 1usize
        if grid.all[o].kind != CellKind.Indicator && grid.all[o].title.len != 0usize {
            picks[item] = QuickPick { grid: grid, spec: o, all: false }
            let (col_row, col_error) = quick_row(a, grid, grid.key + MENU_KEY + 50u64 + u64(o), grid.all[o].title, !grid.hidden[o], false, &picks[item], width)
            if col_error != ok { ret (zero, col_error) }
            rows[n] = col_row
            n += 1usize
            item += 1usize
        }
    }
    // a list taller than the window wraps into two columns, as v3's does (the second starts where the
    // first would run off)
    var total_width = width
    var frame = style.defaults()
    frame.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    frame.border = style.Border { width: 1.0, color: gl.rgb(0x000000u32) }
    let surface = widget.surface_size(grid.theme.runtime)
    var column: widget.Node = zero
    if f32(n) * 17.0 + 8.0 > surface.height - 20.0 && n > 6usize || n > 14usize {
        let half = (n + 1usize) / 2usize
        var left_style = style.defaults()
        left_style.width = style.Length { Px: width }
        var right_style = style.defaults()
        right_style.width = style.Length { Px: width }
        let (halves, halves_error) = mem.alloc[widget.Node](a, 2usize)
        if halves_error != ok { ret (zero, control.TooLarge) }
        halves[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, left_style, rows[0usize..half])
        halves[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, right_style, rows[half..n])
        total_width = width * 2.0
        frame.width = style.Length { Px: total_width }
        column = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, frame, halves[0usize..2usize])
        n = half
    } else {
        frame.width = style.Length { Px: width }
        column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, frame, rows[0usize..n])
    }
    var no_submit: widget.Submit = zero
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, control.TooLarge) }
    scoped[0usize] = column
    let scope = widget.scope(grid.key + MENU_KEY + 3u64, widget.Scope { traps_focus: false, shortcuts: zero, default_action: no_submit, cancel_action: widget.Submit { ctx: mem.cast[*void](grid), invoke: on_menu_dismiss }, keys: zero }, style.defaults(), scoped[0usize..1usize])
    var left = grid.quick_x
    var top = grid.quick_y
    let size = widget.surface_size(grid.theme.runtime)
    let tall = f32(n) * 17.0 + 8.0
    if top + tall > size.height { top = size.height - tall }
    if left + total_width > size.width { left = size.width - total_width }
    if top < 0.0 { top = 0.0 }
    let (holder, holder_error) = mem.alloc[widget.Node](a, 1usize)
    if holder_error != ok { ret (zero, control.TooLarge) }
    holder[0usize] = scope
    ret (widget.overlay(grid.key + MENU_KEY + 1u64, widget.Overlay { anchor: 0u64, placement: .At, offset: geometry.Point { x: left, y: top }, modal: true, dismiss: widget.Submit { ctx: mem.cast[*void](grid), invoke: on_menu_dismiss } }, style.defaults(), holder[0usize..1usize]), ok)
}

// The grid with its context menu target and, open, the menu or the chooser.
fn with_menus(a: *mem.Arena, grid: *Grid, inner: widget.Node) -> (widget.Node, err) {
    if mem.address_of(grid.theme) == 0usize || mem.address_of(grid.theme.runtime) == 0usize { ret (inner, ok) }
    let theme = grid.theme
    let (shows, shows_error) = mem.alloc[widget.Submit](a, 2usize)
    if shows_error != ok { ret (zero, control.TooLarge) }
    shows[0usize] = widget.Submit { ctx: mem.cast[*void](grid), invoke: on_menu_show }
    shows[1usize] = widget.Submit { ctx: mem.cast[*void](grid), invoke: on_menu_dismiss }
    let (aimed, aimed_error) = overlay.context_target(a, grid.key + MENU_KEY, theme, .Grid, "Data grid", grid.key + MENU_KEY + 1u64, grid.menu_open, &shows[0usize], inner)
    if aimed_error != ok { ret (zero, aimed_error) }
    // a header the pointer rests on shows its hint
    var hint_node: widget.Node = zero
    var has_hint = false
    if !grid.menu_open && grid.hints.len != 0usize {
        var shown = 0usize
        while shown < grid.specs.len && !has_hint {
            let spec = grid.origin[shown]
            if spec < grid.hints.len && grid.hints[spec].len != 0usize {
                let header_key = grid.key + 1u64 + 2u64 * u64(shown)
                var hint_ready = false
                if overlay.tooltip_wanted(theme, header_key) {
                    // v3's hint appears about a second after the pointer rests (measured 1045 ms
                    // against the widget's 500 ms), so the grid waits a further half second
                    let now = widget.frame_time(theme.runtime).nanos
                    if grid.hint_key != header_key {
                        grid.hint_key = header_key
                        grid.hint_since = now
                    }
                    if now - grid.hint_since >= 400000000i64 {
                        hint_ready = true
                    } else {
                        widget.request_animation_frame(theme.runtime)
                    }
                } else if grid.hint_key == header_key {
                    grid.hint_key = 0u64
                }
                if hint_ready {
                    let (head_rect, has_head) = control.keyed_bounds(theme.runtime, header_key)
                    if has_head {
                        var words = control.text_options()
                        words.wrap = .Word
                        words.size = grid.look.text_size
                        words.max_lines = 4u32
                        let full_len = grid.specs[shown].title.len + 3usize + grid.hints[spec].len
                        let (hb, hb_error) = str.builder(a, full_len + 8usize)
                        if hb_error != ok { ret (zero, hb_error) }
                        var hsb = hb
                        if str.push(&hsb, grid.specs[shown].title) != ok || str.push(&hsb, " - ") != ok || str.push(&hsb, grid.hints[spec]) != ok { ret (zero, control.TooLarge) }
                        let (words_node, words_error) = control.colored_text(a, 0u64, str.done(&hsb), theme, words, gl.rgb(0x000000u32))
                        if words_error != ok { ret (zero, words_error) }
                        var box = style.defaults()
                        box.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
                        box.border = style.Border { width: 1.0, color: gl.rgb(0x767676u32) }
                        // one line while it fits 340, else wrapped at 340
                        var hint_w = f32(full_len) * 6.4 + 14.0
                        if hint_w > 340.0 { hint_w = 340.0 }
                        box.width = style.Length { Px: hint_w }
                        let (holder, holder_error) = mem.alloc[widget.Node](a, 1usize)
                        if holder_error != ok { ret (zero, control.TooLarge) }
                        holder[0usize] = words_node
                        let padded_hint = widget.padded(0u64, 5.0, 3.0, 5.0, 3.0, box, holder[0usize..1usize])
                        let (overlay_nodes, overlay_error) = mem.alloc[widget.Node](a, 1usize)
                        if overlay_error != ok { ret (zero, control.TooLarge) }
                        overlay_nodes[0usize] = padded_hint
                        let pointer = widget.pointer_position(theme.runtime)
                        hint_node = widget.overlay(grid.key + MENU_KEY + 40u64, widget.Overlay { anchor: 0u64, placement: .At, offset: geometry.Point { x: pointer.x + 12.0, y: head_rect.y + head_rect.height + 6.0 }, modal: false, dismiss: zero }, style.defaults(), overlay_nodes[0usize..1usize])
                        has_hint = true
                    }
                }
            }
            shown += 1usize
        }
    }
    if !grid.menu_open && !grid.chooser_open && !has_hint && !grid.sort_dialog_open && !grid.rules_dialog_open && !grid.crit_open && !grid.wiz_open && grid.filter_pop == 0usize { ret (aimed, ok) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 12usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    var n = 0usize
    parts[n] = aimed
    n += 1usize
    if has_hint {
        parts[n] = hint_node
        n += 1usize
    }
    if grid.menu_open && grid.menu_kind == MENU_QUICK {
        let (quick, quick_error) = quick_panel(a, grid)
        if quick_error != ok { ret (zero, quick_error) }
        parts[n] = quick
        n += 1usize
    } else if grid.menu_open {
        let (commands, commands_error) = menu_commands(a, grid)
        if commands_error != ok { ret (zero, commands_error) }
        let (at, pointed) = widget.context_point(theme.runtime)
        var row_h: f32 = 20.0
        if grid.menu_kind == MENU_HEADER || grid.menu_kind == MENU_ALIGN { row_h = 22.0 }
        if grid.menu_kind == MENU_APP { row_h = 21.0 }
        var menu_x = at.x
        var menu_y = at.y
        if grid.menu_kind == MENU_APP {
            menu_x = grid.app_menu_x
            menu_y = grid.app_menu_y
        }
        if grid.menu_kind == MENU_ALIGN {
            // beside the popup it came from, at the height of its Alignment entry
            menu_x = grid.flat_left + grid.flat_width - 2.0
            menu_y = grid.flat_top + 3.0 + 9.0 * 22.0 + 40.0
        }
        let (menu, menu_error) = flat_menu(a, grid, commands, menu_x, menu_y, row_h)
        if menu_error != ok { ret (zero, menu_error) }
        let _ = pointed
        if grid.menu_kind == MENU_ALIGN {
            // the popup the submenu came from stays under it
            let kept = grid.menu_kind
            grid.menu_kind = MENU_HEADER
            let (parent_commands, parent_error) = menu_commands(a, grid)
            if parent_error != ok { ret (zero, parent_error) }
            grid.parent_drawn = true
            let (parent, parent_menu_error) = flat_menu(a, grid, parent_commands, at.x, at.y, 22.0)
            grid.parent_drawn = false
            if parent_menu_error != ok { ret (zero, parent_menu_error) }
            grid.menu_kind = kept
            parts[n] = parent
            n += 1usize
        }
        parts[n] = menu
        n += 1usize
    }
    if grid.chooser_open {
        let (panel, panel_error) = chooser_panel(a, grid)
        if panel_error != ok { ret (zero, panel_error) }
        if !grid.chooser_placed {
            let (grid_rect, has_grid) = control.keyed_bounds(theme.runtime, grid.key)
            grid.chooser_x = 400.0
            grid.chooser_y = 60.0
            if has_grid {
                grid.chooser_x = grid_rect.x + grid_rect.width - 190.0
                grid.chooser_y = grid_rect.y + 30.0
            }
            grid.chooser_placed = true
        }
        let x = grid.chooser_x
        let y = grid.chooser_y
        let (floating, floating_error) = mem.alloc[widget.Node](a, 1usize)
        if floating_error != ok { ret (zero, control.TooLarge) }
        floating[0usize] = panel
        parts[n] = widget.overlay(grid.key + CHOOSER_KEY, widget.Overlay { anchor: 0u64, placement: .At, offset: geometry.Point { x: x, y: y }, modal: false, dismiss: zero }, style.defaults(), floating[0usize..1usize])
        n += 1usize
    }
    if grid.filter_pop != 0usize && grid.filter_visible && grid.look.on {
        let pop_spec = grid.filter_pop - 1usize
        let (op_rows, op_rows_error) = mem.alloc[widget.Node](a, 12usize)
        if op_rows_error != ok { ret (zero, control.TooLarge) }
        let (op_picks, op_picks_error) = mem.alloc[FilterOpPick](a, 12usize)
        if op_picks_error != ok { ret (zero, control.TooLarge) }
        let (op_submits, op_submits_error) = mem.alloc[widget.Submit](a, 12usize)
        if op_submits_error != ok { ret (zero, control.TooLarge) }
        var oi = 0usize
        while oi < 12usize {
            op_picks[oi] = FilterOpPick { grid: grid, spec: pop_spec, op: u8(oi) }
            op_submits[oi] = widget.Submit { ctx: mem.cast[*void](&op_picks[oi]), invoke: on_filter_op }
            var sign_node: widget.Node = zero
            if grid.has_filter_op_icons {
                let (pic, pic_error) = control.image(a, 0u64, grid.filter_op_icons[oi], 22.0, 18.0, .Contain, "")
                if pic_error != ok { ret (zero, pic_error) }
                sign_node = pic
            } else {
                let (sign_text_node, sign_text_error) = flat_text(a, grid, filter_op_sign(u8(oi)), gl.rgb(0x2E5EA8u32))
                if sign_text_error != ok { ret (zero, sign_text_error) }
                sign_node = sign_text_node
            }
            let (words_node, words_node_error) = flat_text(a, grid, filter_op_words(u8(oi)), gl.rgb(0x000000u32))
            if words_node_error != ok { ret (zero, words_node_error) }
            let (op_parts, op_parts_error) = mem.alloc[widget.Node](a, 2usize)
            if op_parts_error != ok { ret (zero, control.TooLarge) }
            // measured on v3 (FR2): 280 px wide, 33 px rows at 1.5 px a unit
            op_parts[0usize] = widget.padded(0u64, 6.0, 1.0, 0.0, 0.0, control.sized_style(36.0, 22.0), one(a, sign_node))
            op_parts[1usize] = widget.padded(0u64, 0.0, 2.0, 0.0, 0.0, style.defaults(), one(a, words_node))
            var op_style = control.sized_style(187.0, 22.0)
            if u8(oi) == grid.filter_ops[pop_spec] { op_style.background = paint.Brush { Solid: gl.rgb(0x99D1FFu32) } }
            let (op_line, op_line_error) = mem.alloc[widget.Node](a, 1usize)
            if op_line_error != ok { ret (zero, control.TooLarge) }
            op_line[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), op_parts[0usize..2usize])
            op_rows[oi] = widget.region(grid.key + MENU_KEY + 700100u64 + u64(oi), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&op_submits[oi]), invoke: on_filter_op_tap }, gestures: 1u8, enabled: true, focusable: false }, op_style, op_line[0usize..1usize])
            oi += 1usize
        }
        var op_frame = style.defaults()
        op_frame.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
        op_frame.border = style.Border { width: 1.0, color: gl.rgb(0x8E9092u32) }
        let op_column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, op_frame, op_rows[0usize..12usize])
        let (op_held, op_held_error) = mem.alloc[widget.Node](a, 1usize)
        if op_held_error != ok { ret (zero, control.TooLarge) }
        op_held[0usize] = op_column
        var pop_x: f32 = 100.0
        var pop_y: f32 = 300.0
        if mem.address_of(theme.runtime) != 0usize {
            let (sign_rect, has_sign) = control.keyed_bounds(theme.runtime, grid.key + FILTER_KEY + 1100u64 + u64(pop_spec))
            if has_sign {
                pop_x = sign_rect.x
                pop_y = sign_rect.y + sign_rect.height
            }
        }
        parts[n] = widget.overlay(grid.key + MENU_KEY + 700099u64, widget.Overlay { anchor: 0u64, placement: .At, offset: geometry.Point { x: pop_x, y: pop_y }, modal: true, dismiss: widget.Submit { ctx: mem.cast[*void](grid), invoke: on_filter_pop_dismiss } }, style.defaults(), op_held[0usize..1usize])
        n += 1usize
    }
    // the secondary windows from the back to the front: the one touched last stands on top
    var window_order: [4]u8 = [4]u8{ 0u8, 1u8, 2u8, 3u8 }
    var w_a = 0usize
    while w_a < 4usize {
        var w_b = w_a + 1usize
        while w_b < 4usize {
            if grid.win_rank[usize(window_order[w_b])] < grid.win_rank[usize(window_order[w_a])] {
                let swap_w = window_order[w_a]
                window_order[w_a] = window_order[w_b]
                window_order[w_b] = swap_w
            }
            w_b += 1usize
        }
        w_a += 1usize
    }
    var window_pass = 0usize
    while window_pass < 4usize {
    let which = window_order[window_pass]
    window_pass += 1usize
    if which == 3u8 && grid.crit_open {
        let (crit_node, crit_error) = criteria_panel(a, grid)
        if crit_error != ok { ret (zero, crit_error) }
        let crit_size = widget.surface_size(theme.runtime)
        window_place(grid, 3u8, 540.0, 140.0, crit_size.width)
        let (crit_held, crit_held_error) = mem.alloc[widget.Node](a, 1usize)
        if crit_held_error != ok { ret (zero, control.TooLarge) }
        crit_held[0usize] = crit_node
        parts[n] = widget.overlay(grid.key + MENU_KEY + 699902u64, widget.Overlay { anchor: 0u64, placement: .At, offset: geometry.Point { x: grid.win_x[3usize], y: grid.win_y[3usize] }, modal: false, dismiss: zero }, style.defaults(), crit_held[0usize..1usize])
        n += 1usize
    }
    if which == 1u8 && grid.rules_dialog_open {
        let (rules_panel, rules_panel_error) = rules_dialog_panel(a, grid)
        if rules_panel_error != ok { ret (zero, rules_panel_error) }
        let rules_size = widget.surface_size(theme.runtime)
        window_place(grid, 1u8, 640.0, 120.0, rules_size.width)
        let (rules_held, rules_held_error) = mem.alloc[widget.Node](a, 1usize)
        if rules_held_error != ok { ret (zero, control.TooLarge) }
        rules_held[0usize] = rules_panel
        parts[n] = widget.overlay(grid.key + MENU_KEY + 699901u64, widget.Overlay { anchor: 0u64, placement: .At, offset: geometry.Point { x: grid.win_x[1usize], y: grid.win_y[1usize] }, modal: false, dismiss: zero }, style.defaults(), rules_held[0usize..1usize])
        n += 1usize
    }
    if which == 0u8 && grid.sort_dialog_open {
        let (dialog, dialog_error) = sort_dialog_panel(a, grid)
        if dialog_error != ok { ret (zero, dialog_error) }
        let size = widget.surface_size(theme.runtime)
        window_place(grid, 0u8, 528.0, 190.0, size.width)
        let (shown, shown_error) = mem.alloc[widget.Node](a, 1usize)
        if shown_error != ok { ret (zero, control.TooLarge) }
        shown[0usize] = dialog
        parts[n] = widget.overlay(grid.key + MENU_KEY + 699900u64, widget.Overlay { anchor: 0u64, placement: .At, offset: geometry.Point { x: grid.win_x[0usize], y: grid.win_y[0usize] }, modal: false, dismiss: zero }, style.defaults(), shown[0usize..1usize])
        n += 1usize
    }
    if which == 2u8 && grid.wiz_open {
        let (wiz_node, wiz_error) = wiz_panel(a, grid)
        if wiz_error != ok { ret (zero, wiz_error) }
        let wiz_size = widget.surface_size(theme.runtime)
        window_place(grid, 2u8, 520.0, 90.0, wiz_size.width)
        let (wiz_held, wiz_held_error) = mem.alloc[widget.Node](a, 1usize)
        if wiz_held_error != ok { ret (zero, control.TooLarge) }
        wiz_held[0usize] = wiz_node
        parts[n] = widget.overlay(grid.key + MENU_KEY + 699904u64, widget.Overlay { anchor: 0u64, placement: .At, offset: geometry.Point { x: grid.win_x[2usize], y: grid.win_y[2usize] }, modal: false, dismiss: zero }, style.defaults(), wiz_held[0usize..1usize])
        n += 1usize
    }
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..n]), ok)
}

// ---- view options (v3's View menu: grid lines, header, indicator, columns auto width) ---------

fn set_grid_lines(grid: *Grid, lines: GridLines) { grid.lines = lines }

// Show Header: off, the grid has no header row (nor its sort, drag and resize).
fn show_header(grid: *Grid, on: bool) { grid.header_off = !on }

// Show Indicator: the row-indicator columns are shown or not.
fn show_indicator(grid: *Grid, on: bool) {
    var at = 0usize
    while at < grid.all.len {
        if grid.all[at].kind == CellKind.Indicator { grid.hidden[at] = !on }
        at += 1usize
    }
    relayout(grid)
}

// Columns Auto Width: the columns share `total` between them in proportion to their widths, so the
// grid never needs a horizontal scroll bar; off, they keep their own widths.
fn set_auto_width(grid: *Grid, on: bool, total: f32) {
    grid.auto_width = on
    grid.auto_total = total
    relayout(grid)
}

fn clear_selection(grid: *Grid) {
    grid.has_selection = false
    clear_marks(grid)
}

// ---- several selected rows (v3's MultiSelect) ---------------------------------------------

// Turns on selecting several rows: Ctrl+click toggles a row, Shift+click selects the range from the
// anchor, Ctrl+A all, Shift+Up/Down extend.
fn set_multi_select(grid: *Grid, on: bool) {
    grid.multi = on
    if !on { clear_marks(grid) }
}

fn is_marked(grid: *const Grid, row: usize) -> bool {
    if row / 8usize >= grid.marks.len { ret false }
    ret (grid.marks[row / 8usize] >> u8(row % 8usize)) & 1u8 != 0u8
}

fn set_mark(grid: *Grid, row: usize, on: bool) {
    if row / 8usize >= grid.marks.len { ret }
    let was = is_marked(grid, row)
    let bit = 1u8 << u8(row % 8usize)
    if on && !was {
        grid.marks[row / 8usize] = grid.marks[row / 8usize] | bit
        grid.marked += 1usize
    }
    if !on && was {
        grid.marks[row / 8usize] = grid.marks[row / 8usize] & (255u8 ^ bit)
        grid.marked -= 1usize
    }
}

fn clear_marks(grid: *Grid) {
    var at = 0usize
    while at < grid.marks.len {
        grid.marks[at] = 0u8
        at += 1usize
    }
    grid.marked = 0usize
}

// How many rows are selected (the current row counts when no other is).
fn selection_size(grid: *const Grid) -> usize {
    if grid.multi && grid.marked != 0usize { ret grid.marked }
    if grid.has_selection { ret 1usize }
    ret 0usize
}

// Marks the data rows between two visible positions, both included.
fn mark_range(grid: *Grid, from: usize, to: usize) {
    var lo = from
    var hi = to
    if lo > hi {
        lo = to
        hi = from
    }
    let visible = grp.visible_len(grid.g)
    while lo <= hi && lo < visible {
        if !grp.visible_is_group(grid.g, lo) { set_mark(grid, grp.visible_row(grid.g, lo), true) }
        lo += 1usize
    }
}

// Ctrl+A: every data row of the view.
fn select_all(grid: *Grid) {
    if !grid.multi { ret }
    let visible = grp.visible_len(grid.g)
    if visible == 0usize { ret }
    mark_range(grid, 0usize, visible - 1usize)
}

// Shift+Up / Shift+Down: the range from the anchor to the new current row.
fn extend_selection(grid: *Grid, kind: Nav) -> err {
    if !grid.has_anchor && grid.has_position {
        grid.anchor = grid.position
        grid.has_anchor = true
    }
    let kept = grid.anchor
    let moved = navigate(grid, kind)
    if moved != ok { ret moved }
    grid.anchor = kept
    if grid.has_anchor && grid.has_position {
        clear_marks(grid)
        mark_range(grid, grid.anchor, grid.position)
    }
    ret ok
}

// Puts a row of band titles above the header (an empty slice removes it).
fn set_bands(grid: *Grid, bands: []const Band) { grid.bands = bands }

// The band names of a grid whose band row is not shown (v3's collection): the Customization window
// still has its Bands tab.
fn set_band_names(grid: *Grid, names: []const str) { grid.band_names = names }

// The Bands tab without any band (v3's card pool: the tab is there, its list empty).
fn set_band_tabs(grid: *Grid, on: bool) { grid.band_tabs = on }

fn show_navigator(grid: *Grid, on: bool) { grid.navigator_visible = on }

// The visible position of the current data row, if there is one.
fn current_position(grid: *const Grid) -> (usize, bool) {
    if !grid.has_position || grid.position >= grp.visible_len(grid.g) { ret (0usize, false) }
    ret (grid.position, true)
}

// Data rows (not group rows) before position `at`, and the total.
fn data_counts(grid: *const Grid, at: usize) -> (usize, usize) {
    var before = 0usize
    var total = 0usize
    var i = 0usize
    let n = grp.visible_len(grid.g)
    while i < n {
        if !grp.visible_is_group(grid.g, i) {
            if i < at { before += 1usize }
            total += 1usize
        } else if grid.look.on && !grp.visible_is_footer(grid.g, i) {
            // v3 counts the cards of a collapsed group too: "n of N" runs over the records
            let group = grp.visible_group(grid.g, i)
            if !grp.is_expanded(grid.g, group) {
                let held = grp.group_count(grid.g, group)
                if i < at { before += held }
                total += held
            }
        }
        i += 1usize
    }
    ret (before, total)
}

// Makes the data row at visible position `at` current: selected, scrolled into view, reported.
fn go_to(grid: *Grid, at: usize) -> err {
    grid.has_position = true
    grid.position = at
    let row = grp.visible_row(grid.g, at)
    grid.has_selection = true
    grid.selected_row = row
    if grid.multi {
        clear_marks(grid)
        set_mark(grid, row, true)
        grid.anchor = at
        grid.has_anchor = true
    }
    var top = entry_top(grid, at) - 2.0 * grid.row_height
    if top < 0.0 { top = 0.0 }
    grid.offset = top
    ret grid.events.row_picked(grid.events.ctx, row)
}

// Moves the current data row; a move with nowhere to go does nothing (and reports nothing).
fn navigate(grid: *Grid, kind: Nav) -> err {
    let n = grp.visible_len(grid.g)
    if n == 0usize { ret ok }
    var i = 0usize
    if kind == Nav.First {
        while i < n {
            if !grp.visible_is_group(grid.g, i) { ret go_to(grid, i) }
            i += 1usize
        }
        ret ok
    }
    if kind == Nav.Last {
        i = n
        while i > 0usize {
            i -= 1usize
            if !grp.visible_is_group(grid.g, i) { ret go_to(grid, i) }
        }
        ret ok
    }
    let (at, has) = current_position(grid)
    if kind == Nav.NextPage || kind == Nav.PrevPage {
        // a page is the rows the body shows; the nearest data row at the aim
        var page = grid.page_rows
        if page == 0usize { page = 1usize }
        var aim = 0usize
        if kind == Nav.NextPage {
            if has { aim = at + page }
            if aim >= n { aim = n - 1usize }
            i = aim
            while i < n {
                if !grp.visible_is_group(grid.g, i) { ret go_to(grid, i) }
                i += 1usize
            }
            i = aim
            while i > 0usize {
                i -= 1usize
                if !grp.visible_is_group(grid.g, i) { ret go_to(grid, i) }
            }
            ret ok
        }
        if has && at > page { aim = at - page }
        i = aim
        while i < n {
            if !grp.visible_is_group(grid.g, i) { ret go_to(grid, i) }
            i += 1usize
        }
        ret ok
    }
    if kind == Nav.Next {
        i = 0usize
        if has { i = at + 1usize }
        while i < n {
            if !grp.visible_is_group(grid.g, i) { ret go_to(grid, i) }
            i += 1usize
        }
        ret ok
    }
    // Prev
    if !has { ret ok }
    i = at
    while i > 0usize {
        i -= 1usize
        if !grp.visible_is_group(grid.g, i) { ret go_to(grid, i) }
    }
    ret ok
}

// ---- editing ---------------------------------------------------------------------

// The text a cell is edited as: the value without decoration (no currency sign).
fn edit_text_of(grid: *const Grid, spec: usize, row: usize) -> str {
    let s = grid.specs[spec]
    if table.is_null(grid.t, s.column, row) { ret "" }
    let kind = table.column_kind(grid.t, s.column)
    if kind == table.Kind.Str || kind == table.Kind.Dict { ret table.get_str(grid.t, s.column, row) }
    ret ""
}

fn copy_edit(grid: *Grid, text: str) {
    var at = 0usize
    while at < text.len && at < EDIT_TEXT {
        grid.edit_text[at] = text[at]
        at += 1usize
    }
    grid.edit_len = at
}

// Starts editing a cell: the editor holds the cell's text. `NotEditable` for a column that is
// not, or a read-only grid.
fn begin_edit(grid: *Grid, row: usize, spec_index: usize) -> err {
    let (spec, shown) = display_of(grid, spec_index)
    if grid.read_only || !shown || !grid.specs[spec].editable { ret NotEditable }
    if !grid.events.can_edit(grid.events.ctx, row, spec_index) { ret Locked }
    let s = grid.specs[spec]
    var scratch = mem.arena_from(grid.edit_scratch[0usize..160usize])
    let a = &scratch
    var text = edit_text_of(grid, spec, row)
    let kind = table.column_kind(grid.t, s.column)
    if !table.is_null(grid.t, s.column, row) && kind != table.Kind.Str && kind != table.Kind.Dict {
        let (b, b_error) = str.builder(a, 40usize)
        if b_error != ok { ret b_error }
        var sb = b
        var value = 0.0f64
        if kind == table.Kind.I32 { value = f64(table.get_i32(grid.t, s.column, row)) }
        if kind == table.Kind.I64 { value = f64(table.get_i64(grid.t, s.column, row)) }
        if kind == table.Kind.F64 { value = table.get_f64(grid.t, s.column, row) }
        if kind == table.Kind.Bool {
            if table.get_bool(grid.t, s.column, row) { value = 1.0f64 }
            if str.push(&sb, "no") != ok { ret control.TooLarge }
            text = "no"
            if value != 0.0f64 { text = "yes" }
        } else if s.kind == CellKind.Int {
            if str.push_f64_fixed(&sb, value, 0u8) != ok { ret control.TooLarge }
            text = str.done(&sb)
        } else {
            if str.push_f64_fixed(&sb, value, s.decimals) != ok { ret control.TooLarge }
            text = str.done(&sb)
        }
    }
    if kind == table.Kind.Bool {
        // a boolean has no editor: the tap flips it
        let was = table.get_bool(grid.t, s.column, row) && !table.is_null(grid.t, s.column, row)
        table.set_bool(grid.t, s.column, row, !was)
        var old_text = "no"
        var new_text = "yes"
        if was {
            old_text = "yes"
            new_text = "no"
        }
        ret raise_edit(grid, row, spec, old_text, new_text)
    }
    grid.editing = true
    grid.edit_row = row
    grid.edit_spec = spec
    grid.edit_invalid = false
    grid.select_open = false
    copy_edit(grid, text)
    var o = 0usize
    while o < grid.edit_len {
        grid.edit_old[o] = grid.edit_text[o]
        o += 1usize
    }
    grid.edit_old_len = grid.edit_len
    grid.edit_focus_pending = true
    ret ok
}

// The events of a written cell: held back inside a batch.
fn raise_edit(grid: *Grid, row: usize, shown_spec: usize, old: str, new: str) -> err {
    if grid.batch_depth > 0usize {
        grid.batch_count += 1usize
        ret ok
    }
    let spec = grid.origin[shown_spec]
    try grid.events.value_changed(grid.events.ctx, row, spec, old, new)
    ret grid.events.cell_edited(grid.events.ctx, row, spec)
}

// Events of edits between these two are held back; `end_batch` raises one `batch_done`.
fn begin_batch(grid: *Grid) { grid.batch_depth += 1usize }

fn end_batch(grid: *Grid) -> err {
    if grid.batch_depth == 0usize { ret ok }
    grid.batch_depth -= 1usize
    if grid.batch_depth > 0usize { ret ok }
    let count = grid.batch_count
    grid.batch_count = 0usize
    if count == 0usize { ret ok }
    ret grid.events.batch_done(grid.events.ctx, count)
}

fn cancel_edit(grid: *Grid) {
    grid.editing = false
    grid.edit_invalid = false
}

fn truthy(text: str) -> (bool, bool) {
    if text.len == 0usize { ret (false, false) }
    let c = text[0usize]
    if c == 121u8 || c == 89u8 || c == 116u8 || c == 84u8 || c == 49u8 { ret (true, true) }
    if c == 110u8 || c == 78u8 || c == 102u8 || c == 70u8 || c == 48u8 { ret (false, true) }
    ret (false, false)
}

// Parses the editor's text by the column's kind and writes the cell. An empty text is null.
// A text that does not parse (or a dictionary that is full) keeps the editor open, invalid.
fn commit_edit(grid: *Grid) -> err {
    if !grid.editing { ret ok }
    let spec = grid.edit_spec
    let s = grid.specs[spec]
    let row = grid.edit_row
    let text = grid.edit_text[0usize..grid.edit_len]
    let kind = table.column_kind(grid.t, s.column)
    var done = false
    if text.len == 0usize {
        table.set_null(grid.t, s.column, row)
        done = true
    } else if kind == table.Kind.Str || kind == table.Kind.Dict {
        if table.set_str(grid.t, s.column, row, text) == ok { done = true }
    } else if kind == table.Kind.Bool {
        let (value, good) = truthy(text)
        if good {
            table.set_bool(grid.t, s.column, row, value)
            done = true
        }
    } else if kind == table.Kind.F64 {
        var digits = text
        if digits[0usize] == 36u8 && digits.len > 1usize { digits = digits[1usize..] }
        let (value, parse_error) = str.parse_f64(digits)
        if parse_error == ok {
            table.set_f64(grid.t, s.column, row, value)
            done = true
        }
    } else {
        let (value, parse_error) = str.parse_i64(text)
        if parse_error == ok {
            if kind == table.Kind.I32 {
                if value >= -2147483648i64 && value <= 2147483647i64 {
                    table.set_i32(grid.t, s.column, row, i32(value))
                    done = true
                }
            } else {
                table.set_i64(grid.t, s.column, row, value)
                done = true
            }
        }
    }
    if !done {
        grid.edit_invalid = true
        ret ok
    }
    grid.editing = false
    grid.edit_invalid = false
    grid.select_open = false
    if grid.immediate_edit {
        // v3 keeps the row current and its keyboard: Down moves on, Tab edits the next cell
        grid.rest_row = row
        grid.rest_spec = grid.origin[spec]
        grid.rest_pending = true
    }
    ret raise_edit(grid, row, spec, grid.edit_old[0usize..grid.edit_old_len], text)
}

// The select editor of a small dictionary: its toggle and its picks.
type SelectPick = struct { grid: *Grid, id: usize }

fn on_select_toggle(ctx: *void) -> err {
    let grid = mem.cast[*Grid](ctx)
    grid.select_open = !grid.select_open
    ret ok
}

fn on_select_tap(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        grid.select_open = !grid.select_open
        ret ok
    default:
        ret ok
    }
}

fn on_select_tap_pick(ctx: *void, g: widget.Gesture) -> err {
    let pick = mem.cast[*SelectPick](ctx)
    switch g {
    case .Tap as at:
        ret on_select_pick(ctx)
    default:
        ret ok
    }
}

fn on_select_pick(ctx: *void) -> err {
    let pick = mem.cast[*SelectPick](ctx)
    let grid = pick.grid
    let text = table.dict_str(grid.t, grid.specs[grid.edit_spec].column, u32(pick.id))
    copy_edit(grid, text)
    grid.select_open = false
    ret commit_edit(grid)
}

fn on_edit_change(ctx: *void, value: str) -> err {
    let grid = mem.cast[*Grid](ctx)
    grid.edit_len = value.len
    grid.edit_invalid = false
    ret ok
}

fn on_edit_commit(ctx: *void) -> err {
    let grid = mem.cast[*Grid](ctx)
    ret commit_edit(grid)
}

// Tab: commit, then edit the next (or, backward, the previous) editable cell of the row; past
// the last it goes to the first editable cell of the next data row (the previous row's last).
fn edit_move(grid: *Grid, backward: bool) -> err {
    if !grid.editing { ret ok }
    let row = grid.edit_row
    let from = grid.edit_spec
    try commit_edit(grid)
    if grid.editing { ret ok }
    var c = from
    if backward {
        while c > 0usize {
            c -= 1usize
            if grid.specs[c].editable { ret quiet_begin(grid, row, grid.origin[c]) }
        }
    } else {
        c += 1usize
        while c < grid.specs.len {
            if grid.specs[c].editable { ret quiet_begin(grid, row, grid.origin[c]) }
            c += 1usize
        }
    }
    // no editable cell left in this row: the neighbouring data row
    let n = grp.visible_len(grid.g)
    var at = 0usize
    while at < n && (grp.visible_is_group(grid.g, at) || grp.visible_row(grid.g, at) != row) { at += 1usize }
    if at >= n { ret ok }
    var next_at = at
    var found = false
    if backward {
        while next_at > 0usize && !found {
            next_at -= 1usize
            if !grp.visible_is_group(grid.g, next_at) { found = true }
        }
    } else {
        next_at += 1usize
        while next_at < n && !found {
            if !grp.visible_is_group(grid.g, next_at) { found = true } else { next_at += 1usize }
        }
    }
    if !found { ret ok }
    try go_to(grid, next_at)
    var column = 0usize
    var chosen = false
    if backward {
        column = grid.specs.len
        while column > 0usize && !chosen {
            column -= 1usize
            if grid.specs[column].editable { chosen = true }
        }
    } else {
        while column < grid.specs.len && !grid.specs[column].editable { column += 1usize }
        chosen = column < grid.specs.len
    }
    if !chosen { ret ok }
    ret quiet_begin(grid, grp.visible_row(grid.g, next_at), grid.origin[column])
}

// begin_edit that treats a refusal (locked, not editable) as nothing to do.
fn quiet_begin(grid: *Grid, row: usize, spec: usize) -> err {
    let began = begin_edit(grid, row, spec)
    if began == Locked || began == NotEditable { ret ok }
    ret began
}

fn on_edit_tab(ctx: *void) -> err {
    let grid = mem.cast[*Grid](ctx)
    ret edit_move(grid, false)
}

fn on_edit_back_tab(ctx: *void) -> err {
    let grid = mem.cast[*Grid](ctx)
    ret edit_move(grid, true)
}

// Tab with no editor open (after a commit in an immediate-edit grid): edit the cell after the one
// edited last, or the first editable cell of the next row.
// v3's Options > Grids > Enter Key Action (main.vcl.form.pas, VK_RETURN): 0 moves to the next column
// (the last column wraps to the first column of the next row), 1 moves down one row.
fn set_enter_action(grid: *Grid, action: u8) { grid.enter_action = action }

fn on_row_enter(ctx: *void) -> err {
    let grid = mem.cast[*Grid](ctx)
    if grid.editing || grid.read_only { ret ok }
    // Enter must never end the program: a row that is not in the tree to take the focus is no error here
    if grid.enter_action == 1u8 {
        let moved_row = navigate(grid, Nav.Next)
        ret ok
    }
    if grid.focus_column + 1usize < grid.specs.len {
        grid.focus_column += 1usize
        ret ok
    }
    grid.focus_column = 0usize
    let moved = navigate(grid, Nav.Next)
    ret ok
}

fn on_row_tab(ctx: *void) -> err {
    let grid = mem.cast[*Grid](ctx)
    if !grid.immediate_edit || grid.editing || !grid.has_selection { ret ok }
    let row = grid.selected_row
    let (shown, visible) = display_of(grid, grid.rest_spec)
    var d = 0usize
    if visible && row == grid.rest_row { d = shown + 1usize }
    while d < grid.specs.len {
        if grid.specs[d].editable {
            let began = begin_edit(grid, row, grid.origin[d])
            if began != ok && began != Locked && began != NotEditable { ret began }
            ret ok
        }
        d += 1usize
    }
    ret ok
}

fn on_edit_cancel(ctx: *void) -> err {
    let grid = mem.cast[*Grid](ctx)
    cancel_edit(grid)
    ret ok
}

// ---- layout ----------------------------------------------------------------------

fn column_width(grid: *const Grid, spec: usize) -> f32 { ret grid.widths[spec] }

fn resize_column(grid: *Grid, spec: usize, width: f32) {
    var w = width
    if w < 24.0 { w = 24.0 }
    grid.widths[spec] = w
    relayout(grid)
}

// The layout as text: the version, the widths, the sort indicator, the two optional rows and
// the filter texts. Written into `a`.
fn save_layout(a: *mem.Arena, grid: *const Grid) -> (str, err) {
    let (b, b_error) = str.builder(a, 512usize + grid.all.len * (FILTER_TEXT + 48usize))
    if b_error != ok { ret ("", b_error) }
    var sb = b
    if str.push(&sb, "datagrid 1\nwidths") != ok { ret ("", control.TooLarge) }
    var at = 0usize
    while at < grid.all.len {
        if str.push(&sb, " ") != ok || str.push_f64_fixed(&sb, f64(grid.widths[at]), 1u8) != ok { ret ("", control.TooLarge) }
        at += 1usize
    }
    if str.push(&sb, "\norder") != ok { ret ("", control.TooLarge) }
    at = 0usize
    while at < grid.order.len {
        if str.push(&sb, " ") != ok || str.push_usize(&sb, grid.order[at]) != ok { ret ("", control.TooLarge) }
        at += 1usize
    }
    if str.push(&sb, "\nhidden") != ok { ret ("", control.TooLarge) }
    at = 0usize
    while at < grid.hidden.len {
        if grid.hidden[at] {
            if str.push(&sb, " ") != ok || str.push_usize(&sb, at) != ok { ret ("", control.TooLarge) }
        }
        at += 1usize
    }
    if str.push(&sb, "\nsort ") != ok || str.push_usize(&sb, grid.sort_column) != ok { ret ("", control.TooLarge) }
    if grid.descending { if str.push(&sb, " desc") != ok { ret ("", control.TooLarge) } } else { if str.push(&sb, " asc") != ok { ret ("", control.TooLarge) } }
    // the Shift+click sorts after the primary one
    var extra_at = 0usize
    while extra_at < grid.extra_count {
        if str.push(&sb, "\nsortx ") != ok || str.push_usize(&sb, grid.extra_sort[extra_at]) != ok { ret ("", control.TooLarge) }
        if grid.extra_desc[extra_at] { if str.push(&sb, " desc") != ok { ret ("", control.TooLarge) } } else { if str.push(&sb, " asc") != ok { ret ("", control.TooLarge) } }
        extra_at += 1usize
    }
    if grid.filter_visible { if str.push(&sb, "\nfilterrow 1") != ok { ret ("", control.TooLarge) } } else { if str.push(&sb, "\nfilterrow 0") != ok { ret ("", control.TooLarge) } }
    if grid.navigator_visible { if str.push(&sb, "\nnavigator 1") != ok { ret ("", control.TooLarge) } } else { if str.push(&sb, "\nnavigator 0") != ok { ret ("", control.TooLarge) } }
    at = 0usize
    while at < grid.all.len {
        if grid.filter_lens[at] != 0usize {
            if str.push(&sb, "\nfilter ") != ok || str.push_usize(&sb, at) != ok || str.push(&sb, " ") != ok { ret ("", control.TooLarge) }
            if str.push(&sb, grid.filter_text[at * FILTER_TEXT..at * FILTER_TEXT + grid.filter_lens[at]]) != ok { ret ("", control.TooLarge) }
        }
        at += 1usize
    }
    if str.push(&sb, "\n") != ok { ret ("", control.TooLarge) }
    ret (str.done(&sb), ok)
}

// The next token of a line: text up to a space (or the end), and what follows it.
fn next_token(line: str) -> (str, str) {
    var at = 0usize
    while at < line.len && line[at] != 32u8 { at += 1usize }
    if at >= line.len { ret (line, line[line.len..]) }
    ret (line[0usize..at], line[at + 1usize..])
}

fn same_text(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var at = 0usize
    while at < x.len {
        if x[at] != y[at] { ret false }
        at += 1usize
    }
    ret true
}

// Applies saved layout text. Lines it does not know are skipped; a width for a column the grid
// does not have is ignored and a column the text does not mention keeps its width, so a layout
// from an older or newer column set loads. `BadLayout` is a text without the version line.
fn load_layout(grid: *Grid, text: str) -> err {
    grid.extra_count = 0usize
    var rest = text
    var first = true
    while rest.len > 0usize {
        var end = 0usize
        while end < rest.len && rest[end] != 10u8 { end += 1usize }
        let line = rest[0usize..end]
        if end < rest.len { rest = rest[end + 1usize..] } else { rest = rest[rest.len..] }
        let (head, tail) = next_token(line)
        if first {
            if !same_text(head, "datagrid") { ret BadLayout }
            first = false
        } else if same_text(head, "widths") {
            var items = tail
            var spec = 0usize
            while items.len > 0usize && spec < grid.all.len {
                let (word, after) = next_token(items)
                let (value, parse_error) = str.parse_f64(word)
                if parse_error == ok { resize_column(grid, spec, f32(value)) }
                items = after
                spec += 1usize
            }
        } else if same_text(head, "sort") {
            let (number, after) = next_token(tail)
            let (value, parse_error) = str.parse_u64(number)
            if parse_error == ok && usize(value) <= grid.all.len {
                grid.sort_column = usize(value)
                grid.descending = same_text(after, "desc")
            }
        } else if same_text(head, "sortx") {
            let (number, after) = next_token(tail)
            let (value, parse_error) = str.parse_u64(number)
            if parse_error == ok && usize(value) < grid.all.len && grid.extra_count < 4usize {
                grid.extra_sort[grid.extra_count] = usize(value)
                grid.extra_desc[grid.extra_count] = same_text(after, "desc")
                grid.extra_count += 1usize
            }
        } else if same_text(head, "order") {
            // the listed columns first, in that order; the grid's others after them, as they were
            var listed = 0usize
            var items = tail
            var chosen: [64]bool = zero
            var fresh: [64]usize = zero
            while items.len > 0usize && listed < 64usize {
                let (word, after) = next_token(items)
                let (value, parse_error) = str.parse_u64(word)
                if parse_error == ok && usize(value) < grid.all.len && usize(value) < 64usize && !chosen[usize(value)] {
                    chosen[usize(value)] = true
                    fresh[listed] = usize(value)
                    listed += 1usize
                }
                items = after
            }
            var k = 0usize
            while k < grid.order.len && listed < grid.order.len && listed < 64usize {
                if grid.order[k] < 64usize && !chosen[grid.order[k]] {
                    chosen[grid.order[k]] = true
                    fresh[listed] = grid.order[k]
                    listed += 1usize
                }
                k += 1usize
            }
            if listed == grid.order.len {
                k = 0usize
                while k < listed {
                    grid.order[k] = fresh[k]
                    k += 1usize
                }
            }
            relayout(grid)
        } else if same_text(head, "hidden") {
            var items = tail
            var k = 0usize
            while k < grid.hidden.len {
                grid.hidden[k] = false
                k += 1usize
            }
            while items.len > 0usize {
                let (word, after) = next_token(items)
                let (value, parse_error) = str.parse_u64(word)
                if parse_error == ok && usize(value) < grid.all.len { grid.hidden[usize(value)] = true }
                items = after
            }
            relayout(grid)
        } else if same_text(head, "filterrow") {
            grid.filter_visible = same_text(tail, "1")
        } else if same_text(head, "navigator") {
            grid.navigator_visible = same_text(tail, "1")
        } else if same_text(head, "filter") {
            let (number, value_text) = next_token(tail)
            let (spec, parse_error) = str.parse_u64(number)
            if parse_error == ok && usize(spec) < grid.all.len {
                var n = 0usize
                while n < value_text.len && n < FILTER_TEXT {
                    grid.filter_text[usize(spec) * FILTER_TEXT + n] = value_text[n]
                    n += 1usize
                }
                grid.filter_lens[usize(spec)] = n
            }
        }
    }
    if first { ret BadLayout }
    ret ok
}

// Previews: a disclosure on each data row opens, under it, the text of column `spec`.
fn show_preview(grid: *Grid, spec: usize) {
    grid.preview_on = spec < grid.all.len
    grid.preview_spec = spec
    grid.preview_count = 0usize
    relayout(grid)
}

fn hide_preview(grid: *Grid) {
    grid.preview_on = false
    grid.preview_count = 0usize
}

fn preview_is_open(grid: *const Grid, key: widget.Key) -> bool {
    var at = 0usize
    while at < grid.preview_count {
        if grid.preview_open[at] == key { ret true }
        at += 1usize
    }
    ret false
}

// The disclosure of a row: opens or closes its preview.
fn on_expand(ctx: *void, key: widget.Key) -> err {
    let grid = mem.cast[*Grid](ctx)
    var at = 0usize
    while at < grid.preview_count {
        if grid.preview_open[at] == key {
            grid.preview_open[at] = grid.preview_open[grid.preview_count - 1usize]
            grid.preview_count -= 1usize
            ret ok
        }
        at += 1usize
    }
    if grid.preview_count < 32usize {
        grid.preview_open[grid.preview_count] = key
        grid.preview_count += 1usize
    }
    ret ok
}

// The preview of visible entry `index`: the row's text in the preview column, over several lines.
fn on_detail(ctx: *void, a: *mem.Arena, index: usize, out: *widget.Node) -> err {
    let grid = mem.cast[*Grid](ctx)
    var text = ""
    var row_at = 0usize
    var has_row = false
    if index < grp.visible_len(grid.g) && !grp.visible_is_group(grid.g, index) {
        row_at = grp.visible_row(grid.g, index)
        has_row = true
        let (shown, shown_error) = cell_text_of(a, grid, grid.all[grid.preview_spec], row_at)
        if shown_error != ok { ret shown_error }
        text = shown
    }
    if grid.look.on {
        // v3: the rules text under the row from below its Legal column, in the row's ink, one line
        var line = control.text_options()
        line.wrap = .None
        line.size = grid.look.text_size
        var node: widget.Node = zero
        var coloured = false
        if grid.has_ink && has_row {
            let (ink, has_row_ink) = grid.ink_of(grid.ink_ctx, row_at)
            if has_row_ink {
                let (made, made_error) = control.colored_text(a, 0u64, text, grid.theme, line, ink)
                if made_error != ok { ret made_error }
                node = made
                coloured = true
            }
        }
        if !coloured {
            let (plain, plain_error) = control.text(a, 0u64, text, grid.theme, line)
            if plain_error != ok { ret plain_error }
            node = plain
        }
        var fill = style.defaults()
        fill.width = style.Length { Percent: 100.0 }
        fill.height = style.Length { Percent: 100.0 }
        *out = widget.padded(0u64, 35.0, 3.0, 8.0, 0.0, fill, one(a, node))
        ret ok
    }
    var options = control.text_options()
    options.wrap = .Word
    options.role = .BodySmall
    let (node, node_error) = control.text(a, 0u64, text, grid.theme, options)
    if node_error != ok { ret node_error }
    var holder = style.defaults()
    holder.width = style.Length { Percent: 100.0 }
    *out = widget.padded(0u64, 48.0, 6.0, 16.0, 8.0, holder, one(a, node))
    ret ok
}

// Shows or hides the filter row.
fn show_filter_row(grid: *Grid, on: bool) { grid.filter_visible = on }

// The text typed in a column's filter field.
// The operator of a filter row cell, in v3's order: 0 Equals (its default sign), 1 Does not equal,
// 2 Is less than, 3 Is less than or equal to, 4 Is greater than, 5 Is greater than or equal to,
// 6 Is like, 7 Is not like, 8 Contains, 9 Does not contain, 10 Begins with, 11 Ends with.
fn filter_operator(grid: *const Grid, spec: usize) -> u8 { ret grid.filter_ops[spec] }

fn filter_value(grid: *const Grid, spec: usize) -> str {
    if grid.filter_off { ret "" }
    ret grid.filter_text[spec * FILTER_TEXT..spec * FILTER_TEXT + grid.filter_lens[spec]]
}

const KEY_BASE: u64 = 4096u64

// The name of the card row being dragged, kept for the grid it is dragged over.
var drag_ghost_text: [96]u8
var drag_ghost_len: usize
var backdrop_texture: scene.TextureId
var toolbar_texture: scene.TextureId
var toolbar_set: bool
var backdrop_set: bool

fn row_key(grid: *const Grid, row: usize) -> widget.Key { ret grid.key + KEY_BASE + u64(row) }

fn group_key(grid: *const Grid, group: usize) -> widget.Key { ret grid.key + KEY_BASE + u64(table.capacity(grid.t)) + u64(group) }

fn footer_key(grid: *const Grid) -> widget.Key { ret grid.key + KEY_BASE + u64(table.capacity(grid.t)) + u64(grid.g.groups.len) }

fn band_key(grid: *const Grid) -> widget.Key { ret footer_key(grid) + 1u64 }

fn navigator_key(grid: *const Grid) -> widget.Key { ret footer_key(grid) + 2u64 }

// ---- formatting ------------------------------------------------------------------

// Pushes a number the way a column of this kind shows it.
fn push_number(sb: *str.Builder, kind: CellKind, decimals: u8, value: f64) -> err {
    if kind == CellKind.Currency {
        try str.push(sb, "$")
        ret str.push_f64_fixed(sb, value, decimals)
    }
    if kind == CellKind.Int {
        ret str.push_f64_fixed(sb, value, 0u8)
    }
    ret str.push_f64_fixed(sb, value, decimals)
}

fn cell_text(a: *mem.Arena, grid: *const Grid, spec: usize, row: usize) -> (str, err) {
    let (text, text_error) = cell_text_of(a, grid, grid.specs[spec], row)
    ret (text, text_error)
}

fn cell_text_of(a: *mem.Arena, grid: *const Grid, s: ColumnSpec, row: usize) -> (str, err) {
    if table.is_null(grid.t, s.column, row) { ret ("", ok) }
    let kind = table.column_kind(grid.t, s.column)
    if s.kind == CellKind.Text && (kind == table.Kind.Str || kind == table.Kind.Dict) { ret (table.get_str(grid.t, s.column, row), ok) }
    if s.kind == CellKind.Bool {
        if table.get_bool(grid.t, s.column, row) { ret ("Yes", ok) }
        ret ("No", ok)
    }
    let (b, b_error) = str.builder(a, 40usize)
    if b_error != ok { ret ("", b_error) }
    var sb = b
    var value = 0.0f64
    if kind == table.Kind.I32 { value = f64(table.get_i32(grid.t, s.column, row)) }
    if kind == table.Kind.I64 { value = f64(table.get_i64(grid.t, s.column, row)) }
    if kind == table.Kind.F64 { value = table.get_f64(grid.t, s.column, row) }
    if kind == table.Kind.Bool && table.get_bool(grid.t, s.column, row) { value = 1.0f64 }
    if push_number(&sb, s.kind, s.decimals, value) != ok { ret ("", control.TooLarge) }
    ret (str.done(&sb), ok)
}

fn summary_text(a: *mem.Arena, s: ColumnSpec, summary: grp.Summary) -> (str, err) {
    let (b, b_error) = str.builder(a, 40usize)
    if b_error != ok { ret ("", b_error) }
    var sb = b
    let value = grp.summary_value(summary, s.summary_kind)
    var kind = s.kind
    var decimals = s.decimals
    if s.summary_kind == grp.SummaryKind.Rows || s.summary_kind == grp.SummaryKind.Values { kind = CellKind.Int }
    // a mean of integers is not an integer: one decimal unless the column says more
    if s.summary_kind == grp.SummaryKind.Avg && kind == CellKind.Int {
        kind = CellKind.Real
        if decimals == 0u8 { decimals = 1u8 }
    }
    // v3 (main.vcl.form.pas, the summaries' OnGetText): an amount over 999 is written without cents
    if kind == CellKind.Currency && value > 999.0 { decimals = 0u8 }
    if push_number(&sb, kind, decimals, value) != ok { ret ("", control.TooLarge) }
    ret (str.done(&sb), ok)
}

// Neper dark: the v3 look's light constants (white, #F0F0F0) in the dark grid's surfaces; any other look keeps them.
fn skin(grid: *const Grid, value: u32) -> paint.Color {
    if grid.theme.tokens.profile == .Neper && grid.theme.tokens.palette == .Dark && grid.look.on {
        if value == 0xFFFFFFu32 { ret grid.look.even }
        if value == 0xF0F0F0u32 { ret grid.look.group_row }
        if value == 0xF8F8F8u32 { ret gl.rgb(0x181A20u32) }
        if value == 0xEBEBEBu32 { ret gl.rgb(0x24262Du32) }
        if value == 0xE3E3E3u32 { ret gl.rgb(0x272930u32) }
        if value == 0xDCDCDCu32 { ret gl.rgb(0x2F3138u32) }
    }
    ret gl.rgb(value)
}

// A data cell's text: in the row's own ink when the application gave one (`set_row_ink`), else
// in `role`.
fn cell_text_node(a: *mem.Arena, grid: *const Grid, text: str, bold: bool, role: style.ColorRole, row: usize, out: *widget.Node) -> err {
    // v3 marks the typed prefix in the current row's search cell (white on #0078D7)
    if grid.look.on && grid.has_search && grid.search_len > 0usize && grid.has_selection && grid.selected_row == row && search_matches(grid, row) {
        let column = grid.all[grid.search_spec].column
        let cell = table.get_str(grid.t, column, row)
        let n = grid.search_len
        if cell.len == text.len && cell.len >= n {
            var same = true
            var k = 0usize
            while k < cell.len && same {
                if cell[k] != text[k] { same = false }
                k += 1usize
            }
            if same {
                var options = control.text_options()
                options.wrap = .None
                options.size = grid.look.text_size
                let (head, head_error) = control.colored_text(a, 0u64, text[0usize..n], grid.theme, options, gl.rgb(0xFFFFFFu32))
                if head_error != ok { ret head_error }
                var tail_options = options
                tail_options.color = role
                if bold { tail_options.weight = 700u32 }
                var tail: widget.Node = zero
                var tail_error: err = ok
                var has_tail_ink = false
                if grid.has_ink {
                    let (tail_ink, has_row_ink) = grid.ink_of(grid.ink_ctx, row)
                    if has_row_ink {
                        has_tail_ink = true
                        let (colored, colored_error) = control.colored_text(a, 0u64, text[n..], grid.theme, tail_options, tail_ink)
                        tail = colored
                        tail_error = colored_error
                    }
                }
                if !has_tail_ink {
                    let (plain_tail, plain_tail_error) = control.text(a, 0u64, text[n..], grid.theme, tail_options)
                    tail = plain_tail
                    tail_error = plain_tail_error
                }
                if tail_error != ok { ret tail_error }
                var mark_style = style.defaults()
                mark_style.background = paint.Brush { Solid: gl.rgb(0x0078D7u32) }
                let (head_box, head_box_error) = mem.alloc[widget.Node](a, 1usize)
                if head_box_error != ok { ret control.TooLarge }
                head_box[0usize] = head
                let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
                if parts_error != ok { ret control.TooLarge }
                parts[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, mark_style, head_box[0usize..1usize])
                parts[1usize] = tail
                *out = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), parts[0usize..2usize])
                ret ok
            }
        }
    }
    // The Cupertino table view: the row that is selected and holds the keyboard focus is accent-filled, so its text is white.
    if grid.theme.tokens.profile == .CupertinoLike && !grid.look.on && grid.has_selection && grid.selected_row == row && mem.address_of(grid.theme.runtime) != 0usize {
        let (held, has_held) = widget.focused_key(grid.theme.runtime)
        if has_held && held == row_key(grid, row) {
            var white = control.text_options()
            white.wrap = .None
            if bold { white.weight = 700u32 }
            let (lit, lit_error) = control.colored_text(a, 0u64, text, grid.theme, white, style.hex(0xFFFFFFu32))
            if lit_error != ok { ret lit_error }
            *out = lit
            ret ok
        }
    }
    if grid.has_ink {
        let (ink, has_row_ink) = grid.ink_of(grid.ink_ctx, row)
        if has_row_ink {
            var options = control.text_options()
            options.wrap = .None
            if grid.look.on { options.size = grid.look.text_size }
            if bold { options.weight = 700u32 }
            let (coloured, coloured_error) = control.colored_text(a, 0u64, text, grid.theme, options, ink)
            if coloured_error != ok { ret coloured_error }
            *out = coloured
            ret ok
        }
    }
    ret text_node(a, grid, text, bold, role, out)
}

fn text_node(a: *mem.Arena, grid: *const Grid, text: str, bold: bool, role: style.ColorRole, out: *widget.Node) -> err {
    var options = control.text_options()
    options.wrap = .None
    options.color = role
    if grid.look.on { options.size = grid.look.text_size }
    if bold { options.weight = 700u32 }
    let (node, node_error) = control.text(a, 0u64, text, grid.theme, options)
    if node_error != ok { ret node_error }
    *out = node
    ret ok
}

// ---- the table source ------------------------------------------------------------

fn source_count(ctx: *void) -> usize {
    let grid = mem.cast[*Grid](ctx)
    ret grp.visible_len(grid.g)
}

fn source_key(ctx: *void, index: usize) -> widget.Key {
    let grid = mem.cast[*Grid](ctx)
    if grp.visible_is_footer(grid.g, index) { ret group_key(grid, grp.visible_group(grid.g, index)) + FOOTER_KEY_OFFSET }
    if grp.visible_is_group(grid.g, index) { ret group_key(grid, grp.visible_group(grid.g, index)) }
    ret row_key(grid, grp.visible_row(grid.g, index))
}

// A group row: first column "[+] key (count)", the summaries under their columns.
// The shown column that carries a group row's label: the first one that is not an indicator or
// a star (a narrow column of marks cannot hold the text).
fn label_column(grid: *const Grid) -> usize {
    var at = 0usize
    while at < grid.specs.len {
        if grid.specs[at].kind != CellKind.Indicator && (grid.specs[at].kind != CellKind.Star || grid.look.group_flat) { ret at }
        at += 1usize
    }
    ret 0usize
}

// A group row's cell with v3's dotted focus rectangle over it when the group is the current row.
fn group_cell(a: *mem.Arena, grid: *Grid, group: usize, spec: usize, out: *widget.Node) -> err {
    var plain: widget.Node = zero
    let plain_error = group_cell_plain(a, grid, group, spec, &plain)
    if plain_error != ok { ret plain_error }
    var current = false
    if grid.look.on && grid.has_position && grid.position < grp.visible_len(grid.g) {
        if grp.visible_is_group(grid.g, grid.position) && !grp.visible_is_footer(grid.g, grid.position) && grp.visible_group(grid.g, grid.position) == group { current = true }
    }
    if !current {
        *out = plain
        ret ok
    }
    var shape = gl.Shape.DotLine
    if spec == 0usize { shape = gl.Shape.DotEdges }
    var dot_dark = gl.rgb(0x000000u32)
    var dot_light = gl.rgb(0x000000u32)
    var dot_h = grid.look.row_height
    var dot_w = grid.columns[spec].width
    if grid.look.group_flat {
        // looks4-e: dark and light pixels alternate; the left edge stands at x = 17, the first column after the indicator
        shape = gl.Shape.DotsSoft
        if spec == 1usize { shape = gl.Shape.DotsSoftLeft }
        if spec == 0usize { dot_w = 0.0 }
        dot_dark = gl.rgb(0xA2A2A2u32)
        dot_light = gl.rgb(0xDEDEDEu32)
        dot_h = 18.0
    }
    let (dots, dots_error) = gl.mark(a, shape, dot_dark, dot_light, dot_w, dot_h)
    if dots_error != ok { ret dots_error }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
    if layers_error != ok { ret control.TooLarge }
    layers[0usize] = plain
    layers[1usize] = dots
    if spec == 0usize && grid.look.group_flat {
        // looks4-e: the current row's arrow in the indicator column, cut from the live capture
        let (arrow, arrow_error) = gl.pixels(a, gl.gx_row_arrow(), gl.gx_row_arrow_w(), gl.gx_row_arrow_h())
        if arrow_error != ok { ret arrow_error }
        let (three, three_error) = mem.alloc[widget.Node](a, 3usize)
        if three_error != ok { ret control.TooLarge }
        three[0usize] = plain
        three[1usize] = dots
        three[2usize] = widget.padded(0u64, 3.0, 5.0, 0.0, 0.0, style.defaults(), one(a, arrow))
        *out = widget.stack(0u64, style.defaults(), three[0usize..3usize])
        ret ok
    }
    *out = widget.stack(0u64, style.defaults(), layers[0usize..2usize])
    ret ok
}

fn group_cell_plain(a: *mem.Arena, grid: *Grid, group: usize, spec: usize, out: *widget.Node) -> err {
    let s = grid.specs[spec]
    if spec == label_column(grid) {
        let (b, b_error) = str.builder(a, 120usize)
        if b_error != ok { ret b_error }
        var sb = b
        let level = grp.group_level(grid.g, group)
        var indent = 0usize
        while indent < level {
            if str.push(&sb, "      ") != ok { ret control.TooLarge }
            indent += 1usize
        }
        // with the measured look the expander is drawn (a box) before the text
        let drawn_mark = grid.look.on
        if !drawn_mark {
            var mark = "[+] "
            if grp.is_expanded(grid.g, group) { mark = "[-] " }
            if str.push(&sb, mark) != ok { ret control.TooLarge }
        }
        let key_column = grid.g.levels[level].column
        let key_row = grp.group_key_row(grid.g, group)
        if grid.look.on {
            // v3's "Field : value (Count: n)"
            if str.push(&sb, table.column_name(grid.t, key_column)) != ok || str.push(&sb, " : ") != ok { ret control.TooLarge }
        }
        if table.is_null(grid.t, key_column, key_row) {
            if str.push(&sb, "(none)") != ok { ret control.TooLarge }
        } else {
            let kind = table.column_kind(grid.t, key_column)
            if kind == table.Kind.Str || kind == table.Kind.Dict {
                if str.push(&sb, table.get_str(grid.t, key_column, key_row)) != ok { ret control.TooLarge }
            } else {
                if str.push_i64(&sb, i64(key_row)) != ok { ret control.TooLarge }
            }
        }
        if grid.look.on && (!grid.look.group_flat || grid.look.group_counts) {
            if str.push(&sb, " (Count: ") != ok || str.push_usize(&sb, grp.group_count(grid.g, group)) != ok || str.push(&sb, ")") != ok { ret control.TooLarge }
        } else if !grid.look.on {
            if str.push(&sb, "  (") != ok || str.push_usize(&sb, grp.group_count(grid.g, group)) != ok || str.push(&sb, ")") != ok { ret control.TooLarge }
        }
        var label: widget.Node = zero
        let label_error = text_node(a, grid, str.done(&sb), !grid.look.on, .Text, &label)
        if label_error != ok { ret label_error }
        if !grid.look.on {
            *out = label
            ret ok
        }
        var box_shape = gl.Shape.PlusBox
        if grp.is_expanded(grid.g, group) { box_shape = gl.Shape.MinusBox }
        var box: widget.Node = zero
        var box_error: err = ok
        if grid.look.group_flat && !grp.is_expanded(grid.g, group) {
            // looks4-e: the live capture's 10 px bevelled box with the blue plus (3 in, 4 down in the 17 px row)
            let (picture, picture_error) = gl.pixels(a, gl.gx_expander(), gl.gx_expander_w(), gl.gx_expander_h())
            box_error = picture_error
            box = widget.padded(0u64, 4.0, 5.0, 0.0, 0.0, style.defaults(), one(a, picture))
        } else {
            let (drawn, drawn_error) = gl.mark(a, box_shape, gl.rgb(0x919191u32), gl.rgb(0xFFFFFFu32), 11.0, 11.0)
            box_error = drawn_error
            box = drawn
        }
        if box_error != ok { ret box_error }
        let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
        if pair_error != ok { ret control.TooLarge }
        // layered, not a row: a narrow first column must clip the label, not fail the layout
        let (taps, taps_error) = mem.alloc[BoxTap](a, 1usize)
        if taps_error != ok { ret control.TooLarge }
        taps[0usize] = BoxTap { grid: grid, group: group }
        let (box_inner, box_inner_error) = mem.alloc[widget.Node](a, 1usize)
        if box_inner_error != ok { ret control.TooLarge }
        box_inner[0usize] = box
        var box_hit = control.sized_style(17.0, grid.look.row_height)
        pair[0usize] = widget.region(grid.key + MENU_KEY + 600000u64 + u64(group), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&taps[0usize]), invoke: on_box_tap }, gestures: 1u8, enabled: true, focusable: false }, box_hit, box_inner[0usize..1usize])
        var label_left: f32 = 17.0
        var label_top: f32 = 0.0
        if grid.look.group_flat { label_left = 18.0 }
        if grid.look.group_flat { label_top = 3.0 }
        pair[1usize] = widget.padded(0u64, label_left, label_top, 0.0, 0.0, style.defaults(), one(a, label))
        *out = widget.stack(0u64, style.defaults(), pair[0usize..2usize])
        ret ok
    }
    if s.summary >= 0 && usize(s.summary) < grid.g.specs.len {
        let (text, text_error) = summary_text(a, s, grp.group_summary(grid.g, group, usize(s.summary)))
        if text_error != ok { ret text_error }
        ret text_node(a, grid, text, true, .Text, out)
    }
    ret text_node(a, grid, "", true, .Text, out)
}

// v3 shows the editors' buttons in the current row of an in-place editing grid: a spin editor its
// step arrows either side, a button editor its three dots.
fn decorate_editors(a: *mem.Arena, grid: *Grid, column: usize, row: usize, plain: widget.Node) -> (widget.Node, err) {
    var node = plain
    if grid.immediate_edit && grid.look.on && grid.has_selection && row == grid.selected_row && !grid.read_only && grid.origin[column] < grid.editors.len && grid.specs[column].editable {
        let editor_kind = grid.editors[grid.origin[column]]
        if editor_kind == EDITOR_SPIN {
            let ink = gl.rgb(0x000000u32)
            let (left_mark, left_mark_error) = gl.mark(a, .Left, ink, ink, 5.0, 8.0)
            if left_mark_error != ok { ret (zero, left_mark_error) }
            let (right_mark, right_mark_error) = gl.mark(a, .Right, ink, ink, 5.0, 8.0)
            if right_mark_error != ok { ret (zero, right_mark_error) }
            let (spin_parts, spin_parts_error) = mem.alloc[widget.Node](a, 3usize)
            if spin_parts_error != ok { ret (zero, spin_parts_error) }
            spin_parts[0usize] = left_mark
            spin_parts[1usize] = node
            spin_parts[2usize] = right_mark
            var spin_style = style.defaults()
            spin_style.width = style.Length { Percent: 100.0 }
            node = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .SpaceBetween, cross: .Center, gap: 2.0 }, spin_style, spin_parts[0usize..3usize])
        } else if editor_kind == EDITOR_BUTTON {
            var dots: widget.Node = zero
            let dots_error = text_node(a, grid, "...", false, .Text, &dots)
            if dots_error != ok { ret (zero, dots_error) }
            var dots_style = control.sized_style(18.0, 15.0)
            dots_style.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
            dots_style.border = style.Border { width: 1.0, color: gl.rgb(0x8E9092u32) }
            let (dots_box, dots_box_error) = mem.alloc[widget.Node](a, 1usize)
            if dots_box_error != ok { ret (zero, dots_box_error) }
            dots_box[0usize] = dots
            let (button_parts, button_parts_error) = mem.alloc[widget.Node](a, 2usize)
            if button_parts_error != ok { ret (zero, button_parts_error) }
            button_parts[0usize] = node
            button_parts[1usize] = widget.aligned(0u64, .Center, .Center, dots_style, dots_box[0usize..1usize])
            var button_style = style.defaults()
            button_style.width = style.Length { Percent: 100.0 }
            node = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .SpaceBetween, cross: .Center, gap: 2.0 }, button_style, button_parts[0usize..2usize])
        }
    }
    ret (node, ok)
}

fn source_cell(ctx: *void, a: *mem.Arena, index: usize, column: usize, out: *widget.Node) -> err {
    let grid = mem.cast[*Grid](ctx)
    if column >= grid.specs.len { ret control.TooLarge }
    if grp.visible_is_footer(grid.g, index) {
        // the group's summaries under its rows, in the summary cells' look
        let footer_spec = grid.specs[column]
        var footer_text = ""
        if footer_spec.summary >= 0 && usize(footer_spec.summary) < grid.g.specs.len {
            let (summed, summed_error) = summary_text(a, footer_spec, grp.group_summary(grid.g, grp.visible_group(grid.g, index), usize(footer_spec.summary)))
            if summed_error != ok { ret summed_error }
            footer_text = summed
        }
        if footer_text.len == 0usize { ret text_node(a, grid, "", true, .Text, out) }
        var summed_node: widget.Node = zero
        let summed_node_error = text_node(a, grid, footer_text, true, .Text, &summed_node)
        if summed_node_error != ok { ret summed_node_error }
        var summed_style = style.defaults()
        summed_style.width = style.Length { Percent: 100.0 }
        summed_style.background = paint.Brush { Solid: grid.look.footer_cell }
        let (summed_holder, summed_holder_error) = mem.alloc[widget.Node](a, 1usize)
        if summed_holder_error != ok { ret summed_holder_error }
        summed_holder[0usize] = summed_node
        *out = widget.aligned(0u64, .Center, .Center, summed_style, summed_holder[0usize..1usize])
        ret ok
    }
    if grp.visible_is_group(grid.g, index) { ret group_cell(a, grid, grp.visible_group(grid.g, index), column, out) }
    let row = grp.visible_row(grid.g, index)
    if grid.editing && grid.edit_row == row && grid.edit_spec == column && grid.specs[column].choice && table.column_kind(grid.t, grid.specs[column].column) == table.Kind.Dict && table.dict_len(grid.t, grid.specs[column].column) <= 24usize && table.dict_len(grid.t, grid.specs[column].column) != 0usize {
        let dict_column = grid.specs[column].column
        let n = table.dict_len(grid.t, dict_column)
        let (options, options_error) = mem.alloc[str](a, n)
        if options_error != ok { ret options_error }
        let (picks, picks_error) = mem.alloc[SelectPick](a, n)
        if picks_error != ok { ret picks_error }
        let (submits, submits_error) = mem.alloc[widget.Submit](a, n)
        if submits_error != ok { ret submits_error }
        var current = 0usize
        var i = 0usize
        while i < n {
            options[i] = table.dict_str(grid.t, dict_column, u32(i))
            picks[i] = SelectPick { grid: grid, id: i }
            submits[i] = widget.Submit { ctx: mem.cast[*void](&picks[i]), invoke: on_select_pick }
            if same_text(options[i], grid.edit_text[0usize..grid.edit_len]) { current = i }
            i += 1usize
        }
        let (toggle, toggle_error) = mem.alloc[widget.Submit](a, 1usize)
        if toggle_error != ok { ret toggle_error }
        toggle[0usize] = widget.Submit { ctx: mem.cast[*void](grid), invoke: on_select_toggle }
        if grid.look.on {
            // v3's image combo: the value with a down-arrow button in a bordered box; the list opens
            // under it, the current value in blue
            let (value_text, value_error) = flat_text(a, grid, options[current], gl.rgb(0x000000u32))
            if value_error != ok { ret value_error }
            let (arrow, arrow_error) = gl.mark(a, .ArrowDown, gl.rgb(0x000000u32), gl.rgb(0x000000u32), 7.0, 4.0)
            if arrow_error != ok { ret arrow_error }
            var button_style = control.sized_style(17.0, grid.look.row_height - 6.0)
            button_style.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
            button_style.border = style.Border { width: 1.0, color: gl.rgb(0x8E9092u32) }
            let (arrow_held, arrow_held_error) = mem.alloc[widget.Node](a, 1usize)
            if arrow_held_error != ok { ret arrow_held_error }
            arrow_held[0usize] = arrow
            let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
            if parts_error != ok { ret parts_error }
            parts[0usize] = widget.padded(0u64, 4.0, 0.0, 0.0, 0.0, control.sized_style(grid.columns[column].width - 28.0, grid.look.row_height - 4.0), one(a, value_text))
            parts[1usize] = widget.aligned(0u64, .Center, .Center, button_style, arrow_held[0usize..1usize])
            var box_style = control.sized_style(grid.columns[column].width - 2.0, grid.look.row_height - 2.0)
            box_style.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
            box_style.border = style.Border { width: 1.0, color: gl.rgb(0x0078D7u32) }
            let (box_held, box_held_error) = mem.alloc[widget.Node](a, 1usize)
            if box_held_error != ok { ret box_held_error }
            box_held[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), parts[0usize..2usize])
            var closed = widget.region(grid.key + EDIT_KEY, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](grid), invoke: on_select_tap }, gestures: 1u8, enabled: true, focusable: false }, box_style, box_held[0usize..1usize])
            if grid.select_open {
                var rows_list: [32]widget.Node = zero
                var shown_n = n
                if shown_n > 32usize { shown_n = 32usize }
                var r = 0usize
                while r < shown_n {
                    var ink = gl.rgb(0x000000u32)
                    var row_box = control.sized_style(grid.columns[column].width + 40.0, 19.0)
                    row_box.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
                    if r == current {
                        row_box.background = paint.Brush { Solid: gl.rgb(0x0078D7u32) }
                        ink = gl.rgb(0xFFFFFFu32)
                    }
                    let (entry_text, entry_error) = flat_text(a, grid, options[r], ink)
                    if entry_error != ok { ret entry_error }
                    let (entry_held, entry_held_error) = mem.alloc[widget.Node](a, 1usize)
                    if entry_held_error != ok { ret entry_held_error }
                    entry_held[0usize] = widget.padded(0u64, 4.0, 1.0, 0.0, 0.0, style.defaults(), one(a, entry_text))
                    rows_list[r] = widget.region(grid.key + EDIT_KEY + 1u64 + u64(r), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&picks[r]), invoke: on_select_tap_pick }, gestures: 1u8, enabled: true, focusable: false }, row_box, entry_held[0usize..1usize])
                    r += 1usize
                }
                let (list_nodes, list_nodes_error) = mem.alloc[widget.Node](a, shown_n)
                if list_nodes_error != ok { ret list_nodes_error }
                r = 0usize
                while r < shown_n {
                    list_nodes[r] = rows_list[r]
                    r += 1usize
                }
                var list_style = style.defaults()
                list_style.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
                list_style.border = style.Border { width: 1.0, color: gl.rgb(0x0078D7u32) }
                let list = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, list_style, list_nodes[0usize..shown_n])
                let (box_rect, has_box) = control.keyed_bounds(grid.theme.runtime, grid.key + EDIT_KEY)
                var list_x: f32 = 0.0
                var list_y: f32 = 0.0
                if has_box {
                    list_x = box_rect.x
                    list_y = box_rect.y + box_rect.height
                }
                let (list_held, list_held_error) = mem.alloc[widget.Node](a, 1usize)
                if list_held_error != ok { ret list_held_error }
                list_held[0usize] = list
                let (stack_parts, stack_parts_error) = mem.alloc[widget.Node](a, 2usize)
                if stack_parts_error != ok { ret stack_parts_error }
                stack_parts[0usize] = closed
                stack_parts[1usize] = widget.overlay(grid.key + EDIT_KEY + 100u64, widget.Overlay { anchor: 0u64, placement: .At, offset: geometry.Point { x: list_x, y: list_y }, modal: false, dismiss: widget.Submit { ctx: mem.cast[*void](grid), invoke: on_select_toggle } }, style.defaults(), list_held[0usize..1usize])
                *out = widget.stack(0u64, style.defaults(), stack_parts[0usize..2usize])
                ret ok
            }
            *out = closed
            ret ok
        }
        let (chooser, chooser_error) = control.select(a, grid.key + EDIT_KEY, grid.theme, grid.specs[column].title, options, current, grid.select_open, &toggle[0usize], submits)
        if chooser_error != ok { ret chooser_error }
        *out = chooser
        ret ok
    }
    if grid.editing && grid.edit_row == row && grid.edit_spec == column {
        var options = control.field_options()
        options.width = grid.columns[column].width - 12.0
        options.height = 36.0
        options.invalid = grid.edit_invalid
        var field_label = grid.specs[column].title
        if grid.look.on {
            // v3's in-cell editor: no label, as high as the row
            field_label = ""
            options.height = grid.look.row_height - 2.0
            options.width = grid.columns[column].width - 2.0
        }
        let buffer = grid.edit_text[0usize..EDIT_TEXT]
        let me = mem.cast[*void](grid)
        var kind = EDITOR_TEXT
        let edited_spec = grid.origin[column]
        if edited_spec < grid.editors.len { kind = grid.editors[edited_spec] }
        var field: widget.Node = zero
        var field_error: err = ok
        if grid.look.on {
            // v3's in-cell editor: the bare text on white in a thin line, with its arrows or dots
            let width = grid.columns[column].width - 2.0
            let height = grid.look.row_height - 2.0
            var inner_width = width
            if kind == EDITOR_SPIN { inner_width = width - 24.0 }
            if kind == EDITOR_BUTTON { inner_width = width - 18.0 }
            let (bare, bare_error) = control.bare_field(a, grid.key + EDIT_KEY, grid.theme, "", buffer, grid.edit_len, widget.Change[str] { ctx: me, invoke: on_edit_change }, widget.Submit { ctx: me, invoke: on_edit_commit }, inner_width, height, grid.look.text_size, gl.rgb(0xFFFFFFu32), grid.look.selected_line)
            if bare_error != ok { ret bare_error }
            let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
            if parts_error != ok { ret parts_error }
            var n = 0usize
            if kind == EDITOR_SPIN {
                let (steps, steps_error) = mem.alloc[widget.Submit](a, 2usize)
                if steps_error != ok { ret steps_error }
                steps[0usize] = widget.Submit { ctx: me, invoke: on_spin_down }
                steps[1usize] = widget.Submit { ctx: me, invoke: on_spin_up }
                let (left_arrow, left_error) = spin_arrow(a, grid, grid.key + EDIT_KEY + 20u64, gl.Shape.Left, "Decrease", &steps[0usize])
                if left_error != ok { ret left_error }
                let (right_arrow, right_error) = spin_arrow(a, grid, grid.key + EDIT_KEY + 21u64, gl.Shape.Right, "Increase", &steps[1usize])
                if right_error != ok { ret right_error }
                parts[0usize] = left_arrow
                parts[1usize] = bare
                parts[2usize] = right_arrow
                n = 3usize
            } else if kind == EDITOR_BUTTON {
                let (pressed, pressed_error) = mem.alloc[widget.Submit](a, 1usize)
                if pressed_error != ok { ret pressed_error }
                pressed[0usize] = widget.Submit { ctx: me, invoke: on_cell_button }
                let (dots, dots_error) = dots_button(a, grid, grid.key + EDIT_KEY + 22u64, &pressed[0usize])
                if dots_error != ok { ret dots_error }
                parts[0usize] = bare
                parts[1usize] = dots
                n = 2usize
            } else {
                parts[0usize] = bare
                n = 1usize
            }
            field = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), parts[0usize..n])
        } else if kind == EDITOR_BUTTON {
            let (pressed, pressed_error) = mem.alloc[widget.Submit](a, 1usize)
            if pressed_error != ok { ret pressed_error }
            pressed[0usize] = widget.Submit { ctx: me, invoke: on_cell_button }
            let (made_button, made_button_error) = control.button_edit(a, grid.key + EDIT_KEY, grid.theme, field_label, buffer, grid.edit_len, widget.Change[str] { ctx: me, invoke: on_edit_change }, widget.Submit { ctx: me, invoke: on_edit_commit }, &pressed[0usize], "Choose", options)
            field = made_button
            field_error = made_button_error
        } else {
            let (made_field, made_field_error) = control.text_field(a, grid.key + EDIT_KEY, grid.theme, field_label, buffer, grid.edit_len, widget.Change[str] { ctx: me, invoke: on_edit_change }, widget.Submit { ctx: me, invoke: on_edit_commit }, options)
            field = made_field
            field_error = made_field_error
        }
        if field_error != ok { ret field_error }
        if false {
            // v3's spin editor: a step arrow either side of the number
            let (down_submit, down_error) = mem.alloc[widget.Submit](a, 2usize)
            if down_error != ok { ret down_error }
            down_submit[0usize] = widget.Submit { ctx: me, invoke: on_spin_down }
            down_submit[1usize] = widget.Submit { ctx: me, invoke: on_spin_up }
            let (left_arrow, left_error) = spin_arrow(a, grid, grid.key + EDIT_KEY + 20u64, gl.Shape.Left, "Decrease", &down_submit[0usize])
            if left_error != ok { ret left_error }
            let (right_arrow, right_error) = spin_arrow(a, grid, grid.key + EDIT_KEY + 21u64, gl.Shape.Right, "Increase", &down_submit[1usize])
            if right_error != ok { ret right_error }
            // both arrows in one row laid over the field, a gap between them as wide as the number
            let (spin_parts, spin_parts_error) = mem.alloc[widget.Node](a, 5usize)
            if spin_parts_error != ok { ret spin_parts_error }
            let (gap_nodes, gap_error) = mem.alloc[widget.Node](a, 1usize)
            if gap_error != ok { ret gap_error }
            gap_nodes[0usize] = widget.box(0u64, control.sized_style(options.width - 24.0, 1.0), zero)
            spin_parts[2usize] = left_arrow
            spin_parts[3usize] = gap_nodes[0usize]
            spin_parts[4usize] = right_arrow
            let arrow_y = (options.height - 11.0) * 0.5
            spin_parts[1usize] = widget.positioned(0u64, 1.0, arrow_y, style.defaults(), one(a, widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), spin_parts[2usize..5usize])))
            spin_parts[0usize] = field
            field = widget.stack(0u64, style.defaults(), spin_parts[0usize..2usize])
        }
        // Tab and Shift+Tab move the editor, Escape cancels it (a scope round the field)
        let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 2usize)
        if shortcuts_error != ok { ret shortcuts_error }
        shortcuts[0usize] = widget.Shortcut { key: 9u32, modifiers: input.Modifiers { shift: false, control: false, alt: false, meta: false, caps_lock: false, num_lock: false }, action: widget.Submit { ctx: me, invoke: on_edit_tab } }
        shortcuts[1usize] = widget.Shortcut { key: 9u32, modifiers: input.Modifiers { shift: true, control: false, alt: false, meta: false, caps_lock: false, num_lock: false }, action: widget.Submit { ctx: me, invoke: on_edit_back_tab } }
        let scope = widget.scope(grid.key + EDIT_KEY + 1u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..2usize], default_action: widget.Submit { ctx: me, invoke: on_edit_commit }, cancel_action: widget.Submit { ctx: me, invoke: on_edit_cancel }, keys: zero }, style.defaults(), one(a, field))
        *out = scope
        ret ok
    }
    if grid.specs[column].kind == CellKind.Indicator {
        // v3: a triangle on the current row, a thin arrow on each other selected row
        var current = grid.has_selection && grid.selected_row == row
        var others = grid.multi && is_marked(grid, row) && !current
        if !current && !others { ret text_node(a, grid, "", true, .Text, out) }
        var size: f32 = 8.0
        var ink = gl.rgb(0x000000u32)
        if others {
            size = 6.0
            ink = gl.rgb(0x505050u32)
        }
        // a grid that edits in place shows the editing arrow on its current row (v3's collection)
        if current && grid.look.group_flat {
            // looks4-e: v3's own arrow, 1 in and 6 down in the 19 px row
            let (long_pic, long_error) = gl.pixels(a, gl.gx_row_arrow_long(), gl.gx_row_arrow_long_w(), gl.gx_row_arrow_long_h())
            if long_error != ok { ret long_error }
            *out = widget.padded(0u64, 1.0, 6.0, 0.0, 0.0, style.defaults(), one(a, long_pic))
            ret ok
        }
        var arrow_shape = gl.Shape.Right
        var arrow_w = size
        if current && grid.immediate_edit {
            arrow_shape = gl.Shape.ArrowLong
            arrow_w = 11.0
        }
        let (arrow, arrow_error) = gl.mark(a, arrow_shape, ink, ink, arrow_w, size)
        if arrow_error != ok { ret arrow_error }
        *out = arrow
        ret ok
    }
    if grid.specs[column].kind == CellKind.Star {
        // a favourite: a gold star when the boolean is set, nothing otherwise
        if !table.is_null(grid.t, grid.specs[column].column, row) && table.get_bool(grid.t, grid.specs[column].column, row) {
            let (star, star_error) = gl.mark(a, .StarFilled, gl.rgb(0xE8B100u32), gl.rgb(0xFFFFFFu32), 13.0, 13.0)
            if star_error != ok { ret star_error }
            *out = star
            ret ok
        }
        ret text_node(a, grid, "", false, .Text, out)
    }
    if grid.specs[column].kind == CellKind.Bool && grid.look.on {
        // v3's check box (cxCheckBox, recorded in FT2): a 19 px rounded square, blue with a white
        // tick when set, white with a grey edge when not, centred in its cell
        var checked = false
        if !table.is_null(grid.t, grid.specs[column].column, row) { checked = table.get_bool(grid.t, grid.specs[column].column, row) }
        var box = control.sized_style(19.0, 19.0)
        box.radius = 4.0
        let (tick_holder, tick_holder_error) = mem.alloc[widget.Node](a, 1usize)
        if tick_holder_error != ok { ret control.TooLarge }
        var inner: []widget.Node = zero
        if checked {
            box.background = paint.Brush { Solid: gl.rgb(0x005FB8u32) }
            let (tick, tick_error) = gl.mark(a, .Check, gl.rgb(0xFFFFFFu32), gl.rgb(0xFFFFFFu32), 11.0, 11.0)
            if tick_error != ok { ret tick_error }
            tick_holder[0usize] = tick
            inner = tick_holder[0usize..1usize]
        } else {
            box.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
            box.border = style.Border { width: 1.0, color: gl.rgb(0x757575u32) }
        }
        let (box_holder, box_holder_error) = mem.alloc[widget.Node](a, 1usize)
        if box_holder_error != ok { ret control.TooLarge }
        box_holder[0usize] = widget.aligned(0u64, .Center, .Center, box, inner)
        var wide = style.defaults()
        wide.width = style.Length { Percent: 100.0 }
        *out = widget.aligned(0u64, .Center, .Center, wide, box_holder[0usize..1usize])
        ret ok
    }
    if grid.specs[column].kind == CellKind.Custom || grid.specs[column].kind == CellKind.Picture { ret grid.events.custom_cell(grid.events.ctx, a, grid.theme, row, grid.origin[column], out) }
    var role = grid.events.row_role(grid.events.ctx, row)
    let (text, text_error) = cell_text(a, grid, column, row)
    if text_error != ok { ret text_error }
    if !grid.has_rules {
        var plain_node: widget.Node = zero
        try cell_text_node(a, grid, text, false, role, row, &plain_node)
        let (decorated_plain, decorate_plain_error) = decorate_editors(a, grid, column, row, plain_node)
        if decorate_plain_error != ok { ret decorate_plain_error }
        *out = decorated_plain
        ret ok
    }
    let look = rules.format(grid.rule_set, row, grid.specs[column].column)
    if look.has_ink { role = look.ink }
    var shown = text
    if look.icon != 0u8 {
        var glyph = "- "
        if look.icon == 1u8 { glyph = "v " }
        if look.icon == look.buckets { glyph = "^ " }
        let (b, b_error) = str.builder(a, text.len + 4usize)
        if b_error != ok { ret b_error }
        var sb = b
        if str.push(&sb, glyph) != ok { ret control.TooLarge }
        if str.push(&sb, text) != ok { ret control.TooLarge }
        shown = str.done(&sb)
    }
    var node: widget.Node = zero
    try cell_text_node(a, grid, shown, look.bold, role, row, &node)
    let (decorated_node, decorate_error) = decorate_editors(a, grid, column, row, node)
    if decorate_error != ok { ret decorate_error }
    node = decorated_node
    if !look.has_fill && !look.has_bar {
        *out = node
        ret ok
    }
    // a fill or a data bar: the text over a box of the colour (the bar a fraction of its width)
    var layers: []widget.Node = zero
    var count = 0usize
    let (made, made_error) = mem.alloc[widget.Node](a, 3usize)
    if made_error != ok { ret control.TooLarge }
    layers = made
    var back = style.defaults()
    back.width = style.Length { Percent: 100.0 }
    back.height = style.Length { Percent: 100.0 }
    if look.has_bar {
        var bar = style.defaults()
        bar.width = style.Length { Percent: look.bar_span * 100.0 }
        bar.height = style.Length { Percent: 100.0 }
        // v3's default Fill mode is Gradient: the bar's colour fades to white along its own length. A
        // gradient's points are in surface space, so the column's left edge comes from its header as
        // laid out the frame before
        bar.background = paint.Brush { Solid: look.bar_color }
        var bar_length: f32 = 0.0
        if column < grid.columns.len { bar_length = grid.columns[column].width * look.bar_span }
        // Fill mode Solid and Border style Solid of v3's Data Bar Rule Style Settings
        if look.bar_border { bar.border = style.Border { width: 1.0, color: look.bar_color } }
        if !look.bar_solid && bar_length > 2.0 && mem.address_of(grid.theme) != 0usize && mem.address_of(grid.theme.runtime) != 0usize {
            let (head_box, has_head) = control.keyed_bounds(grid.theme.runtime, grid.key + 1u64 + 2u64 * u64(column))
            let (bar_stops, bar_stops_error) = mem.alloc[paint.Stop](a, 2usize)
            if has_head && bar_stops_error == ok {
                bar_stops[0usize] = paint.Stop { offset: 0.0, color: look.bar_color }
                bar_stops[1usize] = paint.Stop { offset: 1.0, color: paint.rgba(1.0, 1.0, 1.0, 1.0) }
                let cell_width = grid.columns[column].width
                if look.bar_rtl {
                    let right_edge = head_box.x + (look.bar_left + look.bar_span) * cell_width
                    bar.background = paint.Brush { Linear: paint.LinearGradient { start: geometry.Point { x: right_edge, y: 0.0 }, end: geometry.Point { x: right_edge - bar_length, y: 0.0 }, stops: bar_stops[0usize..2usize] } }
                } else {
                    let left_edge = head_box.x + look.bar_left * cell_width
                    bar.background = paint.Brush { Linear: paint.LinearGradient { start: geometry.Point { x: left_edge, y: 0.0 }, end: geometry.Point { x: left_edge + bar_length, y: 0.0 }, stops: bar_stops[0usize..2usize] } }
                }
            }
        }
        // Bar direction and Axis (v3): the bar starts where the axis or the unfilled part ends
        layers[count] = widget.box(0u64, bar, zero)
        if look.bar_left > 0.0 {
            // a spacer of the offset's share before the bar (a percent margin would paint over the cell)
            let (offset_bar, offset_error) = offset_node(a, bar, look.bar_left)
            if offset_error != ok { ret offset_error }
            layers[count] = offset_bar
        }
        count += 1usize
        if look.has_axis_line {
            let (axis_node, axis_error) = axis_line_node(a, look.axis_line, look.bar_axis_at)
            if axis_error != ok { ret axis_error }
            layers[count] = axis_node
            count += 1usize
        }
    }
    if look.has_fill { back.background = paint.Brush { Solid: look.fill } }
    // Show Bar Only (v3): the bar alone, the value is not written
    if !(look.has_bar && look.bar_only) {
        layers[count] = node
        count += 1usize
    }
    *out = widget.stack(0u64, back, layers[0usize..count])
    ret ok
}

// The bar `left` of the cell's width in: a spacer, then the bar.
fn offset_node(a: *mem.Arena, bar: style.Style, left: f32) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    var spacer = style.defaults()
    spacer.width = style.Length { Percent: left * 100.0 }
    spacer.height = style.Length { Percent: 100.0 }
    parts[0usize] = widget.box(0u64, spacer, zero)
    parts[1usize] = widget.box(0u64, bar, zero)
    var row = style.defaults()
    row.width = style.Length { Percent: 100.0 }
    row.height = style.Length { Percent: 100.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, row, parts[0usize..2usize]), ok)
}

// The axis of a data bar (Axis color): a 1 px line `at` of the cell's width in, over the cell's height; a
// spacer before it takes the distance (a percent margin on the line itself painted over the cell).
fn axis_line_node(a: *mem.Arena, color: paint.Color, at: f32) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    var spacer = style.defaults()
    spacer.width = style.Length { Percent: at * 100.0 }
    spacer.height = style.Length { Percent: 100.0 }
    var line = style.defaults()
    line.width = style.Length { Px: 1.0 }
    line.height = style.Length { Percent: 100.0 }
    line.background = paint.Brush { Solid: color }
    parts[0usize] = widget.box(0u64, spacer, zero)
    parts[1usize] = widget.box(0u64, line, zero)
    var row = style.defaults()
    row.width = style.Length { Percent: 100.0 }
    row.height = style.Length { Percent: 100.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, row, parts[0usize..2usize]), ok)
}

// The kind of a visible row for the table look: 1 for a group row.
fn row_kind(ctx: *void, index: usize) -> u8 {
    let grid = mem.cast[*Grid](ctx)
    if index < grp.visible_len(grid.g) && grp.visible_is_footer(grid.g, index) { ret 2u8 }
    if index < grp.visible_len(grid.g) && grp.visible_is_group(grid.g, index) { ret 1u8 }
    ret 0u8
}

// The header mark of a column for the table look: 1 (the favourite star) for a Star column.
fn header_glyph(ctx: *void, shown: usize) -> u8 {
    let grid = mem.cast[*Grid](ctx)
    if shown < grid.specs.len && grid.specs[shown].kind == CellKind.Star { ret 1u8 }
    if shown < grid.specs.len && grid.specs[shown].kind == CellKind.Picture { ret 2u8 }
    if shown < grid.specs.len && grid.specs[shown].kind == CellKind.Indicator { ret 3u8 }
    ret 0u8
}

// ---- events ----------------------------------------------------------------------

fn on_sort(ctx: *void, shown: usize) -> err {
    let grid = mem.cast[*Grid](ctx)
    grid.chooser_active = false
    if shown >= grid.specs.len { ret ok }
    if grid.specs[shown].kind == CellKind.Indicator {
        // the glyph of the row indicator's header: the quick column list under it
        grid.menu_open = true
        grid.menu_kind = MENU_QUICK
        if mem.address_of(grid.theme) != 0usize && mem.address_of(grid.theme.runtime) != 0usize {
            let at = widget.pointer_position(grid.theme.runtime)
            let (cell_row, cell_column, rect, has_cell) = widget.cell_rect_at(grid.theme.runtime, at)
            if has_cell && cell_row == 0u32 {
                grid.quick_x = rect.x
                grid.quick_y = rect.y + rect.height
            } else {
                grid.quick_x = at.x
                grid.quick_y = at.y
            }
            let _ = cell_column
        }
        ret ok
    }
    let spec = grid.origin[shown]
    grid.head_spec = spec
    // v3 (DevExpress): Shift+click adds the column to the sort or reverses it there, Ctrl+click takes
    // it out, a plain click sorts by it alone
    var mods: input.Modifiers = zero
    if mem.address_of(grid.theme) != 0usize && mem.address_of(grid.theme.runtime) != 0usize { mods = widget.modifiers(grid.theme.runtime) }
    if mods.shift && grid.look.on {
        if grid.sort_column == spec {
            grid.descending = !grid.descending
        } else {
            var at_extra = 0usize
            var found_extra = false
            while at_extra < grid.extra_count {
                if grid.extra_sort[at_extra] == spec {
                    grid.extra_desc[at_extra] = !grid.extra_desc[at_extra]
                    found_extra = true
                }
                at_extra += 1usize
            }
            if !found_extra && grid.extra_count < 4usize {
                grid.extra_sort[grid.extra_count] = spec
                grid.extra_desc[grid.extra_count] = false
                grid.extra_count += 1usize
            }
        }
        ret grid.events.sort_changed(grid.events.ctx, grid.sort_column, grid.descending)
    }
    if mods.control && grid.look.on {
        var kept = 0usize
        var drop_at = 0usize
        var removed = false
        if grid.sort_column == spec && grid.extra_count > 0usize {
            // the first of the others becomes the primary
            grid.sort_column = grid.extra_sort[0usize]
            grid.descending = grid.extra_desc[0usize]
            drop_at = 0usize
            removed = true
            var shift_at = 1usize
            while shift_at < grid.extra_count {
                grid.extra_sort[shift_at - 1usize] = grid.extra_sort[shift_at]
                grid.extra_desc[shift_at - 1usize] = grid.extra_desc[shift_at]
                shift_at += 1usize
            }
            grid.extra_count -= 1usize
        } else {
            while drop_at < grid.extra_count {
                if grid.extra_sort[drop_at] == spec {
                    removed = true
                } else {
                    grid.extra_sort[kept] = grid.extra_sort[drop_at]
                    grid.extra_desc[kept] = grid.extra_desc[drop_at]
                    kept += 1usize
                }
                drop_at += 1usize
            }
            if removed { grid.extra_count = kept }
        }
        if removed { ret grid.events.sort_changed(grid.events.ctx, grid.sort_column, grid.descending) }
        if grid.sort_column == spec {
            // the only sorted column: v3 clears the sort (the application reads the command)
            grid.sort_column = grid.all.len
            grid.command = CMD_CLEAR_SORT
            grid.command_spec = shown
        }
        ret ok
    }
    grid.extra_count = 0usize
    var descending = false
    if grid.sort_column == spec { descending = !grid.descending }
    grid.sort_column = spec
    grid.descending = descending
    ret grid.events.sort_changed(grid.events.ctx, spec, descending)
}

// A double click on a group row toggles it (v3), as the click on its box does.
fn on_double(ctx: *void, value: widget.Key) -> err {
    let grid = mem.cast[*Grid](ctx)
    let base = grid.key + KEY_BASE
    let rows = u64(table.capacity(grid.t))
    if value < base + rows { ret ok }
    let group = usize(value - base - rows)
    if group >= grp.group_len(grid.g) { ret ok }
    ret grp.set_expanded(grid.g, group, !grp.is_expanded(grid.g, group))
}

type BoxTap = struct { grid: *Grid, group: usize }

fn on_box_tap(ctx: *void, g: widget.Gesture) -> err {
    let tap = mem.cast[*BoxTap](ctx)
    switch g {
    case .Tap as at:
        let grid = tap.grid
        ret grp.set_expanded(grid.g, tap.group, !grp.is_expanded(grid.g, tap.group))
    default:
        ret ok
    }
}

// A tap on a group row focuses it; on a data row it selects it and tells the application.
fn on_pick(ctx: *void, value: widget.Key) -> err {
    let grid = mem.cast[*Grid](ctx)
    let base = grid.key + KEY_BASE
    let rows = u64(table.capacity(grid.t))
    if value < base { ret ok }
    let at = value - base
    if at >= rows {
        let group = usize(at - rows)
        if group < grp.group_len(grid.g) {
            // v3 puts the focus on the group row it toggles (the dotted rectangle)
            var at_group = 0usize
            let shown_total = grp.visible_len(grid.g)
            while at_group < shown_total && !(grp.visible_is_group(grid.g, at_group) && !grp.visible_is_footer(grid.g, at_group) && grp.visible_group(grid.g, at_group) == group) { at_group += 1usize }
            // v3: a click on the row's text only makes it current; the box or a double click toggles
            if at_group < shown_total {
                grid.has_position = true
                grid.position = at_group
                grid.has_selection = false
            }
            if !grid.look.on {
                ret grp.set_expanded(grid.g, group, !grp.is_expanded(grid.g, group))
            }
            ret ok
        }
        ret ok
    }
    grid.chooser_active = false
    var again = grid.has_selection && grid.selected_row == usize(at)
    grid.has_selection = true
    grid.selected_row = usize(at)
    var found = 0usize
    let visible = grp.visible_len(grid.g)
    while found < visible && (grp.visible_is_group(grid.g, found) || grp.visible_row(grid.g, found) != usize(at)) { found += 1usize }
    if found < visible {
        grid.has_position = true
        grid.position = found
    }
    if grid.multi && found < visible {
        // Ctrl+click toggles the row, Shift+click selects from the anchor, a plain click selects one
        var held: input.Modifiers = zero
        if mem.address_of(grid.theme) != 0usize && mem.address_of(grid.theme.runtime) != 0usize { held = widget.modifiers(grid.theme.runtime) }
        if held.control {
            set_mark(grid, usize(at), !is_marked(grid, usize(at)))
            grid.anchor = found
            grid.has_anchor = true
            again = false
        } else if held.shift && grid.has_anchor {
            clear_marks(grid)
            mark_range(grid, grid.anchor, found)
            again = false
        } else {
            clear_marks(grid)
            set_mark(grid, usize(at), true)
            grid.anchor = found
            grid.has_anchor = true
        }
        if held.control || held.shift { ret grid.events.row_picked(grid.events.ctx, usize(at)) }
    }
    // v3: a click on a favourite star flips it at once, the row becoming current with the same click
    if grid.look.on && !again && !grid.read_only && !grid.editing && mem.address_of(grid.theme) != 0usize && mem.address_of(grid.theme.runtime) != 0usize {
        let star_point = widget.pointer_position(grid.theme.runtime)
        let (star_box, star_found) = widget.bounds_for_key(grid.theme.runtime, row_key(grid, usize(at)))
        if star_found && star_point.x >= star_box.x {
            var star_edge = star_box.x
            var star_at = 0usize
            while star_at < grid.specs.len {
                star_edge += grid.widths[grid.origin[star_at]]
                if star_point.x < star_edge {
                    if (grid.specs[star_at].kind == CellKind.Star || grid.specs[star_at].kind == CellKind.Bool) && grid.specs[star_at].editable {
                        let flipped = begin_edit(grid, usize(at), grid.origin[star_at])
                        if flipped != ok && flipped != Locked && flipped != NotEditable { ret flipped }
                        ret grid.events.row_picked(grid.events.ctx, usize(at))
                    }
                    break
                }
                star_at += 1usize
            }
        }
    }
    if (again || grid.immediate_edit) && !grid.read_only && !grid.editing {
        // the first editable column of the row (v3 starts the edit of the clicked cell at once)
        var column = 0usize
        while column < grid.specs.len && !grid.specs[column].editable { column += 1usize }
        // ... or the cell that was tapped, when it is one
        var tapped = false
        var tap_x: f32 = 0.0
        if mem.address_of(grid.theme) != 0usize && mem.address_of(grid.theme.runtime) != 0usize {
            let at_point = widget.pointer_position(grid.theme.runtime)
            let (row_box, row_found) = widget.bounds_for_key(grid.theme.runtime, row_key(grid, usize(at)))
            if row_found && at_point.x >= row_box.x {
                var edge = row_box.x
                var d = 0usize
                while d < grid.specs.len {
                    // the column's header stands where the column is drawn, whatever its stored width
                    var left = edge
                    var right = edge + grid.widths[grid.origin[d]]
                    let (head_box, has_head) = widget.bounds_for_key(grid.theme.runtime, grid.key + 1u64 + 2u64 * u64(d))
                    if has_head {
                        left = head_box.x
                        right = head_box.x + head_box.width
                    }
                    edge = right
                    if at_point.x < right {
                        tapped = true
                        // the tap's distance into the cell, less its padding
                        tap_x = at_point.x - left - 4.0
                        if grid.specs[d].editable { column = d } else if grid.immediate_edit { column = grid.specs.len }
                        break
                    }
                    d += 1usize
                }
            }
        }
        if column < grid.specs.len {
            let began = begin_edit(grid, usize(at), grid.origin[column])
            if began != ok && began != Locked && began != NotEditable { ret began }
            if began == ok && grid.editing && tapped {
                grid.edit_caret_frames = 2usize
                grid.edit_click_x = tap_x
            }
        }
    } else if grid.editing && grid.edit_row != usize(at) {
        cancel_edit(grid)
    }
    ret grid.events.row_picked(grid.events.ctx, usize(at))
}

// One filter field changed: the grid keeps the text (its buffer is the field's) and reports it.
type FilterPick = struct { grid: *Grid, spec: usize }

fn filter_op_sign(op: u8) -> str {
    if op == 1u8 { ret "≠" }
    if op == 2u8 { ret "<" }
    if op == 3u8 { ret "≤" }
    if op == 4u8 { ret ">" }
    if op == 5u8 { ret "≥" }
    if op == 6u8 || op == 7u8 { ret "A%C" }
    if op == 8u8 || op == 9u8 { ret "ABC" }
    if op == 10u8 || op == 11u8 { ret "ABC" }
    ret "="
}

fn filter_op_words(op: u8) -> str {
    if op == 0u8 { ret "Equals" }
    if op == 1u8 { ret "Does not equal" }
    if op == 2u8 { ret "Is less than" }
    if op == 3u8 { ret "Is less than or equal to" }
    if op == 4u8 { ret "Is greater than" }
    if op == 5u8 { ret "Is greater than or equal to" }
    if op == 6u8 { ret "Is like" }
    if op == 7u8 { ret "Is not like" }
    if op == 8u8 { ret "Contains" }
    if op == 9u8 { ret "Does not contain" }
    if op == 10u8 { ret "Begins with" }
    ret "Ends with"
}

type FilterOpPick = struct { grid: *Grid, spec: usize, op: u8 }

fn on_filter_op_tap(ctx: *void, g: widget.Gesture) -> err {
    switch g {
    case .Tap as at:
        let submit = mem.cast[*widget.Submit](ctx)
        ret submit.invoke(submit.ctx)
    default:
        ret ok
    }
}

fn on_filter_sign(ctx: *void, g: widget.Gesture) -> err {
    let pick = mem.cast[*FilterPick](ctx)
    switch g {
    case .Tap as at:
        if pick.grid.filter_pop == pick.spec + 1usize { pick.grid.filter_pop = 0usize } else { pick.grid.filter_pop = pick.spec + 1usize }
        ret ok
    default:
        ret ok
    }
}

fn on_filter_op(ctx: *void) -> err {
    let pick = mem.cast[*FilterOpPick](ctx)
    pick.grid.filter_ops[pick.spec] = pick.op
    pick.grid.filter_pop = 0usize
    ret pick.grid.events.filter_changed(pick.grid.events.ctx, pick.spec, filter_value(pick.grid, pick.spec))
}

fn on_filter_pop_dismiss(ctx: *void) -> err {
    let grid = mem.cast[*Grid](ctx)
    grid.filter_pop = 0usize
    ret ok
}

fn on_filter(ctx: *void, value: str) -> err {
    let pick = mem.cast[*FilterPick](ctx)
    pick.grid.filter_lens[pick.spec] = value.len
    pick.grid.filter_off = false
    ret pick.grid.events.filter_changed(pick.grid.events.ctx, pick.spec, value)
}

fn on_scroll(ctx: *void, value: f32) -> err {
    let grid = mem.cast[*Grid](ctx)
    grid.offset = value
    ret ok
}

fn on_reorder(ctx: *void, value: collection.Reorder) -> err {
    let grid = mem.cast[*Grid](ctx)
    if value.from >= collection.CHOOSER_FROM {
        // a hidden column dragged out of the chooser onto a header
        let carried = value.from - collection.CHOOSER_FROM
        let owner = u64(carried >> 13usize)
        let spec = carried & 8191usize
        if owner != (grid.key & 65535u64) { ret ok }
        if spec < grid.all.len && grid.hidden[spec] {
            grid.hidden[spec] = false
            relayout(grid)
            move_column(grid, spec, value.to)
        }
        ret ok
    }
    if value.from < grid.specs.len && value.to < grid.specs.len { move_column(grid, grid.origin[value.from], value.to) }
    ret ok
}

fn on_resize(ctx: *void, value: collection.ColumnResize) -> err {
    let grid = mem.cast[*Grid](ctx)
    if value.width < 0.0 {
        // a double tap on the handle: the best fit is made at the next build (it needs the fonts)
        if value.column < grid.specs.len {
            grid.fit_spec = grid.origin[value.column]
            grid.fit_pending = true
        }
        ret ok
    }
    if value.column < grid.specs.len { resize_column(grid, grid.origin[value.column], value.width) }
    ret ok
}

// ---- the node --------------------------------------------------------------------

fn one(a: *mem.Arena, node: widget.Node) -> []widget.Node {
    let (nodes, nodes_error) = mem.alloc[widget.Node](a, 1usize)
    if nodes_error != ok { ret zero }
    nodes[0usize] = node
    ret nodes[0usize..1usize]
}

// The band of a displayed column: the index of the band whose spec range holds its spec, or
// `bands.len` for none.
fn band_of(grid: *const Grid, shown: usize) -> usize {
    let spec = grid.origin[shown]
    var b = 0usize
    while b < grid.bands.len {
        if spec >= grid.bands[b].first && spec < grid.bands[b].first + grid.bands[b].count { ret b }
        b += 1usize
    }
    ret grid.bands.len
}

// The band row: each band's title over the displayed columns of the band (a run of neighbours;
// columns of no band stand as a gap).
fn band_row(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, grid.specs.len + 1usize)
    if cells_error != ok { ret (zero, cells_error) }
    var count = 0usize
    var at = 0usize
    while at < grid.specs.len {
        let band = band_of(grid, at)
        var width: f32 = 0.0
        var k = at
        while k < grid.specs.len && band_of(grid, k) == band {
            width += grid.columns[k].width
            k += 1usize
        }
        var cell_style = style.defaults()
        cell_style.width = style.Length { Px: width }
        var title = ""
        if band < grid.bands.len {
            title = grid.bands[band].title
            cell_style.background = paint.Brush { Solid: style.color(grid.theme.tokens, .SurfaceVariant) }
        }
        var inner: widget.Node = zero
        let node_error = text_node(a, grid, title, true, .Text, &inner)
        if node_error != ok { ret (zero, node_error) }
        cells[count] = widget.padded(0u64, 12.0, 4.0, 0.0, 4.0, cell_style, one(a, inner))
        count += 1usize
        at = k
    }
    ret (widget.flex(band_key(grid), ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), cells[0usize..count]), ok)
}

type NavPick = struct { grid: *Grid, kind: Nav }

// ---- horizontal scrolling (v3: the columns wider than the pane scroll, a thumb in the navigator row) ----

// The room of the thumb's track in the navigator row, after its buttons and the position text.
fn htrack(grid: *const Grid) -> f32 {
    var track = grid.hpane - 450.0
    // looks4-e: at 100 % the live capture's track runs from x = 246 to the pane's end
    if grid.look.on && grid.look.group_flat { track = grid.hpane - 245.0 }
    if track < 40.0 { track = 40.0 }
    ret track
}

// Where the vertical bar stands in a sideways-shifted body, relative to the end of the columns: the
// offset (read now: it moves between frames) plus the base measured with the pane.
fn bar_margin_of(grid: *const Grid) -> f32 {
    if !grid.hon { ret 0.0 }
    ret grid.hoff + grid.bar_shift
}

fn hthumb_width(grid: *const Grid) -> f32 {
    var w = htrack(grid)
    if grid.hcontent > 0.0 { w = htrack(grid) * grid.hpane / grid.hcontent }
    if w < 24.0 { w = 24.0 }
    ret w
}

// The node moved left by the scroll offset inside a clip of `h` high: the header, rows and footer
// shift together; the content is `content` wide.
fn hshift(a: *mem.Arena, grid: *Grid, node: widget.Node, content: f32, h: f32) -> (widget.Node, err) {
    let (plain, plain_error) = hshift_clipped(a, grid, node, content, h, 0.0)
    ret (plain, plain_error)
}

// `clip_w` > 0 clips the view to that width (the footer stops where the vertical bar's track begins).
fn hshift_clipped(a: *mem.Arena, grid: *Grid, node: widget.Node, content: f32, h: f32, clip_w: f32) -> (widget.Node, err) {
    var inner_style = style.defaults()
    inner_style.width = style.Length { Px: content }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, control.TooLarge) }
    held[0usize] = widget.box(0u64, inner_style, one(a, node))
    // a scroll view lets the content keep its columns' widths (a positioned child is clamped to the pane
    // plus the offset and the columns shrink, D2502); the offset is the grid's own
    var clip = style.defaults()
    clip.width = style.Length { Percent: 100.0 }
    if clip_w > 0.0 { clip.width = style.Length { Px: clip_w } }
    clip.height = style.Length { Px: h }
    clip.overflow = .Clip
    ret (widget.scroll(grid.key + 3960u64 + u64(h), widget.Scroll { axis: .Horizontal, offset: grid.hoff, overscroll: .Clamp, momentum: false, scrollbar: false, thumb: gl.rgb(0x000000u32), change: zero, virtual_first: 0usize, virtual_count: 0usize, virtual_extent: 0.0, fades: false, virtual_extras: zero }, clip, held[0usize..1usize]), ok)
}

fn on_hthumb(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .DragStart as at:
        grid.hgrab = grid.hoff
        ret ok
    case .Wheel as w:
        var moved = grid.hoff - w.notches * 60.0
        let most_w = grid.hcontent - grid.hpane
        if moved > most_w { moved = most_w }
        if moved < 0.0 { moved = 0.0 }
        grid.hoff = moved
        ret ok
    case .DragMove as d:
        let travel = htrack(grid) - hthumb_width(grid)
        if travel > 1.0 {
            var next = grid.hgrab + d.delta.x * (grid.hcontent - grid.hpane) / travel
            if next < 0.0 { next = 0.0 }
            let most = grid.hcontent - grid.hpane
            if next > most { next = most }
            grid.hoff = next
        }
        ret ok
    default:
        ret ok
    }
}

// The measure of the scrolling for this frame: whether the columns outgrow the pane.
fn measure_hscroll(grid: *Grid, theme: *const control.Theme) {
    var content: f32 = 0.0
    var c = 0usize
    while c < grid.columns.len {
        content += grid.columns[c].width
        c += 1usize
    }
    content += 18.0
    var pane: f32 = 0.0
    if mem.address_of(theme.runtime) != 0usize {
        let (box, has_box) = control.keyed_bounds(theme.runtime, grid.key + 3900u64)
        if has_box { pane = box.width }
    }
    if pane == 0.0 { pane = grid.pane_hint }
    grid.hon = false
    if grid.look.on && pane > 100.0 && content > pane + 1.0 && !grid.auto_width {
        grid.hon = true
        grid.hcontent = content
        grid.hpane = pane
        let most = content - pane
        if grid.hoff > most { grid.hoff = most }
        if grid.hoff < 0.0 { grid.hoff = 0.0 }
        // the vertical bar stays at the pane's right edge: where it would stand, at the end of the
        // columns, moved by the offset and the pane's width
        grid.bar_shift = pane - grid.look.scroll_width - (content - 18.0)
    } else {
        grid.hoff = 0.0
        grid.bar_shift = 0.0
    }
}

fn on_select_all(ctx: *void) -> err {
    select_all(mem.cast[*Grid](ctx))
    ret ok
}

fn on_extend(ctx: *void) -> err {
    let pick = mem.cast[*NavPick](ctx)
    ret extend_selection(pick.grid, pick.kind)
}

fn on_navigate(ctx: *void) -> err {
    let pick = mem.cast[*NavPick](ctx)
    ret navigate(pick.grid, pick.kind)
}

// First / Prev / Next / Last buttons and "Row n of m".
// A navigator button of the measured look: a blue arrow mark (grey where it cannot move).
fn nav_icon(a: *mem.Arena, grid: *Grid, key: widget.Key, kind: Nav, label: str, action: *const widget.Submit) -> (widget.Node, err) {
    let (position, has) = current_position(grid)
    let visible = grp.visible_len(grid.g)
    var enabled = visible != 0usize
    var shape = gl.Shape.Left
    if kind == Nav.First { shape = gl.Shape.FirstBar }
    if kind == Nav.Next { shape = gl.Shape.Right }
    if kind == Nav.Last { shape = gl.Shape.LastBar }
    if kind == Nav.PrevPage { shape = gl.Shape.DoubleLeft }
    if kind == Nav.NextPage { shape = gl.Shape.DoubleRight }
    if has {
        if (kind == Nav.First || kind == Nav.Prev || kind == Nav.PrevPage) && position == 0usize { enabled = false }
        if (kind == Nav.Next || kind == Nav.Last || kind == Nav.NextPage) && position + 1usize >= visible { enabled = false }
    }
    // looks4-e: with no current record v3 (live capture, "0 of 8") greys First, Previous page and Previous
    if !has && grid.look.on && grid.look.group_flat && (kind == Nav.First || kind == Nav.Prev || kind == Nav.PrevPage) { enabled = false }
    if !has && grid.look.on && grid.look.group_flat && (kind == Nav.Next || kind == Nav.Last || kind == Nav.NextPage) { enabled = true }
    var ink = gl.rgb(0x2C7BD6u32)
    if !enabled { ink = gl.rgb(0xC9D3E0u32) }
    var mark: widget.Node = zero
    var live_nav = false
    var live_w: f32 = 19.0
    if grid.look.on && grid.look.group_flat && !grid.has_nav_icons {
        // looks4-e: v3's own button bitmaps, cut from the live capture
        var slot = 2usize
        if kind == Nav.First { slot = 0usize }
        if kind == Nav.PrevPage { slot = 1usize }
        if kind == Nav.Next { slot = 3usize }
        if kind == Nav.NextPage { slot = 4usize }
        if kind == Nav.Last { slot = 5usize }
        live_w = gl.gx_nav_w(slot, enabled)
        if win_look(grid) { live_w = gl.gx_nav_win_w(slot, enabled) }
        // looks5-e: under the pointer v3 draws the button on a blue frame over #E0EEF9 (live hover captures)
        var live_pix = gl.gx_nav(slot, enabled)
        if win_look(grid) { live_pix = gl.gx_nav_win(slot, enabled) }
        var live_hot = false
        if enabled && (slot == 3usize || slot == 4usize) && mem.address_of(grid.theme.runtime) != 0usize && control.control_state(grid.theme, key, true, false).hovered {
            live_pix = gl.gx_nav_hot(slot)
            live_hot = true
        }
                // (the hover bitmaps were cut one column further left than the rest ones: their first column is left out, the node keeps its width)
        var live_skip = 0usize
        if live_hot && win_look(grid) { live_skip = 1usize }
        let (live_mark, live_error) = gl.pixels_skip(a, live_pix, live_w, gl.gx_nav_h(), live_skip)
        if live_error != ok { ret (zero, live_error) }
        mark = live_mark
        if live_hot && win_look(grid) { mark = widget.box(0u64, control.sized_style(live_w, gl.gx_nav_h()), one(a, live_mark)) }
        live_nav = true
    } else if grid.has_nav_icons {
        var picture_at = 0usize
        if kind == Nav.PrevPage { picture_at = 1usize }
        if kind == Nav.Prev { picture_at = 2usize }
        if kind == Nav.Next { picture_at = 3usize }
        if kind == Nav.NextPage { picture_at = 4usize }
        if kind == Nav.Last { picture_at = 5usize }
        var picture = grid.nav_icons[picture_at]
        if !enabled { picture = grid.nav_disabled[picture_at] }
        let (nav_picture, nav_picture_error) = control.image(a, 0u64, picture, 24.0, 30.0, .Contain, "")
        if nav_picture_error != ok { ret (zero, nav_picture_error) }
        mark = nav_picture
    } else {
        let (shape_mark, shape_error) = gl.mark(a, shape, ink, ink, 12.0, 12.0)
        if shape_error != ok { ret (zero, shape_error) }
        mark = shape_mark
    }
    let state = control.control_state(grid.theme, key, enabled, false)
    var look = style.resolve(grid.theme.tokens, .Plain, state)
    look.background = paint.rgba(0.0, 0.0, 0.0, 0.0)
    look.border_width = 0.0
    look.opacity = 1.0
    look.radius = 2.0
    look.custom_padding = true
    look.padding = 4.0
    look.padding_y = 3.0
    if grid.has_nav_icons {
        look.padding = 0.0
        look.padding_y = 0.0
    }
    look.min_width = 20.0
    look.min_height = 18.0
    if live_nav {
        look.padding = 0.0
        look.padding_y = 0.0
        look.radius = 0.0
        look.min_width = live_w
        look.min_height = gl.gx_nav_h()
    }
    let (node, node_error) = control.pressable_states(a, key, grid.theme, 3u8, label, look, enabled, false, 0u32, 0u32, 0u64, action, mark)
    if live_nav && node_error == ok {
        // buttons stand 22 apart (the first three, 19 wide, with 3 between; Previous 1 short of the position box)
        // looks9-w1: the Windows bitmaps run edge to edge (they carry the gap between two buttons themselves)
        if win_look(grid) { ret (node, node_error) }
        var after = 22.0 - live_w
        if kind == Nav.Prev { after = 20.0 - live_w }
        if after < 0.0 { after = 0.0 }
        ret (widget.padded(0u64, 0.0, 0.0, after, 0.0, style.defaults(), one(a, node)), ok)
    }
    ret (node, node_error)
}

// v3's navigator: first, previous page, previous, "n of m", next, next page, last and a funnel.
fn navigator_row_look(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let kinds: [6]Nav = [6]Nav{ Nav.First, Nav.PrevPage, Nav.Prev, Nav.Next, Nav.NextPage, Nav.Last }
    let keys: [6]u64 = [6]u64{ 1u64, 5u64, 2u64, 3u64, 6u64, 4u64 }
    let labels: [6]str = [6]str{ "First", "Previous page", "Previous", "Next", "Next page", "Last" }
    let (picks, picks_error) = mem.alloc[NavPick](a, 6usize)
    if picks_error != ok { ret (zero, picks_error) }
    let (submits, submits_error) = mem.alloc[widget.Submit](a, 6usize)
    if submits_error != ok { ret (zero, submits_error) }
    let (cells, cells_error) = mem.alloc[widget.Node](a, 9usize)
    if cells_error != ok { ret (zero, cells_error) }
    var at = 0usize
    while at < 6usize {
        picks[at] = NavPick { grid: grid, kind: kinds[at] }
        submits[at] = widget.Submit { ctx: mem.cast[*void](&picks[at]), invoke: on_navigate }
        let (icon, icon_error) = nav_icon(a, grid, navigator_key(grid) + keys[at], kinds[at], labels[at], &submits[at])
        if icon_error != ok { ret (zero, icon_error) }
        // the order on screen: First, PrevPage, Prev, text, Next, NextPage, Last, funnel
        var slot = at
        if at >= 3usize { slot = at + 1usize }
        cells[slot] = icon
        at += 1usize
    }
    let (b, b_error) = str.builder(a, 48usize)
    if b_error != ok { ret (zero, b_error) }
    var sb = b
    let (position, has) = current_position(grid)
    let (before, total) = data_counts(grid, position)
    if has {
        if str.push_usize(&sb, before + 1usize) != ok { ret (zero, control.TooLarge) }
    } else {
        if str.push(&sb, "0") != ok { ret (zero, control.TooLarge) }
    }
    if str.push(&sb, " of ") != ok || str.push_usize(&sb, total) != ok { ret (zero, control.TooLarge) }
    var text_options = control.text_options()
    text_options.size = grid.look.text_size
    let (info_text, info_error) = control.text(a, 0u64, str.done(&sb), grid.theme, text_options)
    if info_error != ok { ret (zero, info_error) }
    var info = info_text
    var live_row = grid.look.on && grid.look.group_flat && !grid.has_nav_icons
    if live_row {
        // looks4-e: v3's white position box: the text 5 in, 5 down, 4 after, 23 tall
        var band = control.sized_style(0.0, 23.0)
        band.width = style.Length { Px: 0.0 }
        var live_band = style.defaults()
        live_band.height = style.Length { Px: 23.0 }
        live_band.background = paint.Brush { Solid: skin(grid, 0xFFFFFFu32) }
        // looks5-e: v3's hinted text is wider than ours: the box follows the capture (the next buttons stand 3 px further)
        info = widget.padded(0u64, 5.0, 5.0, 7.0, 0.0, live_band, one(a, info_text))
    } else if grid.has_nav_icons {
        // v3 sets the position on a white band as wide as the gap between its buttons
        var band = control.sized_style(115.0, 30.0)
        band.background = paint.Brush { Solid: skin(grid, 0xFFFFFFu32) }
        info = widget.padded(0u64, 10.0, 8.0, 0.0, 0.0, band, one(a, info_text))
    }
    cells[3usize] = info
    // the funnel
    var funnel_ink = gl.rgb(0x8A8A8Au32)
    let funnel_key = navigator_key(grid) + 7u64
    var funnel_mark: widget.Node = zero
    if live_row {
        var funnel_pix = gl.gx_nav(7usize, true)
        if win_look(grid) { funnel_pix = gl.gx_nav_win(7usize, true) }
        if mem.address_of(grid.theme.runtime) != 0usize && control.control_state(grid.theme, funnel_key, true, false).hovered { funnel_pix = gl.gx_nav_hot(7usize) }
        let (live_funnel, live_funnel_error) = gl.pixels(a, funnel_pix, gl.gx_nav_win_w_if(win_look(grid), 7usize), gl.gx_nav_h())
        if live_funnel_error != ok { ret (zero, live_funnel_error) }
        funnel_mark = live_funnel
    } else if grid.has_nav_icons {
        let (funnel_picture, funnel_picture_error) = control.image(a, 0u64, grid.nav_icons[6usize], 24.0, 30.0, .Contain, "")
        if funnel_picture_error != ok { ret (zero, funnel_picture_error) }
        funnel_mark = funnel_picture
    } else {
        let (funnel_shape, funnel_error) = control.icon_square(a, funnel_ink, .Filter, 16.0)
        if funnel_error != ok { ret (zero, funnel_error) }
        funnel_mark = funnel_shape
    }
    let funnel_state = control.control_state(grid.theme, funnel_key, grid.has_filter_action, false)
    var funnel_look = style.resolve(grid.theme.tokens, .Plain, funnel_state)
    funnel_look.background = paint.rgba(0.0, 0.0, 0.0, 0.0)
    funnel_look.border_width = 0.0
    funnel_look.opacity = 1.0
    funnel_look.radius = 2.0
    funnel_look.custom_padding = true
    funnel_look.padding = 2.0
    funnel_look.padding_y = 1.0
    if grid.has_nav_icons {
        funnel_look.padding = 0.0
        funnel_look.padding_y = 0.0
    }
    funnel_look.min_width = 20.0
    funnel_look.min_height = 18.0
    if live_row {
        funnel_look.padding = 0.0
        funnel_look.padding_y = 0.0
        funnel_look.radius = 0.0
        funnel_look.min_width = gl.gx_nav_win_w_if(win_look(grid), 7usize)
        funnel_look.min_height = gl.gx_nav_h()
    }
    let (funnel, funnel_node_error) = control.pressable_states(a, funnel_key, grid.theme, 3u8, "Filter", funnel_look, grid.has_filter_action, false, 0u32, 0u32, 0u64, &grid.filter_action, funnel_mark)
    if funnel_node_error != ok { ret (zero, funnel_node_error) }
    cells[7usize] = funnel
    var shown = 8usize
    if grid.hon {
        // v3's scroll bar: a dark grey thumb to the right of the funnel, as long as the pane is of the columns
        // the thumb thickens under the pointer, as the vertical one does
        var thumb_h: f32 = 8.6
        if live_row { thumb_h = 8.0 }
        if mem.address_of(grid.theme) != 0usize && control.control_state(grid.theme, navigator_key(grid) + 9u64, true, false).hovered { thumb_h = 8.6 }
        var thumb = control.sized_style(hthumb_width(grid), thumb_h)
        thumb.background = paint.Brush { Solid: gl.rgb(0x808080u32) }
        if live_row {
            // looks4-e: v3's thumb is #858585 with a 1 px lighter rim (#BABABA) all round
            // looks5-e: under the pointer or pressed it is 12 thick (live hover and pressed captures), the ends rounded
            var hot_thumb = false
            if mem.address_of(grid.theme) != 0usize && mem.address_of(grid.theme.runtime) != 0usize {
                let hot_state = control.control_state(grid.theme, navigator_key(grid) + 9u64, true, false)
                hot_thumb = hot_state.hovered || hot_state.pressed
            }
            if hot_thumb { thumb_h = 12.0 }
            thumb = control.sized_style(hthumb_width(grid) + 2.0, thumb_h + 2.0)
            thumb.background = paint.Brush { Solid: gl.rgb(0x858585u32) }
            thumb.border = style.Border { width: 1.0, color: gl.rgb(0xBABABAu32) }
            if hot_thumb { thumb.radius = 4.0 }
        }
        var room = htrack(grid) - hthumb_width(grid)
        var left: f32 = 0.0
        if grid.hcontent > grid.hpane && room > 0.0 { left = room * grid.hoff / (grid.hcontent - grid.hpane) }
        var thumb_start: f32 = 14.0
        var thumb_top: f32 = 0.0
        if live_row { thumb_top = 1.0 }
        if live_row { thumb_start = 17.5 }
        var thumb_kids: []const widget.Node = zero
        if live_row && footer_edged_on(grid) && !hot_thumb_now(grid) {
            // looks9-w1: the thumb's soft ends reach two pixels further out than the bar's own width
            thumb = control.sized_style(hthumb_width(grid) + 4.0, 10.0)
            thumb_start = 15.5
            thumb_kids = one(a, nav_thumb(a, hthumb_width(grid) + 4.0))
        }
        thumb.margin = style.EdgeLengths { left: style.Length { Px: thumb_start + left }, top: style.Length { Px: thumb_top }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
        cells[8usize] = widget.region(navigator_key(grid) + 9u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](grid), invoke: on_hthumb }, gestures: 39u8, enabled: true, focusable: false }, thumb, thumb_kids)
        shown = 9usize
    }
    if live_row {
        // the undo arrow of an editing grid stands between the funnel's neighbour and the funnel
        var live_gap: f32 = 0.0
        if grid.immediate_edit {
            // an editing grid (v3's collection) has the undo arrow between Last and the funnel (not a live button here)
            let (with_undo, with_undo_error) = mem.alloc[widget.Node](a, shown + 1usize)
            if with_undo_error != ok { ret (zero, control.TooLarge) }
            var copy_at = 0usize
            var out_at = 0usize
            while copy_at < shown {
                if copy_at == 7usize {
                    var undo_pix = gl.gx_nav(6usize, true)
                    if win_look(grid) { undo_pix = gl.gx_nav_win(6usize, true) }
                    let (undo_pic, undo_error) = gl.pixels(a, undo_pix, gl.gx_nav_win_w_if(win_look(grid), 6usize), gl.gx_nav_h())
                    if undo_error != ok { ret (zero, undo_error) }
                    with_undo[out_at] = undo_pic
                    out_at += 1usize
                }
                with_undo[out_at] = cells[copy_at]
                out_at += 1usize
                copy_at += 1usize
            }
            var undo_style = style.defaults()
            undo_style.padding = style.EdgeLengths { left: style.Length { Px: nav_left(grid) }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
            let undone = widget.flex(navigator_key(grid), ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, undo_style, with_undo[0usize..shown + 1usize])
            if footer_edged_on(grid) { ret (nav_line_under(a, undone, grid.look.footer_band.red < grid.look.footer_band.green - 0.05), ok) }
            ret (undone, ok)
        }
        var live_style = style.defaults()
        live_style.padding = style.EdgeLengths { left: style.Length { Px: nav_left(grid) }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
        let live_flex = widget.flex(navigator_key(grid), ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: live_gap }, live_style, cells[0usize..shown])
        if footer_edged_on(grid) { ret (nav_line_under(a, live_flex, grid.look.footer_band.red < grid.look.footer_band.green - 0.05), ok) }
        ret (live_flex, ok)
    }
    ret (widget.flex(navigator_key(grid), ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 6.0 }, style.defaults(), cells[0usize..shown]), ok)
}

fn navigator_row(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    if grid.look.on {
        let (looked, looked_error) = navigator_row_look(a, grid)
        ret (looked, looked_error)
    }
    let labels: [4]str = [4]str{ "First", "Prev", "Next", "Last" }
    let (picks, picks_error) = mem.alloc[NavPick](a, 4usize)
    if picks_error != ok { ret (zero, picks_error) }
    let (submits, submits_error) = mem.alloc[widget.Submit](a, 4usize)
    if submits_error != ok { ret (zero, submits_error) }
    let (cells, cells_error) = mem.alloc[widget.Node](a, 5usize)
    if cells_error != ok { ret (zero, cells_error) }
    var at = 0usize
    while at < 4usize {
        var kind = Nav.First
        if at == 1usize { kind = Nav.Prev }
        if at == 2usize { kind = Nav.Next }
        if at == 3usize { kind = Nav.Last }
        picks[at] = NavPick { grid: grid, kind: kind }
        submits[at] = widget.Submit { ctx: mem.cast[*void](&picks[at]), invoke: on_navigate }
        if grid.look.on {
            let (icon, icon_error) = nav_icon(a, grid, navigator_key(grid) + 1u64 + u64(at), kind, labels[at], &submits[at])
            if icon_error != ok { ret (zero, icon_error) }
            cells[at] = icon
            at += 1usize
            continue
        }
        var options = control.button_options()
        options.variant = .Outlined
        let (button, button_error) = control.button(a, navigator_key(grid) + 1u64 + u64(at), grid.theme, labels[at], &submits[at], options)
        if button_error != ok { ret (zero, button_error) }
        cells[at] = button
        at += 1usize
    }
    let (b, b_error) = str.builder(a, 48usize)
    if b_error != ok { ret (zero, b_error) }
    var sb = b
    let (position, has) = current_position(grid)
    let (before, total) = data_counts(grid, position)
    if !grid.look.on && str.push(&sb, "Row ") != ok { ret (zero, control.TooLarge) }
    if has {
        if str.push_usize(&sb, before + 1usize) != ok { ret (zero, control.TooLarge) }
    } else {
        if str.push(&sb, "-") != ok { ret (zero, control.TooLarge) }
    }
    if str.push(&sb, " of ") != ok || str.push_usize(&sb, total) != ok { ret (zero, control.TooLarge) }
    let (info, info_error) = control.text(a, 0u64, str.done(&sb), grid.theme, control.text_options())
    if info_error != ok { ret (zero, info_error) }
    cells[4usize] = info
    ret (widget.flex(navigator_key(grid), ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, style.defaults(), cells[0usize..5usize]), ok)
}

// The filter row: a small text field under each column that asks for one.
fn filter_row(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, grid.specs.len)
    if cells_error != ok { ret (zero, cells_error) }
    let (picks, picks_error) = mem.alloc[FilterPick](a, grid.specs.len)
    if picks_error != ok { ret (zero, picks_error) }
    var at = 0usize
    while at < grid.specs.len {
        let s = grid.specs[at]
        let orig = grid.origin[at]
        picks[at] = FilterPick { grid: grid, spec: orig }
        var cell_style = style.defaults()
        cell_style.width = style.Length { Px: grid.columns[at].width }
        if s.filter {
            var options = control.field_options()
            options.placeholder = "filter"
            options.width = grid.columns[at].width - 12.0
            options.height = 36.0
            let buffer = grid.filter_text[orig * FILTER_TEXT..(orig + 1usize) * FILTER_TEXT]
            let (field, field_error) = control.text_field(a, grid.key + FILTER_KEY + u64(orig), grid.theme, s.title, buffer, grid.filter_lens[orig], widget.Change[str] { ctx: mem.cast[*void](&picks[at]), invoke: on_filter }, zero, options)
            if field_error != ok { ret (zero, field_error) }
            cells[at] = widget.padded(0u64, 0.0, 2.0, 0.0, 2.0, cell_style, one(a, field))
        } else {
            let (blank, blank_error) = control.text(a, 0u64, "", grid.theme, control.text_options())
            if blank_error != ok { ret (zero, blank_error) }
            cells[at] = widget.padded(0u64, 0.0, 2.0, 0.0, 2.0, cell_style, one(a, blank))
        }
        at += 1usize
    }
    ret (widget.flex(grid.key + FILTER_KEY - 1u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), cells[0usize..grid.specs.len]), ok)
}

// v3's filter row (G012, FR1-filter-row-v3): a white row of 28 px right under the header, in each
// filterable column the operator sign ("=") and a flat editor, nothing in the others.
fn v3_filter_row(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, grid.specs.len)
    if cells_error != ok { ret (zero, cells_error) }
    let (picks, picks_error) = mem.alloc[FilterPick](a, grid.specs.len)
    if picks_error != ok { ret (zero, picks_error) }
    // the row turns light blue (v3: #A6D2FF) while its editor holds the keyboard, the editor's cell white
    var held_spec: usize = grid.all.len + 1usize
    if mem.address_of(grid.theme) != 0usize && mem.address_of(grid.theme.runtime) != 0usize {
        let (held, has_held) = widget.focused_key(grid.theme.runtime)
        if has_held && held >= grid.key + FILTER_KEY && held < grid.key + FILTER_KEY + 1024u64 { held_spec = usize(held - grid.key - FILTER_KEY) }
    }
    var at = 0usize
    while at < grid.specs.len {
        let s = grid.specs[at]
        let orig = grid.origin[at]
        picks[at] = FilterPick { grid: grid, spec: orig }
        var cell_style = control.sized_style(grid.columns[at].width, 20.0)
        cell_style.background = paint.Brush { Solid: skin(grid, 0xFFFFFFu32) }
        if held_spec <= grid.all.len && held_spec != orig { cell_style.background = paint.Brush { Solid: gl.rgb(0xA6D2FFu32) } }
        if s.kind == CellKind.Indicator {
            // the funnel of the filter row stands in the indicator column
            let (funnel, funnel_error) = gl.pixels(a, gl.gx_funnel(), gl.gx_funnel_w(), gl.gx_funnel_h())
            if funnel_error != ok { ret (zero, funnel_error) }
            cells[at] = widget.padded(0u64, 1.0, 11.0, 0.0, 0.0, cell_style, one(a, funnel))
            at += 1usize
            continue
        }
        if s.filter {
            var sign_text: widget.Node = zero
            if grid.has_filter_op_icons {
                let (cell_pic, cell_pic_error) = control.image(a, 0u64, grid.filter_op_icons[usize(grid.filter_ops[orig])], 26.0, 20.0, .Contain, "")
                if cell_pic_error != ok { ret (zero, cell_pic_error) }
                sign_text = cell_pic
            } else if grid.filter_ops[orig] == 0u8 {
                // looks4-e: v3's equals mark (10 x 4, two dark bars), cut from the live capture
                let (equals_pic, equals_error) = gl.pixels(a, gl.gx_equals(), gl.gx_equals_w(), gl.gx_equals_h())
                if equals_error != ok { ret (zero, equals_error) }
                sign_text = equals_pic
            } else {
                let (sign_words, sign_error) = flat_text(a, grid, filter_op_sign(grid.filter_ops[orig]), gl.rgb(0x404040u32))
                if sign_error != ok { ret (zero, sign_error) }
                sign_text = sign_words
            }
            var sign_box = control.sized_style(34.0, 20.0)
            let sign = widget.region(grid.key + FILTER_KEY + 1100u64 + u64(orig), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&picks[at]), invoke: on_filter_sign }, gestures: 1u8, enabled: true, focusable: false }, sign_box, one(a, widget.padded(0u64, 6.0, 10.0, 0.0, 0.0, style.defaults(), one(a, sign_text))))
            let buffer = grid.filter_text[orig * FILTER_TEXT..(orig + 1usize) * FILTER_TEXT]
            var inner_width = grid.columns[at].width - 36.0
            var field_fill = skin(grid, 0xFFFFFFu32)
            if held_spec <= grid.all.len && held_spec != orig { field_fill = gl.rgb(0xA6D2FFu32) }
            if inner_width < 8.0 { inner_width = 8.0 }
            let (field, field_error) = control.bare_field(a, grid.key + FILTER_KEY + u64(orig), grid.theme, s.title, buffer, grid.filter_lens[orig], widget.Change[str] { ctx: mem.cast[*void](&picks[at]), invoke: on_filter }, zero, inner_width, 18.0, grid.look.text_size, field_fill, field_fill)
            if field_error != ok { ret (zero, field_error) }
            let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
            if pair_error != ok { ret (zero, control.TooLarge) }
            pair[0usize] = sign
            pair[1usize] = widget.padded(0u64, 0.0, 2.0, 0.0, 0.0, style.defaults(), one(a, field))
            cells[at] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, cell_style, pair[0usize..2usize])
        } else {
            cells[at] = widget.box(0u64, cell_style, zero)
        }
        at += 1usize
    }
    // looks4-e: each filter cell ends in the grid's two-pixel line (#E3E3E3, #F8F8F8)
    var line_at = 0usize
    while line_at < grid.specs.len {
        var edge_a = control.sized_style(1.0, 20.0)
        edge_a.background = paint.Brush { Solid: skin(grid, 0xE3E3E3u32) }
        var edge_b = control.sized_style(1.0, 20.0)
        edge_b.background = paint.Brush { Solid: skin(grid, 0xF8F8F8u32) }
        let (edged, edged_error) = mem.alloc[widget.Node](a, 3usize)
        if edged_error != ok { ret (zero, control.TooLarge) }
        edged[0usize] = cells[line_at]
        edged[1usize] = widget.positioned(0u64, grid.columns[line_at].width - 2.0, 0.0, style.defaults(), one(a, widget.box(0u64, edge_a, zero)))
        edged[2usize] = widget.positioned(0u64, grid.columns[line_at].width - 1.0, 0.0, style.defaults(), one(a, widget.box(0u64, edge_b, zero)))
        cells[line_at] = widget.stack(0u64, control.sized_style(grid.columns[line_at].width, 20.0), edged[0usize..3usize])
        line_at += 1usize
    }
    let filter_cells = widget.flex(grid.key + FILTER_KEY - 1u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), cells[0usize..grid.specs.len])
    // looks4-e: v3's header block ends in two 1 px lines (#EBEBEB, #DCDCDC) from the first column on
    let (stack, stack_error) = mem.alloc[widget.Node](a, 3usize)
    if stack_error != ok { ret (zero, control.TooLarge) }
    var line_a = control.sized_style(4000.0, 1.0)
    line_a.background = paint.Brush { Solid: skin(grid, 0xEBEBEBu32) }
    line_a.margin = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    var line_b = control.sized_style(4000.0, 1.0)
    line_b.background = paint.Brush { Solid: skin(grid, 0xDCDCDCu32) }
    line_b.margin = line_a.margin
    stack[0usize] = filter_cells
    stack[1usize] = widget.box(0u64, line_a, zero)
    stack[2usize] = widget.box(0u64, line_b, zero)
    // then a strip of four pixels before the first row (a #F0F0F0 line, three white ones), as the capture shows
    let (full, full_error) = mem.alloc[widget.Node](a, 5usize)
    if full_error != ok { ret (zero, control.TooLarge) }
    var rim = control.sized_style(4000.0, 1.0)
    rim.background = paint.Brush { Solid: skin(grid, 0xF0F0F0u32) }
    rim.margin = line_a.margin
    var white_strip = control.sized_style(4000.0, 3.0)
    white_strip.background = paint.Brush { Solid: skin(grid, 0xFFFFFFu32) }
    white_strip.margin = line_a.margin
    full[0usize] = filter_cells
    full[1usize] = stack[1usize]
    full[2usize] = stack[2usize]
    full[3usize] = widget.box(0u64, rim, zero)
    full[4usize] = widget.box(0u64, white_strip, zero)
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), full[0usize..5usize]), ok)
}

fn row_filter_active(grid: *const Grid) -> bool {
    var at = 0usize
    while at < grid.all.len {
        if grid.filter_lens[at] != 0usize { ret true }
        at += 1usize
    }
    ret false
}

// "(Name Equals zzzq)": the filter row's conditions as v3's filter panel writes them.
fn filter_summary(a: *mem.Arena, grid: *const Grid) -> (str, err) {
    let (b, b_error) = str.builder(a, 200usize)
    if b_error != ok { ret ("", b_error) }
    var sb = b
    if str.push(&sb, "(") != ok { ret ("", control.TooLarge) }
    var first = true
    var at = 0usize
    while at < grid.all.len {
        if grid.filter_lens[at] != 0usize {
            if !first && str.push(&sb, " And ") != ok { ret ("", control.TooLarge) }
            first = false
            if str.push(&sb, grid.all[at].title) != ok || str.push(&sb, " ") != ok || str.push(&sb, filter_op_words(grid.filter_ops[at])) != ok || str.push(&sb, " ") != ok { ret ("", control.TooLarge) }
            if str.push(&sb, grid.filter_text[at * FILTER_TEXT..at * FILTER_TEXT + grid.filter_lens[at]]) != ok { ret ("", control.TooLarge) }
        }
        at += 1usize
    }
    if str.push(&sb, ")") != ok { ret ("", control.TooLarge) }
    ret (str.done(&sb), ok)
}

// The x of the filter panel: clears every filter-row condition.
fn on_filter_clear(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        var spec = 0usize
        while spec < grid.all.len {
            if grid.filter_lens[spec] != 0usize {
                grid.filter_lens[spec] = 0usize
                let changed_error = grid.events.filter_changed(grid.events.ctx, spec, "")
                if changed_error != ok { ret changed_error }
            }
            spec += 1usize
        }
        ret ok
    default:
        ret ok
    }
}

// The tick of the filter panel: suspends the filter-row conditions (the grid shows every row, the conditions
// stay in their cells) or applies them again.
fn on_filter_toggle(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        grid.filter_off = !grid.filter_off
        var spec = 0usize
        while spec < grid.all.len {
            if grid.filter_lens[spec] != 0usize {
                var value = filter_value(grid, spec)
                if grid.filter_off { value = "" }
                let changed_error = grid.events.filter_changed(grid.events.ctx, spec, value)
                if changed_error != ok { ret changed_error }
            }
            spec += 1usize
        }
        ret ok
    default:
        ret ok
    }
}

// Customize... on the filter panel opens the Advanced Filter.
fn on_filter_customize(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Tap as at:
        open_criteria_editor(grid)
        ret ok
    default:
        ret ok
    }
}

fn filter_panel_button(a: *mem.Arena, grid: *Grid, text: str, fill: u32, ink: u32, width: f32, key: u64, kind: u8) -> (widget.Node, err) {
    let (label, label_error) = flat_text(a, grid, text, gl.rgb(ink))
    if label_error != ok { ret (zero, label_error) }
    var box = control.sized_style(width, 22.0)
    box.background = paint.Brush { Solid: gl.rgb(fill) }
    box.radius = 3.0
    box.margin = style.EdgeLengths { left: style.Length { Px: 6.0 }, top: style.Length { Px: 4.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    let held = widget.padded(0u64, 6.0, 2.0, 0.0, 0.0, style.defaults(), one(a, label))
    if kind == 0u8 { ret (widget.box(0u64, box, one(a, held)), ok) }
    if kind == 3u8 { ret (widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](grid), invoke: on_filter_toggle }, gestures: 1u8, enabled: true, focusable: false }, box, one(a, held)), ok) }
    if kind == 2u8 { ret (widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](grid), invoke: on_filter_customize }, gestures: 1u8, enabled: true, focusable: false }, box, one(a, held)), ok) }
    ret (widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](grid), invoke: on_filter_clear }, gestures: 1u8, enabled: true, focusable: false }, box, one(a, held)), ok)
}

// v3's filter panel above the navigator: clear, enabled, the conditions, Customize...
fn filter_panel_row(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, 4usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    let (clear, clear_error) = filter_panel_button(a, grid, "x", 0xC85050u32, 0xFFFFFFu32, 22.0, grid.key + MENU_KEY + 850880u64, 1u8)
    if clear_error != ok { ret (zero, clear_error) }
    cells[0usize] = clear
    let (tick, tick_error) = filter_panel_button(a, grid, "v", tick_fill(grid), 0xFFFFFFu32, 22.0, grid.key + MENU_KEY + 850882u64, 3u8)
    if tick_error != ok { ret (zero, tick_error) }
    cells[1usize] = tick
    let (summary, summary_error) = filter_summary(a, grid)
    if summary_error != ok { ret (zero, summary_error) }
    let (words, words_error) = flat_text(a, grid, summary, gl.rgb(0x000000u32))
    if words_error != ok { ret (zero, words_error) }
    cells[2usize] = widget.padded(0u64, 12.0, 8.0, 0.0, 0.0, style.defaults(), one(a, words))
    let (custom, custom_error) = filter_panel_button(a, grid, "Customize...", 0xFDFDFDu32, 0x000000u32, 100.0, grid.key + MENU_KEY + 850881u64, 2u8)
    if custom_error != ok { ret (zero, custom_error) }
    cells[3usize] = widget.padded(0u64, 40.0, 0.0, 0.0, 0.0, style.defaults(), one(a, custom))
    var bar = style.defaults()
    bar.height = style.Length { Px: 30.0 }
    bar.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, bar, cells[0usize..4usize]), ok)
}

// looks9-w1: the Windows look's measured grid details (live 100 % captures of the main window) apply to the Windows profile only
fn win_look(grid: *const Grid) -> bool { ret grid.look.on && grid.theme.tokens.profile == .Windows }

fn footer_edged_on(grid: *const Grid) -> bool { ret grid.look.footer_edges && win_look(grid) }

fn nav_left(grid: *const Grid) -> f32 {
    if win_look(grid) { ret 0.0 }
    ret 1.0
}

// looks9-w1: one pixel box at (x, y) of a stack
fn footer_px(a: *mem.Arena, x: f32, y: f32, w: f32, h: f32, value: u32) -> widget.Node {
    var s = control.sized_style(w, h)
    s.background = paint.Brush { Solid: gl.rgb(value) }
    ret widget.positioned(0u64, x, y, style.defaults(), one(a, widget.box(0u64, s, zero)))
}

// looks9-w1: v3's footer cell (live captures) is 20 tall with its own edge pixels. `pal` holds, in order: the band row on top (left px, middle,
// right px), the edge row under it (left px, second px, middle, second last, right px), the body rows' (left, second, second last, right),
// the edge row above the foot (same five) and the band row at the foot (left, middle, right). The body (#E7EAEA) is `cell`, 18 tall,
// standing one row down.
fn footer_edged(a: *mem.Arena, cell: widget.Node, w: f32, pal: [20]u32) -> widget.Node {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 24usize)
    if parts_error != ok { ret cell }
    parts[0usize] = widget.positioned(0u64, 0.0, 1.0, style.defaults(), one(a, cell))
    var n = 1usize
    // rows 0, 19: left px, middle, right px
    parts[n] = footer_px(a, 0.0, 0.0, 1.0, 1.0, pal[0usize])
    parts[n + 1usize] = footer_px(a, 1.0, 0.0, w - 2.0, 1.0, pal[1usize])
    parts[n + 2usize] = footer_px(a, w - 1.0, 0.0, 1.0, 1.0, pal[2usize])
    parts[n + 3usize] = footer_px(a, 0.0, 19.0, 1.0, 1.0, pal[17usize])
    parts[n + 4usize] = footer_px(a, 1.0, 19.0, w - 2.0, 1.0, pal[18usize])
    parts[n + 5usize] = footer_px(a, w - 1.0, 19.0, 1.0, 1.0, pal[19usize])
    n += 6usize
    // rows 1 and 18
    parts[n] = footer_px(a, 0.0, 1.0, 1.0, 1.0, pal[3usize])
    parts[n + 1usize] = footer_px(a, 1.0, 1.0, 1.0, 1.0, pal[4usize])
    parts[n + 2usize] = footer_px(a, 2.0, 1.0, w - 4.0, 1.0, pal[5usize])
    parts[n + 3usize] = footer_px(a, w - 2.0, 1.0, 1.0, 1.0, pal[6usize])
    parts[n + 4usize] = footer_px(a, w - 1.0, 1.0, 1.0, 1.0, pal[7usize])
    parts[n + 5usize] = footer_px(a, 0.0, 18.0, 1.0, 1.0, pal[12usize])
    parts[n + 6usize] = footer_px(a, 1.0, 18.0, 1.0, 1.0, pal[13usize])
    parts[n + 7usize] = footer_px(a, 2.0, 18.0, w - 4.0, 1.0, pal[14usize])
    parts[n + 8usize] = footer_px(a, w - 2.0, 18.0, 1.0, 1.0, pal[15usize])
    parts[n + 9usize] = footer_px(a, w - 1.0, 18.0, 1.0, 1.0, pal[16usize])
    n += 10usize
    // body rows 2 to 17
    parts[n] = footer_px(a, 0.0, 2.0, 1.0, 16.0, pal[8usize])
    parts[n + 1usize] = footer_px(a, 1.0, 2.0, 1.0, 16.0, pal[9usize])
    parts[n + 2usize] = footer_px(a, w - 2.0, 2.0, 1.0, 16.0, pal[10usize])
    parts[n + 3usize] = footer_px(a, w - 1.0, 2.0, 1.0, 16.0, pal[11usize])
    n += 4usize
    ret widget.stack(0u64, control.sized_style(w, 20.0), parts[0usize..n])
}

// the two palettes of `footer_edged`: the collection grid's green band, the pool grid's yellow one
fn footer_palette(green: bool) -> [20]u32 {
    if green {
        ret [20]u32{ 0xC8DAC8u32, 0xC8DAC8u32, 0xC8DAC8u32, 0xD0D8D0u32, 0xDCDDDDu32, 0xDCDDDDu32, 0xDCDDDDu32, 0xC7DAC7u32, 0xD0D8D0u32, 0xE2E5E5u32, 0xDBDCDCu32, 0xC7DAC7u32, 0xD0D8D0u32, 0xE1E3E3u32, 0xE1E3E3u32, 0xE1E3E3u32, 0xC7DAC7u32, 0xCED8CEu32, 0xCED8CEu32, 0xCED8CEu32 }
    }
    ret [20]u32{ 0xEFEFDAu32, 0xEAEAD9u32, 0xF8F8DCu32, 0xE1E1D8u32, 0xDDDDDEu32, 0xDFE0E0u32, 0xD9DADAu32, 0xF1F1DBu32, 0xE1E1D8u32, 0xE3E5E5u32, 0xDCDDDDu32, 0xF1F1DBu32, 0xE1E1D8u32, 0xDCDDDDu32, 0xDEE0E0u32, 0xD9D9D9u32, 0xF1F1DBu32, 0xF0F0DAu32, 0xEBEBDAu32, 0xF8F8DCu32 }
}

fn hot_thumb_now(grid: *const Grid) -> bool {
    if mem.address_of(grid.theme) == 0usize || mem.address_of(grid.theme.runtime) == 0usize { ret false }
    let hot_state = control.control_state(grid.theme, navigator_key(grid) + 9u64, true, false)
    ret hot_state.hovered || hot_state.pressed
}

// looks9-w1: v3's navigator has a #FAFAFA row on top (the buttons stand over it)
fn nav_line_under(a: *mem.Arena, row: widget.Node, green: bool) -> widget.Node {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret row }
    var line_value = 0xF7F7F7u32
    if green { line_value = 0xFAFAFAu32 }
    parts[0usize] = footer_px(a, 0.0, 0.0, 4000.0, 1.0, line_value)
    parts[1usize] = row
    ret widget.stack(0u64, style.defaults(), parts[0usize..2usize])
}

// looks9-w1: the navigator's horizontal thumb as v3 draws it (live capture): `w` wide, 10 tall, a #CACACA top row, an #AAAAAA bottom
// row, a soft two-pixel end each side
fn nav_thumb(a: *mem.Arena, w: f32) -> widget.Node {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 14usize)
    if parts_error != ok { ret widget.spacer(0u64, 0.0) }
    parts[0usize] = footer_px(a, 0.0, 0.0, w, 10.0, 0x858585u32)
    parts[1usize] = footer_px(a, 2.0, 0.0, w - 4.0, 1.0, 0xCACACAu32)
    parts[2usize] = footer_px(a, 2.0, 9.0, w - 4.0, 1.0, 0xAAAAAAu32)
    parts[3usize] = footer_px(a, 0.0, 1.0, 1.0, 8.0, 0xABABABu32)
    parts[4usize] = footer_px(a, 1.0, 1.0, 1.0, 8.0, 0x888888u32)
    parts[5usize] = footer_px(a, w - 2.0, 1.0, 1.0, 8.0, 0x8F8F8Fu32)
    parts[6usize] = footer_px(a, w - 1.0, 1.0, 1.0, 8.0, 0xD3D3D3u32)
    parts[7usize] = footer_px(a, 0.0, 0.0, 1.0, 1.0, 0xD7D7D7u32)
    parts[8usize] = footer_px(a, 1.0, 0.0, 1.0, 1.0, 0xCBCBCBu32)
    parts[9usize] = footer_px(a, w - 2.0, 0.0, 1.0, 1.0, 0xCDCDCDu32)
    parts[10usize] = footer_px(a, w - 1.0, 0.0, 1.0, 1.0, 0xE6E6E6u32)
    parts[11usize] = footer_px(a, 0.0, 9.0, 1.0, 1.0, 0xC3C3C3u32)
    parts[12usize] = footer_px(a, 1.0, 9.0, 1.0, 1.0, 0xACACACu32)
    parts[13usize] = footer_px(a, w - 2.0, 9.0, 1.0, 1.0, 0xB0B0B0u32)
    var s = control.sized_style(w, 10.0)
    ret widget.stack(0u64, s, parts[0usize..14usize])
}

// A row of the footer: the column summaries under their columns.
fn footer_row(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, grid.specs.len)
    if cells_error != ok { ret (zero, cells_error) }
    // v3's footer counts under the first text column ("Count: 120281" in the pool, "Rows: 8" in the
    // collection), centred in a #E7EAEA cell; the other summaries sit under their own columns
    var count_at = grid.specs.len
    var probe = 0usize
    while probe < grid.specs.len && count_at == grid.specs.len {
        let k = grid.specs[probe].kind
        if k == CellKind.Text && grid.specs[probe].summary < 0 { count_at = probe }
        probe += 1usize
    }
    if grid.count_spec != 0usize && grid.count_spec - 1usize < grid.specs.len { count_at = grid.count_spec - 1usize }
    let live_footer = grid.look.on && grid.look.group_flat
    var at = 0usize
    while at < grid.specs.len {
        let s = grid.specs[at]
        var text = ""
        if at == count_at {
            let (b, b_error) = str.builder(a, 40usize)
            if b_error != ok { ret (zero, b_error) }
            var sb = b
            var label = grid.footer_label
            if label.len == 0usize { label = "Count" }
            if str.push(&sb, label) != ok || str.push(&sb, ":") != ok { ret (zero, control.TooLarge) }
            // v3 leaves the number out when the grid is empty
            if grp.row_count(grid.g) != 0usize {
                if str.push(&sb, " ") != ok || str.push_usize(&sb, grp.row_count(grid.g)) != ok { ret (zero, control.TooLarge) }
            }
            text = str.done(&sb)
        } else if s.summary >= 0 && usize(s.summary) < grid.g.specs.len {
            let (shown, shown_error) = summary_text(a, s, grp.footer_summary(grid.g, usize(s.summary)))
            if shown_error != ok { ret (zero, shown_error) }
            text = shown
        }
        var inner: widget.Node = zero
        let node_error = text_node(a, grid, text, !grid.look.group_flat, .Text, &inner)
        if node_error != ok { ret (zero, node_error) }
        var cell_style = style.defaults()
        cell_style.width = style.Length { Px: grid.columns[at].width }
        if grid.look.on && text.len != 0usize { cell_style.background = paint.Brush { Solid: grid.look.footer_cell } }
        if live_footer && s.kind == CellKind.Indicator { cell_style.background = paint.Brush { Solid: skin(grid, 0xF0F0F0u32) } }
        // looks9-w1: the indicator's footer cell is 11 wide in the live capture (its last column a #BCBCBC line)
        if live_footer && footer_edged_on(grid) && s.kind == CellKind.Indicator { cell_style.width = style.Length { Px: grid.columns[at].width - 1.0 } }
        if grid.look.on && text.len != 0usize {
            // v3 (FR-footer recording): the count sits at the left of its cell, a whole number is
            // centred, an amount stands at the right
            let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
            if held_error != ok { ret (zero, control.TooLarge) }
            held[0usize] = inner
            cell_style.height = style.Length { Px: grid.look.row_height + 4.0 }
            if live_footer { cell_style.height = style.Length { Px: 18.0 } }
            if at == count_at {
                cells[at] = widget.padded(0u64, 4.0, 3.0, 0.0, 0.0, cell_style, held[0usize..1usize])
            } else if s.kind == CellKind.Currency || s.kind == CellKind.Real {
                cells[at] = widget.aligned(0u64, .End, .Center, cell_style, held[0usize..1usize])
            } else {
                cells[at] = widget.aligned(0u64, .Center, .Center, cell_style, held[0usize..1usize])
            }
        } else {
            cells[at] = widget.padded(0u64, 12.0, 4.0, 0.0, 4.0, cell_style, one(a, inner))
        }
        // looks9-w1: the live footer's cell is an 18 px box with its own edge pixels, a 2 px band gap between two cells
        if live_footer && footer_edged_on(grid) && text.len != 0usize { cells[at] = footer_edged(a, cells[at], grid.columns[at].width, footer_palette(grid.look.footer_band.red < grid.look.footer_band.green - 0.05)) }
        if live_footer && footer_edged_on(grid) && text.len == 0usize && s.kind == CellKind.Indicator {
            let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
            if pair_error != ok { ret (zero, control.TooLarge) }
            pair[0usize] = cells[at]
            pair[1usize] = footer_px(a, grid.columns[at].width - 2.0, 0.0, 1.0, 20.0, 0xBCBCBCu32)
            cells[at] = widget.stack(0u64, control.sized_style(grid.columns[at].width - 1.0, 20.0), pair[0usize..2usize])
        }
        if live_footer && footer_edged_on(grid) && text.len == 0usize && s.kind == CellKind.Picture {
            let (trio, trio_error) = mem.alloc[widget.Node](a, 3usize)
            if trio_error != ok { ret (zero, control.TooLarge) }
            trio[0usize] = cells[at]
            trio[1usize] = footer_px(a, 0.0, 0.0, 1.0, 20.0, 0xEBEEF2u32)
            trio[2usize] = footer_px(a, 1.0, 0.0, 1.0, 20.0, 0xC7E0C8u32)
            cells[at] = widget.stack(0u64, control.sized_style(grid.columns[at].width, 20.0), trio[0usize..3usize])
        }
        at += 1usize
    }
    var band_style = style.defaults()
    if grid.look.on { band_style.background = paint.Brush { Solid: grid.look.footer_band } }
    if live_footer {
        // looks4-e: v3's footer is 24 px: two light lines, a 20 px band, two darker lines (measured on the live
        // capture; the yellow band's and the green band's lines differ)
        band_style.height = style.Length { Px: 20.0 }
        var green = grid.look.footer_band.red < grid.look.footer_band.green - 0.05
        var top_one = gl.rgb(0xF2F4F6u32)
        var top_two = gl.rgb(0xFAFBECu32)
        var bottom_one = gl.rgb(0xD9D9C8u32)
        var bottom_two = gl.rgb(0xDADADAu32)
        if green {
            top_one = gl.rgb(0xEBE9E9u32)
            top_two = gl.rgb(0xE1EDE6u32)
            bottom_one = gl.rgb(0xBCCEBCu32)
            bottom_two = gl.rgb(0xCACACAu32)
            if footer_edged_on(grid) { bottom_two = gl.rgb(0xCFCFCFu32) }
        }
        let (rows, rows_error) = mem.alloc[widget.Node](a, 5usize)
        if rows_error != ok { ret (zero, control.TooLarge) }
        var l0 = control.sized_style(4000.0, 1.0)
        l0.background = paint.Brush { Solid: top_one }
        var l1 = control.sized_style(4000.0, 1.0)
        l1.background = paint.Brush { Solid: top_two }
        var l2 = control.sized_style(4000.0, 1.0)
        l2.background = paint.Brush { Solid: bottom_one }
        var l3 = control.sized_style(4000.0, 1.0)
        l3.background = paint.Brush { Solid: bottom_two }
        rows[0usize] = widget.box(0u64, l0, zero)
        rows[1usize] = widget.box(0u64, l1, zero)
        rows[2usize] = widget.flex(footer_key(grid), ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, band_style, cells[0usize..grid.specs.len])
        rows[3usize] = widget.box(0u64, l2, zero)
        rows[4usize] = widget.box(0u64, l3, zero)
        ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), rows[0usize..5usize]), ok)
    }
    ret (widget.flex(footer_key(grid), ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, band_style, cells[0usize..grid.specs.len]), ok)
}

// The keyboard of the grid (v3's): Up and Down move the current row by one, PageUp and PageDown by a
// page, Home and End to the first and the last; in a scope round the grid, so a text field or an
// editor that takes the key keeps it.
fn with_keys(a: *mem.Arena, grid: *Grid, node: widget.Node) -> (widget.Node, err) {
    let (picks, picks_error) = mem.alloc[NavPick](a, 6usize)
    if picks_error != ok { ret (zero, control.TooLarge) }
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 100usize)
    if shortcuts_error != ok { ret (zero, control.TooLarge) }
    let codes: [6]u32 = [6]u32{ 38u32, 40u32, 33u32, 34u32, 36u32, 35u32 }
    let kinds: [6]Nav = [6]Nav{ Nav.Prev, Nav.Next, Nav.PrevPage, Nav.NextPage, Nav.First, Nav.Last }
    var none: input.Modifiers = zero
    var at = 0usize
    while at < 6usize {
        picks[at] = NavPick { grid: grid, kind: kinds[at] }
        shortcuts[at] = widget.Shortcut { key: codes[at], modifiers: none, action: widget.Submit { ctx: mem.cast[*void](&picks[at]), invoke: on_navigate } }
        at += 1usize
    }
    var tab_count = 6usize
    if grid.immediate_edit {
        shortcuts[6usize] = widget.Shortcut { key: 9u32, modifiers: none, action: widget.Submit { ctx: mem.cast[*void](grid), invoke: on_row_tab } }
        tab_count = 7usize
    }
    shortcuts[tab_count] = widget.Shortcut { key: 13u32, modifiers: none, action: widget.Submit { ctx: mem.cast[*void](grid), invoke: on_row_enter } }
    tab_count += 1usize
    if grid.multi {
        // Ctrl+A selects every row; Shift+Up and Shift+Down extend the selection
        var with_control: input.Modifiers = zero
        with_control.control = true
        var with_shift: input.Modifiers = zero
        with_shift.shift = true
        shortcuts[tab_count] = widget.Shortcut { key: 65u32, modifiers: with_control, action: widget.Submit { ctx: mem.cast[*void](grid), invoke: on_select_all } }
        shortcuts[tab_count + 1usize] = widget.Shortcut { key: 38u32, modifiers: with_shift, action: widget.Submit { ctx: mem.cast[*void](&picks[0usize]), invoke: on_extend } }
        shortcuts[tab_count + 2usize] = widget.Shortcut { key: 40u32, modifiers: with_shift, action: widget.Submit { ctx: mem.cast[*void](&picks[1usize]), invoke: on_extend } }
        tab_count += 3usize
    }
    // Ctrl+Down / Ctrl+Up: the next and the previous search match; Ctrl+1 goes to the bookmark,
    // Ctrl+Shift+1 sets or clears it
    var ctrl_only: input.Modifiers = zero
    ctrl_only.control = true
    var ctrl_shift: input.Modifiers = zero
    ctrl_shift.control = true
    ctrl_shift.shift = true
    shortcuts[tab_count] = widget.Shortcut { key: 40u32, modifiers: ctrl_only, action: widget.Submit { ctx: mem.cast[*void](grid), invoke: on_search_next } }
    shortcuts[tab_count + 1usize] = widget.Shortcut { key: 38u32, modifiers: ctrl_only, action: widget.Submit { ctx: mem.cast[*void](grid), invoke: on_search_prev } }
    shortcuts[tab_count + 2usize] = widget.Shortcut { key: 49u32, modifiers: ctrl_only, action: widget.Submit { ctx: mem.cast[*void](grid), invoke: on_bookmark_goto } }
    shortcuts[tab_count + 3usize] = widget.Shortcut { key: 49u32, modifiers: ctrl_shift, action: widget.Submit { ctx: mem.cast[*void](grid), invoke: on_bookmark_toggle } }
    var ctrl_alt: input.Modifiers = zero
    ctrl_alt.control = true
    ctrl_alt.alt = true
    shortcuts[tab_count + 4usize] = widget.Shortcut { key: 67u32, modifiers: ctrl_alt, action: widget.Submit { ctx: mem.cast[*void](grid), invoke: on_open_chooser } }
    tab_count += 5usize
    if grid.has_search {
        // type-ahead: a shortcut per letter, digit and space, plain and with Shift, and Backspace
        let (chars, chars_error) = mem.alloc[SearchKey](a, 38usize)
        if chars_error != ok { ret (zero, control.TooLarge) }
        var typed_at = 0usize
        var vk = 32u32
        while vk <= 90u32 {
            if vk == 32u32 || (vk >= 48u32 && vk <= 57u32) || vk >= 65u32 {
                var ch = u8(vk)
                if vk >= 65u32 { ch = u8(vk + 32u32) }
                chars[typed_at] = SearchKey { grid: grid, ch: ch }
                shortcuts[tab_count] = widget.Shortcut { key: vk, modifiers: none, action: widget.Submit { ctx: mem.cast[*void](&chars[typed_at]), invoke: on_search_char } }
                var with_shift: input.Modifiers = zero
                with_shift.shift = true
                shortcuts[tab_count + 1usize] = widget.Shortcut { key: vk, modifiers: with_shift, action: widget.Submit { ctx: mem.cast[*void](&chars[typed_at]), invoke: on_search_char } }
                tab_count += 2usize
                typed_at += 1usize
            }
            vk += 1u32
        }
        chars[typed_at] = SearchKey { grid: grid, ch: 8u8 }
        shortcuts[tab_count] = widget.Shortcut { key: 8u32, modifiers: none, action: widget.Submit { ctx: mem.cast[*void](&chars[typed_at]), invoke: on_search_char } }
        tab_count += 1usize
    }
    var held: [1]widget.Node = zero
    let (holder, holder_error) = mem.alloc[widget.Node](a, 1usize)
    if holder_error != ok { ret (zero, control.TooLarge) }
    holder[0usize] = node
    var no_action: widget.Submit = zero
    let scope = widget.scope(grid.key + KEYBOARD_KEY, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..tab_count], default_action: no_action, cancel_action: widget.Submit { ctx: mem.cast[*void](grid), invoke: on_search_cancel }, keys: zero }, style.defaults(), holder[0usize..1usize])
    ret (scope, ok)
}

// The group box: a panel with a white chip (field name and triangle) for each grouping level.
// A header dropped on the group box asks to group by its column; the application takes the request
// (`take_group_drop`, the table column) and groups, as its menus do.
fn on_group_drop(ctx: *void, g: widget.Gesture) -> err {
    let grid = mem.cast[*Grid](ctx)
    switch g {
    case .Drop as d:
        let tag = collection.header_payload_tag()
        if d.payload <= tag || d.payload > tag + 4096u64 { ret ok }
        let shown = usize(d.payload - tag - 1u64)
        if shown >= grid.specs.len { ret ok }
        grid.group_drop_spec = grid.specs[shown].column
        grid.group_drop_pending = true
        ret ok
    default:
        ret ok
    }
}

fn take_group_drop(grid: *Grid) -> (usize, bool) {
    if !grid.group_drop_pending { ret (0usize, false) }
    grid.group_drop_pending = false
    ret (grid.group_drop_spec, true)
}

type ChipTap = struct { grid: *Grid, level: usize }

fn on_chip_gesture(ctx: *void, g: widget.Gesture) -> err {
    let tap = mem.cast[*ChipTap](ctx)
    switch g {
    case .Tap as at:
        tap.grid.command = CMD_CLEAR_GROUPING
        tap.grid.command_spec = tap.level
        ret ok
    case .DragStart as at:
        ret widget.begin_drag(tap.grid.theme.runtime, CHIP_TAG + u64(tap.level) + 1u64)
    case .Drop as d:
        // a chip dropped on another swaps their order
        if d.payload <= CHIP_TAG || d.payload > CHIP_TAG + 64u64 { ret ok }
        let from = usize(d.payload - CHIP_TAG - 1u64)
        if from == tap.level { ret ok }
        tap.grid.command = CMD_GROUP_SWAP
        tap.grid.command_spec = from
        ret ok
    case .DragEnd as at:
        // a chip let go outside the group box takes its grouping away (v3)
        let grid = tap.grid
        if mem.address_of(grid.theme) == 0usize || mem.address_of(grid.theme.runtime) == 0usize { ret ok }
        let (box_rect, has_box) = control.keyed_bounds(grid.theme.runtime, grid.key + GROUP_BOX_KEY)
        if has_box && (at.y < box_rect.y || at.y >= box_rect.y + box_rect.height || at.x < box_rect.x || at.x >= box_rect.x + box_rect.width) {
            grid.command = CMD_CLEAR_GROUPING
            grid.command_spec = tap.level
        }
        ret ok
    default:
        ret ok
    }
}

fn group_box(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let n = grid.g.level_count
    let (chips, chips_error) = mem.alloc[widget.Node](a, n + 1usize)
    if chips_error != ok { ret (zero, control.TooLarge) }
    var i = 0usize
    while i < n {
        var title: widget.Node = zero
        let title_error = text_node(a, grid, table.column_name(grid.t, grid.g.levels[i].column), false, .Text, &title)
        if title_error != ok { ret (zero, title_error) }
        var triangle: widget.Node = zero
        var triangle_error: err = ok
        if grid.look.on && grid.look.group_flat {
            // looks4-e: the sort mark is v3's own 8 x 9 bitmap
            let (picture, picture_error) = gl.pixels(a, gl.gx_sort_up(), gl.gx_sort_up_w(), gl.gx_sort_up_h())
            triangle = picture
            triangle_error = picture_error
        } else {
            let (drawn_mark, drawn_error) = gl.mark(a, .UpOutline, gl.rgb(0xB9B9B9u32), gl.rgb(0xFFFFFFu32), 9.0, 8.0)
            triangle = drawn_mark
            triangle_error = drawn_error
        }
        if triangle_error != ok { ret (zero, triangle_error) }
        let (inside, inside_error) = mem.alloc[widget.Node](a, 2usize)
        if inside_error != ok { ret (zero, control.TooLarge) }
        inside[0usize] = title
        inside[1usize] = triangle
        if grid.look.on && false { inside[1usize] = title }
        var chip_style = style.defaults()
        chip_style.background = paint.Brush { Solid: skin(grid, 0xFFFFFFu32) }
        chip_style.height = style.Length { Px: 18.7 }
        var chip_left: f32 = 6.0
        if grid.look.on && grid.look.group_flat {
            chip_style.height = style.Length { Px: 18.0 }
            chip_left = 5.0
        }
        let chip_row = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 14.0 }, style.defaults(), inside[0usize..2usize])
        // a tap on a chip takes that grouping away (v3: dragging the chip out of the box)
        let (chip_taps, chip_taps_error) = mem.alloc[ChipTap](a, 1usize)
        if chip_taps_error != ok { ret (zero, control.TooLarge) }
        chip_taps[0usize] = ChipTap { grid: grid, level: i }
        let padded_chip = widget.padded(0u64, chip_left, 0.0, chip_left, 0.0, chip_style, one(a, chip_row))
        chips[i] = widget.region(grid.key + GROUP_BOX_KEY + 16u64 + u64(i), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&chip_taps[0usize]), invoke: on_chip_gesture }, gestures: 1u8 | 2u8 | 8u8, enabled: true, focusable: false }, style.defaults(), one(a, padded_chip))
        i += 1usize
    }
    var panel = style.defaults()
    panel.background = paint.Brush { Solid: grid.look.group_row }
    panel.height = style.Length { Px: 35.0 }
    if grid.look.on && grid.look.group_flat { panel.height = style.Length { Px: 34.0 } }
    panel.width = style.Length { Percent: 100.0 }
    var content: widget.Node = zero
    if n == 0usize {
        // v3's hint of an empty box
        let hint_error = text_node(a, grid, "Drag a column header here to group by that column", false, .Text, &content)
        if hint_error != ok { ret (zero, hint_error) }
    } else {
        content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 6.0 }, style.defaults(), chips[0usize..n])
    }
    let box_key = grid.key + GROUP_BOX_KEY
    var panel_left: f32 = 6.7
    var panel_top: f32 = 7.3
    if grid.look.on && grid.look.group_flat {
        panel_left = 6.0
        panel_top = 8.0
    }
    let padded_panel = widget.padded(0u64, panel_left, panel_top, 6.7, 7.3, panel, one(a, content))
    let (zone, zone_error) = mem.alloc[widget.Node](a, 1usize)
    if zone_error != ok { ret (zero, control.TooLarge) }
    zone[0usize] = padded_panel
    var zone_style = style.defaults()
    zone_style.width = style.Length { Percent: 100.0 }
    let raw_zone = widget.region(box_key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](grid), invoke: on_group_drop }, gestures: widget.GESTURE_DROP, enabled: true, focusable: false }, zone_style, zone[0usize..1usize])
    var drop_zone = raw_zone
    if grid.look.on && grid.look.group_flat {
        // looks4-e: a faint line (#F9F9F9) closes the box, the 35th pixel
        var closing = control.sized_style(4000.0, 1.0)
        closing.background = paint.Brush { Solid: gl.rgb(0xF9F9F9u32) }
        let (zone_and_line, zone_and_line_error) = mem.alloc[widget.Node](a, 2usize)
        if zone_and_line_error != ok { ret (zero, control.TooLarge) }
        zone_and_line[0usize] = raw_zone
        zone_and_line[1usize] = widget.box(0u64, closing, zero)
        drop_zone = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), zone_and_line[0usize..2usize])
    }
    // v3: while a header is over the box, a green arrow above it and one below it show the drop
    if mem.address_of(grid.theme) == 0usize || mem.address_of(grid.theme.runtime) == 0usize { ret (drop_zone, ok) }
    let (lifted, has_lifted) = collection.lifted_column(grid.theme)
    if !has_lifted { ret (drop_zone, ok) }
    let (box_rect, has_box) = control.keyed_bounds(grid.theme.runtime, box_key)
    if !has_box { ret (drop_zone, ok) }
    let at = widget.pointer_position(grid.theme.runtime)
    if at.x < box_rect.x || at.x >= box_rect.x + box_rect.width || at.y < box_rect.y || at.y >= box_rect.y + box_rect.height { ret (drop_zone, ok) }
    let (down_arrow, down_error) = gl.mark(a, .ArrowDown, gl.rgb(0x00FF00u32), gl.rgb(0x00FF00u32), 9.0, 11.0)
    if down_error != ok { ret (zero, down_error) }
    let (up_arrow, up_error) = gl.mark(a, .ArrowUp, gl.rgb(0x00FF00u32), gl.rgb(0x00FF00u32), 9.0, 11.0)
    if up_error != ok { ret (zero, up_error) }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 5usize)
    if layers_error != ok { ret (zero, control.TooLarge) }
    layers[3usize] = down_arrow
    layers[4usize] = up_arrow
    layers[0usize] = drop_zone
    layers[1usize] = widget.overlay(box_key + 1u64, widget.Overlay { anchor: box_key, placement: .Below, offset: geometry.Point { x: 2.0, y: 0.0 - box_rect.height - 11.0 }, modal: false, dismiss: zero }, style.defaults(), layers[3usize..4usize])
    layers[2usize] = widget.overlay(box_key + 2u64, widget.Overlay { anchor: box_key, placement: .Below, offset: geometry.Point { x: 2.0, y: 0.0 }, modal: false, dismiss: zero }, style.defaults(), layers[4usize..5usize])
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), layers[0usize..3usize]), ok)
}

// The grid as a node of `height` for the body; `theme` must stay valid until the next build.
// The current row follows the keyboard (v3's): when a row of this grid holds the focus, it is the
// current row and the application hears `row_picked`.
fn follow_focus(grid: *Grid, theme: *const control.Theme) -> err {
    if mem.address_of(theme.runtime) == 0usize { ret ok }
    if grid.editing && grid.edit_focus_pending {
        // the editor takes the keyboard as soon as it stands in the tree
        if widget.focus_key(theme.runtime, grid.key + EDIT_KEY) == ok { grid.edit_focus_pending = false }
        if grid.edit_caret_frames > 0usize { widget.request_animation_frame(theme.runtime) }
        ret ok
    }
    if grid.editing && grid.edit_caret_frames > 0usize && !grid.edit_focus_pending {
        // v3 puts the caret where the tap was; the editor's text has its place from the second
        // frame on, so the point is applied for the next few frames
        if widget.edit_place_caret(theme.runtime, grid.edit_click_x) { grid.edit_caret_frames -= 1usize }
        if grid.edit_caret_frames > 0usize { widget.request_animation_frame(theme.runtime) }
    }
    if grid.editing { ret ok }
    if grid.rest_pending {
        // after a commit the keyboard goes back to the row
        if widget.focus_key(theme.runtime, row_key(grid, grid.rest_row)) == ok { grid.rest_pending = false }
    }
    let (focus, has_focus) = widget.focused_key(theme.runtime)
    if !has_focus { ret ok }
    let base = grid.key + KEY_BASE
    if focus >= base + u64(table.capacity(grid.t)) && focus < base + u64(table.capacity(grid.t)) + u64(grp.group_len(grid.g)) {
        // the keyboard reached a group row: it is the current row, with no card under it (v3)
        let group = usize(focus - base - u64(table.capacity(grid.t)))
        var at_group = 0usize
        let shown_total = grp.visible_len(grid.g)
        while at_group < shown_total && !(grp.visible_is_group(grid.g, at_group) && !grp.visible_is_footer(grid.g, at_group) && grp.visible_group(grid.g, at_group) == group) { at_group += 1usize }
        if at_group < shown_total && !(grid.has_position && grid.position == at_group && !grid.has_selection) {
            grid.has_position = true
            grid.position = at_group
            grid.has_selection = false
        }
        ret ok
    }
    if focus < base || focus >= base + u64(table.capacity(grid.t)) { ret ok }
    let row = usize(focus - base)
    if grid.has_selection && grid.selected_row == row { ret ok }
    grid.has_selection = true
    grid.selected_row = row
    var found = 0usize
    let visible = grp.visible_len(grid.g)
    while found < visible && (grp.visible_is_group(grid.g, found) || grp.visible_row(grid.g, found) != row) { found += 1usize }
    if found < visible {
        grid.has_position = true
        grid.position = found
    }
    ret grid.events.row_picked(grid.events.ctx, row)
}

// After a sort, a filter or a grouping the current card stays current (v3's): its position in the
// order is found again, and the view moves the least that shows it (up to put it at the top, down to
// put it at the bottom), as v3 does.
fn follow_row_after_reorder(grid: *Grid) {
    if !grid.has_selection || !grid.has_position { ret }
    let visible = grp.visible_len(grid.g)
    if grid.position < visible && !grp.visible_is_group(grid.g, grid.position) && grp.visible_row(grid.g, grid.position) == grid.selected_row { ret }
    var found = 0usize
    while found < visible && (grp.visible_is_group(grid.g, found) || grp.visible_row(grid.g, found) != grid.selected_row) { found += 1usize }
    if found >= visible {
        grid.has_position = false
        ret
    }
    grid.position = found
    var page = grid.page_rows
    if page == 0usize { page = 1usize }
    let top = entry_at(grid, grid.offset)
    if found < top {
        grid.offset = entry_top(grid, found)
    } else if found >= top + page {
        grid.offset = entry_top(grid, found + 1usize - page)
    }
}

// v3's Best Fit: the column takes the width of its widest content (and its title) in the grid's text;
// the widest text is the longest by bytes, found without measuring every row.
fn best_fit(a: *mem.Arena, grid: *Grid, spec: usize) -> err {
    if spec >= grid.all.len { ret ok }
    let s = grid.all[spec]
    if s.kind == CellKind.Indicator || s.kind == CellKind.Star || s.kind == CellKind.Picture || s.kind == CellKind.Custom { ret ok }
    var widest = s.title
    let kind = table.column_kind(grid.t, s.column)
    if kind == table.Kind.Dict {
        let n = table.dict_len(grid.t, s.column)
        var id = 0usize
        while id < n {
            let text = table.dict_str(grid.t, s.column, u32(id))
            if text.len > widest.len { widest = text }
            id += 1usize
        }
    } else if kind == table.Kind.Str {
        var row = 0usize
        let rows = table.row_count(grid.t)
        while row < rows {
            if table.is_live(grid.t, row) {
                let text = table.get_str(grid.t, s.column, row)
                if text.len > widest.len { widest = text }
            }
            row += 1usize
        }
    }
    var text_node_value: widget.Node = zero
    let node_error = text_node(a, grid, widest, false, .Text, &text_node_value)
    if node_error != ok { ret node_error }
    var width = widget.text_width(a, text_node_value)
    // a title with its sort triangle needs a little more
    var extra: f32 = 2.0 * 4.0 + 1.0
    if grid.look.on { extra = 2.0 * grid.look.pad + 1.0 }
    width += extra + 6.0
    if width < 24.0 { width = 24.0 }
    if width > 1600.0 { width = 1600.0 }
    resize_column(grid, spec, width)
    ret ok
}

// After a grouping the application calls this: v3 opens the groups that contain the current card
// and shows it (the card stays current).
fn reveal_current(grid: *Grid) {
    if !grid.has_selection { ret }
    var at = 0usize
    let total = grp.row_count(grid.g)
    while at < total && grp.row_at(grid.g, at) != grid.selected_row { at += 1usize }
    if at >= total { ret }
    var group = 0usize
    while group < grp.group_len(grid.g) {
        if grp.group_first(grid.g, group) <= at && at < grp.group_first(grid.g, group) + grp.group_count(grid.g, group) {
            let opened = grp.set_expanded(grid.g, group, true)
        }
        group += 1usize
    }
    var found = 0usize
    let visible = grp.visible_len(grid.g)
    while found < visible && (grp.visible_is_group(grid.g, found) || grp.visible_row(grid.g, found) != grid.selected_row) { found += 1usize }
    if found >= visible {
        grid.has_position = false
        ret
    }
    grid.has_position = true
    grid.position = found
    var page = grid.page_rows
    if page == 0usize { page = 1usize }
    let top = entry_at(grid, grid.offset)
    if found < top {
        grid.offset = entry_top(grid, found)
    } else if found >= top + page {
        grid.offset = entry_top(grid, found + 1usize - page)
    }
}

// The grid as a node of `height`: its parts, in the context menu target (and chooser) of v3.
fn build(a: *mem.Arena, grid: *Grid, theme: *const control.Theme, height: f32) -> (widget.Node, err) {
    // The Windows look (docs/ui/looks) is the measured v3 grid, unless the application set its own.
    style.windows_dark_enter(theme.tokens)
    if theme.tokens.profile == .Windows {
        // The preset follows the palette: a grid that still carries the other palette's preset is switched (an application's
        // own look is left alone). The presets are told apart by their header: white (light) or #333333 (dark).
        let on_light = grid.look.on && grid.look.header.red > 0.99 && grid.look.selected.red > 0.6 && grid.look.selected.red < 0.7
        let on_dark = grid.look.on && grid.look.header.red > 0.19 && grid.look.header.red < 0.21 && grid.look.selected.red > 0.13 && grid.look.selected.red < 0.16
        if style.windows_dark_on() {
            if !grid.look.on || on_light { set_look(grid, gl.v3_dark()) }
        } else if !grid.look.on || on_dark {
            set_look(grid, gl.v3())
        }
    }
    // Neper dark: the v3 grid's light surfaces become the dark tokens' (the light look is untouched)
    if theme.tokens.profile == .Neper && theme.tokens.palette == .Dark && grid.base_look.on { grid.look = gl.neper_dark_of(grid.look, grid.base_look) }
    // looks4-e: v3's grids draw Tahoma 8 pt (11 px), as its dialogs do
    var drawn_with = theme
    if theme.tokens.profile == .Windows && grid.look.on {
        let (tahoma, tahoma_error) = control.windows_tahoma_theme(a, theme, 11.0)
        if tahoma_error != ok { ret (zero, tahoma_error) }
        let (held_theme, held_error) = mem.alloc[control.Theme](a, 1usize)
        if held_error != ok { ret (zero, held_error) }
        held_theme[0usize] = tahoma
        drawn_with = &held_theme[0usize]
    }
    let (inner, inner_error) = build_parts(a, grid, drawn_with, height)
    if inner_error != ok { ret (zero, inner_error) }
    var (menus, menus_error) = with_menus(a, grid, inner)
    if menus_error == ok && grid.look.on && mem.address_of(theme.runtime) != 0usize {
        // a card row dragged (v3): its name in a green frame under the pointer, drawn by the grid under it;
        // the stack stands always, so the tree keeps its shape while a drag is under way
        var layers_count = 1usize
        let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
        if layers_error != ok { ret (zero, control.TooLarge) }
        layers[0usize] = menus
        let (drag_payload, dragging_now) = widget.dragging(theme.runtime)
        if dragging_now && drag_payload > collection.row_drag_tag() && drag_payload < 2u64 * collection.row_drag_tag() {
            let (source_row, mine) = row_of_key(grid, drag_payload - collection.row_drag_tag())
            if mine && grid.has_search && grid.search_spec < grid.all.len {
                let (label_text, label_error) = cell_text_of(a, grid, grid.all[grid.search_spec], source_row)
                if label_error == ok {
                    var copied = label_text.len
                    if copied > 95usize { copied = 95usize }
                    var at_copy = 0usize
                    while at_copy < copied {
                        drag_ghost_text[at_copy] = label_text[at_copy]
                        at_copy += 1usize
                    }
                    drag_ghost_len = copied
                }
            }
            let pointer_now = widget.pointer_position(theme.runtime)
            let (grid_box, has_grid_box) = control.keyed_bounds(theme.runtime, grid.key)
            if has_grid_box && drag_ghost_len != 0usize && geometry.contains(grid_box, pointer_now) {
                let (ghost_label, ghost_error) = flat_text(a, grid, drag_ghost_text[0usize..drag_ghost_len], gl.rgb(0x000000u32))
                if ghost_error == ok {
                    var ghost_box = style.defaults()
                    ghost_box.background = paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 0.85) }
                    ghost_box.border = style.Border { width: 2.0, color: gl.rgb(0x66FF66u32) }
                    let (ghost_held, ghost_held_error) = mem.alloc[widget.Node](a, 1usize)
                    if ghost_held_error == ok {
                        ghost_held[0usize] = widget.padded(0u64, 8.0, 6.0, 8.0, 6.0, ghost_box, one(a, ghost_label))
                        layers[1usize] = widget.positioned(0u64, pointer_now.x - grid_box.x + 6.0, pointer_now.y - grid_box.y + 6.0, style.defaults(), ghost_held[0usize..1usize])
                        layers_count = 2usize
                    }
                }
            }
        }
        menus = widget.stack(0u64, style.defaults(), layers[0usize..layers_count])
    }
    // v3 draws the current row, never a focus ring: the dotted rectangle and the fill are its focus
    if grid.look.on && mem.address_of(theme.runtime) != 0usize {
        widget.set_focus_ring(theme.runtime, paint.rgba(0.0, 0.0, 0.0, 0.0), theme.tokens.metrics.focus_ring, theme.tokens.metrics.focus_offset)
    }
    ret (menus, menus_error)
}

fn build_parts(a: *mem.Arena, grid: *Grid, theme: *const control.Theme, height: f32) -> (widget.Node, err) {
    grid.theme = theme
    try follow_focus(grid, theme)
    if grp.visible_len(grid.g) == 0usize && !grid.look.on {
        var inner: widget.Node = zero
        let node_error = text_node(a, grid, grid.empty_text, false, .Text, &inner)
        if node_error != ok { ret (zero, node_error) }
        ret (widget.padded(grid.key, 16.0, 16.0, 16.0, 16.0, style.defaults(), one(a, inner)), ok)
    }
    let (selected, selected_error) = mem.alloc[u64](a, 160usize)
    if selected_error != ok { ret (zero, selected_error) }
    var selected_count = 0usize
    if grid.multi {
        // the marked rows among those the body shows (it draws only a window)
        var first = entry_at(grid, grid.offset)
        if first > 2usize { first -= 2usize } else { first = 0usize }
        var shown = grid.page_rows + 6usize
        if shown > 150usize { shown = 150usize }
        var p = first
        let visible_rows = grp.visible_len(grid.g)
        while p < visible_rows && p < first + shown {
            if !grp.visible_is_group(grid.g, p) && is_marked(grid, grp.visible_row(grid.g, p)) {
                selected[selected_count] = row_key(grid, grp.visible_row(grid.g, p))
                selected_count += 1usize
            }
            p += 1usize
        }
    } else if grid.has_selection {
        selected[0usize] = row_key(grid, grid.selected_row)
        selected_count = 1usize
    }
    let me = mem.cast[*void](grid)
    let source = collection.TableSource { ctx: me, count: source_count, key: source_key, cell: source_cell }
    var body_height = height
    if grid.footer_visible && grid.g.specs.len != 0usize { body_height = body_height - grid.row_height - 8.0 }
    if grid.footer_visible && grid.g.specs.len != 0usize && grid.look.on && grid.look.group_flat { body_height = body_height + grid.row_height + 8.0 - 24.0 }
    if grid.filter_visible && !grid.look.on { body_height = body_height - 44.0 }
    if grid.bands.len != 0usize { body_height = body_height - 36.0 }
    if grid.navigator_visible { body_height = body_height - 52.0 }
    if grid.look.on && grid.look.group_flat && !grid.footer_visible && grid.navigator_visible { body_height = body_height - 2.0 }
    if grid.group_box_visible { body_height = body_height - 35.0 }
    grid.page_rows = usize(body_height / grid.row_height)
    follow_row_after_reorder(grid)
    if grid.fit_all_pending {
        grid.fit_all_pending = false
        var fit_at = 0usize
        while fit_at < grid.all.len {
            let all_error = best_fit(a, grid, fit_at)
            if all_error != ok { ret (zero, all_error) }
            fit_at += 1usize
        }
    }
    if grid.fit_pending {
        grid.fit_pending = false
        let fit_error = best_fit(a, grid, grid.fit_spec)
        if fit_error != ok { ret (zero, fit_error) }
    }
    var sort_shown = grid.specs.len
    let (sort_at, sort_visible) = display_of(grid, grid.sort_column)
    if sort_visible { sort_shown = sort_at }
    // looks4-e: the sideways scroll is measured before the table is built, so the first frame already knows it
    measure_hscroll(grid, theme)
    var table_options: collection.TableOptions = zero
    // an empty grid keeps its header and says why under it (v3's NoDataToDisplayInfoText)
    if grp.visible_len(grid.g) == 0usize { table_options.empty_title = grid.empty_text }
    table_options.double = widget.Change[widget.Key] { ctx: mem.cast[*void](grid), invoke: on_double }
    table_options.has_double = true
    if grid.hon && grid.hpane > 0.0 { table_options.empty_width = grid.hpane }
    if grid.look.on {
        let lk = grid.look
        // column alignment: shown columns right or centred by the Alignment popup
        var shown_at = 0usize
        while shown_at < grid.specs.len {
            let origin_at = grid.origin[shown_at]
            grid.right_flags[shown_at] = grid.aligns[origin_at] == 3u8
            grid.also_marks[shown_at] = 0u8
            var extra_at = 0usize
            while extra_at < grid.extra_count {
                if grid.extra_sort[extra_at] == origin_at {
                    grid.also_marks[shown_at] = 1u8
                    if grid.extra_desc[extra_at] { grid.also_marks[shown_at] = 2u8 }
                }
                extra_at += 1usize
            }
            grid.center_flags[shown_at] = grid.aligns[origin_at] == 2u8
            shown_at += 1usize
        }
        table_options.numeric = grid.right_flags[0usize..grid.specs.len]
        table_options.centered = grid.center_flags[0usize..grid.specs.len]
        // the name of a hidden column being dragged out of the chooser follows the pointer
        var drag_label: str = ""
        if mem.address_of(theme.runtime) != 0usize {
            let (dragged_payload, has_dragged) = widget.dragging(theme.runtime)
            let chooser_tag = collection.chooser_payload_tag()
            if has_dragged && dragged_payload > chooser_tag && dragged_payload < chooser_tag + 1073741824u64 {
                let carried = usize(dragged_payload - chooser_tag - 1u64)
                let owner = u64(carried >> 13usize)
                let dragged_spec = carried & 8191usize
                if owner == (grid.key & 65535u64) && dragged_spec < grid.all.len { drag_label = grid.all[dragged_spec].title }
            }
        }
        // v3 paints the selected row of a grid that has not the focus in a pale blue-grey (#D5E4EE)
        var selected_fill = lk.selected
        var selected_edge = lk.selected_line
        var dotted_focus = true
        if !grid.editing && !grid.chooser_active && mem.address_of(theme.runtime) != 0usize {
            let (held, has_held) = widget.focused_key(theme.runtime)
            if lk.idle_on && !grid.force_focus && (!has_held || !grid.has_selection || held != row_key(grid, grid.selected_row)) {
                selected_fill = lk.idle_fill
                selected_edge = lk.idle_edge
                dotted_focus = false
            }
        }
        var v3_filter: widget.Node = zero
        if grid.filter_visible {
            let (made_filter, made_filter_error) = v3_filter_row(a, grid)
            if made_filter_error != ok { ret (zero, made_filter_error) }
            v3_filter = made_filter
        }
        table_options.look = collection.TableLook { on: true, has_head_extra: grid.filter_visible, head_extra: v3_filter, head_extra_height: 26.0, bar_margin: bar_margin_of(grid), header_height: lk.header_height, pad: lk.pad, text_size: lk.text_size, header: lk.header, header_hover: lk.header_hover, header_line: header_rule_of(grid), even: lk.odd, odd: lk.even, selected: selected_fill, selected_line: selected_edge, line: lk.line, group: lk.group_row, kind_ctx: me, kind: row_kind, glyph: header_glyph, track: lk.track, thumb: lk.thumb, scroll_width: lk.scroll_width, focus_on: grid.multi && grid.has_selection, focus_key: row_key(grid, grid.selected_row), drag_label: drag_label, center_head: grid.center_flags[0usize..grid.specs.len], footer_fill: lk.footer_band, footer_extra: footer_extra(), also_sorted: grid.also_marks[0usize..grid.specs.len], detail_height: preview_detail_height(grid), head_text: grid.base_look.text_size, row_drag: true, row_drop: widget.Change[u64] { ctx: me, invoke: on_row_drop }, has_row_drop: grid.has_row_drop, header_hidden: grid.header_off, vertical_off: grid.lines == GridLines.Horizontal || grid.lines == GridLines.None, horizontal_on: grid.lines == GridLines.Both || grid.lines == GridLines.Horizontal, soft_lines: grid.look.group_flat, bar_top: bar_top_of(grid), dotted_focus: dotted_focus, focus_aware: false, selected_focus: lk.selected, tree_dots: false, cell_select: grid.cell_select, dialog_lines: grid.look.dialog_lines, foot_set: grid.look.foot_set, foot_drift: grid.look.foot_drift, foot_g1: grid.look.foot_g1, foot_g2: grid.look.foot_g2, foot_w1: grid.look.foot_w1, foot_w2: grid.look.foot_w2, top_edge_on: !dotted_focus && grid.look.idle_on, top_edge: lk.idle_top, plain_col: grid.look.plain_col, soft_a0: grid.look.soft_a0, soft_x0: grid.look.soft_x0, soft_slope: grid.look.soft_slope }
    }
    // group footers are taller: the list of the entries that are
    if has_extras(grid) && grid.look.on {
        let visible_now = grp.visible_len(grid.g)
        var capacity = grp.group_len(grid.g) + 1usize
        if grid.preview_on { capacity = visible_now + 1usize }
        let (extra_list, extra_error) = mem.alloc[widget.VirtualExtra](a, capacity)
        if extra_error != ok { ret (zero, extra_error) }
        var extra_count = 0usize
        var scan = 0usize
        while scan < visible_now && extra_count < extra_list.len {
            let plus = extra_of(grid, scan)
            if plus != 0.0 {
                extra_list[extra_count] = widget.VirtualExtra { index: scan, extra: plus }
                extra_count += 1usize
            }
            scan += 1usize
        }
        table_options.extras = extra_list[0usize..extra_count]
    }
    if grid.preview_on {
        table_options.expandable = true
        table_options.expanded = grid.preview_open[0usize..grid.preview_count]
        table_options.expand = widget.Change[widget.Key] { ctx: me, invoke: on_expand }
        table_options.detail = collection.TableDetail { ctx: me, build: on_detail }
    }
    if grid.look.on && grid.look.group_flat {
        var viewport_h = body_height - grid.look.header_height
        if grid.filter_visible { viewport_h = viewport_h - 26.0 }
        grid.bar_on = entry_top(grid, grp.visible_len(grid.g)) > viewport_h
    }
    let (body, body_error) = collection.table_with(a, grid.key, theme, "Data grid", grid.columns, source, selected[0usize..selected_count], sort_shown, grid.descending, widget.Change[usize] { ctx: me, invoke: on_sort }, widget.Change[collection.Reorder] { ctx: me, invoke: on_reorder }, widget.Change[collection.ColumnResize] { ctx: me, invoke: on_resize }, widget.Change[widget.Key] { ctx: me, invoke: on_pick }, grid.row_height, grid.offset, widget.Change[f32] { ctx: me, invoke: on_scroll }, body_height, table_options)
    if body_error != ok { ret (zero, body_error) }
    measure_hscroll(grid, theme)
    let (shown_body, shown_body_error) = shown_in_pane(a, grid, body, body_height)
    if shown_body_error != ok { ret (zero, shown_body_error) }
    var part_count = 1usize
    let with_footer = grid.footer_visible && grid.g.specs.len != 0usize
    let with_bands = grid.bands.len != 0usize
    if with_footer { part_count += 1usize }
    let separate_filter = grid.filter_visible && !grid.look.on
    if separate_filter { part_count += 1usize }
    if with_bands { part_count += 1usize }
    let with_filter_panel = grid.look.on
    if with_filter_panel { part_count += 1usize }
    if grid.navigator_visible { part_count += 1usize }
    if grid.group_box_visible { part_count += 1usize }
    if grid.look.on { part_count += 1usize }
    if part_count == 1usize {
        let (keyed_body, keyed_body_error) = with_keys(a, grid, shown_body)
        ret (keyed_body, keyed_body_error)
    }
    let (parts, parts_error) = mem.alloc[widget.Node](a, part_count)
    if parts_error != ok { ret (zero, parts_error) }
    var at = 0usize
    if grid.group_box_visible {
        let (box_node, box_error) = group_box(a, grid)
        if box_error != ok { ret (zero, box_error) }
        parts[at] = box_node
        at += 1usize
    }
    if with_bands {
        let (bands_node, bands_error) = band_row(a, grid)
        if bands_error != ok { ret (zero, bands_error) }
        parts[at] = bands_node
        at += 1usize
    }
    if separate_filter {
        let (filter, filter_error) = filter_row(a, grid)
        if filter_error != ok { ret (zero, filter_error) }
        parts[at] = filter
        at += 1usize
    }
    if grid.look.on {
        // an unseen full-width rule whose width is the pane's, for the horizontal scroll range
        var gauge = style.defaults()
        gauge.width = style.Length { Percent: 100.0 }
        gauge.height = style.Length { Px: 0.0 }
        parts[at] = widget.box(grid.key + 3900u64, gauge, zero)
        at += 1usize
    }
    parts[at] = shown_body
    at += 1usize
    if with_footer {
        let (footer, footer_error) = footer_row(a, grid)
        if footer_error != ok { ret (zero, footer_error) }
        if grid.hon {
            var footer_h = grid.row_height + 8.0
            if grid.look.on && grid.look.group_flat { footer_h = 24.0 }
            var footer_clip: f32 = 0.0
            if grid.look.on && grid.look.group_flat && grid.bar_on { footer_clip = grid.hpane - grid.look.scroll_width }
            let (shifted_footer, shifted_footer_error) = hshift_clipped(a, grid, footer, grid.hcontent, footer_h, footer_clip)
            if shifted_footer_error != ok { ret (zero, shifted_footer_error) }
            parts[at] = shifted_footer
        } else {
            parts[at] = footer
        }
        at += 1usize
    }
    if with_filter_panel {
        // the slot stays when no condition is active, so the editors above keep their focus
        if row_filter_active(grid) {
            let (filter_panel, filter_panel_error) = filter_panel_row(a, grid)
            if filter_panel_error != ok { ret (zero, filter_panel_error) }
            parts[at] = filter_panel
        } else if grid.look.group_flat && !grid.footer_visible && grid.navigator_visible {
            // looks5-e: with no summary footer the navigator's top has two #F7F7F7 pixel rows (live capture, states grids)
            var rule = style.defaults()
            rule.width = style.Length { Percent: 100.0 }
            rule.height = style.Length { Px: 2.0 }
            rule.background = paint.Brush { Solid: gl.rgb(0xF7F7F7u32) }
            parts[at] = widget.box(0u64, rule, zero)
        } else {
            parts[at] = widget.box(0u64, style.defaults(), zero)
        }
        at += 1usize
    }
    if grid.navigator_visible {
        let (navigator, navigator_error) = navigator_row(a, grid)
        if navigator_error != ok { ret (zero, navigator_error) }
        parts[at] = navigator
        at += 1usize
    }
    var frame = style.defaults()
    var gap: f32 = 4.0
    if grid.look.on { gap = 0.0 }
    if grid.look.on && !grid.look.frame_none {
        // the grid is framed by a 1 px line and its parts touch
        // looks4-e: the live capture's frame is two pixels: a darker outer line over a lighter inner one
        frame.border = style.Border { width: 1.0, color: grid.look.frame }
        frame.background = paint.Brush { Solid: gl.rgb(0xC6C8CCu32) }
        gap = 0.0
    }
    var inner_style = style.defaults()
    if grid.look.on && !grid.look.frame_none { inner_style.background = paint.Brush { Solid: skin(grid, 0xF0F0F0u32) } }
    var stacked = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: gap }, inner_style, parts[0usize..part_count])
    if grid.look.on && !grid.look.frame_none && grid.look.ring {
        let (ringed, ring_error) = ring_wrap(a, grid, stacked)
        if ring_error != ok { ret (zero, ring_error) }
        stacked = ringed
        if grid.look.ring_marks.len != 0usize && win_look(grid) {
            let (marked, marked_error) = ring_marks_over(a, grid, stacked)
            if marked_error != ok { ret (zero, marked_error) }
            stacked = marked
        }
    } else if grid.look.on && !grid.look.frame_none { stacked = widget.padded(0u64, 2.0, 2.0, 2.0, 2.0, frame, one(a, stacked)) }
    let (keyed, keyed_error) = with_keys(a, grid, stacked)
    ret (keyed, keyed_error)
}

// looks5-e: the grid's frame as the live capture draws it: two lines on the top and the left, one at the bottom and the right
fn ring_side(a: *mem.Arena, color: paint.Color, left: f32, top: f32, right: f32, bottom: f32, inner: widget.Node) -> widget.Node {
    var s = style.defaults()
    s.background = paint.Brush { Solid: color }
    ret widget.padded(0u64, left, top, right, bottom, s, one(a, inner))
}

fn ring_wrap(a: *mem.Arena, grid: *const Grid, inner: widget.Node) -> (widget.Node, err) {
    let lk = grid.look
    var node = ring_side(a, lk.ring_right, 0.0, 0.0, 1.0, 0.0, inner)
    node = ring_side(a, lk.ring_bottom, 0.0, 0.0, 0.0, 1.0, node)
    node = ring_side(a, lk.ring_left_i, 1.0, 0.0, 0.0, 0.0, node)
    node = ring_side(a, lk.ring_top_i, 0.0, 1.0, 0.0, 0.0, node)
    node = ring_side(a, lk.ring_left_o, 1.0, 0.0, 0.0, 0.0, node)
    node = ring_side(a, lk.ring_top_o, 0.0, 1.0, 0.0, 0.0, node)
    ret (node, ok)
}

// looks9-w1: the ring's one-pixel marks, from `Look.ring_marks`: "x y h rrggbb;..." (x and y from the grid's top-left, decimal)
fn ring_marks_over(a: *mem.Arena, grid: *const Grid, inner: widget.Node) -> (widget.Node, err) {
    let text = grid.look.ring_marks
    var count = 1usize
    var at = 0usize
    while at < text.len {
        if text[at] == 59u8 { count += 1usize }
        at += 1usize
    }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count + 1usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = inner
    var made = 1usize
    at = 0usize
    while at < text.len && made <= count {
        var field: [4]u32 = zero
        var hex: u32 = 0u32
        var k = 0usize
        while k < 4usize && at < text.len {
            var value: u32 = 0u32
            while at < text.len && text[at] != 32u8 && text[at] != 59u8 {
                if k == 3usize { value = value * 16u32 + gl.hex_digit(text[at]) } else { value = value * 10u32 + (u32(text[at]) - 48u32) }
                at += 1usize
            }
            field[k] = value
            k += 1usize
            if at < text.len && text[at] == 32u8 { at += 1usize }
        }
        hex = field[3usize]
        parts[made] = footer_px(a, f32(field[0usize]), f32(field[1usize]), 1.0, f32(field[2usize]), hex)
        made += 1usize
        if at < text.len && text[at] == 59u8 { at += 1usize }
    }
    ret (widget.stack(0u64, style.defaults(), parts[0usize..made]), ok)
}

// looks4-e: the live capture's vertical bar starts at the grid's top, above the group box
fn bar_top_of(grid: *const Grid) -> f32 { ret 0.0 }

// looks4-e: the line under the header row: faint, and white where the filter row continues the header
fn header_rule_of(grid: *const Grid) -> paint.Color {
    if grid.filter_visible { ret grid.look.header }
    ret grid.look.header_line
}

// Blue while the filter-row conditions apply, grey while they are suspended.
fn tick_fill(grid: *const Grid) -> u32 {
    if grid.filter_off { ret 0xB0B0B0u32 }
    ret 0x0F5FBFu32
}

// A header or footer cell of Page Setup: v3's boxes are 166 x 70, several lines tall.
fn cell_field_options() -> control.FieldOptions {
    var options = control.field_options()
    options.rows = 3u32
    options.width = 166.0
    options.height = 70.0
    ret options
}

// The colour of hue step k (0..11) at full saturation and value, as 0xRRGGBB.
fn hue_rgb(k: u8) -> u32 {
    let sector = k / 2u8
    let rising = (k % 2u8) == 1u8
    var up: u32 = 0u32
    if rising { up = 128u32 }
    // six sectors of 60 degrees, each cut in two: the middle channel sits at 128 on odd steps
    if sector == 0u8 { ret (255u32 << 16u32) | (up << 8u32) }
    if sector == 1u8 { ret ((255u32 - up) << 16u32) | (255u32 << 8u32) }
    if sector == 2u8 { ret (255u32 << 8u32) | up }
    if sector == 3u8 { ret ((255u32 - up) << 8u32) | 255u32 }
    if sector == 4u8 { ret (up << 16u32) | 255u32 }
    ret (255u32 << 16u32) | (127u32 - up / 2u32)
}

fn on_hue_chip(ctx: *void, g: widget.Gesture) -> err {
    let t = mem.cast[*SwatchTap](ctx)
    switch g {
    case .Tap as at:
        let grid = t.grid
        grid.cust_rgb = hue_rgb(t.value)
        if grid.fmt_pick == 1u8 { grid.wiz_pos_color = 200u8 }
        if grid.fmt_pick == 2u8 { grid.wiz_neg_color = 201u8 }
        if grid.fmt_pick == 3u8 { grid.wiz_axis_color = 201u8 }
        ret ok
    default:
        ret ok
    }
}

// A strip of twelve hues across the colour popup (v3's editor has a hue square).
fn hue_strip(a: *mem.Arena, grid: *Grid, taps: []SwatchTap) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, 12usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    var k = 0usize
    while k < 12usize {
        taps[k] = SwatchTap { grid: grid, value: u8(k) }
        var chip = control.sized_style(14.0, 18.0)
        chip.background = paint.Brush { Solid: gl.rgb(hue_rgb(u8(k))) }
        chip.margin = style.EdgeLengths { left: style.Length { Px: 3.0 }, top: style.Length { Px: 3.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
        cells[k] = widget.region(grid.key + MENU_KEY + 850900u64 + u64(k), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&taps[k]), invoke: on_hue_chip }, gestures: 1u8, enabled: true, focusable: false }, chip, zero)
        k += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), cells[0usize..12usize]), ok)
}

// Bold words from one face: the text drawn twice, the second copy a pixel to the right (the sample
// registers a single face per font, and the layout has no synthetic bold).
fn faux_bold(a: *mem.Arena, grid: *Grid, text: str, first: widget.Node) -> (widget.Node, err) {
    let (second, second_error) = flat_text(a, grid, text, gl.rgb(0x000000u32))
    if second_error != ok { ret (zero, second_error) }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
    if layers_error != ok { ret (zero, control.TooLarge) }
    layers[0usize] = first
    layers[1usize] = widget.positioned(0u64, 0.8, 0.0, style.defaults(), one(a, second))
    ret (widget.stack(0u64, style.defaults(), layers[0usize..2usize]), ok)
}

// ---- the report Designer (v3: Cards > Print > Designer..., DevExpress's Format Report window) ----

type DesignTap = struct { grid: *Grid, kind: u8, value: usize }

const DZ_ITEMS: usize = 29usize

// Opens the Designer in the print window's slot.
fn show_designer(grid: *Grid) {
    show_print_preview(grid)
    grid.pv_design = true
    if !grid.dz_ready {
        grid.dz_checks = 472961023u64
        grid.dz_ready = true
    }
}

// The tab an item sits on: 0 View, 1 Behaviors, 2 Formatting, 3 Styles, 4 Preview.
fn dz_tab_of(k: usize) -> u8 {
    if k <= 11usize { ret 0u8 }
    if k <= 17usize { ret 1u8 }
    if k <= 25usize { ret 2u8 }
    if k == 28usize { ret 3u8 }
    ret 4u8
}

// The group heading an item stands under; items with the same number share one.
fn dz_group_of(k: usize) -> u8 {
    if k <= 6usize { ret 1u8 }
    if k <= 11usize { ret 2u8 }
    if k <= 13usize { ret 3u8 }
    if k <= 16usize { ret 4u8 }
    if k == 17usize { ret 5u8 }
    if k <= 23usize { ret 6u8 }
    if k <= 25usize { ret 7u8 }
    if k <= 27usize { ret 8u8 }
    ret 0u8
}

fn dz_group_name(group: u8) -> str {
    if group == 1u8 { ret "Show" }
    if group == 2u8 { ret "On Every Page" }
    if group == 3u8 { ret "Selection" }
    if group == 4u8 { ret "Expanding" }
    if group == 5u8 { ret "Size" }
    if group == 6u8 { ret "Refinements" }
    if group == 7u8 { ret "Pagination" }
    if group == 8u8 { ret "Options" }
    ret ""
}

fn dz_label(k: usize) -> str {
    if k == 0usize || k == 7usize { ret "Caption" }
    if k == 1usize || k == 8usize { ret "Bands" }
    if k == 2usize || k == 9usize { ret "Headers" }
    if k == 3usize || k == 10usize { ret "Footers" }
    if k == 4usize { ret "Group Footers" }
    if k == 5usize { ret "Expand Buttons" }
    if k == 6usize || k == 11usize { ret "Filter Bar" }
    if k == 12usize { ret "Process Selection" }
    if k == 13usize { ret "Process Exact Selection" }
    if k == 14usize { ret "Groups" }
    if k == 15usize { ret "Details" }
    if k == 16usize { ret "Cards" }
    if k == 17usize { ret "Auto Width" }
    if k == 18usize { ret "Transparent Graphics" }
    if k == 19usize { ret "Display Graphic As Text" }
    if k == 20usize { ret "Flat CheckMarks" }
    if k == 21usize { ret "Display Track Bars As Text" }
    if k == 22usize { ret "Suppress Background Textures" }
    if k == 23usize { ret "Consume Selection Style" }
    if k == 24usize { ret "By TopLevel Groups" }
    if k == 25usize { ret "One Group Per Page" }
    if k == 26usize { ret "Visible" }
    if k == 27usize { ret "Auto Height" }
    ret "Use Native Styles"
}

fn dz_enabled(k: usize) -> bool { ret k != 13usize && k != 25usize }

fn on_design_tap(ctx: *void, g: widget.Gesture) -> err {
    let t = mem.cast[*DesignTap](ctx)
    switch g {
    case .Tap as at:
        if t.kind == 0u8 { t.grid.dz_tab = u8(t.value) }
        if t.kind == 3u8 { t.grid.dz_style = u8(t.value) + 1u8 }
        if t.kind == 1u8 {
            t.grid.dz_checks = t.grid.dz_checks ^ (1u64 << u64(t.value))
            t.grid.dz_dirty = true
        }
        if t.kind == 5u8 { t.grid.dz_dirty = false }
        if t.kind == 6u8 { t.grid.dz_dlg = u8(t.value) }
        if t.kind == 8u8 { t.grid.dz_style = 0u8 }
        if t.kind == 20u8 { t.grid.sw_tab = u8(t.value) }
        if t.kind == 22u8 {
            t.grid.sw_open = 0u8
            t.grid.wiz_open = false
        }
        if t.kind == 21u8 { t.grid.sw_page = u8(t.value) }
        if t.kind == 9u8 { t.grid.dz_pick_color = windows_basic(t.value) ^ 0xFFFFFFu32 }
        if t.kind == 10u8 { dz_apply_color(t.grid) }
        if t.kind == 11u8 { dz_add_custom(t.grid) }
        if t.kind == 13u8 { t.grid.dz_pick_color = hue_cell_rgb(t.value) ^ 0xFFFFFFu32 }
        if t.kind == 12u8 { t.grid.dz_pick_color = t.grid.dz_custom[t.value] ^ 0xFFFFFFu32 }
        if t.kind == 7u8 { t.grid.dz_modes[t.value] = (t.grid.dz_modes[t.value] + 1u8) % 3u8 }
        if t.kind == 2u8 {
            t.grid.print_open = false
            t.grid.wiz_open = false
            t.grid.pv_design = false
        }
        ret ok
    default:
        ret ok
    }
}

// One check box and its words: a 15 px square, blue with a tick when on, grey words when disabled.
fn dz_check(a: *mem.Arena, grid: *Grid, tap: *DesignTap, k: usize) -> (widget.Node, err) {
    let on = ((grid.dz_checks >> u64(k)) & 1u64) != 0u64
    var ink: u32 = 0x000000u32
    if !dz_enabled(k) { ink = 0xA0A0A0u32 }
    let (words, words_error) = flat_text(a, grid, dz_label(k), gl.rgb(ink))
    if words_error != ok { ret (zero, words_error) }
    var mark = "v"
    if !on { mark = "" }
    let (tick, tick_error) = flat_text(a, grid, mark, gl.rgb(0xFFFFFFu32))
    if tick_error != ok { ret (zero, tick_error) }
    var box = control.sized_style(15.0, 15.0)
    box.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    if on { box.background = paint.Brush { Solid: gl.rgb(0x1F6FCFu32) } }
    box.border = style.Border { width: 1.0, color: gl.rgb(0x8E9092u32) }
    box.radius = 3.0
    box.margin = style.EdgeLengths { left: style.Length { Px: 0.0 }, top: style.Length { Px: 3.0 }, right: style.Length { Px: 6.0 }, bottom: style.Length { Px: 0.0 } }
    let (cells, cells_error) = mem.alloc[widget.Node](a, 2usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    cells[0usize] = widget.aligned(0u64, .Center, .Center, box, one(a, tick))
    cells[1usize] = widget.padded(0u64, 0.0, 2.0, 0.0, 0.0, style.defaults(), one(a, words))
    let line = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(300.0, 23.0), cells[0usize..2usize])
    if !dz_enabled(k) { ret (line, ok) }
    ret (widget.region(grid.key + MENU_KEY + 851000u64 + u64(k), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](tap), invoke: on_design_tap }, gestures: 1u8, enabled: true, focusable: false }, control.sized_style(300.0, 23.0), one(a, line)), ok)
}

fn dz_heading(a: *mem.Arena, grid: *Grid, text: str) -> (widget.Node, err) {
    let (words, words_error) = flat_text(a, grid, text, gl.rgb(0x000000u32))
    if words_error != ok { ret (zero, words_error) }
    ret (widget.padded(0u64, 4.0, 10.0, 0.0, 4.0, style.defaults(), one(a, words)), ok)
}

// The left page of the current tab: headings and check boxes in the items' order.
fn dz_page(a: *mem.Arena, grid: *Grid, taps: []DesignTap) -> (widget.Node, err) {
    let (rows, rows_error) = mem.alloc[widget.Node](a, 24usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    var n = 0usize
    var last: u8 = 255u8
    var k = 0usize
    while k < DZ_ITEMS {
        if dz_tab_of(k) == grid.dz_tab {
            let group = dz_group_of(k)
            if group != last && group != 0u8 {
                let (head, head_error) = dz_heading(a, grid, dz_group_name(group))
                if head_error != ok { ret (zero, head_error) }
                rows[n] = head
                n += 1usize
            }
            last = group
            taps[k] = DesignTap { grid: grid, kind: 1u8, value: k }
            let (line, line_error) = dz_check(a, grid, &taps[k], k)
            if line_error != ok { ret (zero, line_error) }
            rows[n] = line
            n += 1usize
        }
        k += 1usize
    }
    ret (widget.padded(0u64, 14.0, 4.0, 0.0, 0.0, style.defaults(), one(a, widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), rows[0usize..n]))), ok)
}

fn dz_tab_name(i: usize) -> str {
    if i == 0usize { ret "View" }
    if i == 1usize { ret "Behaviors" }
    if i == 2usize { ret "Formatting" }
    if i == 3usize { ret "Styles" }
    if i == 4usize { ret "Preview" }
    if i == 5usize { ret "Cards" }
    ret "Charts"
}

fn dz_tabs(a: *mem.Arena, grid: *Grid, taps: []DesignTap) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, 7usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    var i = 0usize
    while i < 7usize {
        taps[40usize + i] = DesignTap { grid: grid, kind: 0u8, value: i }
        let (words, words_error) = flat_text(a, grid, dz_tab_name(i), gl.rgb(0x000000u32))
        if words_error != ok { ret (zero, words_error) }
        var tab = control.sized_style(76.0, 24.0)
        if usize(grid.dz_tab) == i { tab.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) } }
        cells[i] = widget.region(grid.key + MENU_KEY + 851100u64 + u64(i), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&taps[40usize + i]), invoke: on_design_tap }, gestures: 1u8, enabled: true, focusable: false }, tab, one(a, widget.padded(0u64, 8.0, 4.0, 0.0, 0.0, style.defaults(), one(a, words))))
        i += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(560.0, 26.0), cells[0usize..7usize]), ok)
}

// The grid's first rows as the report would print them, in the right half.
fn dz_preview(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (lines, wide, lines_error) = export_rows(a, grid, 6usize, false)
    if lines_error != ok { ret (zero, lines_error) }
    var shown = wide
    if shown > 5usize { shown = 5usize }
    let (widths, widths_error) = mem.alloc[f32](a, shown + 1usize)
    if widths_error != ok { ret (zero, control.TooLarge) }
    var k = 0usize
    while k < shown {
        widths[k] = 330.0 / f32(shown)
        k += 1usize
    }
    let (rows, rows_error) = mem.alloc[widget.Node](a, 10usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    var n = 0usize
    var r = 0usize
    while r < lines.len && r < 6usize && shown > 0usize {
        let (row, row_error) = print_row(a, grid, lines[r][0usize..shown], widths[0usize..shown], r)
        if row_error != ok { ret (zero, row_error) }
        rows[n] = row
        n += 1usize
        r += 1usize
    }
    if ((grid.dz_checks >> 6u64) & 1u64) != 0u64 {
        let (filter_text, filter_error) = flat_text(a, grid, "<Filter is Empty>", gl.rgb(0xFFFFFFu32))
        if filter_error != ok { ret (zero, filter_error) }
        var strip = control.sized_style(330.0, 22.0)
        strip.background = paint.Brush { Solid: gl.rgb(0xA0A0A0u32) }
        strip.margin = style.EdgeLengths { left: style.Length { Px: 0.0 }, top: style.Length { Px: 150.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
        rows[n] = widget.box(0u64, strip, one(a, widget.padded(0u64, 4.0, 2.0, 0.0, 0.0, style.defaults(), one(a, filter_text))))
        n += 1usize
    }
    var frame = control.sized_style(340.0, 330.0)
    frame.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    frame.border = style.Border { width: 1.0, color: gl.rgb(0x8E9092u32) }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, frame, rows[0usize..n]), ok)
}

fn dz_buttons(a: *mem.Arena, grid: *Grid, tap: *DesignTap) -> (widget.Node, err) {
    let (apply_tap, apply_tap_error) = mem.alloc[DesignTap](a, 3usize)
    if apply_tap_error != ok { ret (zero, control.TooLarge) }
    apply_tap[0usize] = DesignTap { grid: grid, kind: 5u8, value: 0usize }
    apply_tap[1usize] = DesignTap { grid: grid, kind: 6u8, value: 1usize }
    apply_tap[2usize] = DesignTap { grid: grid, kind: 6u8, value: 2usize }
    let (cells, cells_error) = mem.alloc[widget.Node](a, 5usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    var i = 0usize
    while i < 5usize {
        var words = "Title Properties..."
        if i == 1usize { words = "Footnote Properties..." }
        if i == 2usize { words = "OK" }
        if i == 3usize { words = "Cancel" }
        if i == 4usize { words = "Apply" }
        let (label, label_error) = flat_text(a, grid, words, gl.rgb(dz_button_ink(grid, i)))
        if label_error != ok { ret (zero, label_error) }
        var box = control.sized_style(120.0, 28.0)
        box.background = paint.Brush { Solid: gl.rgb(0xFDFDFDu32) }
        box.border = style.Border { width: 1.0, color: gl.rgb(0xADADADu32) }
        box.radius = 4.0
        box.margin = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
        let held = widget.padded(0u64, 14.0, 6.0, 0.0, 0.0, style.defaults(), one(a, label))
        if i < 2usize {
            cells[i] = widget.region(grid.key + MENU_KEY + 851210u64 + u64(i), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&apply_tap[1usize + i]), invoke: on_design_tap }, gestures: 1u8, enabled: true, focusable: false }, box, one(a, held))
        } else if i == 4usize && grid.dz_dirty {
            cells[i] = widget.region(grid.key + MENU_KEY + 851204u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&apply_tap[0usize]), invoke: on_design_tap }, gestures: 1u8, enabled: true, focusable: false }, box, one(a, held))
        } else if i >= 2usize && i < 4usize {
            cells[i] = widget.region(grid.key + MENU_KEY + 851200u64 + u64(i), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](tap), invoke: on_design_tap }, gestures: 1u8, enabled: true, focusable: false }, box, one(a, held))
        } else {
            cells[i] = widget.box(0u64, box, one(a, held))
        }
        i += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(880.0, 36.0), cells[0usize..5usize]), ok)
}

fn designer_panel(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    if grid.dz_dlg == 3u8 {
        let (font_node, font_error) = dz_font_dialog(a, grid)
        ret (font_node, font_error)
    }
    if grid.dz_dlg == 4u8 {
        let (color_node, color_error) = dz_color_dialog(a, grid)
        ret (color_node, color_error)
    }
    if grid.dz_dlg != 0u8 {
        let (dialog, dialog_error) = dz_dialog(a, grid)
        ret (dialog, dialog_error)
    }
    let (taps, taps_error) = mem.alloc[DesignTap](a, 48usize)
    if taps_error != ok { ret (zero, control.TooLarge) }
    taps[47usize] = DesignTap { grid: grid, kind: 2u8, value: 0usize }
    let (rows, rows_error) = mem.alloc[widget.Node](a, 4usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    let (title, title_error) = window_title(a, grid, 2u8, "Format Report", 770.0, 36.0, false)
    if title_error != ok { ret (zero, title_error) }
    rows[0usize] = title
    let (tabs, tabs_error) = dz_tabs(a, grid, taps)
    if tabs_error != ok { ret (zero, tabs_error) }
    let (page, page_error) = dz_page(a, grid, taps)
    if page_error != ok { ret (zero, page_error) }
    let (look, look_error) = dz_preview(a, grid)
    if look_error != ok { ret (zero, look_error) }
    let (halves, halves_error) = mem.alloc[widget.Node](a, 2usize)
    if halves_error != ok { ret (zero, control.TooLarge) }
    let (left, left_error) = mem.alloc[widget.Node](a, 3usize)
    if left_error != ok { ret (zero, control.TooLarge) }
    left[0usize] = tabs
    left[1usize] = page
    let (extra, extra_error) = dz_extra(a, grid)
    if extra_error != ok { ret (zero, extra_error) }
    left[2usize] = extra
    if grid.dz_tab == 2u8 {
        left[1usize] = extra
        left[2usize] = page
    }
    halves[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(370.0, 380.0), left[0usize..3usize])
    halves[1usize] = widget.padded(0u64, 8.0, 4.0, 0.0, 0.0, style.defaults(), one(a, look))
    rows[1usize] = widget.padded(0u64, 14.0, 10.0, 0.0, 0.0, style.defaults(), one(a, widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(740.0, 390.0), halves[0usize..2usize])))
    let (buttons, buttons_error) = dz_buttons(a, grid, &taps[47usize])
    if buttons_error != ok { ret (zero, buttons_error) }
    rows[2usize] = widget.padded(0u64, 14.0, 6.0, 0.0, 0.0, style.defaults(), one(a, buttons))
    var panel = control.sized_style(770.0, 500.0)
    panel.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    panel.border = style.Border { width: 1.0, color: gl.rgb(0x8E9092u32) }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, panel, rows[0usize..3usize]), ok)
}

fn dz_style_name(i: usize) -> str {
    if i == 0usize { ret "BandHeader" }
    if i == 1usize { ret "Caption" }
    if i == 2usize { ret "Card Caption Row" }
    if i == 3usize { ret "Card Row Caption" }
    if i == 4usize { ret "Content" }
    if i == 5usize { ret "Content Even Rows" }
    if i == 6usize { ret "Content Odd Rows" }
    if i == 7usize { ret "Filter Bar" }
    if i == 8usize { ret "Footer" }
    if i == 9usize { ret "Group" }
    if i == 10usize { ret "Header" }
    if i == 11usize { ret "Preview" }
    ret "Selection"
}

// A white box with words in it (a combo, a spin value): v3's Flat and Max Line Count.
fn dz_field(a: *mem.Arena, grid: *Grid, text: str, width: f32) -> (widget.Node, err) {
    let (box, box_error) = v3_edit(a, grid, text, width)
    ret (box, box_error)
}

// The Styles tab's list: thirteen named styles, each with its sample strip and "8 pt. Tahoma".
fn dz_style_box(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (rows, rows_error) = mem.alloc[widget.Node](a, 13usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    let (picks, picks_error) = mem.alloc[DesignTap](a, 13usize)
    if picks_error != ok { ret (zero, control.TooLarge) }
    var i = 0usize
    while i < 13usize {
        picks[i] = DesignTap { grid: grid, kind: 3u8, value: i }
        let (name, name_error) = flat_text(a, grid, dz_style_name(i), gl.rgb(dz_list_ink(grid)))
        if name_error != ok { ret (zero, name_error) }
        let (face, face_error) = flat_text(a, grid, "8 pt. Tahoma", gl.rgb(dz_list_ink(grid)))
        if face_error != ok { ret (zero, face_error) }
        var strip = control.sized_style(50.0, 14.0)
        strip.background = paint.Brush { Solid: gl.rgb(dz_strip_rgb(grid, i)) }
        strip.border = style.Border { width: 1.0, color: gl.rgb(0x8E9092u32) }
        strip.margin = style.EdgeLengths { left: style.Length { Px: 0.0 }, top: style.Length { Px: 4.0 }, right: style.Length { Px: 6.0 }, bottom: style.Length { Px: 0.0 } }
        let (cells, cells_error) = mem.alloc[widget.Node](a, 3usize)
        if cells_error != ok { ret (zero, control.TooLarge) }
        cells[0usize] = widget.padded(0u64, 4.0, 2.0, 0.0, 0.0, control.sized_style(104.0, 20.0), one(a, name))
        cells[1usize] = widget.box(0u64, strip, zero)
        cells[2usize] = widget.padded(0u64, 0.0, 2.0, 0.0, 0.0, style.defaults(), one(a, face))
        let row_line = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, dz_row_style(grid, i), cells[0usize..3usize])
        rows[i] = widget.region(grid.key + MENU_KEY + 851300u64 + u64(i), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&picks[i]), invoke: on_design_tap }, gestures: 1u8, enabled: true, focusable: false }, control.sized_style(250.0, 20.0), one(a, row_line))
        i += 1usize
    }
    var frame = control.sized_style(250.0, 264.0)
    frame.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    frame.border = style.Border { width: 1.0, color: gl.rgb(0x8E9092u32) }
    frame.margin = style.EdgeLengths { left: style.Length { Px: 0.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, frame, rows[0usize..13usize]), ok)
}

// What a tab shows besides its check boxes: Formatting's look-and-feel box, Styles' list, Preview's line count.
fn dz_extra(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    if grid.dz_tab == 3u8 {
        let (list, list_error) = dz_style_list(a, grid)
        ret (list, list_error)
    }
    if grid.dz_tab == 2u8 {
        let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
        if parts_error != ok { ret (zero, control.TooLarge) }
        let (look_head, look_head_error) = dz_heading(a, grid, "Look and Feel")
        if look_head_error != ok { ret (zero, look_head_error) }
        let (flat, flat_error) = dz_field(a, grid, "Flat", 280.0)
        if flat_error != ok { ret (zero, flat_error) }
        parts[0usize] = look_head
        parts[1usize] = flat
        ret (widget.padded(0u64, 14.0, 0.0, 0.0, 0.0, style.defaults(), one(a, widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(330.0, 70.0), parts[0usize..2usize]))), ok)
    }
    if grid.dz_tab == 4u8 {
        let (count, count_error) = dz_field(a, grid, "Max Line Count:   0", 280.0)
        ret (count, count_error)
    }
    ret (widget.box(0u64, style.defaults(), zero), ok)
}

// Apply is grey (nothing to apply yet), the other buttons black.
fn dz_button_ink(grid: *const Grid, i: usize) -> u32 {
    if i == 4usize && !grid.dz_dirty { ret 0xA0A0A0u32 }
    ret 0x000000u32
}

// A grey, inert button of the Styles tab (v3 enables them with a style picked).
fn dz_grey_button(a: *mem.Arena, grid: *Grid, text: str, width: f32, top: f32) -> (widget.Node, err) {
    let enabled = dz_button_ink_for(grid, width) == 0x000000u32
    let (idle, idle_error) = mem.alloc[DesignTap](a, 1usize)
    if idle_error != ok { ret (zero, control.TooLarge) }
    idle[0usize] = DesignTap { grid: grid, kind: 255u8, value: 0usize }
    let (button, button_error) = v3_button(a, grid, text, width, 0u64, &idle[0usize], enabled, top)
    ret (button, button_error)
}

// The button column right of the style list: Font..., Color..., Texture..., Clear.
fn dz_style_buttons(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, 4usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    let (clear_tap, clear_tap_error) = mem.alloc[DesignTap](a, 3usize)
    if clear_tap_error != ok { ret (zero, control.TooLarge) }
    clear_tap[0usize] = DesignTap { grid: grid, kind: 8u8, value: 0usize }
    clear_tap[1usize] = DesignTap { grid: grid, kind: 6u8, value: 3usize }
    clear_tap[2usize] = DesignTap { grid: grid, kind: 6u8, value: 4usize }
    var i = 0usize
    while i < 4usize {
        var words = "Font..."
        if i == 1usize { words = "Color..." }
        if i == 2usize { words = "Texture..." }
        if i == 3usize { words = "Clear" }
        let (button, button_error) = dz_grey_button(a, grid, words, 80.0, 2.0)
        if button_error != ok { ret (zero, button_error) }
        cells[i] = button
        if i == 0usize && grid.dz_style != 0u8 {
            cells[i] = widget.region(grid.key + MENU_KEY + 851281u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&clear_tap[1usize]), invoke: on_design_tap }, gestures: 1u8, enabled: true, focusable: false }, control.sized_style(92.0, 32.0), one(a, button))
        }
        if i == 1usize && grid.dz_style != 0u8 {
            cells[i] = widget.region(grid.key + MENU_KEY + 851282u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&clear_tap[2usize]), invoke: on_design_tap }, gestures: 1u8, enabled: true, focusable: false }, control.sized_style(92.0, 32.0), one(a, button))
        }
        if i == 3usize && grid.dz_style != 0u8 {
            cells[i] = widget.region(grid.key + MENU_KEY + 851280u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&clear_tap[0usize]), invoke: on_design_tap }, gestures: 1u8, enabled: true, focusable: false }, control.sized_style(92.0, 32.0), one(a, button))
        }
        i += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(92.0, 130.0), cells[0usize..4usize]), ok)
}

// Restore Defaults and Save As..., then the Style Sheets box.
fn dz_style_foot(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, 4usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    let (restore, restore_error) = dz_grey_button(a, grid, "Restore Defaults", 120.0, 4.0)
    if restore_error != ok { ret (zero, restore_error) }
    let (save, save_error) = dz_grey_button(a, grid, "Save As...", 100.0, 4.0)
    if save_error != ok { ret (zero, save_error) }
    let (row, row_error) = mem.alloc[widget.Node](a, 2usize)
    if row_error != ok { ret (zero, control.TooLarge) }
    row[0usize] = restore
    row[1usize] = save
    cells[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(340.0, 32.0), row[0usize..2usize])
    let (head, head_error) = dz_heading(a, grid, "Style Sheets")
    if head_error != ok { ret (zero, head_error) }
    cells[1usize] = head
    let (combo, combo_error) = dz_field(a, grid, "", 330.0)
    if combo_error != ok { ret (zero, combo_error) }
    cells[2usize] = combo
    let (sheet_row, sheet_row_error) = dz_sheet_buttons(a, grid)
    if sheet_row_error != ok { ret (zero, sheet_row_error) }
    cells[3usize] = sheet_row
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(350.0, 170.0), cells[0usize..4usize]), ok)
}

fn dz_style_list(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (box, box_error) = dz_style_box(a, grid)
    if box_error != ok { ret (zero, box_error) }
    let (buttons, buttons_error) = dz_style_buttons(a, grid)
    if buttons_error != ok { ret (zero, buttons_error) }
    let (foot, foot_error) = dz_style_foot(a, grid)
    if foot_error != ok { ret (zero, foot_error) }
    let (top, top_error) = mem.alloc[widget.Node](a, 2usize)
    if top_error != ok { ret (zero, control.TooLarge) }
    top[0usize] = box
    top[1usize] = buttons
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    parts[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(350.0, 268.0), top[0usize..2usize])
    parts[1usize] = foot
    ret (widget.padded(0u64, 14.0, 8.0, 0.0, 0.0, style.defaults(), one(a, widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(350.0, 400.0), parts[0usize..2usize]))), ok)
}

// Rows a preview page holds: ten at the default Top and Bottom margins (0.50 in each), one fewer for
// each 27 sheet pixels the two margins take beyond that, one more for each 27 they give back.
fn page_rows(grid: *const Grid) -> usize {
    var sheet: f32 = 690.0
    if grid.pv_orient == 1u8 { sheet = 450.0 }
    let default_px = sheet / (if_f(grid.pv_orient == 1u8, 8.5, 11.0)) * 0.5
    let extra = margin_px(grid, 1usize, sheet) + margin_px(grid, 3usize, sheet) - 2.0 * default_px
    var rows: i64 = 10i64 - i64(extra / 27.0)
    if extra < 0.0 { rows = 10i64 + i64(-extra / 27.0) }
    if rows < 1i64 { rows = 1i64 }
    if rows > 14i64 { rows = 14i64 }
    ret usize(rows)
}

fn if_f(c: bool, a: f32, b: f32) -> f32 {
    if c { ret a }
    ret b
}

// A row of the Styles list: light blue while picked.
fn dz_row_style(grid: *const Grid, i: usize) -> style.Style {
    var s = control.sized_style(250.0, 20.0)
    if usize(grid.dz_style) == i + 1usize { s.background = paint.Brush { Solid: gl.rgb(0xCCE8FFu32) } }
    ret s
}

// Font..., Color..., Texture... and Clear turn black once a style is picked (they still change nothing).
fn dz_style_ink(grid: *const Grid) -> u32 {
    if grid.dz_style != 0u8 { ret 0x000000u32 }
    ret 0xA0A0A0u32
}

// The four 80 px buttons follow the picked style; Restore Defaults and Save As stay grey.
fn dz_button_ink_for(grid: *const Grid, width: f32) -> u32 {
    let native = ((grid.dz_checks >> 28u64) & 1u64) != 0u64
    if !native { ret 0xA0A0A0u32 }
    if width < 76.5 && width > 75.5 { ret 0x000000u32 }
    if width > 99.0 && width < 101.0 { ret 0x000000u32 }
    if width < 90.0 && width > 79.0 { ret dz_style_ink(grid) }
    ret 0xA0A0A0u32
}

// ---- Title Properties / Footnote Properties: v3's "Report Title" window ----

fn dz_dialog_button(a: *mem.Arena, grid: *Grid, text: str, tap: *DesignTap, key: u64) -> (widget.Node, err) {
    let (button, button_error) = v3_button(a, grid, text, 0.0, key, tap, true, 0.0)
    ret (button, button_error)
}

// The dialog body: Mode, the Text / Properties tabs, a white text area, OK and Cancel.
fn dz_dialog(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    var heading = "Report Title"
    var body = "Card Pool"
    if grid.dz_dlg == 2u8 {
        heading = "Report Footnote"
        body = ""
    }
    let (rows, rows_error) = mem.alloc[widget.Node](a, 6usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    let (close, close_error) = mem.alloc[DesignTap](a, 2usize)
    if close_error != ok { ret (zero, control.TooLarge) }
    close[0usize] = DesignTap { grid: grid, kind: 6u8, value: 0usize }
    close[1usize] = DesignTap { grid: grid, kind: 7u8, value: usize(grid.dz_dlg) - 1usize }
    let (title, title_error) = dz_heading(a, grid, heading)
    if title_error != ok { ret (zero, title_error) }
    rows[0usize] = title
    let (mode, mode_error) = dz_mode_row(a, grid, &close[1usize])
    if mode_error != ok { ret (zero, mode_error) }
    rows[1usize] = mode
    let (tabs, tabs_error) = dz_field(a, grid, "Text      Properties", 200.0)
    if tabs_error != ok { ret (zero, tabs_error) }
    rows[2usize] = tabs
    let (words, words_error) = flat_text(a, grid, body, gl.rgb(0x000000u32))
    if words_error != ok { ret (zero, words_error) }
    var area = control.sized_style(550.0, 300.0)
    area.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    area.border = style.Border { width: 1.0, color: gl.rgb(0xC8C8C8u32) }
    area.margin = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: style.Length { Px: 6.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    rows[3usize] = widget.box(0u64, area, one(a, widget.padded(0u64, 4.0, 4.0, 0.0, 0.0, style.defaults(), one(a, words))))
    if grid.dz_dlg == 1u8 {
        let (title_field, title_field_error) = dz_title_field(a, grid)
        if title_field_error != ok { ret (zero, title_field_error) }
        rows[3usize] = widget.padded(0u64, 8.0, 6.0, 0.0, 0.0, style.defaults(), one(a, title_field))
    }
    if grid.dz_dlg == 2u8 {
        let (foot_field, foot_field_error) = dz_foot_field(a, grid)
        if foot_field_error != ok { ret (zero, foot_field_error) }
        rows[3usize] = widget.padded(0u64, 8.0, 6.0, 0.0, 0.0, style.defaults(), one(a, foot_field))
    }
    let (ok_button, ok_error) = dz_dialog_button(a, grid, "OK", &close[0usize], grid.key + MENU_KEY + 851250u64)
    if ok_error != ok { ret (zero, ok_error) }
    let (cancel_button, cancel_error) = dz_dialog_button(a, grid, "Cancel", &close[0usize], grid.key + MENU_KEY + 851251u64)
    if cancel_error != ok { ret (zero, cancel_error) }
    let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
    if pair_error != ok { ret (zero, control.TooLarge) }
    pair[0usize] = ok_button
    pair[1usize] = cancel_button
    rows[4usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(560.0, 44.0), pair[0usize..2usize])
    var panel = control.sized_style(600.0, 480.0)
    panel.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    panel.border = style.Border { width: 1.0, color: gl.rgb(0x8E9092u32) }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, panel, rows[0usize..5usize]), ok)
}

// The report's title: what Title Properties holds, "Collection" until it has been opened.
fn report_title(a: *mem.Arena, grid: *const Grid) -> (str, err) {
    if !dz_prints_here(grid, 0usize) { ret ("", ok) }
    if !grid.dz_title_set { ret ("Collection", ok) }
    let (b, b_error) = str.builder(a, 56usize)
    if b_error != ok { ret ("", b_error) }
    var sb = b
    var i = 0usize
    while i < grid.dz_title_len {
        if str.push_byte(&sb, grid.dz_title[i]) != ok { ret ("", control.TooLarge) }
        i += 1usize
    }
    ret (str.done(&sb), ok)
}

fn on_title_text(ctx: *void, value: str) -> err {
    let grid = mem.cast[*Grid](ctx)
    var n = value.len
    if n > 48usize { n = 48usize }
    var i = 0usize
    while i < n {
        grid.dz_title[i] = value[i]
        i += 1usize
    }
    grid.dz_title_len = n
    grid.dz_title_set = true
    ret ok
}

// The text area of Title Properties: an editable field seeded with "Card Pool".
fn dz_title_field(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    if !grid.dz_title_set {
        var i = 0usize
        let seed = "Card Pool"
        while i < seed.len {
            grid.dz_title[i] = seed[i]
            i += 1usize
        }
        grid.dz_title_len = seed.len
    }
    var options = control.field_options()
    options.rows = 12u32
    options.filled = false
    options.width = 550.0
    options.height = 300.0
    let (field, field_error) = control.text_field(a, grid.key + MENU_KEY + 851260u64, grid.theme, "", grid.dz_title[0usize..48usize], grid.dz_title_len, widget.Change[str] { ctx: mem.cast[*void](grid), invoke: on_title_text }, zero, options)
    ret (field, field_error)
}

// The report's heading over the table, from the report title.
fn preview_heading(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (text, text_error) = report_title(a, grid)
    if text_error != ok { ret (zero, text_error) }
    let (node, node_error) = flat_text(a, grid, text, gl.rgb(0x000000u32))
    ret (node, node_error)
}

fn on_foot_text(ctx: *void, value: str) -> err {
    let grid = mem.cast[*Grid](ctx)
    var n = value.len
    if n > 48usize { n = 48usize }
    var i = 0usize
    while i < n {
        grid.dz_foot[i] = value[i]
        i += 1usize
    }
    grid.dz_foot_len = n
    ret ok
}

// The text area of Footnote Properties: an editable field, empty until typed in.
fn dz_foot_field(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    var options = control.field_options()
    options.rows = 12u32
    options.filled = false
    options.width = 550.0
    options.height = 300.0
    let (field, field_error) = control.text_field(a, grid.key + MENU_KEY + 851261u64, grid.theme, "", grid.dz_foot[0usize..48usize], grid.dz_foot_len, widget.Change[str] { ctx: mem.cast[*void](grid), invoke: on_foot_text }, zero, options)
    ret (field, field_error)
}

// The footnote Footnote Properties holds, one line under the footer band (an empty box when there is none).
fn preview_footnote(a: *mem.Arena, grid: *Grid, left: f32) -> widget.Node {
    var none = control.sized_style(1.0, 1.0)
    if grid.dz_foot_len == 0usize || !dz_prints_here(grid, 1usize) { ret widget.box(0u64, none, zero) }
    let (b, b_error) = str.builder(a, 56usize)
    if b_error != ok { ret widget.box(0u64, none, zero) }
    var sb = b
    var i = 0usize
    while i < grid.dz_foot_len {
        if str.push_byte(&sb, grid.dz_foot[i]) != ok { ret widget.box(0u64, none, zero) }
        i += 1usize
    }
    let (words, words_error) = flat_text(a, grid, str.done(&sb), gl.rgb(0x000000u32))
    if words_error != ok { ret widget.box(0u64, none, zero) }
    ret widget.padded(0u64, left, 2.0, 0.0, 0.0, style.defaults(), one(a, words))
}

fn dz_mode_words(mode: u8) -> str {
    if mode == 1u8 { ret "Mode:   On Every Page" }
    if mode == 2u8 { ret "Mode:   Do Not Print" }
    ret "Mode:   On First Page"
}

// The Mode box of Title / Footnote Properties: a tap steps first page, every page, not printed.
fn dz_mode_row(a: *mem.Arena, grid: *Grid, tap: *DesignTap) -> (widget.Node, err) {
    let (box, box_error) = dz_field(a, grid, dz_mode_words(grid.dz_modes[tap.value]), 560.0)
    if box_error != ok { ret (zero, box_error) }
    ret (widget.region(grid.key + MENU_KEY + 851270u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](tap), invoke: on_design_tap }, gestures: 1u8, enabled: true, focusable: false }, control.sized_style(570.0, 34.0), one(a, box)), ok)
}

// Whether the title (0) or footnote (1) prints on the page being shown.
fn dz_prints_here(grid: *const Grid, which: usize) -> bool {
    let mode = grid.dz_modes[which]
    if mode == 2u8 { ret false }
    if mode == 0u8 && grid.pv_page != 0usize { ret false }
    ret true
}

// v3's New..., Copy..., Delete..., Rename... under the Style Sheets box (only New is live, grey with native styles off).
fn dz_sheet_buttons(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, 4usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    var i = 0usize
    while i < 4usize {
        var words = "New..."
        var width: f32 = 76.0
        if i == 1usize {
            words = "Copy..."
            width = 77.0
        }
        if i == 2usize {
            words = "Delete..."
            width = 77.0
        }
        if i == 3usize {
            words = "Rename..."
            width = 77.0
        }
        let (button, button_error) = dz_grey_button(a, grid, words, width, 8.0)
        if button_error != ok { ret (zero, button_error) }
        cells[i] = button
        i += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(350.0, 36.0), cells[0usize..4usize]), ok)
}

// The style list's text: black, grey once "Use Native Styles" is unticked (as v3 draws it).
fn dz_list_ink(grid: *const Grid) -> u32 {
    if ((grid.dz_checks >> 28u64) & 1u64) == 0u64 { ret 0xA0A0A0u32 }
    ret 0x000000u32
}

// ---- the Font window of the Styles tab (v3: the system's font dialog) ----

// A white list box: one line per entry, the first one highlighted blue.
fn dz_pick_list(a: *mem.Arena, grid: *Grid, items: []const str, width: f32, height: f32) -> (widget.Node, err) {
    let (rows, rows_error) = mem.alloc[widget.Node](a, items.len + 1usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    var i = 0usize
    while i < items.len {
        var ink: u32 = 0x000000u32
        if i == 0usize { ink = 0xFFFFFFu32 }
        let (words, words_error) = flat_text(a, grid, items[i], gl.rgb(ink))
        if words_error != ok { ret (zero, words_error) }
        var line = control.sized_style(width - 2.0, 20.0)
        if i == 0usize { line.background = paint.Brush { Solid: gl.rgb(0x0078D7u32) } }
        rows[i] = widget.box(0u64, line, one(a, widget.padded(0u64, 3.0, 2.0, 0.0, 0.0, style.defaults(), one(a, words))))
        i += 1usize
    }
    var frame = control.sized_style(width, height)
    frame.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    frame.border = style.Border { width: 1.0, color: gl.rgb(0x828790u32) }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, frame, rows[0usize..items.len]), ok)
}

fn dz_font_lists(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, 3usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    let names: [7]str = [7]str{ "Tahoma", "Tempus Sans ITC", "Times New Roman", "Trebuchet MS", "Tw Cen MT", "Ubuntu Mono", "Verdana" }
    let looks: [4]str = [4]str{ "Regular", "Bold", "Oblique", "Bold Oblique" }
    let sizes: [8]str = [8]str{ "8", "9", "10", "11", "12", "14", "16", "18" }
    let (font_list, font_error) = dz_pick_list(a, grid, names[0usize..7usize], 220.0, 142.0)
    if font_error != ok { ret (zero, font_error) }
    let (look_list, look_error) = dz_pick_list(a, grid, looks[0usize..4usize], 166.0, 142.0)
    if look_error != ok { ret (zero, look_error) }
    let (size_list, size_error) = dz_pick_list(a, grid, sizes[0usize..8usize], 84.0, 142.0)
    if size_error != ok { ret (zero, size_error) }
    cells[0usize] = widget.padded(0u64, 16.0, 0.0, 0.0, 0.0, style.defaults(), one(a, font_list))
    cells[1usize] = widget.padded(0u64, 12.0, 0.0, 0.0, 0.0, style.defaults(), one(a, look_list))
    cells[2usize] = widget.padded(0u64, 12.0, 0.0, 0.0, 0.0, style.defaults(), one(a, size_list))
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(560.0, 150.0), cells[0usize..3usize]), ok)
}

fn dz_font_effects(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, 4usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    let (head, head_error) = dz_heading(a, grid, "Effects")
    if head_error != ok { ret (zero, head_error) }
    cells[0usize] = head
    let (strike, strike_error) = dz_field(a, grid, "[ ] Strikeout", 200.0)
    if strike_error != ok { ret (zero, strike_error) }
    cells[1usize] = strike
    let (under, under_error) = dz_field(a, grid, "[ ] Underline", 200.0)
    if under_error != ok { ret (zero, under_error) }
    cells[2usize] = under
    let (color, color_error) = dz_field(a, grid, "Color:  Black", 200.0)
    if color_error != ok { ret (zero, color_error) }
    cells[3usize] = color
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(240.0, 200.0), cells[0usize..4usize]), ok)
}

fn dz_font_sample(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (head, head_error) = dz_heading(a, grid, "Sample")
    if head_error != ok { ret (zero, head_error) }
    let (words, words_error) = flat_text(a, grid, "AaBbYyZz", gl.rgb(0x000000u32))
    if words_error != ok { ret (zero, words_error) }
    var box = control.sized_style(250.0, 70.0)
    box.border = style.Border { width: 1.0, color: gl.rgb(0xD0D0D0u32) }
    box.margin = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    let (script, script_error) = dz_field(a, grid, "Script:   Western", 250.0)
    if script_error != ok { ret (zero, script_error) }
    let (cells, cells_error) = mem.alloc[widget.Node](a, 3usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    cells[0usize] = head
    cells[1usize] = widget.box(0u64, box, one(a, widget.padded(0u64, 90.0, 26.0, 0.0, 0.0, style.defaults(), one(a, words))))
    cells[2usize] = script
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(270.0, 200.0), cells[0usize..3usize]), ok)
}

fn dz_font_dialog(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (rows, rows_error) = mem.alloc[widget.Node](a, 5usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    let (close, close_error) = mem.alloc[DesignTap](a, 1usize)
    if close_error != ok { ret (zero, control.TooLarge) }
    close[0usize] = DesignTap { grid: grid, kind: 6u8, value: 0usize }
    let (title, title_error) = dz_heading(a, grid, "Font")
    if title_error != ok { ret (zero, title_error) }
    rows[0usize] = title
    let (lists, lists_error) = dz_font_lists(a, grid)
    if lists_error != ok { ret (zero, lists_error) }
    rows[1usize] = lists
    let (effects, effects_error) = dz_font_effects(a, grid)
    if effects_error != ok { ret (zero, effects_error) }
    let (sample, sample_error) = dz_font_sample(a, grid)
    if sample_error != ok { ret (zero, sample_error) }
    let (low, low_error) = mem.alloc[widget.Node](a, 2usize)
    if low_error != ok { ret (zero, control.TooLarge) }
    low[0usize] = effects
    low[1usize] = sample
    rows[2usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(560.0, 210.0), low[0usize..2usize])
    let (ok_button, ok_error) = dz_dialog_button(a, grid, "OK", &close[0usize], grid.key + MENU_KEY + 851252u64)
    if ok_error != ok { ret (zero, ok_error) }
    let (cancel_button, cancel_error) = dz_dialog_button(a, grid, "Cancel", &close[0usize], grid.key + MENU_KEY + 851253u64)
    if cancel_error != ok { ret (zero, cancel_error) }
    let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
    if pair_error != ok { ret (zero, control.TooLarge) }
    pair[0usize] = ok_button
    pair[1usize] = cancel_button
    rows[3usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(560.0, 44.0), pair[0usize..2usize])
    var panel = control.sized_style(620.0, 520.0)
    panel.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    panel.border = style.Border { width: 1.0, color: gl.rgb(0x8E9092u32) }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, panel, rows[0usize..4usize]), ok)
}

// ---- the Color Editor of the Styles tab (v3: the DevExpress colour editor) ----

fn dz_swatch_grid(a: *mem.Arena, grid: *Grid, rows_n: usize, filled: bool) -> (widget.Node, err) {
    let (rows, rows_error) = mem.alloc[widget.Node](a, rows_n + 1usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    let (taps, taps_error) = mem.alloc[DesignTap](a, 49usize)
    if taps_error != ok { ret (zero, control.TooLarge) }
    var r = 0usize
    while r < rows_n {
        let (cells, cells_error) = mem.alloc[widget.Node](a, 8usize)
        if cells_error != ok { ret (zero, control.TooLarge) }
        var c = 0usize
        while c < 8usize {
            var cell = control.sized_style(32.0, 30.0)
            cell.border = style.Border { width: 1.0, color: gl.rgb(0xA0A0A0u32) }
            cell.margin = style.EdgeLengths { left: style.Length { Px: 2.0 }, top: style.Length { Px: 2.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
            if filled { cell.background = paint.Brush { Solid: gl.rgb(windows_basic(r * 8usize + c)) } }
            let used = !filled && r * 8usize + c < grid.dz_custom_n
            if used { cell.background = paint.Brush { Solid: gl.rgb(grid.dz_custom[r * 8usize + c]) } }
            cells[c] = widget.box(0u64, cell, zero)
            if filled || used {
                var kind: u8 = 9u8
                if used { kind = 12u8 }
                taps[r * 8usize + c] = DesignTap { grid: grid, kind: kind, value: r * 8usize + c }
                cells[c] = widget.region(grid.key + MENU_KEY + 851400u64 + u64(kind) * 100u64 + u64(r * 8usize + c), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&taps[r * 8usize + c]), invoke: on_design_tap }, gestures: 1u8, enabled: true, focusable: false }, cell, zero)
            }
            c += 1usize
        }
        rows[r] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), cells[0usize..8usize])
        r += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), rows[0usize..rows_n]), ok)
}

fn dz_color_left(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 5usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    let (basic_head, basic_error) = dz_heading(a, grid, "Basic Colors")
    if basic_error != ok { ret (zero, basic_error) }
    let (basic, basic_grid_error) = dz_swatch_grid(a, grid, 6usize, true)
    if basic_grid_error != ok { ret (zero, basic_grid_error) }
    let (custom_head, custom_error) = dz_heading(a, grid, "Custom Colors")
    if custom_error != ok { ret (zero, custom_error) }
    let (custom, custom_grid_error) = dz_swatch_grid(a, grid, 2usize, false)
    if custom_grid_error != ok { ret (zero, custom_grid_error) }
    let (define, define_error) = dz_field(a, grid, "Define Custom Colors >>", 300.0)
    if define_error != ok { ret (zero, define_error) }
    parts[0usize] = basic_head
    parts[1usize] = basic
    parts[2usize] = custom_head
    parts[3usize] = custom
    parts[4usize] = define
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(310.0, 400.0), parts[0usize..5usize]), ok)
}

fn dz_color_right(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 10usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    let picked = grid.dz_pick_color ^ 0xFFFFFFu32
    let (square, square_error) = dz_hue_square(a, grid, picked)
    if square_error != ok { ret (zero, square_error) }
    parts[0usize] = square
    var i = 0usize
    while i < 6usize {
        var label = "H:"
        var value: u32 = hsl_channel(picked, 0usize)
        if i == 1usize {
            label = "S:"
            value = hsl_channel(picked, 1usize)
        }
        if i == 2usize {
            label = "L:"
            value = hsl_channel(picked, 2usize)
        }
        if i == 3usize {
            label = "R:"
            value = (picked >> 16u32) & 255u32
        }
        if i == 4usize {
            label = "G:"
            value = (picked >> 8u32) & 255u32
        }
        if i == 5usize {
            label = "B:"
            value = picked & 255u32
        }
        let (words, words_error) = dz_channel_text(a, label, value)
        if words_error != ok { ret (zero, words_error) }
        let (box, box_error) = dz_field(a, grid, words, 140.0)
        if box_error != ok { ret (zero, box_error) }
        parts[1usize + i] = box
        if i >= 3usize {
            let (spin, spin_error) = dz_channel_spin(a, grid, i - 3usize, value)
            if spin_error != ok { ret (zero, spin_error) }
            parts[1usize + i] = spin
        }
        i += 1usize
    }
    let (hex_text, hex_text_error) = hex_label(a, picked)
    if hex_text_error != ok { ret (zero, hex_text_error) }
    let (hex_box, hex_box_error) = dz_field(a, grid, hex_text, 140.0)
    if hex_box_error != ok { ret (zero, hex_box_error) }
    parts[7usize] = hex_box
    let (add_tap, add_tap_error) = mem.alloc[DesignTap](a, 1usize)
    if add_tap_error != ok { ret (zero, control.TooLarge) }
    add_tap[0usize] = DesignTap { grid: grid, kind: 11u8, value: 0usize }
    let (add_button, add_button_error) = dz_dialog_button(a, grid, "Add to Custom Colors", &add_tap[0usize], grid.key + MENU_KEY + 851256u64)
    if add_button_error != ok { ret (zero, add_button_error) }
    parts[8usize] = add_button
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(330.0, 470.0), parts[0usize..9usize]), ok)
}

fn dz_color_dialog(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (rows, rows_error) = mem.alloc[widget.Node](a, 4usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    let (close, close_error) = mem.alloc[DesignTap](a, 2usize)
    if close_error != ok { ret (zero, control.TooLarge) }
    close[0usize] = DesignTap { grid: grid, kind: 6u8, value: 0usize }
    close[1usize] = DesignTap { grid: grid, kind: 10u8, value: 0usize }
    let (title, title_error) = dz_heading(a, grid, "Color Editor")
    if title_error != ok { ret (zero, title_error) }
    rows[0usize] = title
    let (left, left_error) = dz_color_left(a, grid)
    if left_error != ok { ret (zero, left_error) }
    let (right, right_error) = dz_color_right(a, grid)
    if right_error != ok { ret (zero, right_error) }
    let (halves, halves_error) = mem.alloc[widget.Node](a, 2usize)
    if halves_error != ok { ret (zero, control.TooLarge) }
    halves[0usize] = left
    halves[1usize] = right
    rows[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(680.0, 480.0), halves[0usize..2usize])
    let (ok_button, ok_error) = dz_dialog_button(a, grid, "OK", &close[1usize], grid.key + MENU_KEY + 851254u64)
    if ok_error != ok { ret (zero, ok_error) }
    let (cancel_button, cancel_error) = dz_dialog_button(a, grid, "Cancel", &close[0usize], grid.key + MENU_KEY + 851255u64)
    if cancel_error != ok { ret (zero, cancel_error) }
    let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
    if pair_error != ok { ret (zero, control.TooLarge) }
    pair[0usize] = ok_button
    pair[1usize] = cancel_button
    rows[2usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(680.0, 44.0), pair[0usize..2usize])
    var panel = control.sized_style(700.0, 590.0)
    panel.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    panel.border = style.Border { width: 1.0, color: gl.rgb(0x8E9092u32) }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, panel, rows[0usize..3usize]), ok)
}

// The 48 basic colours of v3's Color Editor, sampled from its window (CE1-color-editor-v3.png), row by row.
fn windows_basic(i: usize) -> u32 {
    let colors: [48]u32 = [48]u32{ 0xFF8080u32, 0xFFFF80u32, 0x80FF80u32, 0x00FF80u32, 0x80FFFFu32, 0x0080FFu32, 0xFF80C0u32, 0xFF80FFu32, 0xFF0000u32, 0xFFFF00u32, 0x80FF00u32, 0x00FF40u32, 0x00FFFFu32, 0x0080C0u32, 0x8080C0u32, 0xFF00FFu32, 0x804040u32, 0xFF8040u32, 0x00FF00u32, 0x008080u32, 0x004080u32, 0x8080FFu32, 0x800040u32, 0xFF0080u32, 0x800000u32, 0xFF8000u32, 0x008000u32, 0x008040u32, 0x0000FFu32, 0x0000A0u32, 0x800080u32, 0x8000FFu32, 0x400000u32, 0x804000u32, 0x004000u32, 0x004040u32, 0x000080u32, 0x000040u32, 0x400040u32, 0x400080u32, 0x000000u32, 0x808000u32, 0x808040u32, 0x808080u32, 0x408080u32, 0xC0C0C0u32, 0x400040u32, 0xFFFFFFu32 }
    if i >= 48usize { ret 0xFFFFFFu32 }
    ret colors[i]
}

// OK in the Color Editor: the picked colour becomes the picked style's sample colour.
fn dz_apply_color(grid: *Grid) {
    if grid.dz_style != 0u8 {
        let at = usize(grid.dz_style) - 1usize
        grid.dz_style_rgb[at] = grid.dz_pick_color ^ 0xFFFFFFu32
        grid.dz_style_has = grid.dz_style_has | (1u16 << u16(at))
    }
    grid.dz_dlg = 0u8
}

// "R:  255": a label and a channel of the colour picked in the Color Editor.
fn dz_channel_text(a: *mem.Arena, label: str, value: u32) -> (str, err) {
    let (b, b_error) = str.builder(a, 16usize)
    if b_error != ok { ret ("", b_error) }
    var sb = b
    if str.push(&sb, label) != ok || str.push(&sb, "  ") != ok || str.push_u64(&sb, u64(value)) != ok { ret ("", control.TooLarge) }
    ret (str.done(&sb), ok)
}

// The sample strip of a style: the colour picked for it in the Color Editor, else the defaults.
fn dz_strip_rgb(grid: *const Grid, i: usize) -> u32 {
    if ((grid.dz_style_has >> u16(i)) & 1u16) != 0u16 { ret grid.dz_style_rgb[i] }
    if i == 7usize { ret 0xA0A0A0u32 }
    ret 0xE0E0E0u32
}

// The header row of the printed table: the "Header" style's colour from the Designer (list entry 10), else light grey.
fn print_header_fill(grid: *const Grid) -> u32 {
    if ((grid.dz_style_has >> 10u16) & 1u16) != 0u16 { ret grid.dz_style_rgb[10usize] }
    ret 0xF0F0F0u32
}

// The data cells of the printed table: the "Content" style's colour from the Designer (list entry 4), else white.
fn dz_content_fill(grid: *const Grid) -> u32 {
    if ((grid.dz_style_has >> 4u16) & 1u16) != 0u16 { ret grid.dz_style_rgb[4usize] }
    ret 0xFFFFFFu32
}

// A data cell's colour: the style of its row (rows 1, 3, 5 ... are "Content Even Rows", index 0, 2 ...; 2, 4 ... "Odd"),
// else the Content style's, else white.
fn dz_row_fill(grid: *const Grid, row: usize) -> u32 {
    var at: usize = 5usize
    if row % 2usize == 0usize { at = 6usize }
    if ((grid.dz_style_has >> u16(at)) & 1u16) != 0u16 { ret grid.dz_style_rgb[at] }
    ret dz_content_fill(grid)
}

// One channel (0 hue, 1 saturation, 2 lightness) of an 0xRRGGBB colour, each scaled 0..255 (v3's white reads L 255).
fn hsl_channel(rgb: u32, which: usize) -> u32 {
    let r = i32((rgb >> 16u32) & 255u32)
    let g = i32((rgb >> 8u32) & 255u32)
    let b = i32(rgb & 255u32)
    var hi = r
    if g > hi { hi = g }
    if b > hi { hi = b }
    var lo = r
    if g < lo { lo = g }
    if b < lo { lo = b }
    let sum = hi + lo
    let span = hi - lo
    if which == 2usize { ret u32(sum / 2) }
    if span == 0 { ret 0u32 }
    if which == 1usize {
        var dark = sum
        if dark > 255 { dark = 510 - sum }
        ret u32(span * 255 / dark)
    }
    // hue in sixths of the circle, then scaled so a full turn is 255
    var sixth: i32 = 0
    if hi == r { sixth = ((g - b) * 255 / span) }
    if hi == g { sixth = 2 * 255 + ((b - r) * 255 / span) }
    if hi == b { sixth = 4 * 255 + ((r - g) * 255 / span) }
    var turn = sixth / 6
    if turn < 0 { turn += 255 }
    ret u32(turn)
}

// "$ FFFFFF": the picked colour in hex, as v3's Color Editor shows it.
fn hex_label(a: *mem.Arena, rgb: u32) -> (str, err) {
    let (b, b_error) = str.builder(a, 12usize)
    if b_error != ok { ret ("", b_error) }
    var sb = b
    if str.push(&sb, "$  ") != ok { ret ("", control.TooLarge) }
    var shift: u32 = 20u32
    while true {
        let nibble = (rgb >> shift) & 15u32
        var digit = u8(48u32 + nibble)
        if nibble > 9u32 { digit = u8(55u32 + nibble) }
        if str.push_byte(&sb, digit) != ok { ret ("", control.TooLarge) }
        if shift == 0u32 { break }
        shift -= 4u32
    }
    ret (str.done(&sb), ok)
}

// "Add to Custom Colors": the picked colour goes into the next free slot (the oldest drops out when all 16 are full).
fn dz_add_custom(grid: *Grid) {
    let picked = grid.dz_pick_color ^ 0xFFFFFFu32
    if grid.dz_custom_n < 16usize {
        grid.dz_custom[grid.dz_custom_n] = picked
        grid.dz_custom_n += 1usize
        ret
    }
    var i = 1usize
    while i < 16usize {
        grid.dz_custom[i - 1usize] = grid.dz_custom[i]
        i += 1usize
    }
    grid.dz_custom[15usize] = picked
}

fn dz_stop(offset: f32, red: f32, green: f32, blue: f32, alpha: f32) -> paint.Stop {
    ret paint.Stop { offset: offset, color: paint.rgba(red, green, blue, alpha) }
}

// The colour of hue position t (0..1 around the circle) at full saturation: red, yellow, green, cyan, blue, magenta, red.
fn hue_at(t: f32) -> paint.Color {
    let x = t * 6.0
    var sector: i32 = i32(x)
    if sector > 5 { sector = 5 }
    let f = x - f32(sector)
    if sector == 0 { ret paint.rgba(1.0, f, 0.0, 1.0) }
    if sector == 1 { ret paint.rgba(1.0 - f, 1.0, 0.0, 1.0) }
    if sector == 2 { ret paint.rgba(0.0, 1.0, f, 1.0) }
    if sector == 3 { ret paint.rgba(0.0, 1.0 - f, 1.0, 1.0) }
    if sector == 4 { ret paint.rgba(f, 0.0, 1.0, 1.0) }
    ret paint.rgba(1.0, 0.0, 1.0 - f, 1.0)
}

// v3's colour square from solid pieces (gradient coordinates are window-relative here): 24 hue columns, each
// under a stack of eight grey bands that fade it toward grey going down; the picked colour in a box at the right.
fn dz_hue_square(a: *mem.Arena, grid: *Grid, picked: u32) -> (widget.Node, err) {
    let (columns, columns_error) = mem.alloc[widget.Node](a, 25usize)
    if columns_error != ok { ret (zero, control.TooLarge) }
    let (taps, taps_error) = mem.alloc[DesignTap](a, 192usize)
    if taps_error != ok { ret (zero, control.TooLarge) }
    var c = 0usize
    while c < 24usize {
        let (bands, bands_error) = mem.alloc[widget.Node](a, 9usize)
        if bands_error != ok { ret (zero, control.TooLarge) }
        var band = 0usize
        while band < 8usize {
            var piece = control.sized_style(9.6, 23.75)
            let hue = hue_at(f32(c) / 24.0)
            let fade = f32(band) / 7.0
            piece.background = paint.Brush { Solid: paint.rgba(hue.red + (0.5 - hue.red) * fade, hue.green + (0.5 - hue.green) * fade, hue.blue + (0.5 - hue.blue) * fade, 1.0) }
            let at = c * 8usize + band
            taps[at] = DesignTap { grid: grid, kind: 13u8, value: at }
            bands[band] = widget.region(grid.key + MENU_KEY + 851600u64 + u64(at), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&taps[at]), invoke: on_design_tap }, gestures: 1u8, enabled: true, focusable: false }, piece, zero)
            band += 1usize
        }
        columns[c] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(9.6, 190.0), bands[0usize..8usize])
        c += 1usize
    }
    var chip = control.sized_style(60.0, 60.0)
    chip.background = paint.Brush { Solid: gl.rgb(picked) }
    chip.border = style.Border { width: 1.0, color: gl.rgb(0xA0A0A0u32) }
    chip.margin = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    columns[24usize] = widget.box(0u64, chip, zero)
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(310.0, 190.0), columns[0usize..25usize]), ok)
}

// The colour of piece `index` (column * 8 + band) of the hue square, as 0xRRGGBB.
fn hue_cell_rgb(index: usize) -> u32 {
    let hue = hue_at(f32(index / 8usize) / 24.0)
    let fade = f32(index % 8usize) / 7.0
    let r = u32((hue.red + (0.5 - hue.red) * fade) * 255.0 + 0.5)
    let g = u32((hue.green + (0.5 - hue.green) * fade) * 255.0 + 0.5)
    let b = u32((hue.blue + (0.5 - hue.blue) * fade) * 255.0 + 0.5)
    ret (r << 16u32) | (g << 8u32) | b
}

// The title heading's own style: the "Caption" style's colour from the Designer (list entry 1) as its background.
fn caption_look(grid: *const Grid) -> style.Style {
    var s = style.defaults()
    if ((grid.dz_style_has >> 1u16) & 1u16) != 0u16 { s.background = paint.Brush { Solid: gl.rgb(grid.dz_style_rgb[1usize]) } }
    ret s
}

// Sets one channel (0 red, 1 green, 2 blue) of the Color Editor's pick.
fn dz_set_pick_channel(grid: *Grid, channel: usize, value: i64) {
    var v = value
    if v < 0i64 { v = 0i64 }
    if v > 255i64 { v = 255i64 }
    var shift: u32 = 16u32
    if channel == 1usize { shift = 8u32 }
    if channel == 2usize { shift = 0u32 }
    let current = grid.dz_pick_color ^ 0xFFFFFFu32
    let changed = (current & ~(255u32 << shift)) | (u32(v) << shift)
    grid.dz_pick_color = changed ^ 0xFFFFFFu32
}

fn on_pick_spin(ctx: *void, value: i64) -> err {
    let t = mem.cast[*DesignTap](ctx)
    dz_set_pick_channel(t.grid, t.value, value)
    ret ok
}

fn on_pick_text(ctx: *void, value: str) -> err {
    let t = mem.cast[*DesignTap](ctx)
    var v: i64 = 0i64
    var i = 0usize
    while i < value.len && i < 3usize {
        if value[i] >= 48u8 && value[i] <= 57u8 { v = v * 10i64 + i64(value[i] - 48u8) }
        i += 1usize
    }
    dz_set_pick_channel(t.grid, t.value, v)
    ret ok
}

// R, G or B of the Color Editor as a spin box: arrows step 8, typed digits set the value.
fn dz_channel_spin(a: *mem.Arena, grid: *Grid, channel: usize, value: u32) -> (widget.Node, err) {
    let (taps, taps_error) = mem.alloc[DesignTap](a, 1usize)
    if taps_error != ok { ret (zero, control.TooLarge) }
    taps[0usize] = DesignTap { grid: grid, kind: 0u8, value: channel }
    let (buffer, buffer_error) = mem.alloc[u8](a, 4usize)
    if buffer_error != ok { ret (zero, control.TooLarge) }
    let (spin, spin_error) = control.spin_box_sized(a, grid.key + MENU_KEY + 851700u64 + u64(channel) * 8u64, grid.theme, "", buffer[0usize..4usize], i64(value), 0i64, 255i64, 8i64, widget.Change[i64] { ctx: mem.cast[*void](&taps[0usize]), invoke: on_pick_spin }, widget.Change[str] { ctx: mem.cast[*void](&taps[0usize]), invoke: on_pick_text }, 140.0)
    if spin_error != ok { ret (zero, spin_error) }
    var name = "R:"
    if channel == 1usize { name = "G:" }
    if channel == 2usize { name = "B:" }
    let (label, label_error) = flat_text(a, grid, name, gl.rgb(0x000000u32))
    if label_error != ok { ret (zero, label_error) }
    let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
    if pair_error != ok { ret (zero, control.TooLarge) }
    pair[0usize] = widget.padded(0u64, 4.0, 14.0, 0.0, 0.0, control.sized_style(34.0, 40.0), one(a, label))
    pair[1usize] = spin
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), pair[0usize..2usize]), ok)
}

// ---- v3's standard controls: sizes from the Delphi forms (TcxButton 75 x 23, edits 21 high), flat DevExpress look ----

fn v3_button_w() -> f32 { ret 75.0 }
fn v3_button_h() -> f32 { ret 23.0 }
fn v3_edit_h() -> f32 { ret 21.0 }

// The label of a v3 button, centred (grey when disabled).
fn v3_button_label(a: *mem.Arena, grid: *Grid, text: str, enabled: bool) -> (widget.Node, err) {
    var ink: u32 = 0x000000u32
    if !enabled { ink = 0xA0A0A0u32 }
    let (label, label_error) = flat_text(a, grid, text, gl.rgb(ink))
    if label_error != ok { ret (zero, label_error) }
    var centred = style.defaults()
    centred.width = style.Length { Percent: 100.0 }
    centred.height = style.Length { Percent: 100.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Center, cross: .Center, gap: 0.0 }, centred, one(a, label)), ok)
}

// A flat button, 75 x 23 (wider for a long label): #FDFDFD, a 1 px #ADADAD border, radius 3, 8 units from its left neighbour.
// `tap` makes it live; a null `tap` draws it inert; `top` adds space above.
fn v3_button(a: *mem.Arena, grid: *Grid, text: str, wide: f32, key: u64, tap: *DesignTap, live: bool, top: f32) -> (widget.Node, err) {
    let (face, face_error) = v3_button_label(a, grid, text, live)
    if face_error != ok { ret (zero, face_error) }
    var width = v3_button_w()
    if wide > width { width = wide }
    var box = control.sized_style(width, v3_button_h())
    box.background = paint.Brush { Solid: gl.rgb(0xFDFDFDu32) }
    box.border = style.Border { width: 1.0, color: gl.rgb(0xADADADu32) }
    box.radius = 3.0
    box.margin = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: style.Length { Px: top }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    if !live { ret (widget.box(0u64, box, one(a, face)), ok) }
    ret (widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](tap), invoke: on_design_tap }, gestures: 1u8, enabled: true, focusable: false }, box, one(a, face)), ok)
}

// A flat edit or combo face, 21 high: white, a 1 px #ABABAB border, the text left.
fn v3_edit(a: *mem.Arena, grid: *Grid, text: str, width: f32) -> (widget.Node, err) {
    let (words, words_error) = flat_text(a, grid, text, gl.rgb(0x000000u32))
    if words_error != ok { ret (zero, words_error) }
    var box = control.sized_style(width, v3_edit_h())
    box.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    box.border = style.Border { width: 1.0, color: gl.rgb(0xABABABu32) }
    box.margin = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: style.Length { Px: 2.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 2.0 } }
    ret (widget.box(0u64, box, one(a, widget.padded(0u64, 4.0, 2.0, 0.0, 0.0, style.defaults(), one(a, words)))), ok)
}

// ---- read-only v3 tables for the Messages, Options > Shortcuts and Statistics windows (TcxGridTableView, flat) ----

fn st_text_cell(a: *mem.Arena, grid: *Grid, text: str, width: f32, height: f32, align: u8, ink: u32, fill: paint.Color) -> (widget.Node, err) {
    let (label, label_error) = flat_text(a, grid, text, gl.rgb(ink))
    if label_error != ok { ret (zero, label_error) }
    var box = control.sized_style(width, height)
    box.background = paint.Brush { Solid: fill }
    if align == 1u8 { ret (widget.aligned(0u64, .Center, .Center, box, one(a, label)), ok) }
    if align == 2u8 { ret (widget.aligned(0u64, .End, .Center, box, one(a, widget.padded(0u64, 0.0, 0.0, 4.0, 0.0, style.defaults(), one(a, label)))), ok) }
    ret (widget.aligned(0u64, .Start, .Center, box, one(a, widget.padded(0u64, 4.0, 0.0, 0.0, 0.0, style.defaults(), one(a, label)))), ok)
}

// The header row: column titles, the sort glyph at the right of column `sort_col`.
fn st_header(a: *mem.Arena, grid: *Grid, titles: []const str, widths: []const f32, aligns: []const u8, sort_col: usize) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, titles.len + 1usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    var c = 0usize
    while c < titles.len {
        let (cell, cell_error) = st_text_cell(a, grid, titles[c], widths[c], grid.look.header_height, aligns[c], 0x000000u32, grid.look.header)
        if cell_error != ok { ret (zero, cell_error) }
        cells[c] = cell
        if c == sort_col {
            let (glyph, glyph_error) = flat_text(a, grid, "▽", gl.rgb(0x808080u32))
            if glyph_error != ok { ret (zero, glyph_error) }
            let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
            if pair_error != ok { ret (zero, control.TooLarge) }
            pair[0usize] = cell
            pair[1usize] = widget.positioned(0u64, widths[c] - 16.0, 3.0, style.defaults(), one(a, glyph))
            cells[c] = widget.stack(0u64, control.sized_style(widths[c], grid.look.header_height), pair[0usize..2usize])
        }
        c += 1usize
    }
    var line = style.defaults()
    line.border = style.Border { width: 1.0, color: grid.look.header_line }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, line, cells[0usize..titles.len]), ok)
}

// One data row of a table: its cells (row-major in `cells`), striped (the first row grey), `ink` its text colour.
fn st_row(a: *mem.Arena, grid: *Grid, cells: []const str, widths: []const f32, aligns: []const u8, row: usize, ink: u32, picked: bool, fixed: bool) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, widths.len + 1usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    var fill = grid.look.odd
    if row % 2usize == 1usize { fill = grid.look.even }
    if picked { fill = grid.look.selected }
    var c = 0usize
    while c < widths.len {
        var cell_fill = fill
        if fixed && c == 0usize { cell_fill = gl.rgb(0xC0C0C0u32) }
        let (cell, cell_error) = st_text_cell(a, grid, cells[row * widths.len + c], widths[c], grid.look.row_height, aligns[c], ink, cell_fill)
        if cell_error != ok { ret (zero, cell_error) }
        parts[c] = cell
        c += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..widths.len]), ok)
}

// A read-only table `width` x `height`: header, striped rows (`picked` is the highlighted row, 255 for none), and `empty`
// centred when there are no rows. `inks` holds a text colour per row, or is empty.
fn st_table(a: *mem.Arena, grid: *Grid, titles: []const str, widths: []const f32, aligns: []const u8, cells: []const str, inks: []const u32, sort_col: usize, picked: usize, fixed: bool, empty: str, width: f32, height: f32) -> (widget.Node, err) {
    var nrows = 0usize
    if titles.len > 0usize { nrows = cells.len / titles.len }
    var shown = usize((height - grid.look.header_height) / grid.look.row_height)
    if nrows < shown { shown = nrows }
    let (rows, rows_error) = mem.alloc[widget.Node](a, shown + 2usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    let (head, head_error) = st_header(a, grid, titles, widths, aligns, sort_col)
    if head_error != ok { ret (zero, head_error) }
    rows[0usize] = head
    var r = 0usize
    while r < shown {
        var ink: u32 = 0x000000u32
        if r < inks.len { ink = inks[r] }
        let (row, row_error) = st_row(a, grid, cells, widths, aligns, r, ink, r == picked, fixed)
        if row_error != ok { ret (zero, row_error) }
        rows[1usize + r] = row
        r += 1usize
    }
    var body = 1usize + shown
    if nrows == 0usize {
        let (words, words_error) = flat_text(a, grid, empty, gl.rgb(0x808080u32))
        if words_error != ok { ret (zero, words_error) }
        var blank = control.sized_style(width, height - grid.look.header_height)
        rows[body] = widget.aligned(0u64, .Center, .Center, blank, one(a, words))
        body += 1usize
    }
    var frame = control.sized_style(width, height)
    frame.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    frame.border = style.Border { width: 1.0, color: grid.look.frame }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, frame, rows[0usize..body]), ok)
}

// ---- the windows: 1 Messages (View > Messages), 2 Options > Shortcuts, 3 Statistics (File > Statistics) ----

fn show_messages(grid: *Grid) {
    show_print_preview(grid)
    grid.print_open = false
    grid.sw_open = 1u8
}

fn show_options(grid: *Grid) {
    show_print_preview(grid)
    grid.print_open = false
    grid.sw_open = 2u8
    grid.sw_page = 2u8
}

fn show_statistics(grid: *Grid) {
    show_print_preview(grid)
    grid.print_open = false
    grid.sw_open = 3u8
    grid.sw_tab = 3u8
}

fn sw_panel(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    if grid.sw_open == 1u8 {
        let (node, node_error) = messages_panel(a, grid)
        ret (node, node_error)
    }
    if grid.sw_open == 2u8 {
        let (node, node_error) = options_panel(a, grid)
        ret (node, node_error)
    }
    let (node, node_error) = statistics_panel(a, grid)
    ret (node, node_error)
}

fn sw_frame(width: f32, height: f32) -> style.Style {
    var panel = control.sized_style(width, height)
    panel.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    panel.border = style.Border { width: 1.0, color: gl.rgb(0x8E9092u32) }
    ret panel
}

fn messages_panel(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (rows, rows_error) = mem.alloc[widget.Node](a, 2usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    let (title, title_error) = window_title(a, grid, 2u8, "Messages", 470.0, 32.0, false)
    if title_error != ok { ret (zero, title_error) }
    rows[0usize] = title
    let titles: [4]str = [4]str{ "", "Event", "Timestamp", "Message" }
    let widths: [4]f32 = [4]f32{ 22.0, 100.0, 150.0, 196.0 }
    let aligns: [4]u8 = [4]u8{ 0u8, 0u8, 0u8, 0u8 }
    let none: [0]str = zero
    let no_inks: [0]u32 = zero
    let (grid_node, grid_error) = st_table(a, grid, titles[0usize..4usize], widths[0usize..4usize], aligns[0usize..4usize], none[0usize..0usize], no_inks[0usize..0usize], 2usize, 255usize, false, "<No messages to display>", 468.0, 188.0)
    if grid_error != ok { ret (zero, grid_error) }
    rows[1usize] = grid_node
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, sw_frame(470.0, 222.0), rows[0usize..2usize]), ok)
}

fn opt_page_name(i: usize) -> str {
    if i == 0usize { ret "Interface (F2)" }
    if i == 1usize { ret "Decks (F3)" }
    if i == 2usize { ret "Shortcuts (F4)" }
    if i == 3usize { ret "Passwords (F5)" }
    if i == 4usize { ret "Internet Authentication (F6)" }
    if i == 5usize { ret "Rules (F7)" }
    if i == 6usize { ret "Prices (F8)" }
    if i == 7usize { ret "Grids (F9)" }
    if i == 8usize { ret "Defaults (F10)" }
    if i == 9usize { ret "Card Art (F11)" }
    ret "Morph (F12)"
}

// The page list at the left of Options: eleven 190 x 36 buttons, the chosen one blue.
fn opt_pages(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, 12usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    let (taps, taps_error) = mem.alloc[DesignTap](a, 11usize)
    if taps_error != ok { ret (zero, control.TooLarge) }
    var i = 0usize
    while i < 11usize {
        taps[i] = DesignTap { grid: grid, kind: 21u8, value: i }
        let (label, label_error) = flat_text(a, grid, opt_page_name(i), gl.rgb(0x000000u32))
        if label_error != ok { ret (zero, label_error) }
        var button = control.sized_style(190.0, 34.0)
        button.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
        if usize(grid.sw_page) == i { button.background = paint.Brush { Solid: gl.rgb(0xAFC2EAu32) } }
        button.border = style.Border { width: 1.0, color: gl.rgb(0xD0D0D0u32) }
        button.margin = style.EdgeLengths { left: style.Length { Px: 4.0 }, top: style.Length { Px: 2.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
        cells[i] = widget.region(grid.key + MENU_KEY + 852100u64 + u64(i), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&taps[i]), invoke: on_design_tap }, gestures: 1u8, enabled: true, focusable: false }, button, one(a, widget.padded(0u64, 34.0, 9.0, 0.0, 0.0, style.defaults(), one(a, label))))
        i += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(200.0, 420.0), cells[0usize..11usize]), ok)
}

// The grey section bar of a page: the page's name in bold, "General" at the right.
fn opt_header(a: *mem.Arena, grid: *Grid, name: str) -> (widget.Node, err) {
    let (title, title_error) = flat_text(a, grid, name, gl.rgb(0xFFFFFFu32))
    if title_error != ok { ret (zero, title_error) }
    let (shadow, shadow_error) = flat_text(a, grid, name, gl.rgb(0xFFFFFFu32))
    if shadow_error != ok { ret (zero, shadow_error) }
    let (general, general_error) = flat_text(a, grid, "General", gl.rgb(0x202020u32))
    if general_error != ok { ret (zero, general_error) }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 3usize)
    if layers_error != ok { ret (zero, control.TooLarge) }
    layers[0usize] = widget.positioned(0u64, 8.0, 4.0, style.defaults(), one(a, title))
    layers[1usize] = widget.positioned(0u64, 8.8, 4.0, style.defaults(), one(a, shadow))
    layers[2usize] = widget.positioned(0u64, 400.0, 4.0, style.defaults(), one(a, general))
    var bar = control.sized_style(476.0, 24.0)
    bar.background = paint.Brush { Solid: gl.rgb(0x9C9C9Cu32) }
    ret (widget.stack(0u64, bar, layers[0usize..3usize]), ok)
}

// The Shortcuts page: the commands in a read-only table, then the shortcut box with Set and Reset.
fn opt_shortcuts(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let titles: [4]str = [4]str{ "", "Group", "Command", "Shortcut" }
    let widths: [4]f32 = [4]f32{ 24.0, 127.0, 196.0, 127.0 }
    let aligns: [4]u8 = [4]u8{ 0u8, 0u8, 0u8, 0u8 }
    let cells: [72]str = [72]str{ "", "File", "New", "Ctrl+N", "", "File", "Open", "Ctrl+O", "", "File", "Save", "Ctrl+S", "", "File", "Save As", "", "", "File", "Save All", "Ctrl+Shift+S", "", "File", "Close", "", "", "File", "Close All", "Ctrl+Shift+F4", "", "File", "Delete Deck", "", "", "File", "Properties", "Ctrl+I", "", "File", "Legality", "F6", "", "File", "Statistics", "F7", "", "File", "Deck from Card Pool", "Ctrl+F2", "", "File", "Collection from Card Pool", "Ctrl+F3", "", "File", "Deck from Collection", "Ctrl+F4", "", "File", "Toggle Mode", "F12", "", "File", "Toggle Mode in Reverse", "Shift+F12", "", "File", "Import", "", "", "File", "Update Prices", "" }
    let no_inks: [0]u32 = zero
    let (grid_node, grid_error) = st_table(a, grid, titles[0usize..4usize], widths[0usize..4usize], aligns[0usize..4usize], cells[0usize..72usize], no_inks[0usize..0usize], 255usize, 0usize, false, "", 476.0, 290.0)
    if grid_error != ok { ret (zero, grid_error) }
    let (box, box_error) = v3_edit(a, grid, "Ctrl + N", 340.0)
    if box_error != ok { ret (zero, box_error) }
    let (set_button, set_error) = v3_idle(a, grid, "Set", 0.0, true)
    if set_error != ok { ret (zero, set_error) }
    let (reset_button, reset_error) = v3_idle(a, grid, "Reset", 0.0, true)
    if reset_error != ok { ret (zero, reset_error) }
    let (foot, foot_error) = mem.alloc[widget.Node](a, 3usize)
    if foot_error != ok { ret (zero, control.TooLarge) }
    foot[0usize] = box
    foot[1usize] = set_button
    foot[2usize] = reset_button
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    parts[0usize] = grid_node
    parts[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, control.sized_style(476.0, 30.0), foot[0usize..3usize])
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(476.0, 330.0), parts[0usize..2usize]), ok)
}

// A v3 button with no action yet; `black` writes its label in black (an enabled look), else grey.
fn v3_idle(a: *mem.Arena, grid: *Grid, text: str, wide: f32, black: bool) -> (widget.Node, err) {
    let (idle, idle_error) = mem.alloc[DesignTap](a, 1usize)
    if idle_error != ok { ret (zero, control.TooLarge) }
    idle[0usize] = DesignTap { grid: grid, kind: 255u8, value: 0usize }
    if black {
        let (face, face_error) = v3_button_label(a, grid, text, true)
        if face_error != ok { ret (zero, face_error) }
        var width = v3_button_w()
        if wide > width { width = wide }
        var box = control.sized_style(width, v3_button_h())
        box.background = paint.Brush { Solid: gl.rgb(0xFDFDFDu32) }
        box.border = style.Border { width: 1.0, color: gl.rgb(0xADADADu32) }
        box.radius = 3.0
        box.margin = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
        ret (widget.box(0u64, box, one(a, face)), ok)
    }
    let (grey, grey_error) = v3_button(a, grid, text, wide, 0u64, &idle[0usize], false, 0.0)
    ret (grey, grey_error)
}

fn options_panel(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (rows, rows_error) = mem.alloc[widget.Node](a, 3usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    let (title, title_error) = window_title(a, grid, 2u8, "Options", 700.0, 32.0, false)
    if title_error != ok { ret (zero, title_error) }
    rows[0usize] = title
    let (pages, pages_error) = opt_pages(a, grid)
    if pages_error != ok { ret (zero, pages_error) }
    let (head, head_error) = opt_header(a, grid, opt_page_name(usize(grid.sw_page)))
    if head_error != ok { ret (zero, head_error) }
    let (body, body_error) = opt_shortcuts(a, grid)
    if body_error != ok { ret (zero, body_error) }
    let (right, right_error) = mem.alloc[widget.Node](a, 2usize)
    if right_error != ok { ret (zero, control.TooLarge) }
    right[0usize] = head
    right[1usize] = body
    let (halves, halves_error) = mem.alloc[widget.Node](a, 2usize)
    if halves_error != ok { ret (zero, control.TooLarge) }
    halves[0usize] = pages
    halves[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(480.0, 420.0), right[0usize..2usize])
    rows[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(700.0, 424.0), halves[0usize..2usize])
    let (ok_button, ok_error) = v3_idle(a, grid, "OK", 0.0, true)
    if ok_error != ok { ret (zero, ok_error) }
    let (cancel_button, cancel_error) = v3_idle(a, grid, "Cancel", 0.0, true)
    if cancel_error != ok { ret (zero, cancel_error) }
    let (apply_button, apply_error) = v3_idle(a, grid, "Apply", 0.0, true)
    if apply_error != ok { ret (zero, apply_error) }
    let (foot, foot_error) = mem.alloc[widget.Node](a, 3usize)
    if foot_error != ok { ret (zero, control.TooLarge) }
    foot[0usize] = widget.padded(0u64, 440.0, 0.0, 0.0, 0.0, style.defaults(), one(a, ok_button))
    foot[1usize] = cancel_button
    foot[2usize] = apply_button
    rows[2usize] = widget.padded(0u64, 0.0, 6.0, 0.0, 0.0, style.defaults(), one(a, widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(700.0, 30.0), foot[0usize..3usize])))
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, sw_frame(700.0, 500.0), rows[0usize..3usize]), ok)
}

fn stat_tab_name(i: usize) -> str {
    if i == 0usize { ret "Colors" }
    if i == 1usize { ret "Rarity" }
    if i == 2usize { ret "Card Type" }
    if i == 3usize { ret "Editions" }
    if i == 4usize { ret "Mana Analyser" }
    if i == 5usize { ret "Mana Product" }
    if i == 6usize { ret "Power Analyser" }
    if i == 7usize { ret "Probability" }
    if i == 8usize { ret "Mana Slots" }
    if i == 9usize { ret "Start Hand" }
    ret "Advanced"
}

// The width of a tab: v3 puts a 22 px picture before the name, so the name is drawn after that space.
fn stat_tab_w(i: usize) -> f32 {
    if i == 0usize { ret 56.5 }
    if i == 1usize { ret 54.0 }
    if i == 2usize { ret 73.0 }
    if i == 3usize { ret 61.0 }
    if i == 4usize { ret 93.5 }
    if i == 5usize { ret 89.0 }
    if i == 6usize { ret 96.5 }
    if i == 7usize { ret 74.5 }
    if i == 8usize { ret 74.0 }
    if i == 9usize { ret 77.5 }
    ret 67.5
}

fn stat_banner_text(i: usize) -> str {
    if i == 0usize { ret "Card breakdown by card colors." }
    if i == 1usize { ret "Card breakdown by rarity." }
    if i == 2usize { ret "Card breakdown by card types." }
    if i == 3usize { ret "Card breakdown by editions." }
    if i == 4usize { ret "Mana cost analysis of the deck." }
    if i == 5usize { ret "Mana product analysis of the deck." }
    if i == 6usize { ret "Power analysis of the deck." }
    if i == 7usize { ret "Detailed turn breakdown by drawing cards probability." }
    if i == 8usize { ret "Mana Slots analysis (known as George Baxter Analysis) allows you to evaluate the actual mana required to play the cards." }
    ret "Descriptive statistics on main deck card characteristics."
}

// The tab strip: eleven tabs, the chosen one white (v3 puts a picture on each; here the names only).
fn stat_tabs(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, 12usize)
    if cells_error != ok { ret (zero, control.TooLarge) }
    let (taps, taps_error) = mem.alloc[DesignTap](a, 11usize)
    if taps_error != ok { ret (zero, control.TooLarge) }
    var i = 0usize
    while i < 11usize {
        taps[i] = DesignTap { grid: grid, kind: 20u8, value: i }
        let (label, label_error) = flat_text(a, grid, stat_tab_name(i), gl.rgb(0x000000u32))
        if label_error != ok { ret (zero, label_error) }
        var tab = control.sized_style(stat_tab_w(i), 26.0)
        if usize(grid.sw_tab) == i { tab.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) } }
        tab.border = style.Border { width: 1.0, color: gl.rgb(0xD0D0D0u32) }
        cells[i] = widget.region(grid.key + MENU_KEY + 852200u64 + u64(i), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&taps[i]), invoke: on_design_tap }, gestures: 1u8, enabled: true, focusable: false }, tab, one(a, widget.padded(0u64, 20.0, 5.0, 0.0, 0.0, style.defaults(), one(a, label))))
        i += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(889.0, 26.0), cells[0usize..11usize]), ok)
}

// The grey banner under the tabs, 40 high; the Probability one has a second line.
fn stat_banner(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (words, words_error) = flat_text(a, grid, stat_banner_text(usize(grid.sw_tab)), gl.rgb(0x000000u32))
    if words_error != ok { ret (zero, words_error) }
    let (more, more_error) = flat_text(a, grid, "Probability is the measure of how likely an event is.", gl.rgb(0x000000u32))
    if more_error != ok { ret (zero, more_error) }
    var lines = one(a, words)
    if grid.sw_tab == 7u8 {
        let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
        if pair_error != ok { ret (zero, control.TooLarge) }
        pair[0usize] = words
        pair[1usize] = more
        lines = pair[0usize..2usize]
    }
    var bar = control.sized_style(889.0, 40.0)
    bar.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    bar.border = style.Border { width: 1.0, color: gl.rgb(0xC8C8C8u32) }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Center, cross: .Center, gap: 0.0 }, bar, lines), ok)
}

fn stat_editions(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let titles: [3]str = [3]str{ "Edition", "Abbreviation", "Quantity" }
    let widths: [3]f32 = [3]f32{ 297.0, 298.0, 294.5 }
    let aligns: [3]u8 = [3]u8{ 0u8, 1u8, 1u8 }
    let cells: [3]str = [3]str{ "Mystery Booster Commander Edition", "MBC", "12" }
    let inks: [1]u32 = [1]u32{ 0xFF1493u32 }
    let (tbl, tbl_error) = st_table(a, grid, titles[0usize..3usize], widths[0usize..3usize], aligns[0usize..3usize], cells[0usize..3usize], inks[0usize..1usize], 2usize, 255usize, false, "", 889.0, 394.0)
    ret (tbl, tbl_error)
}

fn stat_advanced(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let titles: [6]str = [6]str{ "Characteristic", "Power", "Toughness", "CMC", "Mana Product", "# of Rules" }
    let widths: [6]f32 = [6]f32{ 207.0, 137.0, 137.0, 137.0, 137.0, 135.0 }
    let aligns: [6]u8 = [6]u8{ 0u8, 2u8, 2u8, 2u8, 2u8, 2u8 }
    let cells: [102]str = [102]str{ "Count (N)", "2", "2", "9", "5", "12", "Missing (N*)", "10", "10", "3", "7", "0", "Arithmetic Mean", "2.500", "2.500", "2.556", "5.000", "1.000", "Trimmed Mean (5%)", "2.500", "2.500", "2.556", "5.000", "1.000", "Harmonic Mean", "2.400", "2.400", "2.400", "5.000", "1.000", "Geometric Mean", "2.449", "2.449", "2.473", "5.000", "1.000", "MSSD", "0.500", "0.500", "0.375", "0.000", "0.000", "Mode", "-INF", "-INF", "2", "5", "1", "Mode Frequency", "0", "0", "5", "5", "12", "Standard Deviation", "0.707", "0.707", "0.726", "0.000", "0.000", "Population Std Dev", "0.500", "0.500", "0.685", "0.000", "0.000", "Sum", "5", "5", "23", "25", "12", "Sum of Squares", "13", "13", "63", "125", "12", "Variance", "0.500", "0.500", "0.528", "0.000", "0.000", "Total Variance", "0.500", "0.500", "4.222", "0.000", "0.000", "Population Variance", "0.250", "0.250", "0.469", "0.000", "0.000", "Minimum", "2", "2", "2", "5", "1" }
    let no_inks: [0]u32 = zero
    let (tbl, tbl_error) = st_table(a, grid, titles[0usize..6usize], widths[0usize..6usize], aligns[0usize..6usize], cells[0usize..102usize], no_inks[0usize..0usize], 255usize, 255usize, true, "", 889.0, 394.0)
    ret (tbl, tbl_error)
}

// ---- small absolute-layout pieces for the controls on the Statistics tabs ----

fn st_place(a: *mem.Arena, x: f32, y: f32, node: widget.Node) -> widget.Node {
    ret widget.positioned(0u64, x * 0.9, y, style.defaults(), one(a, node))
}

// A bare rectangle at (x, y): fill and 1 px line colours, a corner radius.
fn st_rect(a: *mem.Arena, x: f32, y: f32, w: f32, h: f32, fill: u32, line: u32, radius: f32) -> (widget.Node, err) {
    let (none, none_error) = mem.alloc[widget.Node](a, 1usize)
    if none_error != ok { ret (zero, control.TooLarge) }
    var box = control.sized_style(w * 0.9, h)
    box.background = paint.Brush { Solid: gl.rgb(fill) }
    box.border = style.Border { width: 1.0, color: gl.rgb(line) }
    box.radius = radius
    ret (st_place(a, x, y, widget.box(0u64, box, none[0usize..0usize])), ok)
}

// Words at (x, y); bold is the faux-bold of the Designer.
fn st_words(a: *mem.Arena, grid: *Grid, x: f32, y: f32, text: str, ink: u32, bold: bool) -> (widget.Node, err) {
    let (first, first_error) = flat_text(a, grid, text, gl.rgb(ink))
    if first_error != ok { ret (zero, first_error) }
    if bold {
        let (heavy, heavy_error) = faux_bold(a, grid, text, first)
        if heavy_error != ok { ret (zero, heavy_error) }
        ret (st_place(a, x, y, heavy), ok)
    }
    ret (st_place(a, x, y, first), ok)
}

// A group box: a 1 px #DCDCDC frame with its caption over the top edge.
fn st_group(a: *mem.Arena, grid: *Grid, x: f32, y: f32, w: f32, h: f32, caption: str) -> (widget.Node, err) {
    let (frame, frame_error) = st_rect(a, x, y + 8.0, w, h - 8.0, 0xF0F0F0u32, 0xDCDCDCu32, 3.0)
    if frame_error != ok { ret (zero, frame_error) }
    let (words, words_error) = flat_text(a, grid, caption, gl.rgb(0x000000u32))
    if words_error != ok { ret (zero, words_error) }
    var cap = style.defaults()
    cap.background = paint.Brush { Solid: gl.rgb(0xF0F0F0u32) }
    let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
    if pair_error != ok { ret (zero, control.TooLarge) }
    pair[0usize] = frame
    pair[1usize] = widget.positioned(0u64, (x + 6.0) * 0.9, y, cap, one(a, words))
    ret (widget.stack(0u64, style.defaults(), pair[0usize..2usize]), ok)
}

// A radio line at (x, y): a 13 px disc, a blue dot inside when chosen, the words after it.
fn st_radio(a: *mem.Arena, grid: *Grid, x: f32, y: f32, on: bool, text: str) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    var fill: u32 = 0xFFFFFFu32
    if on { fill = 0x0A64C8u32 }
    let (disc, disc_error) = st_rect(a, x, y + 2.0, 14.0, 14.0, fill, 0x6E6E6Eu32, 7.0)
    if disc_error != ok { ret (zero, disc_error) }
    parts[0usize] = disc
    let (words, words_error) = st_words(a, grid, x + 20.0, y, text, 0x000000u32, false)
    if words_error != ok { ret (zero, words_error) }
    parts[1usize] = words
    if on {
        let (dot, dot_error) = st_rect(a, x + 4.0, y + 6.0, 6.0, 6.0, 0xFFFFFFu32, 0xFFFFFFu32, 3.0)
        if dot_error != ok { ret (zero, dot_error) }
        parts[2usize] = dot
        ret (widget.stack(0u64, style.defaults(), parts[0usize..3usize]), ok)
    }
    ret (widget.stack(0u64, style.defaults(), parts[0usize..2usize]), ok)
}

// A spin box at (x, y): the value in a 21 high edit, two small arrows in a strip at its right.
fn st_spin(a: *mem.Arena, grid: *Grid, x: f32, y: f32, w: f32, text: str) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    let (edit, edit_error) = st_rect(a, x, y, w, 21.0, 0xFFFFFFu32, 0xABABABu32, 0.0)
    if edit_error != ok { ret (zero, edit_error) }
    parts[0usize] = edit
    let (value, value_error) = st_words(a, grid, x + 4.0, y + 3.0, text, 0x000000u32, false)
    if value_error != ok { ret (zero, value_error) }
    parts[1usize] = value
    let (up, up_error) = st_words(a, grid, x + w - 14.0, y - 1.0, "▴", 0x404040u32, false)
    if up_error != ok { ret (zero, up_error) }
    parts[2usize] = up
    let (down, down_error) = st_words(a, grid, x + w - 14.0, y + 8.0, "▾", 0x404040u32, false)
    if down_error != ok { ret (zero, down_error) }
    parts[3usize] = down
    ret (widget.stack(0u64, style.defaults(), parts[0usize..4usize]), ok)
}

// A flat v3 button at (x, y), 23 high, `ink` the label colour (grey when idle).
fn st_button(a: *mem.Arena, grid: *Grid, x: f32, y: f32, w: f32, text: str, ink: u32) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    let (face, face_error) = st_rect(a, x, y, w, 23.0, 0xFDFDFDu32, 0xADADADu32, 3.0)
    if face_error != ok { ret (zero, face_error) }
    parts[0usize] = face
    var left = x + (w - 7.8 * f32(text.len)) / 2.0
    if left < x + 4.0 { left = x + 4.0 }
    let (words, words_error) = st_words(a, grid, left, y + 3.0, text, ink, false)
    if words_error != ok { ret (zero, words_error) }
    parts[1usize] = words
    ret (widget.stack(0u64, style.defaults(), parts[0usize..2usize]), ok)
}

// ---- Probability: the card list, Operator and Mode, the turn bars ----

fn stat_prob_table(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let titles: [3]str = [3]str{ "Card Name", "Deck Qty", "Desired Qty" }
    let widths: [3]f32 = [3]f32{ 396.0, 181.0, 182.5 }
    let aligns: [3]u8 = [3]u8{ 0u8, 1u8, 1u8 }
    let cells: [30]str = [30]str{ "Jet Collector", "1", "0", "Euru, Acorn Scrounger", "1", "0", "Dust to Dust", "1", "0", "Chaos Warp", "1", "0", "Chromatic Lantern", "1", "0", "Fellwar Stone", "1", "0", "Jeweled Amulet", "1", "0", "Mind Stone", "1", "0", "Swiftfoot Boots", "1", "0", "Thought Vessel", "1", "0" }
    let no_inks: [0]u32 = zero
    let (tbl, tbl_error) = st_table(a, grid, titles[0usize..3usize], widths[0usize..3usize], aligns[0usize..3usize], cells[0usize..30usize], no_inks[0usize..0usize], 255usize, 255usize, false, "", 774.0, 230.0)
    ret (st_place(a, 6.0, 10.0, tbl), tbl_error)
}

fn stat_prob_bars(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 36usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    var n = 0usize
    let names: [11]str = [11]str{ "T0", "T1", "T2", "T3", "T4", "T5", "T6", "T7", "T8", "T9", "T5" }
    var t = 0usize
    while t < 11usize {
        var x = 16.0 + 32.0 * f32(t)
        if t == 10usize { x = 349.0 }
        let name = names[t]
        let (bar, bar_error) = st_rect(a, x, 281.0, 27.0, 67.0, 0xE8E8E8u32, 0xA0A0A0u32, 0.0)
        if bar_error != ok { ret (zero, bar_error) }
        parts[n] = bar
        let (pct, pct_error) = st_words(a, grid, x + 3.0, 288.0, "0%", 0x000000u32, false)
        if pct_error != ok { ret (zero, pct_error) }
        parts[n + 1usize] = pct
        let (label, label_error) = st_words(a, grid, x + 3.0, 352.0, name, 0x000000u32, true)
        if label_error != ok { ret (zero, label_error) }
        parts[n + 2usize] = label
        n += 3usize
        t += 1usize
    }
    ret (widget.stack(0u64, style.defaults(), parts[0usize..n]), ok)
}

fn stat_probability(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 16usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    let (tbl, tbl_error) = stat_prob_table(a, grid)
    if tbl_error != ok { ret (zero, tbl_error) }
    parts[0usize] = tbl
    let (op, op_error) = st_group(a, grid, 874.0, 6.0, 113.0, 74.0, "Operator:")
    if op_error != ok { ret (zero, op_error) }
    parts[1usize] = op
    let (and_radio, and_error) = st_radio(a, grid, 882.0, 24.0, true, "And")
    if and_error != ok { ret (zero, and_error) }
    parts[2usize] = and_radio
    let (or_radio, or_error) = st_radio(a, grid, 882.0, 52.0, false, "Or")
    if or_error != ok { ret (zero, or_error) }
    parts[3usize] = or_radio
    let (mode, mode_error) = st_group(a, grid, 874.0, 91.0, 113.0, 70.0, "Mode:")
    if mode_error != ok { ret (zero, mode_error) }
    parts[4usize] = mode
    let (least, least_error) = st_radio(a, grid, 882.0, 109.0, true, "At Least")
    if least_error != ok { ret (zero, least_error) }
    parts[5usize] = least
    let (exactly, exactly_error) = st_radio(a, grid, 882.0, 135.0, false, "Exactly")
    if exactly_error != ok { ret (zero, exactly_error) }
    parts[6usize] = exactly
    let (combo, combo_error) = st_group(a, grid, 6.0, 252.0, 980.0, 125.0, "Probability of drawing current combo:")
    if combo_error != ok { ret (zero, combo_error) }
    parts[7usize] = combo
    let (bars, bars_error) = stat_prob_bars(a, grid)
    if bars_error != ok { ret (zero, bars_error) }
    parts[8usize] = bars
    let (rule, rule_error) = st_rect(a, 337.0, 266.0, 1.0, 105.0, 0xA0A0A0u32, 0xA0A0A0u32, 0.0)
    if rule_error != ok { ret (zero, rule_error) }
    parts[9usize] = rule
    let (turn, turn_error) = st_words(a, grid, 385.0, 272.0, "Turn", 0x000000u32, false)
    if turn_error != ok { ret (zero, turn_error) }
    parts[10usize] = turn
    let (spin, spin_error) = st_spin(a, grid, 385.0, 295.0, 44.0, "5")
    if spin_error != ok { ret (zero, spin_error) }
    parts[11usize] = spin
    let (describe, describe_error) = st_button(a, grid, 898.0, 272.0, 76.0, "Describe", 0xA0A0A0u32)
    if describe_error != ok { ret (zero, describe_error) }
    parts[12usize] = describe
    let (clear, clear_error) = st_button(a, grid, 898.0, 306.0, 76.0, "Clear", 0x000000u32)
    if clear_error != ok { ret (zero, clear_error) }
    parts[13usize] = clear
    ret (widget.stack(0u64, control.sized_style(889.0, 394.0), parts[0usize..14usize]), ok)
}

// ---- Mana Slots: the card list and the needed-slots panel ----

fn stat_slots_table(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let titles: [4]str = [4]str{ "Card", "Qty", "Cost", "Importance" }
    let widths: [4]f32 = [4]f32{ 290.0, 132.5, 132.5, 166.5 }
    let aligns: [4]u8 = [4]u8{ 0u8, 1u8, 1u8, 0u8 }
    let cells: [40]str = [40]str{ "Chaos Warp", "1", "RCC", "Average", "Chromatic Lantern", "1", "CCC", "Average", "Dust to Dust", "1", "WWC", "Average", "Euru, Acorn Scrounger", "1", "BGCC", "Average", "Fellwar Stone", "1", "CC", "Average", "Jet Collector", "1", "GC", "Average", "Jeweled Amulet", "1", "", "Average", "Mind Stone", "1", "CC", "Average", "Swiftfoot Boots", "1", "CC", "Average", "Thought Vessel", "1", "CC", "Average" }
    let inks: [10]u32 = [10]u32{ 0xFF2020u32, 0x808080u32, 0x606060u32, 0xFF6A2Au32, 0x808080u32, 0x1E9A1Eu32, 0x808080u32, 0x808080u32, 0x808080u32, 0x808080u32 }
    let (tbl, tbl_error) = st_table(a, grid, titles[0usize..4usize], widths[0usize..4usize], aligns[0usize..4usize], cells[0usize..40usize], inks[0usize..10usize], 0usize, 255usize, false, "", 721.0, 366.0)
    ret (st_place(a, 6.0, 10.0, tbl), tbl_error)
}

// One line of the needed-slots panel: a coloured disc and "4.00 (17.73%)".
fn stat_slot_line(a: *mem.Arena, grid: *Grid, y: f32, disc: u32, text: str, ink: u32) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    let (ball, ball_error) = st_rect(a, 832.0, y, 20.0, 20.0, disc, 0x404040u32, 10.0)
    if ball_error != ok { ret (zero, ball_error) }
    parts[0usize] = ball
    let (words, words_error) = st_words(a, grid, 860.0, y + 2.0, text, ink, false)
    if words_error != ok { ret (zero, words_error) }
    parts[1usize] = words
    ret (widget.stack(0u64, style.defaults(), parts[0usize..2usize]), ok)
}

fn stat_mana_slots(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 12usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    let (tbl, tbl_error) = stat_slots_table(a, grid)
    if tbl_error != ok { ret (zero, tbl_error) }
    parts[0usize] = tbl
    let (panel, panel_error) = st_group(a, grid, 822.0, 6.0, 163.0, 204.0, "Needed Mana Slots:")
    if panel_error != ok { ret (zero, panel_error) }
    parts[1usize] = panel
    let discs: [6]u32 = [6]u32{ 0xF5CD3Cu32, 0xBFE3F5u32, 0x3A3A3Au32, 0xD9534Fu32, 0x2DB34Au32, 0xD9D5C8u32 }
    let texts: [6]str = [6]str{ "4.00 (17.73%)", "0.00 (0.00%)", "3.00 (13.30%)", "3.00 (13.30%)", "4.24 (18.81%)", "8.32 (36.86%)" }
    var i = 0usize
    while i < 6usize {
        var ink: u32 = 0x000000u32
        if i == 1usize { ink = 0xA0A0A0u32 }
        let (line, line_error) = stat_slot_line(a, grid, 30.0 + 25.0 * f32(i), discs[i], texts[i], ink)
        if line_error != ok { ret (zero, line_error) }
        parts[2usize + i] = line
        i += 1usize
    }
    let (total, total_error) = st_words(a, grid, 835.0, 190.0, "Total slots: 22.56", 0x000000u32, true)
    if total_error != ok { ret (zero, total_error) }
    parts[8usize] = total
    let (help, help_error) = st_button(a, grid, 825.0, 223.0, 77.0, "Help", 0x000000u32)
    if help_error != ok { ret (zero, help_error) }
    parts[9usize] = help
    ret (widget.stack(0u64, control.sized_style(889.0, 394.0), parts[0usize..10usize]), ok)
}

// ---- Start Hand: the deck, the hand, the cards in play and the discard pile ----

fn stat_hand_deck(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let titles: [2]str = [2]str{ "No", "Card" }
    let widths: [2]f32 = [2]f32{ 27.0, 160.0 }
    let aligns: [2]u8 = [2]u8{ 0u8, 0u8 }
    let cells: [10]str = [10]str{ "1", "Chaos Warp (3)", "2", "Jeweled Amulet (0)", "3", "Exotic Orchard (0)", "4", "Mind Stone (2)", "5", "Thought Vessel (2)" }
    let inks: [5]u32 = [5]u32{ 0xFF2020u32, 0x808080u32, 0x808080u32, 0x808080u32, 0x808080u32 }
    let (tbl, tbl_error) = st_table(a, grid, titles[0usize..2usize], widths[0usize..2usize], aligns[0usize..2usize], cells[0usize..10usize], inks[0usize..5usize], 255usize, 255usize, false, "", 187.0, 341.0)
    ret (st_place(a, 4.0, 83.0, tbl), tbl_error)
}

fn stat_hand_hand(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let titles: [2]str = [2]str{ "No", "Card (CMC)" }
    let widths: [2]f32 = [2]f32{ 38.5, 387.0 }
    let aligns: [2]u8 = [2]u8{ 0u8, 0u8 }
    let cells: [14]str = [14]str{ "1", "Euru, Acorn Scrounger (4)", "2", "Jet Collector (2)", "3", "Swiftfoot Boots (2)", "4", "Fellwar Stone (2)", "5", "Dust to Dust (3)", "6", "Path of Ancestry (0)", "7", "Chromatic Lantern (3)" }
    let inks: [7]u32 = [7]u32{ 0xFF6A2Au32, 0x1E9A1Eu32, 0x808080u32, 0x808080u32, 0x606060u32, 0x808080u32, 0x808080u32 }
    let (tbl, tbl_error) = st_table(a, grid, titles[0usize..2usize], widths[0usize..2usize], aligns[0usize..2usize], cells[0usize..14usize], inks[0usize..7usize], 255usize, 255usize, false, "", 426.0, 341.0)
    ret (st_place(a, 258.0, 83.0, tbl), tbl_error)
}

fn stat_hand_pile(a: *mem.Arena, grid: *Grid, y: f32, h: f32) -> (widget.Node, err) {
    let titles: [2]str = [2]str{ "No", "Card" }
    let widths: [2]f32 = [2]f32{ 27.0, 160.0 }
    let aligns: [2]u8 = [2]u8{ 0u8, 0u8 }
    let none: [0]str = zero
    let no_inks: [0]u32 = zero
    let (tbl, tbl_error) = st_table(a, grid, titles[0usize..2usize], widths[0usize..2usize], aligns[0usize..2usize], none[0usize..0usize], no_inks[0usize..0usize], 255usize, 255usize, false, "<No cards were found in the deck>", 187.0, h)
    ret (st_place(a, 778.0, y, tbl), tbl_error)
}

fn stat_hand_arrows(a: *mem.Arena, grid: *Grid, x: f32, y: f32) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    let (forward, forward_error) = st_button(a, grid, x, y, 30.0, "»", 0xA0A0A0u32)
    if forward_error != ok { ret (zero, forward_error) }
    parts[0usize] = forward
    let (back, back_error) = st_button(a, grid, x, y + 26.0, 30.0, "«", 0xA0A0A0u32)
    if back_error != ok { ret (zero, back_error) }
    parts[1usize] = back
    ret (widget.stack(0u64, style.defaults(), parts[0usize..2usize]), ok)
}

fn stat_hand_top(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 8usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    let (size, size_error) = st_words(a, grid, 177.0, 8.0, "Hand Size", 0x000000u32, false)
    if size_error != ok { ret (zero, size_error) }
    parts[0usize] = size
    let (spin, spin_error) = st_spin(a, grid, 177.0, 31.0, 70.0, "7")
    if spin_error != ok { ret (zero, spin_error) }
    parts[1usize] = spin
    let names: [5]str = [5]str{ "New Hand", "Mulligan", "Draw Card", "Draw All", "Setup..." }
    let lefts: [5]f32 = [5]f32{ 258.0, 342.0, 428.0, 514.0, 907.0 }
    var i = 0usize
    while i < 5usize {
        let (button, button_error) = st_button(a, grid, lefts[i], 31.0, 76.0, names[i], 0x000000u32)
        if button_error != ok { ret (zero, button_error) }
        parts[2usize + i] = button
        i += 1usize
    }
    ret (widget.stack(0u64, style.defaults(), parts[0usize..7usize]), ok)
}

fn stat_hand_labels(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    let names: [4]str = [4]str{ "Cards in Deck", "Cards in Hand", "Cards in Play", "Cards in Discard Pile" }
    let xs: [4]f32 = [4]f32{ 4.0, 255.0, 779.0, 779.0 }
    let ys: [4]f32 = [4]f32{ 76.0, 76.0, 76.0, 323.0 }
    var i = 0usize
    while i < 4usize {
        let (words, words_error) = st_words(a, grid, xs[i], ys[i] - 14.0, names[i], 0x000000u32, false)
        if words_error != ok { ret (zero, words_error) }
        parts[i] = words
        i += 1usize
    }
    ret (widget.stack(0u64, style.defaults(), parts[0usize..4usize]), ok)
}

fn stat_start_hand(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 10usize)
    if parts_error != ok { ret (zero, control.TooLarge) }
    let (top, top_error) = stat_hand_top(a, grid)
    if top_error != ok { ret (zero, top_error) }
    parts[0usize] = top
    let (labels, labels_error) = stat_hand_labels(a, grid)
    if labels_error != ok { ret (zero, labels_error) }
    parts[1usize] = labels
    let (deck, deck_error) = stat_hand_deck(a, grid)
    if deck_error != ok { ret (zero, deck_error) }
    parts[2usize] = deck
    let (hand, hand_error) = stat_hand_hand(a, grid)
    if hand_error != ok { ret (zero, hand_error) }
    parts[3usize] = hand
    let (play, play_error) = stat_hand_pile(a, grid, 83.0, 215.0)
    if play_error != ok { ret (zero, play_error) }
    parts[4usize] = play
    let (discard, discard_error) = stat_hand_pile(a, grid, 330.0, 94.0)
    if discard_error != ok { ret (zero, discard_error) }
    parts[5usize] = discard
    let (left_arrows, left_error) = stat_hand_arrows(a, grid, 220.0, 218.0)
    if left_error != ok { ret (zero, left_error) }
    parts[6usize] = left_arrows
    let (play_arrows, play_arrows_error) = stat_hand_arrows(a, grid, 740.0, 162.0)
    if play_arrows_error != ok { ret (zero, play_arrows_error) }
    parts[7usize] = play_arrows
    let (discard_arrows, discard_arrows_error) = stat_hand_arrows(a, grid, 740.0, 356.0)
    if discard_arrows_error != ok { ret (zero, discard_arrows_error) }
    parts[8usize] = discard_arrows
    ret (widget.stack(0u64, control.sized_style(889.0, 434.0), parts[0usize..9usize]), ok)
}

// The tab's content: the grid tabs are built; the chart tabs say so.
fn stat_content(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    if grid.sw_tab == 3u8 {
        let (node, node_error) = stat_editions(a, grid)
        ret (node, node_error)
    }
    if grid.sw_tab == 7u8 {
        let (node, node_error) = stat_probability(a, grid)
        ret (node, node_error)
    }
    if grid.sw_tab == 8u8 {
        let (node, node_error) = stat_mana_slots(a, grid)
        ret (node, node_error)
    }
    if grid.sw_tab == 9u8 {
        let (node, node_error) = stat_start_hand(a, grid)
        ret (node, node_error)
    }
    if grid.sw_tab == 10u8 {
        let (node, node_error) = stat_advanced(a, grid)
        ret (node, node_error)
    }
    let (note, note_error) = flat_text(a, grid, "(this tab is not built yet)", gl.rgb(0x808080u32))
    if note_error != ok { ret (zero, note_error) }
    var blank = control.sized_style(889.0, 394.0)
    blank.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    ret (widget.aligned(0u64, .Center, .Center, blank, one(a, note)), ok)
}

fn statistics_panel(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (rows, rows_error) = mem.alloc[widget.Node](a, 6usize)
    if rows_error != ok { ret (zero, control.TooLarge) }
    let (close, close_error) = mem.alloc[DesignTap](a, 1usize)
    if close_error != ok { ret (zero, control.TooLarge) }
    close[0usize] = DesignTap { grid: grid, kind: 22u8, value: 0usize }
    let (title, title_error) = window_title(a, grid, 2u8, "Statistics", 891.0, 32.0, false)
    if title_error != ok { ret (zero, title_error) }
    rows[0usize] = title
    let (tabs, tabs_error) = stat_tabs(a, grid)
    if tabs_error != ok { ret (zero, tabs_error) }
    rows[1usize] = tabs
    var n = 2usize
    if grid.sw_tab != 9u8 {
        let (banner, banner_error) = stat_banner(a, grid)
        if banner_error != ok { ret (zero, banner_error) }
        rows[n] = banner
        n += 1usize
    }
    let (content, content_error) = stat_content(a, grid)
    if content_error != ok { ret (zero, content_error) }
    rows[n] = content
    n += 1usize
    let (button, button_error) = v3_button(a, grid, "Close", 0.0, grid.key + MENU_KEY + 852300u64, &close[0usize], true, 6.0)
    if button_error != ok { ret (zero, button_error) }
    rows[n] = widget.padded(0u64, 810.0, 0.0, 0.0, 0.0, style.defaults(), one(a, button))
    n += 1usize
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, sw_frame(891.0, 530.0), rows[0usize..n]), ok)
}
