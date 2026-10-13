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
use e.data.table as table
use e.data.tablegroup as grp
use e.ui.collection
use e.ui.control
use e.ui.gridrules as rules
use e.ui.gridlook as gl
use e.ui.input
use e.gfx.paint
use e.gfx.geometry
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget

const FILTER_TEXT: usize = 40usize
const FILTER_KEY: u64 = 2048u64
const EDIT_KEY: u64 = 3000u64
const EDIT_TEXT: usize = 64usize
const KEYBOARD_KEY: u64 = 3200u64
const GROUP_BOX_KEY: u64 = 3300u64

type CellKind = enum u8 { Text, Int, Real, Currency, Bool, Custom, Indicator, Star, Picture }

// A titled span over `count` columns from spec `first`.
type Band = struct { title: str, first: usize, count: usize }

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
    edit_focus_pending: bool,
    multi: bool,
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
    }
    let (marks, marks_error) = mem.alloc[u8](a, (table.capacity(t) + 7usize) / 8usize)
    if marks_error != ok { ret (zero, marks_error) }
    var cleared = 0usize
    while cleared < marks.len {
        marks[cleared] = 0u8
        cleared += 1usize
    }
    grid.marks = marks
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
    if look.on { grid.row_height = look.row_height }
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

fn show_group_box(grid: *Grid, on: bool) { grid.group_box_visible = on }

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
    var top = f32(at) * grid.row_height - 2.0 * grid.row_height
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
    if index < grp.visible_len(grid.g) && !grp.visible_is_group(grid.g, index) {
        let (shown, shown_error) = cell_text_of(a, grid, grid.all[grid.preview_spec], grp.visible_row(grid.g, index))
        if shown_error != ok { ret shown_error }
        text = shown
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
fn filter_value(grid: *const Grid, spec: usize) -> str { ret grid.filter_text[spec * FILTER_TEXT..spec * FILTER_TEXT + grid.filter_lens[spec]] }

const KEY_BASE: u64 = 4096u64

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
    if push_number(&sb, kind, decimals, value) != ok { ret ("", control.TooLarge) }
    ret (str.done(&sb), ok)
}

// A data cell's text: in the row's own ink when the application gave one (`set_row_ink`), else
// in `role`.
fn cell_text_node(a: *mem.Arena, grid: *const Grid, text: str, bold: bool, role: style.ColorRole, row: usize, out: *widget.Node) -> err {
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
    if grp.visible_is_group(grid.g, index) { ret group_key(grid, grp.visible_group(grid.g, index)) }
    ret row_key(grid, grp.visible_row(grid.g, index))
}

// A group row: first column "[+] key (count)", the summaries under their columns.
// The shown column that carries a group row's label: the first one that is not an indicator or
// a star (a narrow column of marks cannot hold the text).
fn label_column(grid: *const Grid) -> usize {
    var at = 0usize
    while at < grid.specs.len {
        if grid.specs[at].kind != CellKind.Indicator && grid.specs[at].kind != CellKind.Star { ret at }
        at += 1usize
    }
    ret 0usize
}

