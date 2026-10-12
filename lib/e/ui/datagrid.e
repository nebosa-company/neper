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
// ponytail: one level of header and the filter row sits above it (the table owns the header);
// Tab to the next editable cell and column visibility are what remains.

use e.mem
use e.str
use e.data.table as table
use e.data.tablegroup as grp
use e.ui.collection
use e.ui.control
use e.gfx.paint
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget

const FILTER_TEXT: usize = 40usize
const FILTER_KEY: u64 = 2048u64
const EDIT_KEY: u64 = 3000u64
const EDIT_TEXT: usize = 64usize

type CellKind = enum u8 { Text, Int, Real, Currency, Bool, Custom, Indicator }

// A titled span over `count` columns from spec `first`.
type Band = struct { title: str, first: usize, count: usize }

type Nav = enum u8 { First, Prev, Next, Last }

// One grid column: the table column it shows and how, and which applied group summary it
// shows on group rows and in the footer (`summary` < 0: none); `filter` asks for a field in the
// filter row.
type ColumnSpec = struct { title: str, width: f32, column: usize, kind: CellKind, decimals: u8, summary: i32, summary_kind: grp.SummaryKind, filter: bool, editable: bool }

type Events = struct {
    ctx: *void,
    sort_changed: fn(*void, usize, bool) -> err,
    row_picked: fn(*void, usize) -> err,
    filter_changed: fn(*void, usize, str) -> err,
    cell_edited: fn(*void, usize, usize) -> err,
    custom_cell: fn(*void, *mem.Arena, *const control.Theme, usize, usize, *widget.Node) -> err,
    row_role: fn(*void, usize) -> style.ColorRole
}

type Grid = struct {
    t: *table.Table,
    g: *grp.Grouping,
    specs: []const ColumnSpec,
    columns: []collection.Column,
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
    filter_text: []u8,
    filter_lens: []usize,
    theme: *const control.Theme
}

error TooManyColumns
error NotEditable
error BadLayout

fn ignore_sort(ctx: *void, column: usize, descending: bool) -> err { ret ok }

fn ignore_row(ctx: *void, row: usize) -> err { ret ok }

fn ignore_filter(ctx: *void, spec: usize, text: str) -> err { ret ok }

fn ignore_edit(ctx: *void, row: usize, spec: usize) -> err { ret ok }

fn no_custom_cell(ctx: *void, a: *mem.Arena, t: *const control.Theme, row: usize, spec: usize, out: *widget.Node) -> err { ret ok }

fn plain_role(ctx: *void, row: usize) -> style.ColorRole { ret .Text }

// Events that do nothing, for a grid that only displays.
fn no_events() -> Events {
    ret Events { ctx: nil, sort_changed: ignore_sort, row_picked: ignore_row, filter_changed: ignore_filter, cell_edited: ignore_edit, custom_cell: no_custom_cell, row_role: plain_role }
}

fn create(a: *mem.Arena, t: *table.Table, g: *grp.Grouping, specs: []const ColumnSpec, events: Events, key: widget.Key) -> (Grid, err) {
    var grid: Grid = zero
    grid.t = t
    grid.g = g
    grid.specs = specs
    grid.events = events
    grid.key = key
    grid.empty_text = "No data to display"
    grid.sort_column = specs.len
    grid.row_height = 28.0
    grid.footer_visible = true
    if specs.len != 0usize {
        let (columns, columns_error) = mem.alloc[collection.Column](a, specs.len)
        if columns_error != ok { ret (grid, columns_error) }
        var at = 0usize
        while at < specs.len {
            columns[at] = collection.Column { title: specs[at].title, width: specs[at].width }
            at += 1usize
        }
        grid.columns = columns
        let (text, text_error) = mem.alloc[u8](a, specs.len * FILTER_TEXT)
        if text_error != ok { ret (grid, text_error) }
        grid.filter_text = text
        let (lens, lens_error) = mem.alloc[usize](a, specs.len)
        if lens_error != ok { ret (grid, lens_error) }
        var k = 0usize
        while k < specs.len {
            lens[k] = 0usize
            k += 1usize
        }
        grid.filter_lens = lens
    }
    ret (grid, ok)
}

// The header's sort indicator (not the sort itself): a spec index, or `specs.len` for none.
fn show_sort(grid: *Grid, spec: usize, descending: bool) {
    grid.sort_column = spec
    grid.descending = descending
}