fn group_cell(a: *mem.Arena, grid: *Grid, group: usize, spec: usize, out: *widget.Node) -> err {
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
        if grid.look.on {
            if str.push(&sb, " (Count: ") != ok || str.push_usize(&sb, grp.group_count(grid.g, group)) != ok || str.push(&sb, ")") != ok { ret control.TooLarge }
        } else {
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
        let (box, box_error) = gl.mark(a, box_shape, gl.rgb(0x919191u32), gl.rgb(0xFFFFFFu32), 11.0, 11.0)
        if box_error != ok { ret box_error }
        let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
        if pair_error != ok { ret control.TooLarge }
        // layered, not a row: a narrow first column must clip the label, not fail the layout
        pair[0usize] = box
        pair[1usize] = widget.padded(0u64, 17.0, 0.0, 0.0, 0.0, style.defaults(), one(a, label))
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

fn source_cell(ctx: *void, a: *mem.Arena, index: usize, column: usize, out: *widget.Node) -> err {
    let grid = mem.cast[*Grid](ctx)
    if column >= grid.specs.len { ret control.TooLarge }
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
        let (arrow, arrow_error) = gl.mark(a, .Right, ink, ink, size, size)
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
    if grid.specs[column].kind == CellKind.Custom || grid.specs[column].kind == CellKind.Picture { ret grid.events.custom_cell(grid.events.ctx, a, grid.theme, row, grid.origin[column], out) }
    var role = grid.events.row_role(grid.events.ctx, row)
    let (text, text_error) = cell_text(a, grid, column, row)
    if text_error != ok { ret text_error }
    if !grid.has_rules { ret cell_text_node(a, grid, text, false, role, row, out) }
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
    if !look.has_fill && !look.has_bar {
        *out = node
        ret ok
    }
    // a fill or a data bar: the text over a box of the colour (the bar a fraction of its width)
    var layers: []widget.Node = zero
    var count = 0usize
    let (made, made_error) = mem.alloc[widget.Node](a, 2usize)
    if made_error != ok { ret control.TooLarge }
    layers = made
    var back = style.defaults()
    back.width = style.Length { Percent: 100.0 }
    back.height = style.Length { Percent: 100.0 }
    if look.has_bar {
        var bar = style.defaults()
        bar.width = style.Length { Percent: look.bar * 100.0 }
        bar.height = style.Length { Percent: 100.0 }
        bar.background = paint.Brush { Solid: look.bar_color }
        layers[count] = widget.box(0u64, bar, zero)
        count += 1usize
    }
    if look.has_fill { back.background = paint.Brush { Solid: look.fill } }
    layers[count] = node
    count += 1usize
    *out = widget.stack(0u64, back, layers[0usize..count])
    ret ok
}

// The kind of a visible row for the table look: 1 for a group row.
fn row_kind(ctx: *void, index: usize) -> u8 {
    let grid = mem.cast[*Grid](ctx)
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
    if shown >= grid.specs.len { ret ok }
    let spec = grid.origin[shown]
    var descending = false
    if grid.sort_column == spec { descending = !grid.descending }
    grid.sort_column = spec
    grid.descending = descending
    ret grid.events.sort_changed(grid.events.ctx, spec, descending)
}

// A tap on a group row toggles it; on a data row it selects it and tells the application.
fn on_pick(ctx: *void, value: widget.Key) -> err {
    let grid = mem.cast[*Grid](ctx)
    let base = grid.key + KEY_BASE
    let rows = u64(table.capacity(grid.t))
    if value < base { ret ok }
    let at = value - base
    if at >= rows {
        let group = usize(at - rows)
        if group < grp.group_len(grid.g) {
            ret grp.set_expanded(grid.g, group, !grp.is_expanded(grid.g, group))
        }
        ret ok
    }
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
                    edge += grid.widths[grid.origin[d]]
                    if at_point.x < edge {
                        tapped = true
                        // the tap's distance into the cell, less its padding
                        tap_x = at_point.x - (edge - grid.widths[grid.origin[d]]) - 4.0
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

fn on_filter(ctx: *void, value: str) -> err {
    let pick = mem.cast[*FilterPick](ctx)
    pick.grid.filter_lens[pick.spec] = value.len
    ret pick.grid.events.filter_changed(pick.grid.events.ctx, pick.spec, value)
}

fn on_scroll(ctx: *void, value: f32) -> err {
    let grid = mem.cast[*Grid](ctx)
    grid.offset = value
    ret ok
}

fn on_reorder(ctx: *void, value: collection.Reorder) -> err {
    let grid = mem.cast[*Grid](ctx)
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
    var ink = gl.rgb(0x2C7BD6u32)
    if !enabled { ink = gl.rgb(0xC9D3E0u32) }
    let (mark, mark_error) = gl.mark(a, shape, ink, ink, 12.0, 12.0)
    if mark_error != ok { ret (zero, mark_error) }
    let state = control.control_state(grid.theme, key, enabled, false)
    var look = style.resolve(grid.theme.tokens, .Plain, state)
    look.background = paint.rgba(0.0, 0.0, 0.0, 0.0)
    look.border_width = 0.0
    look.opacity = 1.0
    look.radius = 2.0
    look.custom_padding = true
    look.padding = 4.0
    look.padding_y = 3.0
    look.min_width = 20.0
    look.min_height = 18.0
    let (node, node_error) = control.pressable_states(a, key, grid.theme, 3u8, label, look, enabled, false, 0u32, 0u32, 0u64, action, mark)
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
    let (cells, cells_error) = mem.alloc[widget.Node](a, 8usize)
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
    let (info, info_error) = control.text(a, 0u64, str.done(&sb), grid.theme, text_options)
    if info_error != ok { ret (zero, info_error) }
    cells[3usize] = info
    // the funnel
    var funnel_ink = gl.rgb(0x8A8A8Au32)
    let funnel_key = navigator_key(grid) + 7u64
    let (funnel_mark, funnel_error) = control.icon_square(a, funnel_ink, .Filter, 16.0)
    if funnel_error != ok { ret (zero, funnel_error) }
    let funnel_state = control.control_state(grid.theme, funnel_key, grid.has_filter_action, false)
    var funnel_look = style.resolve(grid.theme.tokens, .Plain, funnel_state)
    funnel_look.background = paint.rgba(0.0, 0.0, 0.0, 0.0)
    funnel_look.border_width = 0.0
    funnel_look.opacity = 1.0
    funnel_look.radius = 2.0
    funnel_look.custom_padding = true
    funnel_look.padding = 2.0
    funnel_look.padding_y = 1.0
    funnel_look.min_width = 20.0
    funnel_look.min_height = 18.0
    let (funnel, funnel_node_error) = control.pressable_states(a, funnel_key, grid.theme, 3u8, "Filter", funnel_look, grid.has_filter_action, false, 0u32, 0u32, 0u64, &grid.filter_action, funnel_mark)
    if funnel_node_error != ok { ret (zero, funnel_node_error) }
    cells[7usize] = funnel
    ret (widget.flex(navigator_key(grid), ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 6.0 }, style.defaults(), cells[0usize..8usize]), ok)
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

// A row of the footer: the column summaries under their columns.
fn footer_row(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, grid.specs.len)
    if cells_error != ok { ret (zero, cells_error) }
    var at = 0usize
    while at < grid.specs.len {
        let s = grid.specs[at]
        var text = ""
        if at == 0usize {
            text = "Total"
        } else if s.summary >= 0 && usize(s.summary) < grid.g.specs.len {
            let (shown, shown_error) = summary_text(a, s, grp.footer_summary(grid.g, usize(s.summary)))
            if shown_error != ok { ret (zero, shown_error) }
            text = shown
        }
        var inner: widget.Node = zero
        let node_error = text_node(a, grid, text, true, .Text, &inner)
        if node_error != ok { ret (zero, node_error) }
        var cell_style = style.defaults()
        cell_style.width = style.Length { Px: grid.columns[at].width }
        if grid.look.on && text.len != 0usize { cell_style.background = paint.Brush { Solid: grid.look.footer_cell } }
        cells[at] = widget.padded(0u64, 12.0, 4.0, 0.0, 4.0, cell_style, one(a, inner))
        at += 1usize
    }
    var band_style = style.defaults()
    if grid.look.on { band_style.background = paint.Brush { Solid: grid.look.footer_band } }
    ret (widget.flex(footer_key(grid), ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, band_style, cells[0usize..grid.specs.len]), ok)
}

// The keyboard of the grid (v3's): Up and Down move the current row by one, PageUp and PageDown by a
// page, Home and End to the first and the last; in a scope round the grid, so a text field or an
// editor that takes the key keeps it.
fn with_keys(a: *mem.Arena, grid: *Grid, node: widget.Node) -> (widget.Node, err) {
    let (picks, picks_error) = mem.alloc[NavPick](a, 6usize)
    if picks_error != ok { ret (zero, control.TooLarge) }
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 10usize)
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
    var held: [1]widget.Node = zero
    let (holder, holder_error) = mem.alloc[widget.Node](a, 1usize)
    if holder_error != ok { ret (zero, control.TooLarge) }
    holder[0usize] = node
    var no_action: widget.Submit = zero
    let scope = widget.scope(grid.key + KEYBOARD_KEY, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..tab_count], default_action: no_action, cancel_action: no_action, keys: zero }, style.defaults(), holder[0usize..1usize])
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

fn group_box(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let n = grid.g.level_count
    let (chips, chips_error) = mem.alloc[widget.Node](a, n + 1usize)
    if chips_error != ok { ret (zero, control.TooLarge) }
    var i = 0usize
    while i < n {
        var title: widget.Node = zero
        let title_error = text_node(a, grid, table.column_name(grid.t, grid.g.levels[i].column), false, .Text, &title)
        if title_error != ok { ret (zero, title_error) }
        let (triangle, triangle_error) = gl.mark(a, .UpOutline, gl.rgb(0xB9B9B9u32), gl.rgb(0xFFFFFFu32), 9.0, 8.0)
        if triangle_error != ok { ret (zero, triangle_error) }
        let (inside, inside_error) = mem.alloc[widget.Node](a, 2usize)
        if inside_error != ok { ret (zero, control.TooLarge) }
        inside[0usize] = title
        inside[1usize] = triangle
        if grid.look.on && false { inside[1usize] = title }
        var chip_style = style.defaults()
        chip_style.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
        chip_style.height = style.Length { Px: 18.7 }
        let chip_row = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 14.0 }, style.defaults(), inside[0usize..2usize])
        chips[i] = widget.padded(0u64, 6.0, 0.0, 6.0, 0.0, chip_style, one(a, chip_row))
        i += 1usize
    }
    var panel = style.defaults()
    panel.background = paint.Brush { Solid: grid.look.group_row }
    panel.height = style.Length { Px: 35.0 }
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
    let padded_panel = widget.padded(0u64, 6.7, 7.3, 6.7, 7.3, panel, one(a, content))
    let (zone, zone_error) = mem.alloc[widget.Node](a, 1usize)
    if zone_error != ok { ret (zero, control.TooLarge) }
    zone[0usize] = padded_panel
    var zone_style = style.defaults()
    zone_style.width = style.Length { Percent: 100.0 }
    let drop_zone = widget.region(box_key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](grid), invoke: on_group_drop }, gestures: widget.GESTURE_DROP, enabled: true, focusable: false }, zone_style, zone[0usize..1usize])
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
    let top = usize(grid.offset / grid.row_height)
    if found < top {
        grid.offset = f32(found) * grid.row_height
    } else if found >= top + page {
        grid.offset = f32(found + 1usize - page) * grid.row_height
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
    let top = usize(grid.offset / grid.row_height)
    if found < top {
        grid.offset = f32(found) * grid.row_height
    } else if found >= top + page {
        grid.offset = f32(found + 1usize - page) * grid.row_height
    }
}

fn build(a: *mem.Arena, grid: *Grid, theme: *const control.Theme, height: f32) -> (widget.Node, err) {
    grid.theme = theme
    try follow_focus(grid, theme)
    if grp.visible_len(grid.g) == 0usize {
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
        var first = usize(grid.offset / grid.row_height)
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
    if grid.filter_visible { body_height = body_height - 44.0 }
    if grid.bands.len != 0usize { body_height = body_height - 36.0 }
    if grid.navigator_visible { body_height = body_height - 52.0 }
    if grid.group_box_visible { body_height = body_height - 35.0 }
    grid.page_rows = usize(body_height / grid.row_height)
    follow_row_after_reorder(grid)
    if grid.fit_pending {
        grid.fit_pending = false
        let fit_error = best_fit(a, grid, grid.fit_spec)
        if fit_error != ok { ret (zero, fit_error) }
    }
    var sort_shown = grid.specs.len
    let (sort_at, sort_visible) = display_of(grid, grid.sort_column)
    if sort_visible { sort_shown = sort_at }
    var table_options: collection.TableOptions = zero
    if grid.look.on {
        let lk = grid.look
        table_options.look = collection.TableLook { on: true, header_height: lk.header_height, pad: lk.pad, text_size: lk.text_size, header: lk.header, header_hover: lk.header_hover, header_line: lk.header_line, even: lk.even, odd: lk.odd, selected: lk.selected, selected_line: lk.selected_line, line: lk.line, group: lk.group_row, kind_ctx: me, kind: row_kind, glyph: header_glyph, track: lk.track, thumb: lk.thumb, scroll_width: lk.scroll_width, focus_on: grid.multi && grid.has_selection, focus_key: row_key(grid, grid.selected_row) }
    }
    if grid.preview_on {
        table_options.expandable = true
        table_options.expanded = grid.preview_open[0usize..grid.preview_count]
        table_options.expand = widget.Change[widget.Key] { ctx: me, invoke: on_expand }
        table_options.detail = collection.TableDetail { ctx: me, build: on_detail }
    }
    let (body, body_error) = collection.table_with(a, grid.key, theme, "Data grid", grid.columns, source, selected[0usize..selected_count], sort_shown, grid.descending, widget.Change[usize] { ctx: me, invoke: on_sort }, widget.Change[collection.Reorder] { ctx: me, invoke: on_reorder }, widget.Change[collection.ColumnResize] { ctx: me, invoke: on_resize }, widget.Change[widget.Key] { ctx: me, invoke: on_pick }, grid.row_height, grid.offset, widget.Change[f32] { ctx: me, invoke: on_scroll }, body_height, table_options)
    if body_error != ok { ret (zero, body_error) }
    var part_count = 1usize
    let with_footer = grid.footer_visible && grid.g.specs.len != 0usize
    let with_bands = grid.bands.len != 0usize
    if with_footer { part_count += 1usize }
    if grid.filter_visible { part_count += 1usize }
    if with_bands { part_count += 1usize }
    if grid.navigator_visible { part_count += 1usize }
    if grid.group_box_visible { part_count += 1usize }
    if part_count == 1usize {
        let (keyed_body, keyed_body_error) = with_keys(a, grid, body)
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
    if grid.filter_visible {
        let (filter, filter_error) = filter_row(a, grid)
        if filter_error != ok { ret (zero, filter_error) }
        parts[at] = filter
        at += 1usize
    }
    parts[at] = body
    at += 1usize
    if with_footer {
        let (footer, footer_error) = footer_row(a, grid)
        if footer_error != ok { ret (zero, footer_error) }
        parts[at] = footer
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
    if grid.look.on {
        // the grid is framed by a 1 px line and its parts touch
        frame.border = style.Border { width: 1.0, color: grid.look.frame }
        gap = 0.0
    }
    let stacked = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: gap }, frame, parts[0usize..part_count])
    let (keyed, keyed_error) = with_keys(a, grid, stacked)
    ret (keyed, keyed_error)
}