fn clear_selection(grid: *Grid) { grid.has_selection = false }

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
fn begin_edit(grid: *Grid, row: usize, spec: usize) -> err {
    if grid.read_only || spec >= grid.specs.len || !grid.specs[spec].editable { ret NotEditable }
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
    grid.editing = true
    grid.edit_row = row
    grid.edit_spec = spec
    grid.edit_invalid = false
    copy_edit(grid, text)
    ret ok
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
    ret grid.events.cell_edited(grid.events.ctx, row, spec)
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

// ---- layout ----------------------------------------------------------------------

fn column_width(grid: *const Grid, spec: usize) -> f32 { ret grid.columns[spec].width }

fn resize_column(grid: *Grid, spec: usize, width: f32) {
    var w = width
    if w < 24.0 { w = 24.0 }
    grid.columns[spec].width = w
}

// The layout as text: the version, the widths, the sort indicator, the two optional rows and
// the filter texts. Written into `a`.
fn save_layout(a: *mem.Arena, grid: *const Grid) -> (str, err) {
    let (b, b_error) = str.builder(a, 512usize + grid.specs.len * (FILTER_TEXT + 24usize))
    if b_error != ok { ret ("", b_error) }
    var sb = b
    if str.push(&sb, "datagrid 1\nwidths") != ok { ret ("", control.TooLarge) }
    var at = 0usize
    while at < grid.specs.len {
        if str.push(&sb, " ") != ok || str.push_f64_fixed(&sb, f64(grid.columns[at].width), 1u8) != ok { ret ("", control.TooLarge) }
        at += 1usize
    }
    if str.push(&sb, "\nsort ") != ok || str.push_usize(&sb, grid.sort_column) != ok { ret ("", control.TooLarge) }
    if grid.descending { if str.push(&sb, " desc") != ok { ret ("", control.TooLarge) } } else { if str.push(&sb, " asc") != ok { ret ("", control.TooLarge) } }
    if grid.filter_visible { if str.push(&sb, "\nfilterrow 1") != ok { ret ("", control.TooLarge) } } else { if str.push(&sb, "\nfilterrow 0") != ok { ret ("", control.TooLarge) } }
    if grid.navigator_visible { if str.push(&sb, "\nnavigator 1") != ok { ret ("", control.TooLarge) } } else { if str.push(&sb, "\nnavigator 0") != ok { ret ("", control.TooLarge) } }
    at = 0usize
    while at < grid.specs.len {
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
            while items.len > 0usize && spec < grid.specs.len {
                let (word, after) = next_token(items)
                let (value, parse_error) = str.parse_f64(word)
                if parse_error == ok { resize_column(grid, spec, f32(value)) }
                items = after
                spec += 1usize
            }
        } else if same_text(head, "sort") {
            let (number, after) = next_token(tail)
            let (value, parse_error) = str.parse_u64(number)
            if parse_error == ok && usize(value) <= grid.specs.len {
                grid.sort_column = usize(value)
                grid.descending = same_text(after, "desc")
            }
        } else if same_text(head, "filterrow") {
            grid.filter_visible = same_text(tail, "1")
        } else if same_text(head, "navigator") {
            grid.navigator_visible = same_text(tail, "1")
        } else if same_text(head, "filter") {
            let (number, value_text) = next_token(tail)
            let (spec, parse_error) = str.parse_u64(number)
            if parse_error == ok && usize(spec) < grid.specs.len {
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
    grid.preview_on = spec < grid.specs.len
    grid.preview_spec = spec
    grid.preview_count = 0usize
    // the disclosure leads the first cell: it needs room
    if grid.preview_on && grid.columns.len != 0usize && grid.columns[0usize].width < 64.0 { grid.columns[0usize].width = 64.0 }
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
        let (shown, shown_error) = cell_text(a, grid, grid.preview_spec, grp.visible_row(grid.g, index))
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
    let s = grid.specs[spec]
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

fn text_node(a: *mem.Arena, grid: *const Grid, text: str, bold: bool, role: style.ColorRole, out: *widget.Node) -> err {
    var options = control.text_options()
    options.wrap = .None
    options.color = role
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
fn group_cell(a: *mem.Arena, grid: *Grid, group: usize, spec: usize, out: *widget.Node) -> err {
    let s = grid.specs[spec]
    if spec == 0usize {
        let (b, b_error) = str.builder(a, 120usize)
        if b_error != ok { ret b_error }
        var sb = b
        let level = grp.group_level(grid.g, group)
        var indent = 0usize
        while indent < level {
            if str.push(&sb, "      ") != ok { ret control.TooLarge }
            indent += 1usize
        }
        var mark = "[+] "
        if grp.is_expanded(grid.g, group) { mark = "[-] " }
        if str.push(&sb, mark) != ok { ret control.TooLarge }
        let key_column = grid.g.levels[level].column
        let key_row = grp.group_key_row(grid.g, group)
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
        if str.push(&sb, "  (") != ok || str.push_usize(&sb, grp.group_count(grid.g, group)) != ok || str.push(&sb, ")") != ok { ret control.TooLarge }
        ret text_node(a, grid, str.done(&sb), true, .Text, out)
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
    if grid.editing && grid.edit_row == row && grid.edit_spec == column {
        var options = control.field_options()
        options.width = grid.columns[column].width - 12.0
        options.height = 36.0
        options.invalid = grid.edit_invalid
        let buffer = grid.edit_text[0usize..EDIT_TEXT]
        let me = mem.cast[*void](grid)
        let (field, field_error) = control.text_field(a, grid.key + EDIT_KEY, grid.theme, grid.specs[column].title, buffer, grid.edit_len, widget.Change[str] { ctx: me, invoke: on_edit_change }, widget.Submit { ctx: me, invoke: on_edit_commit }, options)
        if field_error != ok { ret field_error }
        *out = field
        ret ok
    }
    if grid.specs[column].kind == CellKind.Indicator {
        var mark = ""
        if grid.has_selection && grid.selected_row == row { mark = ">" }
        ret text_node(a, grid, mark, true, .Text, out)
    }
    if grid.specs[column].kind == CellKind.Custom { ret grid.events.custom_cell(grid.events.ctx, a, grid.theme, row, column, out) }
    let role = grid.events.row_role(grid.events.ctx, row)
    let (text, text_error) = cell_text(a, grid, column, row)
    if text_error != ok { ret text_error }
    ret text_node(a, grid, text, false, role, out)
}

// ---- events ----------------------------------------------------------------------

fn on_sort(ctx: *void, spec: usize) -> err {
    let grid = mem.cast[*Grid](ctx)
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
    let again = grid.has_selection && grid.selected_row == usize(at)
    grid.has_selection = true
    grid.selected_row = usize(at)
    var found = 0usize
    let visible = grp.visible_len(grid.g)
    while found < visible && (grp.visible_is_group(grid.g, found) || grp.visible_row(grid.g, found) != usize(at)) { found += 1usize }
    if found < visible {
        grid.has_position = true
        grid.position = found
    }
    if again && !grid.read_only && !grid.editing {
        // the first editable column of the row
        var column = 0usize
        while column < grid.specs.len && !grid.specs[column].editable { column += 1usize }
        if column < grid.specs.len {
            let began = begin_edit(grid, usize(at), column)
            if began != ok { ret began }
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

fn no_reorder(ctx: *void, value: collection.Reorder) -> err { ret ok }

fn on_resize(ctx: *void, value: collection.ColumnResize) -> err {
    let grid = mem.cast[*Grid](ctx)
    if value.column < grid.specs.len { resize_column(grid, value.column, value.width) }
    ret ok
}

// ---- the node --------------------------------------------------------------------

fn one(a: *mem.Arena, node: widget.Node) -> []widget.Node {
    let (nodes, nodes_error) = mem.alloc[widget.Node](a, 1usize)
    if nodes_error != ok { ret zero }
    nodes[0usize] = node
    ret nodes[0usize..1usize]
}

// The band row: each band's title over the columns it spans.
fn band_row(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, grid.specs.len + 1usize)
    if cells_error != ok { ret (zero, cells_error) }
    var count = 0usize
    var at = 0usize
    while at < grid.specs.len {
        // the band that starts here, or a plain gap up to the next band
        var span = 1usize
        var title = ""
        var found = false
        var b = 0usize
        while b < grid.bands.len {
            if grid.bands[b].first == at && grid.bands[b].count > 0usize {
                span = grid.bands[b].count
                title = grid.bands[b].title
                found = true
            }
            b += 1usize
        }
        var width: f32 = 0.0
        var k = 0usize
        while k < span && at + k < grid.specs.len {
            width += grid.columns[at + k].width
            k += 1usize
        }
        var cell_style = style.defaults()
        cell_style.width = style.Length { Px: width }
        if found {
            cell_style.background = paint.Brush { Solid: style.color(grid.theme.tokens, .SurfaceVariant) }
        }
        var inner: widget.Node = zero
        let node_error = text_node(a, grid, title, true, .Text, &inner)
        if node_error != ok { ret (zero, node_error) }
        cells[count] = widget.padded(0u64, 12.0, 4.0, 0.0, 4.0, cell_style, one(a, inner))
        count += 1usize
        at += k
    }
    ret (widget.flex(band_key(grid), ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), cells[0usize..count]), ok)
}

type NavPick = struct { grid: *Grid, kind: Nav }

fn on_navigate(ctx: *void) -> err {
    let pick = mem.cast[*NavPick](ctx)
    ret navigate(pick.grid, pick.kind)
}

// First / Prev / Next / Last buttons and "Row n of m".
fn navigator_row(a: *mem.Arena, grid: *Grid) -> (widget.Node, err) {
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
    if str.push(&sb, "Row ") != ok { ret (zero, control.TooLarge) }
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
        picks[at] = FilterPick { grid: grid, spec: at }
        var cell_style = style.defaults()
        cell_style.width = style.Length { Px: grid.columns[at].width }
        if s.filter {
            var options = control.field_options()
            options.placeholder = "filter"
            options.width = grid.columns[at].width - 12.0
            options.height = 36.0
            let buffer = grid.filter_text[at * FILTER_TEXT..(at + 1usize) * FILTER_TEXT]
            let (field, field_error) = control.text_field(a, grid.key + FILTER_KEY + u64(at), grid.theme, s.title, buffer, grid.filter_lens[at], widget.Change[str] { ctx: mem.cast[*void](&picks[at]), invoke: on_filter }, zero, options)
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
        cells[at] = widget.padded(0u64, 12.0, 4.0, 0.0, 4.0, cell_style, one(a, inner))
        at += 1usize
    }
    ret (widget.flex(footer_key(grid), ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), cells[0usize..grid.specs.len]), ok)
}

// The grid as a node of `height` for the body; `theme` must stay valid until the next build.
fn build(a: *mem.Arena, grid: *Grid, theme: *const control.Theme, height: f32) -> (widget.Node, err) {
    grid.theme = theme
    if grp.visible_len(grid.g) == 0usize {
        var inner: widget.Node = zero
        let node_error = text_node(a, grid, grid.empty_text, false, .Text, &inner)
        if node_error != ok { ret (zero, node_error) }
        ret (widget.padded(grid.key, 16.0, 16.0, 16.0, 16.0, style.defaults(), one(a, inner)), ok)
    }
    let (selected, selected_error) = mem.alloc[u64](a, 1usize)
    if selected_error != ok { ret (zero, selected_error) }
    var selected_count = 0usize
    if grid.has_selection {
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
    var sort_shown = grid.sort_column
    var table_options: collection.TableOptions = zero
    if grid.preview_on {
        table_options.expandable = true
        table_options.expanded = grid.preview_open[0usize..grid.preview_count]
        table_options.expand = widget.Change[widget.Key] { ctx: me, invoke: on_expand }
        table_options.detail = collection.TableDetail { ctx: me, build: on_detail }
    }
    let (body, body_error) = collection.table_with(a, grid.key, theme, "Data grid", grid.columns, source, selected[0usize..selected_count], sort_shown, grid.descending, widget.Change[usize] { ctx: me, invoke: on_sort }, widget.Change[collection.Reorder] { ctx: me, invoke: no_reorder }, widget.Change[collection.ColumnResize] { ctx: me, invoke: on_resize }, widget.Change[widget.Key] { ctx: me, invoke: on_pick }, grid.row_height, grid.offset, widget.Change[f32] { ctx: me, invoke: on_scroll }, body_height, table_options)
    if body_error != ok { ret (zero, body_error) }
    var part_count = 1usize
    let with_footer = grid.footer_visible && grid.g.specs.len != 0usize
    let with_bands = grid.bands.len != 0usize
    if with_footer { part_count += 1usize }
    if grid.filter_visible { part_count += 1usize }
    if with_bands { part_count += 1usize }
    if grid.navigator_visible { part_count += 1usize }
    if part_count == 1usize { ret (body, ok) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, part_count)
    if parts_error != ok { ret (zero, parts_error) }
    var at = 0usize
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
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, style.defaults(), parts[0usize..part_count]), ok)
}
