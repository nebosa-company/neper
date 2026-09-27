// examples/ui/main.e — a desktop gallery of every control the Neper UI chain
// offers (all 111 of docs/ux/components), one tab per family, each control live:
// the model behind the page keeps what a tap, a keystroke or a drag changes and
// the next frame shows it. One source builds for Windows and Linux.
//
//   build\windows\tests\selfhost\neper-self.exe emit-executable examples\ui\main.e . x64 windows build\examples\ui.exe
//   build\windows\tests\selfhost\neper-self.exe emit-executable examples\ui\main.e . x64 linux build\examples\ui
//   ui [tab 0-14]
//   ui audit
//
// The Linux build is cross-emitted by the Windows-hosted compiler: the gallery is
// past what the Linux-hosted one holds (tool.Capacity). `ui audit` runs
// `e.ui.audit` over every tab in three palettes without a window, prints a line
// per finding and a count of each kind, and exits 1 when there is any (D1601).
//
// The text is set in Segoe UI on Windows and DejaVu Sans on Linux; with no font
// the page is silent boxes, so the program says so and stops.

use e.fs
use e.gpu
use e.io
use e.mem
use e.os
use e.os.shell
use e.str
use e.time
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.text.shape
use e.ui.app
use e.ui.audit
use e.ui.collection
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.navigation
use e.ui.overlay
use e.ui.style
use e.ui.widget
use e.ui.window

const TABS: usize = 15usize
const SHELL_TAB: usize = 14usize
const MAX_NODES: usize = 64usize
const TAB_PICKS: usize = 44usize
const PICK_BASE: usize = 64usize
const PICK_SLOTS: usize = 768usize
const TRAY_ID: u32 = 1u32

// A pick: the model, the index it chooses, the model slot it writes (a flag, a
// value or a real) and a flag it closes (NO_FLAG for none).
type Pick = struct { model: *Model, index: usize, slot: usize, close: usize }
type KeySet = struct { keys: [8]widget.Key, count: usize }

// The generic slots: flags toggled by a submit, values chosen by a pick or a
// change, reals moved by a slider-like change.
const NO_FLAG: usize = 99usize
const F_RECORD: usize = 0usize
const F_AUTO: usize = 1usize
const F_TOKENS: usize = 2usize
const F_PICKER: usize = 3usize
const F_REFRESH: usize = 4usize
const F_CONTEXT: usize = 5usize
const F_DETAIL: usize = 6usize
const F_DRAWER: usize = 7usize
const F_SWITCHER: usize = 8usize
const F_PALETTE: usize = 9usize
const F_RICH: usize = 10usize
const F_MENU: usize = 11usize
const F_MODAL: usize = 12usize
const F_POPUP: usize = 13usize
const F_FLYOUT: usize = 14usize
const F_SHEET: usize = 15usize
const F_BOTTOM: usize = 16usize
const F_ACTIONS: usize = 17usize
const F_RANGE: usize = 18usize
const F_REVEAL: usize = 19usize
const F_NOTIFY: usize = 20usize
const F_HIDE: usize = 21usize
const F_RANGE_END: usize = 22usize
const F_MULTI: usize = 23usize
const F_CLEAR_DROPS: usize = 28usize
const F_BADGE: usize = 29usize
const FLAGS: usize = 32usize

const V_RADIO: usize = 0usize
const V_INNER_TAB: usize = 1usize
const V_AUTO_ACTIVE: usize = 2usize
const V_TOKEN_ACTIVE: usize = 3usize
const V_PICKED: usize = 4usize
const V_FAMILY: usize = 5usize
const V_FACE: usize = 6usize
const V_CAROUSEL: usize = 7usize
const V_VIEW: usize = 8usize
const V_DEST: usize = 9usize
const V_BAR_MENU: usize = 10usize
const V_STEP: usize = 11usize
const V_SWITCH: usize = 12usize
const V_PALETTE_ACTIVE: usize = 13usize
const V_COMMAND: usize = 14usize
const V_DOCUMENT: usize = 15usize
const V_NAV: usize = 16usize
const V_DEPTH: usize = 17usize
const V_CODE: usize = 18usize
const V_AUTO: usize = 19usize
const V_TOKEN_TEXT: usize = 20usize
const V_PALETTE: usize = 21usize
const V_PROPERTY: usize = 22usize
const V_AUTO_PICK: usize = 23usize
const V_SELECTABLE: usize = 24usize

const R_PANE: usize = 0usize
const R_LIST: usize = 1usize
const R_GRID: usize = 2usize
const R_DATA: usize = 3usize
const R_SPLIT: usize = 4usize

type Model = struct {
    theme: *const control.Theme,
    flags: [32]bool,
    values: [32]usize,
    reals: [8]f32,
    pick_next: usize,
    // content and input
    selectable: [96]u8,
    code: [16]u8,
    auto: [32]u8,
    token_text: [32]u8,
    tokens_shown: [6]str,
    token_count: usize,
    token_pool: [192]u8,
    token_used: usize,
    palette: [32]u8,
    property_text: [32]u8,
    chord: control.Chord,
    font_size: i64,
    // data
    order: [5]usize,
    collapsed: KeySet,
    pair_bytes: [256]u8,
    pairs: [4]collection.Pair,
    pair_count: usize,
    // workspace and presentation
    closed: [4]bool,
    dock: navigation.DockSizes,
    range_from: time.Date,
    range_to: time.Date,
    span: time.Duration,
    // shell
    shell_note: str,
    notices: usize,
    drops: usize,
    drop_bytes: [4096]u8,
    drop_used: usize,
    dropped: [12]str,
    dropped_count: usize,
    tokens: style.ThemeTokens,
    fonts: []shape.Font,
    registered: bool,
    texture: scene.TextureId,
    pixels: [16]u8,
    storage: []u8,
    frame: mem.Arena,
    picks: []Pick,
    tab: usize,
    // buttons
    presses: usize,
    bold: bool,
    dark: bool,
    // choice
    agree: bool,
    colour: usize,
    notify: bool,
    segment: usize,
    rating: u32,
    // range
    volume: f32,
    low: f32,
    high: f32,
    count: i64,
    angle: f32,
    // fields
    name: [64]u8,
    name_len: usize,
    secret: [64]u8,
    secret_len: usize,
    query: [64]u8,
    query_len: usize,
    note: [256]u8,
    note_len: usize,
    fruit: usize,
    fruit_open: bool,
    city: usize,
    // surfaces
    expanded: bool,
    section: usize,
    split: f32,
    // feedback
    banner_shown: bool,
    // collections
    row: widget.Key,
    sort_column: usize,
    descending: bool,
    open_nodes: [8]widget.Key,
    open_count: usize,
    node: widget.Key,
    page_index: usize,
    // overlays
    menu_open: bool,
    dialog_open: bool,
    popover_open: bool,
    choice: usize,
    date: time.Date,
    shown: time.Date,
    date_open: bool,
    clock: time.Time,
    colour_value: paint.Color,
}

// ---------------------------------------------------------------- actions

fn on_press(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    m.presses += 1usize
    ret ok
}

fn on_bold(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    m.bold = !m.bold
    ret ok
}

fn on_dark(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    m.dark = !m.dark
    if m.dark { m.tokens = style.reference(.Dark) } else { m.tokens = style.reference(.Light) }
    ret ok
}

fn on_agree(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    m.agree = !m.agree
    ret ok
}

fn on_notify(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    m.notify = !m.notify
    ret ok
}

fn on_tab(ctx: *void) -> err {
    let p = mem.cast[*Pick](ctx)
    p.model.tab = p.index
    ret ok
}

fn on_colour(ctx: *void) -> err {
    let p = mem.cast[*Pick](ctx)
    p.model.colour = p.index
    ret ok
}

fn on_segment(ctx: *void) -> err {
    let p = mem.cast[*Pick](ctx)
    p.model.segment = p.index
    ret ok
}

fn on_fruit(ctx: *void) -> err {
    let p = mem.cast[*Pick](ctx)
    p.model.fruit = p.index
    p.model.fruit_open = false
    ret ok
}

fn on_fruit_toggle(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    m.fruit_open = !m.fruit_open
    ret ok
}

fn on_city(ctx: *void) -> err {
    let p = mem.cast[*Pick](ctx)
    p.model.city = p.index
    ret ok
}

fn on_section(ctx: *void) -> err {
    let p = mem.cast[*Pick](ctx)
    if p.model.section == p.index { p.model.section = 99usize } else { p.model.section = p.index }
    ret ok
}

fn on_expand(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    m.expanded = !m.expanded
    ret ok
}

fn on_rating(ctx: *void, value: u32) -> err {
    let m = mem.cast[*Model](ctx)
    m.rating = value
    ret ok
}

fn on_volume(ctx: *void, value: f32) -> err {
    let m = mem.cast[*Model](ctx)
    m.volume = value
    ret ok
}

fn on_low(ctx: *void, value: f32) -> err {
    let m = mem.cast[*Model](ctx)
    m.low = value
    ret ok
}

fn on_high(ctx: *void, value: f32) -> err {
    let m = mem.cast[*Model](ctx)
    m.high = value
    ret ok
}

fn on_count(ctx: *void, value: i64) -> err {
    let m = mem.cast[*Model](ctx)
    m.count = value
    ret ok
}

fn on_angle(ctx: *void, value: f32) -> err {
    let m = mem.cast[*Model](ctx)
    m.angle = value
    ret ok
}

fn on_split(ctx: *void, value: f32) -> err {
    let m = mem.cast[*Model](ctx)
    m.split = value
    ret ok
}

fn on_name(ctx: *void, value: str) -> err {
    let m = mem.cast[*Model](ctx)
    m.name_len = value.len
    ret ok
}

fn on_secret(ctx: *void, value: str) -> err {
    let m = mem.cast[*Model](ctx)
    m.secret_len = value.len
    ret ok
}

fn on_query(ctx: *void, value: str) -> err {
    let m = mem.cast[*Model](ctx)
    m.query_len = value.len
    ret ok
}

fn on_clear_query(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    m.query_len = 0usize
    ret ok
}

fn on_note(ctx: *void, value: str) -> err {
    let m = mem.cast[*Model](ctx)
    m.note_len = value.len
    ret ok
}

fn on_banner(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    m.banner_shown = !m.banner_shown
    ret ok
}

fn on_menu(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    m.menu_open = !m.menu_open
    ret ok
}

fn on_dialog(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    m.dialog_open = !m.dialog_open
    ret ok
}

fn on_choice(ctx: *void) -> err {
    let p = mem.cast[*Pick](ctx)
    p.model.choice = p.index
    p.model.menu_open = false
    p.model.dialog_open = false
    ret ok
}

fn none(ctx: *void) -> err {
    ret ok
}

fn on_popover(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    m.popover_open = !m.popover_open
    ret ok
}

fn on_date_open(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    m.date_open = !m.date_open
    ret ok
}

fn on_show(ctx: *void, value: time.Date) -> err {
    let m = mem.cast[*Model](ctx)
    m.shown = value
    ret ok
}

fn on_date(ctx: *void, value: time.Date) -> err {
    let m = mem.cast[*Model](ctx)
    m.date = value
    m.date_open = false
    ret ok
}

fn on_clock(ctx: *void, value: time.Time) -> err {
    let m = mem.cast[*Model](ctx)
    m.clock = value
    ret ok
}

fn on_colour_value(ctx: *void, value: paint.Color) -> err {
    let m = mem.cast[*Model](ctx)
    m.colour_value = value
    ret ok
}

fn on_row(ctx: *void, value: widget.Key) -> err {
    let m = mem.cast[*Model](ctx)
    m.row = value
    ret ok
}

fn on_sort(ctx: *void, value: usize) -> err {
    let m = mem.cast[*Model](ctx)
    if m.sort_column == value { m.descending = !m.descending } else { m.descending = false }
    m.sort_column = value
    ret ok
}

fn on_node(ctx: *void, value: widget.Key) -> err {
    let m = mem.cast[*Model](ctx)
    m.node = value
    ret ok
}

fn on_node_toggle(ctx: *void, value: widget.Key) -> err {
    let m = mem.cast[*Model](ctx)
    var i = 0usize
    while i < m.open_count {
        if m.open_nodes[i] == value {
            m.open_nodes[i] = m.open_nodes[m.open_count - 1usize]
            m.open_count -= 1usize
            ret ok
        }
        i += 1usize
    }
    if m.open_count < 8usize {
        m.open_nodes[m.open_count] = value
        m.open_count += 1usize
    }
    ret ok
}

fn on_page(ctx: *void, value: usize) -> err {
    let m = mem.cast[*Model](ctx)
    m.page_index = value
    ret ok
}

fn no_change_f32(ctx: *void, value: f32) -> err {
    ret ok
}

fn no_change_reorder(ctx: *void, value: collection.Reorder) -> err {
    ret ok
}

fn no_change_resize(ctx: *void, value: collection.ColumnResize) -> err {
    ret ok
}

// ---------------------------------------------------------------- table and tree sources

const ROWS: usize = 12usize
const COLUMNS: usize = 3usize

fn planet(index: usize) -> str {
    let names: [12]str = [12]str{ "Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune", "Pluto", "Ceres", "Eris", "Haumea" }
    ret names[index % 12usize]
}

fn table_count(ctx: *void) -> usize {
    ret ROWS
}

fn table_key(ctx: *void, index: usize) -> widget.Key {
    ret 1u64 + u64(index)
}

fn table_cell(ctx: *void, a: *mem.Arena, row: usize, column: usize, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    var value = planet(row)
    if column == 1usize { value = counted(a, "", (row + 1usize) * 7usize) }
    if column == 2usize {
        value = "rocky"
        if row >= 4usize { value = "gas" }
    }
    let (node, node_error) = control.text(a, 0u64, value, t, control.text_options())
    if node_error != ok { ret node_error }
    *out = node
    ret ok
}

// The tree: three branches under the root, each with three leaves; a node's key is
// `branch * 10 + leaf` (a branch has leaf 0).
fn tree_count(ctx: *void, parent: widget.Key) -> usize {
    if parent == 0u64 { ret 3usize }
    if parent % 10u64 == 0u64 { ret 3usize }
    ret 0usize
}

fn tree_key(ctx: *void, parent: widget.Key, index: usize) -> widget.Key {
    if parent == 0u64 { ret (u64(index) + 1u64) * 10u64 }
    ret parent + u64(index) + 1u64
}

fn tree_has_children(ctx: *void, node: widget.Key) -> bool {
    ret node % 10u64 == 0u64
}

fn tree_build(ctx: *void, a: *mem.Arena, node: widget.Key, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    var value = counted(a, "Leaf ", usize(node))
    if node % 10u64 == 0u64 { value = counted(a, "Branch ", usize(node / 10u64)) }
    let (text_node, node_error) = control.text(a, 0u64, value, t, control.text_options())
    if node_error != ok { ret node_error }
    *out = text_node
    ret ok
}

// ---------------------------------------------------------------- helpers

// A submit over the model, in the build arena: an element keeps the pointer past
// the build, so it must not live on a stack.
fn submit(a: *mem.Arena, m: *Model, f: fn(*void) -> err) -> *widget.Submit {
    var none_at_all: *widget.Submit = zero
    let (one, one_error) = mem.alloc[widget.Submit](a, 1usize)
    if one_error != ok { ret none_at_all }
    one[0usize] = widget.Submit { ctx: mem.cast[*void](m), invoke: f }
    ret &one[0usize]
}

// Submits over the pick contexts `first..first+n`, each carrying its index.
fn picks(a: *mem.Arena, m: *Model, first: usize, n: usize, f: fn(*void) -> err) -> ([]widget.Submit, err) {
    let (out, out_error) = mem.alloc[widget.Submit](a, n)
    if out_error != ok { ret (out, out_error) }
    var i = 0usize
    while i < n {
        m.picks[first + i] = Pick { model: m, index: i, slot: 0usize, close: NO_FLAG }
        out[i] = widget.Submit { ctx: mem.cast[*void](&m.picks[first + i]), invoke: f }
        i += 1usize
    }
    ret (out, ok)
}

// A page's rows: a vertical flex of what was pushed, in a scroll view.
type Page = struct { a: *mem.Arena, t: *const control.Theme, nodes: []widget.Node, n: usize, failed: err }

fn page(a: *mem.Arena, t: *const control.Theme) -> (Page, err) {
    let (nodes, nodes_error) = mem.alloc[widget.Node](a, MAX_NODES)
    if nodes_error != ok { ret (zero, nodes_error) }
    ret (Page { a: a, t: t, nodes: nodes, n: 0usize, failed: ok }, ok)
}

fn add(p: *Page, node: widget.Node, node_error: err) {
    if node_error != ok { p.failed = node_error }
    if p.failed != ok || p.n >= p.nodes.len { ret }
    p.nodes[p.n] = node
    p.n += 1usize
}

fn caption(p: *Page, key: widget.Key, value: str) {
    var options = control.text_options()
    options.role = .Title
    let (node, node_error) = control.text(p.a, key, value, p.t, options)
    add(p, node, node_error)
}

fn label(p: *Page, key: widget.Key, value: str) {
    var options = control.text_options()
    options.role = .BodySmall
    options.color = .TextMuted
    let (node, node_error) = control.text(p.a, key, value, p.t, options)
    add(p, node, node_error)
}

fn finish(p: *Page, key: widget.Key) -> (widget.Node, err) {
    if p.failed != ok { ret (zero, p.failed) }
    let gap = p.t.tokens.spacing.md
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: gap }, style.defaults(), p.nodes[0usize..p.n])
    let (inner, inner_error) = mem.alloc[widget.Node](p.a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = widget.padded(0u64, gap, gap, gap, gap, style.defaults(), slice_of(p.a, column))
    var fill = style.defaults()
    fill.width = style.Length { Percent: 100.0 }
    fill.height = style.Length { Flex: 1.0 }
    let (view, view_error) = widget.scroll_view(p.a, key, .Vertical, fill, inner[0usize..1usize])
    ret (view, view_error)
}

fn slice_of(a: *mem.Arena, node: widget.Node) -> []widget.Node {
    let (one, one_error) = mem.alloc[widget.Node](a, 1usize)
    if one_error != ok { ret zero }
    one[0usize] = node
    ret one[0usize..1usize]
}

fn row_of(p: *Page, key: widget.Key, items: []const widget.Node) {
    let node = widget.flex(key, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: p.t.tokens.spacing.sm }, style.defaults(), items)
    add(p, node, ok)
}

fn counted(a: *mem.Arena, prefix: str, n: usize) -> str {
    let (b, b_error) = str.builder(a, 64usize)
    if b_error != ok { ret prefix }
    var sb = b
    if str.push(&sb, prefix) != ok || str.push_usize(&sb, n) != ok { ret prefix }
    ret str.done(&sb)
}

fn measured(a: *mem.Arena, prefix: str, v: f32) -> str {
    let (b, b_error) = str.builder(a, 64usize)
    if b_error != ok { ret prefix }
    var sb = b
    if str.push(&sb, prefix) != ok || str.push_f32(&sb, v) != ok { ret prefix }
    ret str.done(&sb)
}

// ---------------------------------------------------------------- pages

fn buttons_page(a: *mem.Arena, t: *const control.Theme, m: *Model) -> (widget.Node, err) {
    let (pg, pg_error) = page(a, t)
    if pg_error != ok { ret (zero, pg_error) }
    var p = pg
    caption(&p, 1u64, "Buttons")
    label(&p, 2u64, counted(a, "Filled, outlined and plain buttons; presses so far: ", m.presses))
    let (items, items_error) = mem.alloc[widget.Node](a, 7usize)
    if items_error != ok { ret (zero, items_error) }
    let press = submit(a, m, on_press)
    let (filled, filled_error) = control.button(a, 100u64, t, "Filled", press, control.button_options())
    if filled_error != ok { ret (zero, filled_error) }
    items[0usize] = filled
    var outlined = control.button_options()
    outlined.variant = .Outlined
    let (outlined_node, outlined_error) = control.button(a, 101u64, t, "Outlined", press, outlined)
    if outlined_error != ok { ret (zero, outlined_error) }
    items[1usize] = outlined_node
    var plain = control.button_options()
    plain.variant = .Plain
    let (plain_node, plain_error) = control.button(a, 102u64, t, "Plain", press, plain)
    if plain_error != ok { ret (zero, plain_error) }
    items[2usize] = plain_node
    var off = control.button_options()
    off.enabled = false
    let (off_node, off_error) = control.button(a, 103u64, t, "Disabled", press, off)
    if off_error != ok { ret (zero, off_error) }
    items[3usize] = off_node
    let bold = submit(a, m, on_bold)
    let (toggle, toggle_error) = control.toggle_button(a, 104u64, t, "Bold", m.bold, bold, outlined)
    if toggle_error != ok { ret (zero, toggle_error) }
    items[4usize] = toggle
    let (link, link_error) = control.link(a, 105u64, t, "A link", press)
    if link_error != ok { ret (zero, link_error) }
    items[5usize] = link
    let (pictured, pictured_error) = control.icon_button(a, 108u64, t, m.texture, "Picture", press, outlined)
    if pictured_error != ok { ret (zero, pictured_error) }
    items[6usize] = pictured
    row_of(&p, 3u64, items[0usize..7usize])
    caption(&p, 4u64, "Theme")
    let dark = submit(a, m, on_dark)
    let (theme_switch, switch_error) = control.switch_control(a, 106u64, t, "Dark palette", m.dark, dark, true)
    add(&p, theme_switch, switch_error)
    caption(&p, 5u64, "Split button and speed dial")
    let (chips, chips_error) = mem.alloc[widget.Node](a, 2usize)
    if chips_error != ok { ret (zero, chips_error) }
    let menu = submit(a, m, on_menu)
    let (split, split_error) = control.split_button(a, 107u64, t, "Save", press, m.menu_open, menu)
    if split_error != ok { ret (zero, split_error) }
    chips[0usize] = split
    let dial_labels: [3]str = [3]str{ "New", "Open", "Print" }
    let (dial_actions, dial_error) = picks(a, m, 40usize, 3usize, on_choice)
    if dial_error != ok { ret (zero, dial_error) }
    let dialog = submit(a, m, on_dialog)
    let (speed, speed_error) = control.speed_dial(a, 120u64, t, "Actions", dial_labels[..], dial_actions, m.dialog_open, dialog)
    if speed_error != ok { ret (zero, speed_error) }
    chips[1usize] = speed
    row_of(&p, 6u64, chips[0usize..2usize])
    let (node, node_error) = finish(&p, 7u64)
    ret (node, node_error)
}

fn choice_page(a: *mem.Arena, t: *const control.Theme, m: *Model) -> (widget.Node, err) {
    let (pg, pg_error) = page(a, t)
    if pg_error != ok { ret (zero, pg_error) }
    var p = pg
    caption(&p, 1u64, "Checkbox and switch")
    let agree = submit(a, m, on_agree)
    let (check, check_error) = control.checkbox(a, 100u64, t, "I agree to the terms", m.agree, false, agree, true)
    add(&p, check, check_error)
    let (mixed, mixed_error) = control.checkbox(a, 101u64, t, "Some of the above", false, true, agree, true)
    add(&p, mixed, mixed_error)
    let (off, off_error) = control.checkbox(a, 102u64, t, "Not available", false, false, agree, false)
    add(&p, off, off_error)
    let notify = submit(a, m, on_notify)
    let (sw, sw_error) = control.switch_control(a, 103u64, t, "Notifications", m.notify, notify, true)
    add(&p, sw, sw_error)
    caption(&p, 2u64, "Radio group")
    let colours: [3]str = [3]str{ "Red", "Green", "Blue" }
    let (colour_picks, colour_error) = picks(a, m, 8usize, 3usize, on_colour)
    if colour_error != ok { ret (zero, colour_error) }
    let (radios, radios_error) = control.radio_group(a, 110u64, t, "Colour", colours[..], m.colour, colour_picks, true)
    add(&p, radios, radios_error)
    caption(&p, 3u64, "Segmented control")
    let views: [3]str = [3]str{ "Day", "Week", "Month" }
    let (segment_picks, segment_error) = picks(a, m, 12usize, 3usize, on_segment)
    if segment_error != ok { ret (zero, segment_error) }
    let (segments, segments_error) = control.segmented_control(a, 120u64, t, "View", views[..], m.segment, segment_picks, true)
    add(&p, segments, segments_error)
    caption(&p, 4u64, "Rating and chips")
    let (rate, rate_error) = control.rating(a, 130u64, t, "Stars", m.rating, 5u32, widget.Change[u32] { ctx: mem.cast[*void](m), invoke: on_rating })
    add(&p, rate, rate_error)
    let (chips, chips_error) = mem.alloc[widget.Node](a, 4usize)
    if chips_error != ok { ret (zero, chips_error) }
    let bold = submit(a, m, on_bold)
    let quiet = submit(a, m, none)
    let (assist, assist_error) = control.chip(a, 140u64, t, "Assist", .Assist, false, quiet, quiet)
    if assist_error != ok { ret (zero, assist_error) }
    chips[0usize] = assist
    let (filter, filter_error) = control.chip(a, 141u64, t, "Filter", .Filter, m.bold, bold, quiet)
    if filter_error != ok { ret (zero, filter_error) }
    chips[1usize] = filter
    let (input_chip, input_error) = control.chip(a, 142u64, t, "Input", .Input, false, quiet, quiet)
    if input_error != ok { ret (zero, input_error) }
    chips[2usize] = input_chip
    let (suggestion, suggestion_error) = control.chip(a, 143u64, t, "Suggestion", .Suggestion, false, quiet, quiet)
    if suggestion_error != ok { ret (zero, suggestion_error) }
    chips[3usize] = suggestion
    row_of(&p, 5u64, chips[0usize..4usize])
    let (node, node_error) = finish(&p, 6u64)
    ret (node, node_error)
}

fn change_f32(m: *Model, f: fn(*void, f32) -> err) -> widget.Change[f32] {
    ret widget.Change[f32] { ctx: mem.cast[*void](m), invoke: f }
}

fn range_page(a: *mem.Arena, t: *const control.Theme, m: *Model) -> (widget.Node, err) {
    let (pg, pg_error) = page(a, t)
    if pg_error != ok { ret (zero, pg_error) }
    var p = pg
    caption(&p, 1u64, "Sliders")
    label(&p, 2u64, measured(a, "Volume: ", m.volume))
    let (volume, volume_error) = control.slider(a, 100u64, t, "Volume", m.volume, 0.0, 100.0, 1.0, change_f32(m, on_volume), true)
    add(&p, volume, volume_error)
    let (range, range_error) = control.range_slider(a, 110u64, t, "Range", m.low, m.high, 0.0, 100.0, 5.0, change_f32(m, on_low), change_f32(m, on_high), true)
    add(&p, range, range_error)
    let (off, off_error) = control.slider(a, 120u64, t, "Disabled", 30.0, 0.0, 100.0, 1.0, change_f32(m, no_change_f32), false)
    add(&p, off, off_error)
    caption(&p, 3u64, "Progress")
    let (bar, bar_error) = control.progress_bar(a, 130u64, t, "Progress", m.volume / 100.0, false, 240.0)
    add(&p, bar, bar_error)
    let (busy, busy_error) = control.progress_bar(a, 131u64, t, "Busy", 0.0, true, 240.0)
    add(&p, busy, busy_error)
    let (rings, rings_error) = mem.alloc[widget.Node](a, 4usize)
    if rings_error != ok { ret (zero, rings_error) }
    let (ring, ring_error) = control.progress_ring(a, 140u64, t, "Ring", m.volume / 100.0, false, 48.0)
    if ring_error != ok { ret (zero, ring_error) }
    rings[0usize] = ring
    let (gauge, gauge_error) = control.gauge(a, 141u64, t, "Gauge", m.volume, 0.0, 100.0, 72.0)
    if gauge_error != ok { ret (zero, gauge_error) }
    rings[1usize] = gauge
    let (level, level_error) = control.level(a, 142u64, t, "Level", m.volume, 0.0, 100.0, 0.6, 0.85, 160.0)
    if level_error != ok { ret (zero, level_error) }
    rings[2usize] = level
    let (dial, dial_error) = control.dial(a, 143u64, t, "Angle", m.angle, 0.0, 360.0, change_f32(m, on_angle), 64.0)
    if dial_error != ok { ret (zero, dial_error) }
    rings[3usize] = dial
    row_of(&p, 4u64, rings[0usize..4usize])
    caption(&p, 5u64, "Stepper and spin box")
    let (steps, steps_error) = mem.alloc[widget.Node](a, 2usize)
    if steps_error != ok { ret (zero, steps_error) }
    let count_change = widget.Change[i64] { ctx: mem.cast[*void](m), invoke: on_count }
    let (stepper, stepper_error) = control.stepper(a, 150u64, t, "Count", m.count, 0i64, 20i64, 1i64, count_change)
    if stepper_error != ok { ret (zero, stepper_error) }
    steps[0usize] = stepper
    let (spin_buffer, spin_error) = mem.alloc[u8](a, 32usize)
    if spin_error != ok { ret (zero, spin_error) }
    let (spin, spin_box_error) = control.spin_box(a, 160u64, t, "Count", spin_buffer, m.count, 0i64, 20i64, 1i64, count_change, widget.Change[str] { ctx: mem.cast[*void](m), invoke: on_note })
    if spin_box_error != ok { ret (zero, spin_box_error) }
    steps[1usize] = spin
    row_of(&p, 6u64, steps[0usize..2usize])
    let (node, node_error) = finish(&p, 7u64)
    ret (node, node_error)
}

fn fields_page(a: *mem.Arena, t: *const control.Theme, m: *Model) -> (widget.Node, err) {
    let (pg, pg_error) = page(a, t)
    if pg_error != ok { ret (zero, pg_error) }
    var p = pg
    let ctx = mem.cast[*void](m)
    let quiet = submit(a, m, none)
    caption(&p, 1u64, "Text fields")
    var name_options = control.field_options()
    name_options.placeholder = "Your name"
    let (name, name_error) = control.text_field(a, 100u64, t, "Name", m.name[..], m.name_len, widget.Change[str] { ctx: ctx, invoke: on_name }, zero, name_options)
    add(&p, name, name_error)
    let (secret, secret_error) = control.password_field(a, 110u64, t, "Password", m.secret[..], m.secret_len, widget.Change[str] { ctx: ctx, invoke: on_secret }, zero, control.field_options())
    add(&p, secret, secret_error)
    let clear = submit(a, m, on_clear_query)
    var search_options = control.field_options()
    search_options.placeholder = "Search"
    let (search, search_error) = control.search_field(a, 120u64, t, m.query[..], m.query_len, widget.Change[str] { ctx: ctx, invoke: on_query }, zero, clear, search_options)
    add(&p, search, search_error)
    var note_options = control.field_options()
    note_options.rows = 3u32
    note_options.width = 320.0
    let (note, note_error) = control.text_area(a, 130u64, t, "Notes", m.note[..], m.note_len, widget.Change[str] { ctx: ctx, invoke: on_note }, note_options)
    add(&p, note, note_error)
    var invalid_options = control.field_options()
    invalid_options.invalid = true
    let (email, email_error) = control.text_field(a, 141u64, t, "Email", m.query[..], 0usize, widget.Change[str] { ctx: ctx, invoke: on_query }, zero, invalid_options)
    if email_error != ok { ret (zero, email_error) }
    let (formed, formed_error) = control.form_field(a, 140u64, t, "Email", 141u64, email, "We never share it", control.Message { validity: .Invalid, text: "An address needs an @" }, true)
    add(&p, formed, formed_error)
    // The parts a form field is made of, assembled by hand.
    let (nick_label, nick_label_error) = control.field_label(a, 300u64, t, "Nickname", 310u64, true)
    add(&p, nick_label, nick_label_error)
    let (nick, nick_error) = control.text_field(a, 310u64, t, "", m.name[..], m.name_len, widget.Change[str] { ctx: ctx, invoke: on_name }, zero, control.field_options())
    add(&p, nick, nick_error)
    let (nick_message, nick_message_error) = control.field_message(a, 320u64, t, control.Message { validity: .Valid, text: "Shown to other players" }, 310u64)
    add(&p, nick_message, nick_message_error)
    caption(&p, 2u64, "Choosers")
    let fruits: [4]str = [4]str{ "Apple", "Pear", "Plum", "Fig" }
    let (fruit_picks, fruit_error) = picks(a, m, 16usize, 4usize, on_fruit)
    if fruit_error != ok { ret (zero, fruit_error) }
    let fruit_toggle = submit(a, m, on_fruit_toggle)
    let (chosen, chosen_error) = control.select(a, 150u64, t, "Fruit", fruits[..], m.fruit, m.fruit_open, fruit_toggle, fruit_picks)
    add(&p, chosen, chosen_error)
    let cities: [4]str = [4]str{ "Lisbon", "Oslo", "Prague", "Sofia" }
    let (city_picks, city_error) = picks(a, m, 20usize, 4usize, on_city)
    if city_error != ok { ret (zero, city_error) }
    let (listed, listed_error) = control.list_box(a, 160u64, t, "City", cities[..], m.city, city_picks, 3u32, 200.0)
    add(&p, listed, listed_error)
    let (combo_buffer, combo_error) = mem.alloc[u8](a, 64usize)
    if combo_error != ok { ret (zero, combo_error) }
    let (combo, combo_box_error) = control.combo_box(a, 170u64, t, "City", combo_buffer, 0usize, widget.Change[str] { ctx: ctx, invoke: on_note }, cities[..], m.city, false, city_picks, widget.Change[usize] { ctx: ctx, invoke: on_page }, quiet, control.field_options())
    add(&p, combo, combo_box_error)
    let (node, node_error) = finish(&p, 3u64)
    ret (node, node_error)
}

fn surfaces_page(a: *mem.Arena, t: *const control.Theme, m: *Model) -> (widget.Node, err) {
    let (pg, pg_error) = page(a, t)
    if pg_error != ok { ret (zero, pg_error) }
    var p = pg
    caption(&p, 1u64, "Panel, card and group box")
    let (panel_text, panel_text_error) = control.text(a, 0u64, "A panel holds a page of content", t, control.text_options())
    if panel_text_error != ok { ret (zero, panel_text_error) }
    let (card_text, card_text_error) = control.text(a, 0u64, "A card lifts a summary", t, control.text_options())
    if card_text_error != ok { ret (zero, card_text_error) }
    let (group_text, group_text_error) = control.text(a, 0u64, "A group box names a set", t, control.text_options())
    if group_text_error != ok { ret (zero, group_text_error) }
    let (surfaces, surfaces_error) = mem.alloc[widget.Node](a, 3usize)
    if surfaces_error != ok { ret (zero, surfaces_error) }
    let (panel, panel_error) = control.panel(a, 100u64, t, slice_of(a, panel_text))
    if panel_error != ok { ret (zero, panel_error) }
    surfaces[0usize] = panel
    let (card, card_error) = control.card(a, 101u64, t, slice_of(a, card_text))
    if card_error != ok { ret (zero, card_error) }
    surfaces[1usize] = card
    let (group, group_error) = control.group_box(a, 102u64, t, "Options", slice_of(a, group_text))
    if group_error != ok { ret (zero, group_error) }
    surfaces[2usize] = group
    row_of(&p, 2u64, surfaces[0usize..3usize])
    caption(&p, 3u64, "Divider, badge, avatar, placeholder, skeleton")
    let (small, small_error) = mem.alloc[widget.Node](a, 5usize)
    if small_error != ok { ret (zero, small_error) }
    let (divider, divider_error) = control.divider(a, 110u64, t, .Vertical, 32.0)
    if divider_error != ok { ret (zero, divider_error) }
    small[0usize] = divider
    let (badge, badge_error) = control.badge(a, 111u64, t, "3")
    if badge_error != ok { ret (zero, badge_error) }
    small[1usize] = badge
    let (avatar, avatar_error) = control.avatar(a, 112u64, t, m.texture, 32.0, "Ada")
    if avatar_error != ok { ret (zero, avatar_error) }
    small[2usize] = avatar
    let (placeholder, placeholder_error) = control.placeholder(a, 113u64, t, 80.0, 32.0)
    if placeholder_error != ok { ret (zero, placeholder_error) }
    small[3usize] = placeholder
    let (skeleton, skeleton_error) = control.skeleton(a, 114u64, t, 120.0, 16.0, 0.5)
    if skeleton_error != ok { ret (zero, skeleton_error) }
    small[4usize] = skeleton
    row_of(&p, 4u64, small[0usize..5usize])
    caption(&p, 5u64, "Disclosure, expander and accordion")
    let expand = submit(a, m, on_expand)
    let (hidden, hidden_error) = control.text(a, 0u64, "The content a disclosure reveals", t, control.text_options())
    if hidden_error != ok { ret (zero, hidden_error) }
    let (disclosure, disclosure_error) = control.disclosure(a, 120u64, t, "Details", m.expanded, expand, hidden)
    add(&p, disclosure, disclosure_error)
    let (expander, expander_error) = control.expander(a, 130u64, t, "More", m.expanded, expand, hidden)
    add(&p, expander, expander_error)
    let sections: [3]str = [3]str{ "First", "Second", "Third" }
    let (section_picks, section_error) = picks(a, m, 24usize, 3usize, on_section)
    if section_error != ok { ret (zero, section_error) }
    let (contents, contents_error) = mem.alloc[widget.Node](a, 3usize)
    if contents_error != ok { ret (zero, contents_error) }
    var i = 0usize
    while i < 3usize {
        let (content, content_error) = control.text(a, 0u64, counted(a, "Section ", i + 1usize), t, control.text_options())
        if content_error != ok { ret (zero, content_error) }
        contents[i] = content
        i += 1usize
    }
    let (accordion, accordion_error) = control.accordion(a, 140u64, t, "Sections", sections[..], contents[0usize..3usize], m.section, section_picks)
    add(&p, accordion, accordion_error)
    caption(&p, 6u64, "Split view")
    let (left, left_error) = control.text(a, 0u64, "Left pane: drag the handle", t, control.text_options())
    if left_error != ok { ret (zero, left_error) }
    let (right, right_error) = control.text(a, 0u64, "Right pane", t, control.text_options())
    if right_error != ok { ret (zero, right_error) }
    let (split, split_error) = control.split_view(a, 150u64, t, .Horizontal, left, right, m.split, 80.0, 80.0, change_f32(m, on_split), 480.0, 80.0)
    add(&p, split, split_error)
    let (node, node_error) = finish(&p, 7u64)
    ret (node, node_error)
}

fn feedback_page(a: *mem.Arena, t: *const control.Theme, m: *Model) -> (widget.Node, err) {
    let (pg, pg_error) = page(a, t)
    if pg_error != ok { ret (zero, pg_error) }
    var p = pg
    let ctx = mem.cast[*void](m)
    let quiet = submit(a, m, none)
    let banner_toggle = submit(a, m, on_banner)
    caption(&p, 1u64, "Banner and info bar (the banner brings a snackbar and a toast)")
    let (labels, labels_error) = mem.alloc[str](a, 1usize)
    if labels_error != ok { ret (zero, labels_error) }
    labels[0usize] = "Undo"
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (zero, actions_error) }
    actions[0usize] = widget.Submit { ctx: ctx, invoke: on_banner }
    if m.banner_shown {
        let (banner, banner_error) = control.banner(a, 100u64, t, .Warning, "Your changes are not saved yet", labels[0usize..1usize], actions[0usize..1usize], 480.0)
        add(&p, banner, banner_error)
    } else {
        let (show, show_error) = control.button(a, 100u64, t, "Show the banner", banner_toggle, control.button_options())
        add(&p, show, show_error)
    }
    let (info, info_error) = control.info_bar(a, 110u64, t, .Info, "Builds finished on both hosts", labels[0usize..0usize], actions[0usize..0usize], quiet, 480.0)
    add(&p, info, info_error)
    let (success, success_error) = control.info_bar(a, 111u64, t, .Success, "Saved", labels[0usize..0usize], actions[0usize..0usize], quiet, 480.0)
    add(&p, success, success_error)
    let (failure, failure_error) = control.info_bar(a, 112u64, t, .Error, "The host refused the write", labels[0usize..0usize], actions[0usize..0usize], quiet, 480.0)
    add(&p, failure, failure_error)
    caption(&p, 2u64, "Snackbar, toast and notifications")
    let (notices, notices_error) = mem.alloc[control.Notice](a, 2usize)
    if notices_error != ok { ret (zero, notices_error) }
    notices[0usize] = control.Notice { text: "Message sent", action_label: "Undo", action: widget.Submit { ctx: ctx, invoke: none }, dismiss: widget.Submit { ctx: ctx, invoke: none } }
    notices[1usize] = control.Notice { text: "Three files copied", action_label: "", action: zero, dismiss: widget.Submit { ctx: ctx, invoke: none } }
    // The transient pair floats over the window's edges while the banner is up.
    if m.banner_shown {
        let (snack, snack_error) = control.snackbar(a, 120u64, t, notices[0usize..1usize], 320.0)
        add(&p, snack, snack_error)
        let (toast, toast_error) = control.toast(a, 121u64, t, notices[1usize..2usize], 320.0)
        add(&p, toast, toast_error)
    }
    let (list, list_error) = control.notification_list(a, 130u64, t, "Notifications", notices[0usize..2usize], quiet, 400.0, 120.0)
    add(&p, list, list_error)
    caption(&p, 3u64, "Empty state and validation summary")
    let (empty, empty_error) = control.empty_state(a, 140u64, t, zero, "No projects yet", "Create one to see it here", "Create", quiet, 320.0)
    add(&p, empty, empty_error)
    let (messages, messages_error) = mem.alloc[control.Message](a, 2usize)
    if messages_error != ok { ret (zero, messages_error) }
    messages[0usize] = control.Message { validity: .Invalid, text: "Name is required" }
    messages[1usize] = control.Message { validity: .Warning, text: "Password is short" }
    let (field_keys, keys_error) = mem.alloc[widget.Key](a, 2usize)
    if keys_error != ok { ret (zero, keys_error) }
    field_keys[0usize] = 100u64
    field_keys[1usize] = 110u64
    let (jumps, jumps_error) = picks(a, m, 28usize, 2usize, none)
    if jumps_error != ok { ret (zero, jumps_error) }
    let (summary, summary_error) = control.validation_summary(a, 150u64, t, messages[0usize..2usize], field_keys[0usize..2usize], jumps)
    add(&p, summary, summary_error)
    let (node, node_error) = finish(&p, 4u64)
    ret (node, node_error)
}

fn collections_page(a: *mem.Arena, t: *const control.Theme, m: *Model) -> (widget.Node, err) {
    let (pg, pg_error) = page(a, t)
    if pg_error != ok { ret (zero, pg_error) }
    var p = pg
    let ctx = mem.cast[*void](m)
    let theme_ctx = mem.cast[*void](t)
    caption(&p, 1u64, "List and grid")
    let (items, items_error) = mem.alloc[widget.Node](a, 4usize)
    if items_error != ok { ret (zero, items_error) }
    let (keys, keys_error) = mem.alloc[widget.Key](a, 4usize)
    if keys_error != ok { ret (zero, keys_error) }
    var i = 0usize
    while i < 4usize {
        let (item, item_error) = control.text(a, 0u64, planet(i), t, control.text_options())
        if item_error != ok { ret (zero, item_error) }
        items[i] = item
        keys[i] = 1u64 + u64(i)
        i += 1usize
    }
    let (selected, selected_error) = mem.alloc[widget.Key](a, 1usize)
    if selected_error != ok { ret (zero, selected_error) }
    selected[0usize] = m.row
    let (both, both_error) = mem.alloc[widget.Node](a, 2usize)
    if both_error != ok { ret (zero, both_error) }
    let (list, list_error) = collection.list(a, 100u64, t, "Planets", items[0usize..4usize], keys[0usize..4usize], selected[0usize..1usize], true, 200.0)
    if list_error != ok { ret (zero, list_error) }
    both[0usize] = list
    let (cells, cells_error) = mem.alloc[widget.Node](a, 4usize)
    if cells_error != ok { ret (zero, cells_error) }
    i = 0usize
    while i < 4usize {
        let (cell, cell_error) = control.placeholder(a, 0u64, t, 64.0, 48.0)
        if cell_error != ok { ret (zero, cell_error) }
        cells[i] = cell
        i += 1usize
    }
    let (grid, grid_error) = collection.grid_view(a, 110u64, t, "Tiles", cells[0usize..4usize], keys[0usize..4usize], selected[0usize..1usize], geometry.Size { width: 72.0, height: 56.0 }, 8.0, 180.0)
    if grid_error != ok { ret (zero, grid_error) }
    both[1usize] = grid
    row_of(&p, 2u64, both[0usize..2usize])
    caption(&p, 3u64, "Table: tap a header to sort, a row to select")
    let (columns, columns_error) = mem.alloc[collection.Column](a, COLUMNS)
    if columns_error != ok { ret (zero, columns_error) }
    columns[0usize] = collection.Column { title: "Planet", width: 140.0 }
    columns[1usize] = collection.Column { title: "Moons", width: 80.0 }
    columns[2usize] = collection.Column { title: "Kind", width: 100.0 }
    let source = collection.TableSource { ctx: theme_ctx, count: table_count, key: table_key, cell: table_cell }
    let (table, table_error) = collection.table(a, 120u64, t, "Planets", columns[0usize..COLUMNS], source, selected[0usize..1usize], m.sort_column, m.descending, widget.Change[usize] { ctx: ctx, invoke: on_sort }, widget.Change[collection.Reorder] { ctx: ctx, invoke: no_change_reorder }, widget.Change[collection.ColumnResize] { ctx: ctx, invoke: no_change_resize }, widget.Change[widget.Key] { ctx: ctx, invoke: on_row }, 28.0, 0.0, change_f32(m, no_change_f32), 160.0)
    add(&p, table, table_error)
    caption(&p, 6u64, "Header row, table rows and list rows, assembled by hand")
    let (built, built_error) = mem.alloc[widget.Node](a, 4usize)
    if built_error != ok { ret (zero, built_error) }
    let (header, header_error) = collection.header_row(a, 9000u64, t, columns[0usize..COLUMNS], m.sort_column, m.descending, widget.Change[usize] { ctx: ctx, invoke: on_sort }, widget.Change[collection.Reorder] { ctx: ctx, invoke: no_change_reorder }, widget.Change[collection.ColumnResize] { ctx: ctx, invoke: no_change_resize })
    if header_error != ok { ret (zero, header_error) }
    built[0usize] = header
    var r = 0usize
    while r < 3usize {
        let (row_cells, row_cells_error) = mem.alloc[widget.Node](a, COLUMNS)
        if row_cells_error != ok { ret (zero, row_cells_error) }
        var c = 0usize
        while c < COLUMNS {
            let cell_error = table_cell(theme_ctx, a, r, c, &row_cells[c])
            if cell_error != ok { ret (zero, cell_error) }
            c += 1usize
        }
        let table_key_of_row = 9100u64 + u64(r)
        let (made, made_error) = collection.table_row(a, t, columns[0usize..COLUMNS], row_cells[0usize..COLUMNS], table_key_of_row, r, 3usize, 28.0, m.row == table_key_of_row, widget.Change[widget.Key] { ctx: ctx, invoke: on_row }, 13u8)
        if made_error != ok { ret (zero, made_error) }
        built[r + 1usize] = made
        r += 1usize
    }
    add(&p, widget.flex(9099u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), built[0usize..4usize]), ok)
    let (listed, listed_error) = mem.alloc[widget.Node](a, 3usize)
    if listed_error != ok { ret (zero, listed_error) }
    r = 0usize
    while r < 3usize {
        let (item, item_error) = control.text(a, 0u64, planet(r + 4usize), t, control.text_options())
        if item_error != ok { ret (zero, item_error) }
        let (made, made_error) = collection.row(a, t, item, 9200u64 + u64(r), r, 3usize, 32.0, 240.0, r < 2usize, r == 1usize)
        if made_error != ok { ret (zero, made_error) }
        listed[r] = made
        r += 1usize
    }
    add(&p, widget.flex(9199u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), listed[0usize..3usize]), ok)
    caption(&p, 4u64, "Tree and pagination")
    let tree_source = collection.TreeSource { ctx: theme_ctx, count: tree_count, key: tree_key, has_children: tree_has_children, build: tree_build }
    let (node_selected, node_error) = mem.alloc[widget.Key](a, 1usize)
    if node_error != ok { ret (zero, node_error) }
    node_selected[0usize] = m.node
    let (tree, tree_error) = collection.tree(a, 130u64, t, "Outline", tree_source, m.open_nodes[0usize..m.open_count], node_selected[0usize..1usize], widget.Change[widget.Key] { ctx: ctx, invoke: on_node_toggle }, widget.Change[widget.Key] { ctx: ctx, invoke: on_node }, 26.0, 240.0)
    add(&p, tree, tree_error)
    let (pages, pages_error) = collection.pagination(a, 140u64, t, "Pages", 9usize, m.page_index, 5usize, widget.Change[usize] { ctx: ctx, invoke: on_page })
    add(&p, pages, pages_error)
    let (dots, dots_error) = collection.page_indicator(a, 150u64, t, 9usize, m.page_index, widget.Change[usize] { ctx: ctx, invoke: on_page })
    add(&p, dots, dots_error)
    let (finished, finished_error) = finish(&p, 5u64)
    ret (finished, finished_error)
}

fn overlays_page(a: *mem.Arena, t: *const control.Theme, m: *Model) -> (widget.Node, err) {
    let (pg, pg_error) = page(a, t)
    if pg_error != ok { ret (zero, pg_error) }
    var p = pg
    let ctx = mem.cast[*void](m)
    caption(&p, 1u64, "Navigation")
    let (actions, actions_error) = mem.alloc[navigation.Action](a, 3usize)
    if actions_error != ok { ret (zero, actions_error) }
    actions[0usize] = navigation.Action { label: "New", action: widget.Submit { ctx: ctx, invoke: on_press }, icon: m.texture, enabled: true }
    actions[1usize] = navigation.Action { label: "Open", action: widget.Submit { ctx: ctx, invoke: on_press }, icon: m.texture, enabled: true }
    actions[2usize] = navigation.Action { label: "Share", action: widget.Submit { ctx: ctx, invoke: on_press }, icon: m.texture, enabled: false }
    let (bar, bar_error) = navigation.app_bar(a, 100u64, t, "Gallery", actions[0usize..1usize], actions[1usize..3usize], 600.0)
    add(&p, bar, bar_error)
    let (toolbar, toolbar_error) = navigation.toolbar(a, 110u64, t, "Tools", actions[0usize..3usize])
    add(&p, toolbar, toolbar_error)
    let (worded, worded_error) = mem.alloc[navigation.Action](a, 2usize)
    if worded_error != ok { ret (zero, worded_error) }
    worded[0usize] = navigation.Action { label: "Discard", action: widget.Submit { ctx: ctx, invoke: on_press }, icon: zero, enabled: true }
    worded[1usize] = navigation.Action { label: "Save", action: widget.Submit { ctx: ctx, invoke: on_press }, icon: zero, enabled: true }
    let (action_row, action_row_error) = navigation.action_row(a, 115u64, t, worded[0usize..2usize], .Outlined)
    add(&p, action_row, action_row_error)
    let crumbs: [3]str = [3]str{ "Home", "Examples", "Controls" }
    let (crumb_picks, crumbs_error) = picks(a, m, 32usize, 3usize, none)
    if crumbs_error != ok { ret (zero, crumbs_error) }
    let (breadcrumbs, breadcrumbs_error) = navigation.breadcrumbs(a, 120u64, t, "Path", crumbs[..], crumb_picks)
    add(&p, breadcrumbs, breadcrumbs_error)
    let sections: [3]str = [3]str{ "Ready", "UTF-8", "Ln 12, Col 4" }
    let (status, status_error) = navigation.status_bar(a, 130u64, t, sections[..], 600.0)
    add(&p, status, status_error)
    caption(&p, 2u64, "Menu button, popover and dialog")
    let (menu_items, menu_error) = mem.alloc[overlay.MenuItem](a, 3usize)
    if menu_error != ok { ret (zero, menu_error) }
    let (item_picks, item_error) = picks(a, m, 36usize, 3usize, on_choice)
    if item_error != ok { ret (zero, item_error) }
    menu_items[0usize] = overlay.MenuItem { label: "Cut", action: item_picks[0usize], enabled: true }
    menu_items[1usize] = overlay.MenuItem { label: "Copy", action: item_picks[1usize], enabled: true }
    menu_items[2usize] = overlay.MenuItem { label: "Paste", action: item_picks[2usize], enabled: false }
    let (openers, openers_error) = mem.alloc[widget.Node](a, 3usize)
    if openers_error != ok { ret (zero, openers_error) }
    let menu_toggle = submit(a, m, on_menu)
    let (menu, menu_button_error) = overlay.menu_button(a, 140u64, t, "Edit", menu_items[0usize..3usize], m.menu_open, menu_toggle)
    if menu_button_error != ok { ret (zero, menu_button_error) }
    openers[0usize] = menu
    let popover_toggle = submit(a, m, on_popover)
    let (anchor, anchor_error) = control.button(a, 150u64, t, "Popover", popover_toggle, control.button_options())
    if anchor_error != ok { ret (zero, anchor_error) }
    openers[1usize] = anchor
    let dialog_toggle = submit(a, m, on_dialog)
    let (opener, opener_error) = control.button(a, 160u64, t, "Dialog", dialog_toggle, control.button_options())
    if opener_error != ok { ret (zero, opener_error) }
    openers[2usize] = opener
    row_of(&p, 3u64, openers[0usize..3usize])
    label(&p, 4u64, counted(a, "Last menu choice: ", m.choice))
    let (hint, hint_error) = control.text(a, 0u64, "A popover explains its anchor", t, control.text_options())
    if hint_error != ok { ret (zero, hint_error) }
    let (popover, popover_error) = overlay.popover(a, 170u64, t, 150u64, .Below, "About", hint, m.popover_open, popover_toggle)
    add(&p, popover, popover_error)
    let (tip, tip_error) = overlay.tooltip(a, 180u64, t, 160u64, "Opens a modal dialog", widget.interaction(t.runtime, 160u64).hovered)
    add(&p, tip, tip_error)
    let (buttons, buttons_error) = mem.alloc[overlay.DialogButton](a, 2usize)
    if buttons_error != ok { ret (zero, buttons_error) }
    buttons[0usize] = overlay.DialogButton { label: "Cancel", action: widget.Submit { ctx: ctx, invoke: on_dialog }, kind: .Cancel }
    buttons[1usize] = overlay.DialogButton { label: "Delete", action: widget.Submit { ctx: ctx, invoke: on_dialog }, kind: .Destructive }
    let (alert, alert_error) = overlay.alert_dialog(a, 190u64, t, "Delete the project?", "This cannot be undone.", buttons[0usize..2usize], m.dialog_open)
    add(&p, alert, alert_error)
    caption(&p, 5u64, "Pickers")
    let date_toggle = submit(a, m, on_date_open)
    let (dated, dated_error) = overlay.date_picker(a, 200u64, t, "Date", m.date, true, m.date_open, date_toggle, m.shown, widget.Change[time.Date] { ctx: ctx, invoke: on_show }, widget.Change[time.Date] { ctx: ctx, invoke: on_date })
    add(&p, dated, dated_error)
    let (timed, timed_error) = overlay.time_picker(a, 220u64, t, "Time", m.clock, false, widget.Change[time.Time] { ctx: ctx, invoke: on_clock })
    add(&p, timed, timed_error)
    let (coloured, coloured_error) = overlay.color_picker(a, 240u64, t, "Colour", m.colour_value, true, widget.Change[paint.Color] { ctx: ctx, invoke: on_colour_value }, 320.0)
    add(&p, coloured, coloured_error)
    let (node, node_error) = finish(&p, 6u64)
    ret (node, node_error)
}

// ---------------------------------------------------------------- generic slots

fn on_flag(ctx: *void) -> err {
    let p = mem.cast[*Pick](ctx)
    p.model.flags[p.slot] = !p.model.flags[p.slot]
    ret ok
}

// A pick's index into values[slot], closing the flag it names.
fn on_choose(ctx: *void) -> err {
    let p = mem.cast[*Pick](ctx)
    p.model.values[p.slot] = p.index
    if p.close < FLAGS { p.model.flags[p.close] = false }
    ret ok
}

fn on_value(ctx: *void, value: usize) -> err {
    let p = mem.cast[*Pick](ctx)
    p.model.values[p.slot] = value
    if p.close < FLAGS { p.model.flags[p.close] = false }
    ret ok
}

fn on_real(ctx: *void, value: f32) -> err {
    let p = mem.cast[*Pick](ctx)
    p.model.reals[p.slot] = value
    ret ok
}

// A typed text: its length into values[slot], opening the flag it names.
fn on_typed(ctx: *void, value: str) -> err {
    let p = mem.cast[*Pick](ctx)
    p.model.values[p.slot] = value.len
    if p.close < FLAGS { p.model.flags[p.close] = true }
    ret ok
}

// The next free pick of this frame; the slots past PICK_BASE are reclaimed per build.
fn claim(m: *Model, index: usize, slot: usize, close: usize) -> *void {
    if m.pick_next >= m.picks.len { m.pick_next = PICK_BASE }
    m.picks[m.pick_next] = Pick { model: m, index: index, slot: slot, close: close }
    let at = mem.cast[*void](&m.picks[m.pick_next])
    m.pick_next += 1usize
    ret at
}

fn toggler(a: *mem.Arena, m: *Model, slot: usize) -> *widget.Submit {
    var none_at_all: *widget.Submit = zero
    let (one, one_error) = mem.alloc[widget.Submit](a, 1usize)
    if one_error != ok { ret none_at_all }
    one[0usize] = widget.Submit { ctx: claim(m, 0usize, slot, NO_FLAG), invoke: on_flag }
    ret &one[0usize]
}

fn choices(a: *mem.Arena, m: *Model, n: usize, slot: usize, close: usize) -> ([]widget.Submit, err) {
    let (out, out_error) = mem.alloc[widget.Submit](a, n)
    if out_error != ok { ret (out, out_error) }
    var i = 0usize
    while i < n {
        out[i] = widget.Submit { ctx: claim(m, i, slot, close), invoke: on_choose }
        i += 1usize
    }
    ret (out, ok)
}

fn flag_toggles(a: *mem.Arena, m: *Model, first: usize, n: usize) -> ([]widget.Submit, err) {
    let (out, out_error) = mem.alloc[widget.Submit](a, n)
    if out_error != ok { ret (out, out_error) }
    var i = 0usize
    while i < n {
        out[i] = widget.Submit { ctx: claim(m, 0usize, first + i, NO_FLAG), invoke: on_flag }
        i += 1usize
    }
    ret (out, ok)
}

fn value_of(m: *Model, slot: usize, close: usize) -> widget.Change[usize] {
    ret widget.Change[usize] { ctx: claim(m, 0usize, slot, close), invoke: on_value }
}

fn real_of(m: *Model, slot: usize) -> widget.Change[f32] {
    ret widget.Change[f32] { ctx: claim(m, 0usize, slot, NO_FLAG), invoke: on_real }
}

fn typed_of(m: *Model, slot: usize, opens: usize) -> widget.Change[str] {
    ret widget.Change[str] { ctx: claim(m, 0usize, slot, opens), invoke: on_typed }
}

fn toggle_key(s: *KeySet, value: widget.Key) {
    var i = 0usize
    while i < s.count {
        if s.keys[i] == value {
            s.keys[i] = s.keys[s.count - 1usize]
            s.count -= 1usize
            ret
        }
        i += 1usize
    }
    if s.count < 8usize {
        s.keys[s.count] = value
        s.count += 1usize
    }
}

fn copy_into(dst: []u8, s: str) -> usize {
    var i = 0usize
    while i < s.len && i < dst.len {
        dst[i] = s[i]
        i += 1usize
    }
    ret i
}

// ---------------------------------------------------------------- specific changes

fn on_chord(ctx: *void, value: control.Chord) -> err {
    let m = mem.cast[*Model](ctx)
    m.chord = value
    m.flags[F_RECORD] = false
    ret ok
}

fn on_font_size(ctx: *void, value: i64) -> err {
    let m = mem.cast[*Model](ctx)
    m.font_size = value
    ret ok
}

fn on_auto_pick(ctx: *void) -> err {
    let p = mem.cast[*Pick](ctx)
    let m = p.model
    m.values[V_AUTO] = copy_into(m.auto[..], planet(p.index))
    m.flags[F_AUTO] = false
    ret ok
}

fn on_token_add(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    let n = m.values[V_TOKEN_TEXT]
    if n == 0usize || m.token_count >= 6usize || m.token_used + n > m.token_pool.len { ret ok }
    let start = m.token_used
    m.token_used += copy_into(m.token_pool[start..m.token_pool.len], m.token_text[0usize..n])
    m.tokens_shown[m.token_count] = m.token_pool[start..m.token_used]
    m.token_count += 1usize
    m.values[V_TOKEN_TEXT] = 0usize
    m.flags[F_TOKENS] = false
    ret ok
}

fn on_token_pick(ctx: *void) -> err {
    let p = mem.cast[*Pick](ctx)
    let m = p.model
    m.values[V_TOKEN_TEXT] = copy_into(m.token_text[..], planet(p.index))
    ret on_token_add(mem.cast[*void](m))
}

fn on_token_remove(ctx: *void) -> err {
    let p = mem.cast[*Pick](ctx)
    let m = p.model
    if p.index >= m.token_count { ret ok }
    var i = p.index
    while i + 1usize < m.token_count {
        m.tokens_shown[i] = m.tokens_shown[i + 1usize]
        i += 1usize
    }
    m.token_count -= 1usize
    ret ok
}

fn on_reorder(ctx: *void, value: collection.Reorder) -> err {
    let m = mem.cast[*Model](ctx)
    if value.from >= 5usize || value.to >= 5usize { ret ok }
    let moved = m.order[value.from]
    var i = value.from
    while i < value.to {
        m.order[i] = m.order[i + 1usize]
        i += 1usize
    }
    while i > value.to {
        m.order[i] = m.order[i - 1usize]
        i -= 1usize
    }
    m.order[value.to] = moved
    ret ok
}

fn on_refresh(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    m.flags[F_REFRESH] = !m.flags[F_REFRESH]
    ret ok
}

fn on_reveal(ctx: *void, value: bool) -> err {
    let m = mem.cast[*Model](ctx)
    m.flags[F_REVEAL] = value
    ret ok
}

fn on_collapse(ctx: *void, value: widget.Key) -> err {
    let m = mem.cast[*Model](ctx)
    toggle_key(&m.collapsed, value)
    ret ok
}

fn on_pair_edit(ctx: *void, value: collection.PairEdit) -> err {
    let m = mem.cast[*Model](ctx)
    if value.index >= m.pair_count { ret ok }
    if value.value { m.pairs[value.index].value_len = value.text.len } else { m.pairs[value.index].name_len = value.text.len }
    ret ok
}

fn on_pair_remove(ctx: *void, value: usize) -> err {
    let m = mem.cast[*Model](ctx)
    if value >= m.pair_count { ret ok }
    // Swapped down, so every pair keeps a buffer of its own.
    var i = value
    while i + 1usize < m.pair_count {
        let held = m.pairs[i]
        m.pairs[i] = m.pairs[i + 1usize]
        m.pairs[i + 1usize] = held
        i += 1usize
    }
    m.pair_count -= 1usize
    ret ok
}

fn on_pair_add(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    if m.pair_count >= 4usize { ret ok }
    m.pairs[m.pair_count].name_len = 0usize
    m.pairs[m.pair_count].value_len = 0usize
    m.pair_count += 1usize
    ret ok
}

fn on_pop(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    if m.values[V_DEPTH] > 0usize { m.values[V_DEPTH] -= 1usize }
    ret ok
}

fn on_push(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    if m.values[V_DEPTH] < 2usize { m.values[V_DEPTH] += 1usize }
    ret ok
}

fn on_back(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    if m.values[V_STEP] > 0usize { m.values[V_STEP] -= 1usize }
    ret ok
}

fn on_next(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    if m.values[V_STEP] < 2usize { m.values[V_STEP] += 1usize }
    ret ok
}

fn on_restart(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    m.values[V_STEP] = 0usize
    ret ok
}

// The menu bar: a title's toggle opens its menu, or closes it when it is open.
fn on_bar_menu(ctx: *void) -> err {
    let p = mem.cast[*Pick](ctx)
    if p.model.values[V_BAR_MENU] == p.index { p.model.values[V_BAR_MENU] = 99usize } else { p.model.values[V_BAR_MENU] = p.index }
    ret ok
}

fn on_bar_command(ctx: *void) -> err {
    let p = mem.cast[*Pick](ctx)
    p.model.values[V_COMMAND] = p.index
    p.model.values[V_BAR_MENU] = 99usize
    p.model.flags[F_CONTEXT] = false
    p.model.flags[F_MENU] = false
    p.model.flags[F_ACTIONS] = false
    p.model.flags[F_MODAL] = false
    ret ok
}

// The shown documents are the open ones; a close names one of those.
fn open_document(m: *Model, shown: usize) -> usize {
    var seen = 0usize
    var i = 0usize
    while i < 4usize {
        if !m.closed[i] {
            if seen == shown { ret i }
            seen += 1usize
        }
        i += 1usize
    }
    ret 4usize
}

fn on_document_close(ctx: *void, value: usize) -> err {
    let m = mem.cast[*Model](ctx)
    let at = open_document(m, value)
    if at < 4usize { m.closed[at] = true }
    // The last one closed brings them all back, so the demo never runs dry.
    if open_document(m, 0usize) == 4usize {
        var i = 0usize
        while i < 4usize {
            m.closed[i] = false
            i += 1usize
        }
    }
    m.values[V_DOCUMENT] = 0usize
    ret ok
}

fn no_change_move(ctx: *void, value: navigation.DocumentMove) -> err {
    ret ok
}

fn on_dock(ctx: *void, value: navigation.DockSizes) -> err {
    let m = mem.cast[*Model](ctx)
    m.dock = value
    ret ok
}

fn on_range_pick(ctx: *void, value: time.Date) -> err {
    let m = mem.cast[*Model](ctx)
    if !m.flags[F_RANGE_END] {
        m.range_from = value
        m.range_to = value
        m.flags[F_RANGE_END] = true
        ret ok
    }
    m.range_to = value
    m.flags[F_RANGE_END] = false
    m.flags[F_RANGE] = false
    ret ok
}

fn on_span(ctx: *void, value: time.Duration) -> err {
    let m = mem.cast[*Model](ctx)
    m.span = value
    ret ok
}

fn on_calendar(ctx: *void, value: time.Date) -> err {
    let m = mem.cast[*Model](ctx)
    m.date = value
    ret ok
}

// ---------------------------------------------------------------- more sources

fn row_count(ctx: *void) -> usize {
    ret 200usize
}

fn row_key(ctx: *void, index: usize) -> widget.Key {
    ret 1u64 + u64(index)
}

fn row_build(ctx: *void, a: *mem.Arena, index: usize, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    let (node, node_error) = control.text(a, 0u64, counted(a, "Row ", index + 1usize), t, control.text_options())
    if node_error != ok { ret node_error }
    *out = node
    ret ok
}

fn tile_build(ctx: *void, a: *mem.Arena, index: usize, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    let (node, node_error) = control.badge(a, 0u64, t, counted(a, "", index + 1usize))
    if node_error != ok { ret node_error }
    *out = node
    ret ok
}

fn tree_cell(ctx: *void, a: *mem.Arena, node: widget.Key, column: usize, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    var value = counted(a, "", usize(node) * 3usize)
    if column == 0usize { value = counted(a, "Item ", usize(node)) }
    if column == 2usize {
        value = "file"
        if node % 10u64 == 0u64 { value = "folder" }
    }
    let (text_node, node_error) = control.text(a, 0u64, value, t, control.text_options())
    if node_error != ok { ret node_error }
    *out = text_node
    ret ok
}

fn property_count(ctx: *void) -> usize {
    ret 4usize
}

fn property_at(ctx: *void, index: usize) -> collection.Property {
    if index == 0usize { ret collection.Property { key: 101u64, name: "Name", group: "Document" } }
    if index == 1usize { ret collection.Property { key: 102u64, name: "Copies", group: "Document" } }
    if index == 2usize { ret collection.Property { key: 103u64, name: "Dark", group: "Look" } }
    ret collection.Property { key: 104u64, name: "Alerts", group: "Look" }
}

fn property_editor(ctx: *void, a: *mem.Arena, index: usize, out: *widget.Node) -> err {
    let m = mem.cast[*Model](ctx)
    let t = m.theme
    if index == 0usize {
        let (field, field_error) = control.text_field(a, 3200u64, t, "", m.property_text[..], m.values[V_PROPERTY], typed_of(m, V_PROPERTY, NO_FLAG), zero, control.field_options())
        if field_error != ok { ret field_error }
        *out = field
        ret ok
    }
    if index == 1usize {
        let (stepped, stepped_error) = control.stepper(a, 3210u64, t, "Copies", m.count, 0i64, 20i64, 1i64, widget.Change[i64] { ctx: ctx, invoke: on_count })
        if stepped_error != ok { ret stepped_error }
        *out = stepped
        ret ok
    }
    if index == 2usize {
        let (box, box_error) = control.checkbox(a, 3220u64, t, "Dark palette", m.dark, false, submit(a, m, on_dark), true)
        if box_error != ok { ret box_error }
        *out = box
        ret ok
    }
    let (sw, sw_error) = control.switch_control(a, 3230u64, t, "Alerts", m.notify, submit(a, m, on_notify), true)
    if sw_error != ok { ret sw_error }
    *out = sw
    ret ok
}

// Five bars, the volume slider's value their scale.
fn canvas_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 160.0, height: 64.0 }
}

fn canvas_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let m = mem.cast[*Model](ctx)
    let bar = area.width / 9.0
    var i = 0usize
    while i < 5usize {
        let share = (f32(i + 1usize) / 5.0) * (0.2 + m.volume / 125.0)
        let h = area.height * share
        let rect = geometry.Rect { x: area.x + bar * (2.0 * f32(i)), y: area.y + area.height - h, width: bar, height: h }
        try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: rect, brush: paint.Brush { Solid: style.color(&m.tokens, .Primary) } } })
        i += 1usize
    }
    ret ok
}

fn digits_only(ctx: *void, value: str) -> bool {
    var i = 0usize
    while i < value.len {
        if value[i] < 48u8 || value[i] > 57u8 { ret false }
        i += 1usize
    }
    ret true
}

// A card number's shape: the digits in groups of four.
fn grouped(ctx: *void, out: []u8, value: str) -> usize {
    var n = 0usize
    var i = 0usize
    while i < value.len && n < out.len {
        if i > 0usize && i % 4usize == 0usize && n < out.len {
            out[n] = 32u8
            n += 1usize
        }
        if n < out.len {
            out[n] = value[i]
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

fn text_of(a: *mem.Arena, t: *const control.Theme, value: str) -> (widget.Node, err) {
    let (node, node_error) = control.text(a, 0u64, value, t, control.text_options())
    ret (node, node_error)
}

// ---------------------------------------------------------------- content

fn content_page(a: *mem.Arena, t: *const control.Theme, m: *Model) -> (widget.Node, err) {
    let (pg, pg_error) = page(a, t)
    if pg_error != ok { ret (zero, pg_error) }
    var p = pg
    let press = submit(a, m, on_press)
    caption(&p, 1u64, "Selectable and rich text")
    let (selectable, selectable_error) = control.selectable_text(a, 100u64, m.selectable[..], m.values[V_SELECTABLE], t, control.text_options())
    add(&p, selectable, selectable_error)
    let (spans, spans_error) = mem.alloc[control.Span](a, 3usize)
    if spans_error != ok { ret (zero, spans_error) }
    spans[0usize] = control.Span { value: "Rich text mixes ", role: .Body, color: .Text, link: zero }
    spans[1usize] = control.Span { value: "roles and colours", role: .Title, color: .Primary, link: zero }
    spans[2usize] = control.Span { value: " with a link", role: .Body, color: .Primary, link: widget.Submit { ctx: mem.cast[*void](m), invoke: on_press } }
    let (rich, rich_error) = control.rich_text(a, 110u64, spans[0usize..3usize], t)
    add(&p, rich, rich_error)
    caption(&p, 2u64, "Icon, image, canvas, surface and floating action buttons")
    let (media, media_error) = mem.alloc[widget.Node](a, 6usize)
    if media_error != ok { ret (zero, media_error) }
    let (glyph, glyph_error) = control.icon(a, 120u64, m.texture, 24.0, "Picture")
    if glyph_error != ok { ret (zero, glyph_error) }
    media[0usize] = glyph
    let (picture, picture_error) = control.image(a, 121u64, m.texture, 64.0, 48.0, .Fill, "A picture")
    if picture_error != ok { ret (zero, picture_error) }
    media[1usize] = picture
    let (plot, plot_error) = control.canvas(a, 122u64, widget.Custom { ctx: mem.cast[*void](m), measure: canvas_measure, paint: canvas_paint, state: zero }, "Bars that follow the volume")
    if plot_error != ok { ret (zero, plot_error) }
    media[2usize] = plot
    let (inside, inside_error) = text_of(a, t, "A plain surface")
    if inside_error != ok { ret (zero, inside_error) }
    let (plain, plain_error) = control.surface(a, 123u64, t, control.surface_options(t), slice_of(a, inside))
    if plain_error != ok { ret (zero, plain_error) }
    media[3usize] = plain
    let (fab, fab_error) = control.fab(a, 124u64, t, m.texture, "Add", press, .Default)
    if fab_error != ok { ret (zero, fab_error) }
    media[4usize] = fab
    let (wide, wide_error) = control.fab(a, 125u64, t, m.texture, "Compose", press, .Extended)
    if wide_error != ok { ret (zero, wide_error) }
    media[5usize] = wide
    row_of(&p, 3u64, media[0usize..6usize])
    caption(&p, 4u64, "Single radios and a tab strip")
    let sizes: [3]str = [3]str{ "Small", "Medium", "Large" }
    let (size_picks, size_error) = choices(a, m, 3usize, V_RADIO, NO_FLAG)
    if size_error != ok { ret (zero, size_error) }
    let (radios, radios_error) = mem.alloc[widget.Node](a, 3usize)
    if radios_error != ok { ret (zero, radios_error) }
    var i = 0usize
    while i < 3usize {
        let (one, one_error) = control.radio(a, 130u64 + u64(i), t, sizes[i], m.values[V_RADIO] == i, &size_picks[i], true)
        if one_error != ok { ret (zero, one_error) }
        radios[i] = one
        i += 1usize
    }
    row_of(&p, 5u64, radios[0usize..3usize])
    let strip: [3]str = [3]str{ "Overview", "Details", "History" }
    let (strip_picks, strip_error) = choices(a, m, 3usize, V_INNER_TAB, NO_FLAG)
    if strip_error != ok { ret (zero, strip_error) }
    let (tabs, tabs_error) = control.tabs(a, 140u64, t, strip[..], m.values[V_INNER_TAB], strip_picks)
    add(&p, tabs, tabs_error)
    label(&p, 6u64, counted(a, "Tab strip selection: ", m.values[V_INNER_TAB]))
    caption(&p, 7u64, "Resizable pane")
    let (pane_text, pane_text_error) = text_of(a, t, "Drag my edge")
    if pane_text_error != ok { ret (zero, pane_text_error) }
    let (pane, pane_error) = control.resizable_pane(a, 150u64, t, "Pane", .Horizontal, m.reals[R_PANE], 120.0, 480.0, real_of(m, R_PANE), pane_text)
    add(&p, pane, pane_error)
    caption(&p, 8u64, "Form")
    let (fields, fields_error) = mem.alloc[widget.Node](a, 2usize)
    if fields_error != ok { ret (zero, fields_error) }
    let (who, who_error) = control.text_field(a, 161u64, t, "User", m.name[..], m.name_len, widget.Change[str] { ctx: mem.cast[*void](m), invoke: on_name }, zero, control.field_options())
    if who_error != ok { ret (zero, who_error) }
    fields[0usize] = who
    let (secret, secret_error) = control.password_field(a, 170u64, t, "Password", m.secret[..], m.secret_len, widget.Change[str] { ctx: mem.cast[*void](m), invoke: on_secret }, zero, control.field_options())
    if secret_error != ok { ret (zero, secret_error) }
    fields[1usize] = secret
    let (signed, form_error) = control.form(a, 160u64, t, "Sign in", 360.0, fields[0usize..2usize], widget.Submit { ctx: mem.cast[*void](m), invoke: on_press }, widget.Submit { ctx: mem.cast[*void](m), invoke: none })
    add(&p, signed, form_error)
    let (node, node_error) = finish(&p, 9u64)
    ret (node, node_error)
}

// ---------------------------------------------------------------- input

fn input_page(a: *mem.Arena, t: *const control.Theme, m: *Model) -> (widget.Node, err) {
    let (pg, pg_error) = page(a, t)
    if pg_error != ok { ret (zero, pg_error) }
    var p = pg
    let ctx = mem.cast[*void](m)
    caption(&p, 1u64, "Shortcut recorder and formatted field")
    let (recorder, recorder_error) = control.shortcut_recorder(a, 100u64, t, "Shortcut", m.chord, m.flags[F_RECORD], toggler(a, m, F_RECORD), widget.Change[control.Chord] { ctx: ctx, invoke: on_chord })
    add(&p, recorder, recorder_error)
    let adapter = control.Format { ctx: ctx, accept: digits_only, format: grouped }
    let (card, card_error) = control.formatted_field(a, 110u64, t, "Card number", m.code[..], m.values[V_CODE], adapter, typed_of(m, V_CODE, NO_FLAG), typed_of(m, V_CODE, NO_FLAG), control.field_options())
    add(&p, card, card_error)
    caption(&p, 2u64, "Autocomplete and tokens")
    let names: [6]str = [6]str{ "Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn" }
    let (auto_picks, auto_error) = mem.alloc[widget.Submit](a, 6usize)
    if auto_error != ok { ret (zero, auto_error) }
    let (token_picks, token_error) = mem.alloc[widget.Submit](a, 6usize)
    if token_error != ok { ret (zero, token_error) }
    var i = 0usize
    while i < 6usize {
        auto_picks[i] = widget.Submit { ctx: claim(m, i, 0usize, NO_FLAG), invoke: on_auto_pick }
        token_picks[i] = widget.Submit { ctx: claim(m, i, 0usize, NO_FLAG), invoke: on_token_pick }
        i += 1usize
    }
    let (completion, auto_field_error) = control.autocomplete(a, 120u64, t, "Planet", m.auto[..], m.values[V_AUTO], typed_of(m, V_AUTO, F_AUTO), names[..], m.values[V_AUTO_ACTIVE], m.flags[F_AUTO], auto_picks, value_of(m, V_AUTO_ACTIVE, NO_FLAG), toggler(a, m, F_AUTO), control.field_options())
    add(&p, completion, auto_field_error)
    let (removes, removes_error) = mem.alloc[widget.Submit](a, 6usize)
    if removes_error != ok { ret (zero, removes_error) }
    i = 0usize
    while i < 6usize {
        removes[i] = widget.Submit { ctx: claim(m, i, 0usize, NO_FLAG), invoke: on_token_remove }
        i += 1usize
    }
    let (tokens, tokens_error) = control.token_field(a, 200u64, t, "Destinations", m.tokens_shown[0usize..m.token_count], removes[0usize..m.token_count], m.token_text[..], m.values[V_TOKEN_TEXT], typed_of(m, V_TOKEN_TEXT, F_TOKENS), widget.Submit { ctx: ctx, invoke: on_token_add }, names[..], m.values[V_TOKEN_ACTIVE], m.flags[F_TOKENS], token_picks, value_of(m, V_TOKEN_ACTIVE, NO_FLAG), toggler(a, m, F_TOKENS), 420.0)
    add(&p, tokens, tokens_error)
    caption(&p, 3u64, "Picker and multi-select list")
    let sizes: [4]str = [4]str{ "A4", "A5", "Letter", "Legal" }
    let (size_picks, size_error) = choices(a, m, 4usize, V_PICKED, F_PICKER)
    if size_error != ok { ret (zero, size_error) }
    let (picked, picker_error) = control.picker(a, 300u64, t, "Paper", sizes[..], m.values[V_PICKED], m.flags[F_PICKER], toggler(a, m, F_PICKER), size_picks, .Popup)
    add(&p, picked, picker_error)
    let toppings: [5]str = [5]str{ "Cheese", "Olives", "Basil", "Peppers", "Onion" }
    let (multi_toggles, multi_error) = flag_toggles(a, m, F_MULTI, 5usize)
    if multi_error != ok { ret (zero, multi_error) }
    let (multi, multi_list_error) = control.multi_select_list(a, 400u64, t, "Toppings", toppings[..], m.flags[F_MULTI..F_MULTI + 5usize], multi_toggles, 4u32, 240.0)
    add(&p, multi, multi_list_error)
    caption(&p, 4u64, "Font picker")
    let families: [4]str = [4]str{ "Segoe UI", "Consolas", "Georgia", "Arial" }
    let faces: [3]str = [3]str{ "Regular", "Bold", "Italic" }
    let (font, font_error) = control.font_picker(a, 500u64, t, "Font", families[..], m.values[V_FAMILY], faces[..], m.values[V_FACE], m.font_size, "The quick brown fox", value_of(m, V_FAMILY, NO_FLAG), value_of(m, V_FACE, NO_FLAG), widget.Change[i64] { ctx: ctx, invoke: on_font_size }, 4u32, 480.0)
    add(&p, font, font_error)
    let (node, node_error) = finish(&p, 5u64)
    ret (node, node_error)
}

// ---------------------------------------------------------------- data

fn data_page(a: *mem.Arena, t: *const control.Theme, m: *Model) -> (widget.Node, err) {
    let (pg, pg_error) = page(a, t)
    if pg_error != ok { ret (zero, pg_error) }
    var p = pg
    let ctx = mem.cast[*void](m)
    let theme_ctx = mem.cast[*void](t)
    let (selected, selected_error) = mem.alloc[widget.Key](a, 1usize)
    if selected_error != ok { ret (zero, selected_error) }
    selected[0usize] = m.row
    caption(&p, 1u64, "Virtual list and virtual grid (200 items each)")
    let rows = collection.Source { ctx: theme_ctx, count: row_count, key: row_key, build: row_build }
    let tiles = collection.Source { ctx: theme_ctx, count: row_count, key: row_key, build: tile_build }
    let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
    if pair_error != ok { ret (zero, pair_error) }
    let (vlist, vlist_error) = collection.virtual_list(a, 1000u64, t, "Rows", rows, selected[0usize..1usize], 28.0, m.reals[R_LIST], real_of(m, R_LIST), true, 220.0, 160.0)
    if vlist_error != ok { ret (zero, vlist_error) }
    pair[0usize] = vlist
    let (vgrid, vgrid_error) = collection.virtual_grid(a, 2000u64, t, "Tiles", tiles, selected[0usize..1usize], geometry.Size { width: 48.0, height: 40.0 }, 6.0, m.reals[R_GRID], real_of(m, R_GRID), 280.0, 160.0)
    if vgrid_error != ok { ret (zero, vgrid_error) }
    pair[1usize] = vgrid
    row_of(&p, 2u64, pair[0usize..2usize])
    caption(&p, 3u64, "Carousel and page view")
    let (slides, slides_error) = mem.alloc[widget.Node](a, 3usize)
    if slides_error != ok { ret (zero, slides_error) }
    let (sheets, sheets_error) = mem.alloc[widget.Node](a, 3usize)
    if sheets_error != ok { ret (zero, sheets_error) }
    var i = 0usize
    while i < 3usize {
        let (slide, slide_error) = text_of(a, t, counted(a, "Slide ", i + 1usize))
        if slide_error != ok { ret (zero, slide_error) }
        slides[i] = slide
        let (sheet, sheet_error) = text_of(a, t, counted(a, "Page ", i + 1usize))
        if sheet_error != ok { ret (zero, sheet_error) }
        sheets[i] = sheet
        i += 1usize
    }
    let (paged, paged_error) = mem.alloc[widget.Node](a, 2usize)
    if paged_error != ok { ret (zero, paged_error) }
    let (carousel, carousel_error) = collection.carousel(a, 3000u64, t, slides[0usize..3usize], m.values[V_CAROUSEL], value_of(m, V_CAROUSEL, NO_FLAG), 260.0, 120.0)
    if carousel_error != ok { ret (zero, carousel_error) }
    paged[0usize] = carousel
    let (view, view_error) = collection.page_view(a, 3100u64, t, sheets[0usize..3usize], m.values[V_VIEW], value_of(m, V_VIEW, NO_FLAG), 260.0, 120.0)
    if view_error != ok { ret (zero, view_error) }
    paged[1usize] = view
    row_of(&p, 4u64, paged[0usize..2usize])
    caption(&p, 5u64, "Reorderable list, pull to refresh, swipe actions")
    let (items, items_error) = mem.alloc[widget.Node](a, 5usize)
    if items_error != ok { ret (zero, items_error) }
    let (keys, keys_error) = mem.alloc[widget.Key](a, 5usize)
    if keys_error != ok { ret (zero, keys_error) }
    i = 0usize
    while i < 5usize {
        let (item, item_error) = text_of(a, t, planet(m.order[i]))
        if item_error != ok { ret (zero, item_error) }
        items[i] = item
        keys[i] = 10u64 + u64(m.order[i])
        i += 1usize
    }
    let (trio, trio_error) = mem.alloc[widget.Node](a, 3usize)
    if trio_error != ok { ret (zero, trio_error) }
    let (reorder, reorder_error) = collection.reorderable_list(a, 3200u64, t, "Order", items[0usize..5usize], keys[0usize..5usize], 30.0, widget.Change[collection.Reorder] { ctx: ctx, invoke: on_reorder }, 180.0)
    if reorder_error != ok { ret (zero, reorder_error) }
    trio[0usize] = reorder
    var feed = "Pull down, or press Refresh"
    if m.flags[F_REFRESH] { feed = "Refreshing: press Refresh again to finish" }
    let (feed_text, feed_error) = text_of(a, t, feed)
    if feed_error != ok { ret (zero, feed_error) }
    let (pull, pull_error) = collection.pull_to_refresh(a, 3300u64, t, feed_text, m.flags[F_REFRESH], submit(a, m, on_refresh), 220.0, 150.0)
    if pull_error != ok { ret (zero, pull_error) }
    trio[1usize] = pull
    let (swiped_text, swiped_error) = text_of(a, t, "Swipe me left")
    if swiped_error != ok { ret (zero, swiped_error) }
    let swipe_labels: [2]str = [2]str{ "Archive", "Delete" }
    let (swipe_actions, swipe_actions_error) = mem.alloc[widget.Submit](a, 2usize)
    if swipe_actions_error != ok { ret (zero, swipe_actions_error) }
    swipe_actions[0usize] = widget.Submit { ctx: ctx, invoke: on_press }
    swipe_actions[1usize] = widget.Submit { ctx: ctx, invoke: on_press }
    let (swipe, swipe_error) = collection.swipe_actions(a, 3400u64, t, swiped_text, swipe_labels[..], swipe_actions[0usize..2usize], m.flags[F_REVEAL], widget.Change[bool] { ctx: ctx, invoke: on_reveal }, 280.0, 48.0)
    if swipe_error != ok { ret (zero, swipe_error) }
    trio[2usize] = swipe
    row_of(&p, 6u64, trio[0usize..3usize])
    caption(&p, 7u64, "Data grid (virtual) and tree table")
    let (columns, columns_error) = mem.alloc[collection.Column](a, COLUMNS)
    if columns_error != ok { ret (zero, columns_error) }
    columns[0usize] = collection.Column { title: "Planet", width: 140.0 }
    columns[1usize] = collection.Column { title: "Moons", width: 80.0 }
    columns[2usize] = collection.Column { title: "Kind", width: 100.0 }
    let source = collection.TableSource { ctx: theme_ctx, count: table_count, key: table_key, cell: table_cell }
    let (grid, grid_error) = collection.data_grid(a, 4000u64, t, "Planets", columns[0usize..COLUMNS], source, selected[0usize..1usize], m.sort_column, m.descending, widget.Change[usize] { ctx: ctx, invoke: on_sort }, widget.Change[collection.Reorder] { ctx: ctx, invoke: no_change_reorder }, widget.Change[collection.ColumnResize] { ctx: ctx, invoke: no_change_resize }, widget.Change[widget.Key] { ctx: ctx, invoke: on_row }, 28.0, m.reals[R_DATA], real_of(m, R_DATA), 160.0)
    add(&p, grid, grid_error)
    let tree_source = collection.TreeSource { ctx: theme_ctx, count: tree_count, key: tree_key, has_children: tree_has_children, build: tree_build }
    let (node_selected, node_selected_error) = mem.alloc[widget.Key](a, 1usize)
    if node_selected_error != ok { ret (zero, node_selected_error) }
    node_selected[0usize] = m.node
    let (tree_columns, tree_columns_error) = mem.alloc[collection.Column](a, 3usize)
    if tree_columns_error != ok { ret (zero, tree_columns_error) }
    tree_columns[0usize] = collection.Column { title: "Name", width: 180.0 }
    tree_columns[1usize] = collection.Column { title: "Size", width: 80.0 }
    tree_columns[2usize] = collection.Column { title: "Kind", width: 100.0 }
    let cells = collection.CellSource { ctx: theme_ctx, cell: tree_cell }
    let (tree_table, tree_table_error) = collection.tree_table(a, 5000u64, t, "Files", tree_columns[0usize..3usize], tree_source, cells, m.open_nodes[0usize..m.open_count], node_selected[0usize..1usize], widget.Change[widget.Key] { ctx: ctx, invoke: on_node_toggle }, widget.Change[widget.Key] { ctx: ctx, invoke: on_node }, m.sort_column, m.descending, widget.Change[usize] { ctx: ctx, invoke: on_sort }, widget.Change[collection.Reorder] { ctx: ctx, invoke: no_change_reorder }, widget.Change[collection.ColumnResize] { ctx: ctx, invoke: no_change_resize }, 26.0)
    add(&p, tree_table, tree_table_error)
    caption(&p, 8u64, "Outline, property grid and key-value editor")
    let (outline, outline_error) = collection.outline(a, 6000u64, t, "Outline", tree_source, m.open_nodes[0usize..m.open_count], node_selected[0usize..1usize], widget.Change[widget.Key] { ctx: ctx, invoke: on_node_toggle }, widget.Change[widget.Key] { ctx: ctx, invoke: on_node }, 26.0, 280.0)
    add(&p, outline, outline_error)
    let properties = collection.PropertySource { ctx: ctx, count: property_count, property: property_at, editor: property_editor }
    let (grid_of_properties, properties_error) = collection.property_grid(a, 7000u64, t, "Properties", properties, m.collapsed.keys[0usize..m.collapsed.count], widget.Change[widget.Key] { ctx: ctx, invoke: on_collapse }, 120.0, 420.0)
    add(&p, grid_of_properties, properties_error)
    let (pairs, pairs_error) = collection.key_value_editor(a, 8000u64, t, "Headers", m.pairs[0usize..m.pair_count], widget.Change[collection.PairEdit] { ctx: ctx, invoke: on_pair_edit }, widget.Change[usize] { ctx: ctx, invoke: on_pair_remove }, submit(a, m, on_pair_add), 420.0)
    add(&p, pairs, pairs_error)
    let (node, node_error) = finish(&p, 9u64)
    ret (node, node_error)
}

// ---------------------------------------------------------------- navigation

fn navigation_page(a: *mem.Arena, t: *const control.Theme, m: *Model) -> (widget.Node, err) {
    let (pg, pg_error) = page(a, t)
    if pg_error != ok { ret (zero, pg_error) }
    var p = pg
    let ctx = mem.cast[*void](m)
    let places: [4]str = [4]str{ "Home", "Search", "Library", "Settings" }
    caption(&p, 1u64, "Menu bar and context menu")
    let (commands, commands_error) = mem.alloc[overlay.MenuItem](a, 9usize)
    if commands_error != ok { ret (zero, commands_error) }
    let command_names: [9]str = [9]str{ "New", "Open", "Exit", "Undo", "Redo", "Cut", "Zoom in", "Zoom out", "Full screen" }
    var i = 0usize
    while i < 9usize {
        commands[i] = overlay.MenuItem { label: command_names[i], action: widget.Submit { ctx: claim(m, i, 0usize, NO_FLAG), invoke: on_bar_command }, enabled: true }
        i += 1usize
    }
    let (menus, menus_error) = mem.alloc[navigation.MenuBarItem](a, 3usize)
    if menus_error != ok { ret (zero, menus_error) }
    menus[0usize] = navigation.MenuBarItem { label: "File", items: commands[0usize..3usize] }
    menus[1usize] = navigation.MenuBarItem { label: "Edit", items: commands[3usize..6usize] }
    menus[2usize] = navigation.MenuBarItem { label: "View", items: commands[6usize..9usize] }
    let (bar_toggles, bar_toggles_error) = mem.alloc[widget.Submit](a, 3usize)
    if bar_toggles_error != ok { ret (zero, bar_toggles_error) }
    i = 0usize
    while i < 3usize {
        bar_toggles[i] = widget.Submit { ctx: claim(m, i, 0usize, NO_FLAG), invoke: on_bar_menu }
        i += 1usize
    }
    let (bar, bar_error) = navigation.menu_bar(a, 1000u64, t, "Main menu", menus[0usize..3usize], m.values[V_BAR_MENU], bar_toggles[0usize..3usize])
    add(&p, bar, bar_error)
    let context_toggle = toggler(a, m, F_CONTEXT)
    let (opener, opener_error) = control.button(a, 1100u64, t, "Open a context menu", context_toggle, control.button_options())
    add(&p, opener, opener_error)
    let (context, context_error) = navigation.context_menu(a, 1200u64, t, 1100u64, "Context", commands[3usize..6usize], m.flags[F_CONTEXT], context_toggle)
    add(&p, context, context_error)
    label(&p, 2u64, counted(a, "Last command: ", m.values[V_COMMAND]))
    caption(&p, 3u64, "Navigation stack")
    let titles: [3]str = [3]str{ "Inbox", "Thread", "Message" }
    let (stack_pages, stack_pages_error) = mem.alloc[widget.Node](a, 3usize)
    if stack_pages_error != ok { ret (zero, stack_pages_error) }
    i = 0usize
    while i < 3usize {
        let (deeper, deeper_error) = control.button(a, 1400u64 + u64(i), t, "Go deeper", submit(a, m, on_push), control.button_options())
        if deeper_error != ok { ret (zero, deeper_error) }
        stack_pages[i] = deeper
        i += 1usize
    }
    let depth = m.values[V_DEPTH] + 1usize
    let (stack, stack_error) = navigation.navigation_stack(a, 1300u64, t, titles[0usize..depth], stack_pages[0usize..depth], submit(a, m, on_pop), 480.0)
    if stack_error != ok { ret (zero, stack_error) }
    // The stack fills the height it is given, and a scroll view gives it none: a
    // box of its own bounds it.
    var bounded = style.defaults()
    bounded.width = style.Length { Px: 480.0 }
    bounded.height = style.Length { Px: 160.0 }
    add(&p, widget.box(1299u64, bounded, slice_of(a, stack)), ok)
    caption(&p, 4u64, "Destination bar, rail, bottom navigation, sidebar, drawer")
    let (dest_picks, dest_error) = choices(a, m, 4usize, V_DEST, NO_FLAG)
    if dest_error != ok { ret (zero, dest_error) }
    let (destinations, destinations_error) = navigation.destination_bar(a, 1500u64, t, places[..], m.values[V_DEST], dest_picks, .Bottom, 480.0)
    add(&p, destinations, destinations_error)
    let (nav_picks, nav_error) = choices(a, m, 4usize, V_NAV, F_DRAWER)
    if nav_error != ok { ret (zero, nav_error) }
    let (bars, bars_error) = mem.alloc[widget.Node](a, 2usize)
    if bars_error != ok { ret (zero, bars_error) }
    let (rail, rail_error) = navigation.navigation_rail(a, 1600u64, t, places[..], m.values[V_NAV], nav_picks, 80.0)
    if rail_error != ok { ret (zero, rail_error) }
    bars[0usize] = rail
    let (side, side_error) = navigation.sidebar(a, 1700u64, t, places[..], m.values[V_NAV], nav_picks, 200.0)
    if side_error != ok { ret (zero, side_error) }
    bars[1usize] = side
    row_of(&p, 5u64, bars[0usize..2usize])
    let (bottom, bottom_error) = navigation.bottom_navigation(a, 1800u64, t, places[..], m.values[V_NAV], nav_picks, 480.0)
    add(&p, bottom, bottom_error)
    let drawer_toggle = toggler(a, m, F_DRAWER)
    let (drawer_opener, drawer_opener_error) = control.button(a, 1900u64, t, "Open the drawer", drawer_toggle, control.button_options())
    add(&p, drawer_opener, drawer_opener_error)
    let (drawer, drawer_error) = navigation.navigation_drawer(a, 2000u64, t, places[..], m.values[V_NAV], nav_picks, m.flags[F_DRAWER], drawer_toggle, 280.0)
    add(&p, drawer, drawer_error)
    caption(&p, 6u64, "Bottom app bar and navigation split")
    let (actions, actions_error) = mem.alloc[navigation.Action](a, 3usize)
    if actions_error != ok { ret (zero, actions_error) }
    actions[0usize] = navigation.Action { label: "Search", action: widget.Submit { ctx: ctx, invoke: on_press }, icon: m.texture, enabled: true }
    actions[1usize] = navigation.Action { label: "Share", action: widget.Submit { ctx: ctx, invoke: on_press }, icon: m.texture, enabled: true }
    actions[2usize] = navigation.Action { label: "Compose", action: widget.Submit { ctx: ctx, invoke: on_press }, icon: m.texture, enabled: true }
    let (app_bar, app_bar_error) = navigation.bottom_app_bar(a, 2100u64, t, "Actions", actions[0usize..2usize], &actions[2usize], 480.0)
    add(&p, app_bar, app_bar_error)
    let (primary, primary_error) = control.button(a, 2250u64, t, "Show the detail", toggler(a, m, F_DETAIL), control.button_options())
    if primary_error != ok { ret (zero, primary_error) }
    let (detail, detail_error) = text_of(a, t, "The detail pane")
    if detail_error != ok { ret (zero, detail_error) }
    let (split, split_error) = navigation.navigation_split(a, 2200u64, t, primary, detail, m.flags[F_DETAIL], m.reals[R_SPLIT], real_of(m, R_SPLIT), 560.0, 120.0)
    add(&p, split, split_error)
    caption(&p, 7u64, "Wizard")
    let steps: [3]str = [3]str{ "Account", "Profile", "Confirm" }
    let (step_text, step_text_error) = text_of(a, t, counted(a, "Step ", m.values[V_STEP] + 1usize))
    if step_text_error != ok { ret (zero, step_text_error) }
    let (wizard, wizard_error) = navigation.wizard(a, 2300u64, t, "Set up", steps[..], m.values[V_STEP], step_text, true, submit(a, m, on_back), submit(a, m, on_next), submit(a, m, on_restart), submit(a, m, on_restart), 560.0, 220.0)
    add(&p, wizard, wizard_error)
    caption(&p, 8u64, "Window switcher and command palette")
    let (openers, openers_error) = mem.alloc[widget.Node](a, 2usize)
    if openers_error != ok { ret (zero, openers_error) }
    let switcher_toggle = toggler(a, m, F_SWITCHER)
    let (switch_open, switch_open_error) = control.button(a, 2400u64, t, "Switch windows", switcher_toggle, control.button_options())
    if switch_open_error != ok { ret (zero, switch_open_error) }
    openers[0usize] = switch_open
    let palette_toggle = toggler(a, m, F_PALETTE)
    let (palette_open, palette_open_error) = control.button(a, 2401u64, t, "Command palette", palette_toggle, control.button_options())
    if palette_open_error != ok { ret (zero, palette_open_error) }
    openers[1usize] = palette_open
    row_of(&p, 9u64, openers[0usize..2usize])
    let windows: [3]str = [3]str{ "Gallery", "Notes", "Terminal" }
    let (switcher, switcher_error) = navigation.window_switcher(a, 2500u64, t, "Windows", windows[..], m.values[V_SWITCH], m.flags[F_SWITCHER], value_of(m, V_SWITCH, NO_FLAG), value_of(m, V_SWITCH, F_SWITCHER), switcher_toggle, 360.0)
    add(&p, switcher, switcher_error)
    let (palette, palette_error) = navigation.command_palette(a, 2600u64, t, "Commands", m.palette[..], m.values[V_PALETTE], typed_of(m, V_PALETTE, NO_FLAG), command_names[..], m.values[V_PALETTE_ACTIVE], m.flags[F_PALETTE], value_of(m, V_PALETTE_ACTIVE, NO_FLAG), value_of(m, V_COMMAND, F_PALETTE), palette_toggle, 480.0)
    add(&p, palette, palette_error)
    let (node, node_error) = finish(&p, 10u64)
    ret (node, node_error)
}

// ---------------------------------------------------------------- workspace

fn workspace_page(a: *mem.Arena, t: *const control.Theme, m: *Model) -> (widget.Node, err) {
    let (pg, pg_error) = page(a, t)
    if pg_error != ok { ret (zero, pg_error) }
    var p = pg
    let ctx = mem.cast[*void](m)
    let names: [4]str = [4]str{ "main.e", "notes.md", "build.log", "README" }
    let (documents, documents_error) = mem.alloc[navigation.Document](a, 4usize)
    if documents_error != ok { ret (zero, documents_error) }
    var n = 0usize
    var i = 0usize
    while i < 4usize {
        if !m.closed[i] {
            documents[n] = navigation.Document { key: 1u64 + u64(i), title: names[i], dirty: i == 1usize, pinned: i == 3usize }
            n += 1usize
        }
        i += 1usize
    }
    var current = m.values[V_DOCUMENT]
    if current >= n { current = 0usize }
    caption(&p, 1u64, "Document tabs: a close button closes, the last close reopens all")
    let (tabs, tabs_error) = navigation.document_tabs(a, 1000u64, t, "Documents", documents[0usize..n], current, value_of(m, V_DOCUMENT, NO_FLAG), widget.Change[usize] { ctx: ctx, invoke: on_document_close }, widget.Change[navigation.DocumentMove] { ctx: ctx, invoke: no_change_move })
    add(&p, tabs, tabs_error)
    caption(&p, 2u64, "Dock layout of dock panels")
    let quiet = submit(a, m, none)
    let (explorer_text, explorer_text_error) = text_of(a, t, "Explorer")
    if explorer_text_error != ok { ret (zero, explorer_text_error) }
    let (explorer, explorer_error) = navigation.dock_panel(a, 2000u64, t, "Explorer", explorer_text, quiet)
    if explorer_error != ok { ret (zero, explorer_error) }
    let (outline_text, outline_text_error) = text_of(a, t, "Outline")
    if outline_text_error != ok { ret (zero, outline_text_error) }
    let (outline_panel, outline_panel_error) = navigation.dock_panel(a, 2100u64, t, "Outline", outline_text, quiet)
    if outline_panel_error != ok { ret (zero, outline_panel_error) }
    let (output_text, output_text_error) = text_of(a, t, "Build succeeded")
    if output_text_error != ok { ret (zero, output_text_error) }
    let (output, output_error) = navigation.dock_panel(a, 2200u64, t, "Output", output_text, quiet)
    if output_error != ok { ret (zero, output_error) }
    let (editor_text, editor_text_error) = text_of(a, t, "fn main() -> err { ret ok }")
    if editor_text_error != ok { ret (zero, editor_text_error) }
    let (dock, dock_error) = navigation.dock_layout(a, 2300u64, t, explorer, editor_text, outline_panel, output, m.dock, widget.Change[navigation.DockSizes] { ctx: ctx, invoke: on_dock }, 900.0, 320.0)
    add(&p, dock, dock_error)
    caption(&p, 3u64, "Multi-document workspace")
    let (view, view_error) = text_of(a, t, counted(a, "Editing document ", current + 1usize))
    if view_error != ok { ret (zero, view_error) }
    let (workspace, workspace_error) = navigation.multi_document_workspace(a, 3000u64, t, "Workspace", documents[0usize..n], current, view, value_of(m, V_DOCUMENT, NO_FLAG), widget.Change[usize] { ctx: ctx, invoke: on_document_close }, widget.Change[navigation.DocumentMove] { ctx: ctx, invoke: no_change_move }, 900.0, 260.0)
    add(&p, workspace, workspace_error)
    let (node, node_error) = finish(&p, 4u64)
    ret (node, node_error)
}

// ---------------------------------------------------------------- presentation

fn opener_button(a: *mem.Arena, t: *const control.Theme, key: widget.Key, value: str, action: *const widget.Submit, out: []widget.Node, at: usize) -> err {
    let (node, node_error) = control.button(a, key, t, value, action, control.button_options())
    if node_error != ok { ret node_error }
    out[at] = node
    ret ok
}

fn presentation_page(a: *mem.Arena, t: *const control.Theme, m: *Model) -> (widget.Node, err) {
    let (pg, pg_error) = page(a, t)
    if pg_error != ok { ret (zero, pg_error) }
    var p = pg
    let ctx = mem.cast[*void](m)
    caption(&p, 1u64, "Tooltips, menus, popups, flyouts, dialogs and sheets")
    let rich = toggler(a, m, F_RICH)
    let plain_menu = toggler(a, m, F_MENU)
    let popup_toggle = toggler(a, m, F_POPUP)
    let flyout_toggle = toggler(a, m, F_FLYOUT)
    let modal = toggler(a, m, F_MODAL)
    let side_sheet = toggler(a, m, F_SHEET)
    let bottom_sheet = toggler(a, m, F_BOTTOM)
    let actions_toggle = toggler(a, m, F_ACTIONS)
    let (openers, openers_error) = mem.alloc[widget.Node](a, 8usize)
    if openers_error != ok { ret (zero, openers_error) }
    var opened: err = opener_button(a, t, 1000u64, "Rich tooltip", rich, openers, 0usize)
    if opened == ok { opened = opener_button(a, t, 1001u64, "Menu", plain_menu, openers, 1usize) }
    if opened == ok { opened = opener_button(a, t, 1002u64, "Popup", popup_toggle, openers, 2usize) }
    if opened == ok { opened = opener_button(a, t, 1003u64, "Flyout", flyout_toggle, openers, 3usize) }
    if opened == ok { opened = opener_button(a, t, 1004u64, "Dialog", modal, openers, 4usize) }
    if opened == ok { opened = opener_button(a, t, 1005u64, "Sheet", side_sheet, openers, 5usize) }
    if opened == ok { opened = opener_button(a, t, 1006u64, "Bottom sheet", bottom_sheet, openers, 6usize) }
    if opened == ok { opened = opener_button(a, t, 1007u64, "Action sheet", actions_toggle, openers, 7usize) }
    if opened != ok { ret (zero, opened) }
    row_of(&p, 2u64, openers[0usize..8usize])
    label(&p, 3u64, counted(a, "Last command: ", m.values[V_COMMAND]))
    let (items, items_error) = mem.alloc[overlay.MenuItem](a, 3usize)
    if items_error != ok { ret (zero, items_error) }
    items[0usize] = overlay.MenuItem { label: "Rename", action: widget.Submit { ctx: claim(m, 1usize, 0usize, NO_FLAG), invoke: on_bar_command }, enabled: true }
    items[1usize] = overlay.MenuItem { label: "Duplicate", action: widget.Submit { ctx: claim(m, 2usize, 0usize, NO_FLAG), invoke: on_bar_command }, enabled: true }
    items[2usize] = overlay.MenuItem { label: "Delete", action: widget.Submit { ctx: claim(m, 3usize, 0usize, NO_FLAG), invoke: on_bar_command }, enabled: false }
    let shown = m.flags[F_RICH] || widget.interaction(t.runtime, 1000u64).hovered
    let (tip, tip_error) = overlay.rich_tooltip(a, 1100u64, t, 1000u64, "Rich tooltip", "A subhead, a body and actions", items[0usize..2usize], shown)
    add(&p, tip, tip_error)
    let (menu, menu_error) = overlay.menu(a, 1200u64, t, 1001u64, "Actions", items[0usize..3usize], m.flags[F_MENU], plain_menu)
    add(&p, menu, menu_error)
    let (popup_text, popup_text_error) = text_of(a, t, "A popup, anchored below")
    if popup_text_error != ok { ret (zero, popup_text_error) }
    let (popup, popup_error) = overlay.popup(a, 1300u64, t, 1002u64, .Below, popup_text, m.flags[F_POPUP])
    add(&p, popup, popup_error)
    let (flyout_text, flyout_text_error) = text_of(a, t, "A flyout dismisses on an outside tap")
    if flyout_text_error != ok { ret (zero, flyout_text_error) }
    let (flyout, flyout_error) = overlay.flyout(a, 1400u64, t, 1003u64, .Below, "Flyout", flyout_text, m.flags[F_FLYOUT], flyout_toggle)
    add(&p, flyout, flyout_error)
    let (buttons, buttons_error) = mem.alloc[overlay.DialogButton](a, 2usize)
    if buttons_error != ok { ret (zero, buttons_error) }
    buttons[0usize] = overlay.DialogButton { label: "Close", action: widget.Submit { ctx: claim(m, 0usize, F_MODAL, NO_FLAG), invoke: on_flag }, kind: .Cancel }
    buttons[1usize] = overlay.DialogButton { label: "Keep", action: widget.Submit { ctx: claim(m, 4usize, 0usize, NO_FLAG), invoke: on_bar_command }, kind: .Default }
    let (dialog_text, dialog_text_error) = text_of(a, t, "A dialog holds any content")
    if dialog_text_error != ok { ret (zero, dialog_text_error) }
    let (dialog, dialog_error) = overlay.dialog(a, 1500u64, t, "Dialog", dialog_text, buttons[0usize..2usize], m.flags[F_MODAL], true)
    add(&p, dialog, dialog_error)
    let (sheet_text, sheet_text_error) = text_of(a, t, "A side sheet")
    if sheet_text_error != ok { ret (zero, sheet_text_error) }
    let (sheet, sheet_error) = overlay.sheet(a, 1600u64, t, "Sheet", sheet_text, m.flags[F_SHEET], side_sheet, 320.0)
    add(&p, sheet, sheet_error)
    let (bottom_text, bottom_text_error) = text_of(a, t, "A bottom sheet")
    if bottom_text_error != ok { ret (zero, bottom_text_error) }
    let (bottom, bottom_error) = overlay.bottom_sheet(a, 1700u64, t, "Bottom sheet", bottom_text, m.flags[F_BOTTOM], bottom_sheet, 200.0)
    add(&p, bottom, bottom_error)
    let (sheet_buttons, sheet_buttons_error) = mem.alloc[overlay.DialogButton](a, 3usize)
    if sheet_buttons_error != ok { ret (zero, sheet_buttons_error) }
    sheet_buttons[0usize] = overlay.DialogButton { label: "Share", action: widget.Submit { ctx: claim(m, 5usize, 0usize, NO_FLAG), invoke: on_bar_command }, kind: .Default }
    sheet_buttons[1usize] = overlay.DialogButton { label: "Delete", action: widget.Submit { ctx: claim(m, 6usize, 0usize, NO_FLAG), invoke: on_bar_command }, kind: .Destructive }
    sheet_buttons[2usize] = overlay.DialogButton { label: "Cancel", action: widget.Submit { ctx: claim(m, 0usize, F_ACTIONS, NO_FLAG), invoke: on_flag }, kind: .Cancel }
    let (action_sheet, action_sheet_error) = overlay.action_sheet(a, 1800u64, t, "Photo", sheet_buttons[0usize..3usize], m.flags[F_ACTIONS], actions_toggle)
    add(&p, action_sheet, action_sheet_error)
    caption(&p, 4u64, "Calendar, date range and duration")
    let (calendar, calendar_error) = overlay.calendar(a, 2000u64, t, "Calendar", m.shown, m.date, true, false, m.date, m.date, widget.Change[time.Date] { ctx: ctx, invoke: on_show }, widget.Change[time.Date] { ctx: ctx, invoke: on_calendar })
    add(&p, calendar, calendar_error)
    let (ranged, ranged_error) = overlay.date_range_picker(a, 2500u64, t, "Stay", m.range_from, m.range_to, true, m.flags[F_RANGE], toggler(a, m, F_RANGE), m.shown, widget.Change[time.Date] { ctx: ctx, invoke: on_show }, widget.Change[time.Date] { ctx: ctx, invoke: on_range_pick })
    add(&p, ranged, ranged_error)
    let (span, span_error) = overlay.duration_picker(a, 3000u64, t, "Timer", m.span, widget.Change[time.Duration] { ctx: ctx, invoke: on_span })
    add(&p, span, span_error)
    let (node, node_error) = finish(&p, 5u64)
    ret (node, node_error)
}

// ---------------------------------------------------------------- shell

fn yes_no(value: bool) -> str {
    if value { ret "yes" }
    ret "no"
}

fn shell_page(a: *mem.Arena, t: *const control.Theme, m: *Model) -> (widget.Node, err) {
    let (pg, pg_error) = page(a, t)
    if pg_error != ok { ret (zero, pg_error) }
    var p = pg
    caption(&p, 1u64, "Windows shell")
    let caps = app.shell_capabilities()
    let (b, b_error) = str.builder(a, 256usize)
    if b_error != ok { ret (zero, b_error) }
    var sb = b
    if str.push(&sb, "tray ") != ok || str.push(&sb, yes_no(caps.tray)) != ok || str.push(&sb, ", jump list ") != ok || str.push(&sb, yes_no(caps.jump_list)) != ok || str.push(&sb, ", taskbar ") != ok || str.push(&sb, yes_no(caps.taskbar)) != ok || str.push(&sb, ", notifications ") != ok || str.push(&sb, yes_no(caps.notices)) != ok || str.push(&sb, ", drop target ") != ok || str.push(&sb, yes_no(caps.drop_target)) != ok { ret (zero, control.TooLarge) }
    label(&p, 2u64, str.done(&sb))
    label(&p, 3u64, m.shell_note)
    caption(&p, 4u64, "Tray and notifications")
    label(&p, 5u64, "The tray icon's right-click menu shows or hides this window, sends a notification, opens this tab, or quits.")
    let (buttons, buttons_error) = mem.alloc[widget.Node](a, 3usize)
    if buttons_error != ok { ret (zero, buttons_error) }
    let (send, send_error) = control.button(a, 100u64, t, "Send a Windows notification", toggler(a, m, F_NOTIFY), control.button_options())
    if send_error != ok { ret (zero, send_error) }
    buttons[0usize] = send
    var outlined = control.button_options()
    outlined.variant = .Outlined
    let (hide, hide_error) = control.button(a, 101u64, t, "Hide to the tray", toggler(a, m, F_HIDE), outlined)
    if hide_error != ok { ret (zero, hide_error) }
    buttons[1usize] = hide
    let (badge, badge_error) = control.toggle_button(a, 102u64, t, "Badge the tray icon", m.flags[F_BADGE], toggler(a, m, F_BADGE), outlined)
    if badge_error != ok { ret (zero, badge_error) }
    buttons[2usize] = badge
    row_of(&p, 6u64, buttons[0usize..3usize])
    label(&p, 7u64, counted(a, "Notifications sent: ", m.notices))
    caption(&p, 8u64, "Taskbar and jump list")
    label(&p, 9u64, "The taskbar button's progress follows the Range tab's volume slider. Right-click the taskbar button for the jump list: each task opens the gallery on a tab.")
    let (volume, volume_error) = control.slider(a, 110u64, t, "Taskbar progress", m.volume, 0.0, 100.0, 1.0, change_f32(m, on_volume), true)
    add(&p, volume, volume_error)
    caption(&p, 10u64, "Drop files from Explorer anywhere on this window")
    label(&p, 11u64, counted(a, "Drops so far: ", m.drops))
    let (lines, lines_error) = mem.alloc[widget.Node](a, 12usize)
    if lines_error != ok { ret (zero, lines_error) }
    var i = 0usize
    while i < m.dropped_count {
        let (line, line_error) = control.list_row(a, 200u64 + u64(i), t, m.dropped[i], false, submit(a, m, none))
        if line_error != ok { ret (zero, line_error) }
        lines[i] = line
        i += 1usize
    }
    if m.dropped_count == 0usize {
        let (empty, empty_error) = control.empty_state(a, 190u64, t, zero, "Nothing dropped yet", "Drag files or text here from another program", "Clear", submit(a, m, none), 420.0)
        add(&p, empty, empty_error)
    } else {
        let (card, card_error) = control.card(a, 180u64, t, lines[0usize..m.dropped_count])
        add(&p, card, card_error)
        let (clear, clear_error) = control.button(a, 181u64, t, "Clear the list", toggler(a, m, F_CLEAR_DROPS), outlined)
        add(&p, clear, clear_error)
    }
    let (node, node_error) = finish(&p, 12u64)
    ret (node, node_error)
}

// ---------------------------------------------------------------- the frame

fn build(m: *Model, ctx: *widget.BuildContext) -> (widget.Node, err) {
    m.frame = mem.arena_from(m.storage)
    let a = &m.frame
    if !m.registered {
        let renderer = widget.renderer_of(ctx.runtime)
        if scene.register_font(renderer, m.fonts[0usize]) != ok { ret (zero, control.TooLarge) }
        // A 2x2 picture for the controls that show one: the avatar, the icon button.
        var i = 0usize
        while i < 4usize {
            m.pixels[i * 4usize] = 64u8
            m.pixels[i * 4usize + 1usize] = 128u8
            m.pixels[i * 4usize + 2usize] = 255u8
            m.pixels[i * 4usize + 3usize] = 255u8
            i += 1usize
        }
        let (view, view_error) = image.make_const(m.pixels[..], 2u32, 2u32, 8usize, .Rgba8, .Premultiplied)
        if view_error != ok { ret (zero, control.TooLarge) }
        let (texture, upload_error) = scene.upload_image(renderer, view)
        if upload_error != ok { ret (zero, control.TooLarge) }
        m.texture = texture
        m.registered = true
    }
    let theme = control.Theme { tokens: &m.tokens, fonts: m.fonts, language: "en", runtime: ctx.runtime }
    let t = &theme
    m.theme = t
    m.pick_next = PICK_BASE
    let labels: [TABS]str = [TABS]str{ "Buttons", "Choice", "Range", "Fields", "Surfaces", "Feedback", "Collections", "Overlays", "Content", "Input", "Data", "Navigation", "Workspace", "Presentation", "Shell" }
    let (tab_picks, picks_error) = picks(a, m, TAB_PICKS, TABS, on_tab)
    if picks_error != ok { ret (zero, picks_error) }
    let (pages, pages_error) = mem.alloc[widget.Node](a, TABS)
    if pages_error != ok { ret (zero, pages_error) }
    var current: widget.Node = zero
    var page_error: err = ok
    if m.tab == 0usize {
        let (node, node_error) = buttons_page(a, t, m)
        current = node
        page_error = node_error
    } else if m.tab == 1usize {
        let (node, node_error) = choice_page(a, t, m)
        current = node
        page_error = node_error
    } else if m.tab == 2usize {
        let (node, node_error) = range_page(a, t, m)
        current = node
        page_error = node_error
    } else if m.tab == 3usize {
        let (node, node_error) = fields_page(a, t, m)
        current = node
        page_error = node_error
    } else if m.tab == 4usize {
        let (node, node_error) = surfaces_page(a, t, m)
        current = node
        page_error = node_error
    } else if m.tab == 5usize {
        let (node, node_error) = feedback_page(a, t, m)
        current = node
        page_error = node_error
    } else if m.tab == 6usize {
        let (node, node_error) = collections_page(a, t, m)
        current = node
        page_error = node_error
    } else if m.tab == 7usize {
        let (node, node_error) = overlays_page(a, t, m)
        current = node
        page_error = node_error
    } else if m.tab == 8usize {
        let (node, node_error) = content_page(a, t, m)
        current = node
        page_error = node_error
    } else if m.tab == 9usize {
        let (node, node_error) = input_page(a, t, m)
        current = node
        page_error = node_error
    } else if m.tab == 10usize {
        let (node, node_error) = data_page(a, t, m)
        current = node
        page_error = node_error
    } else if m.tab == 11usize {
        let (node, node_error) = navigation_page(a, t, m)
        current = node
        page_error = node_error
    } else if m.tab == 12usize {
        let (node, node_error) = workspace_page(a, t, m)
        current = node
        page_error = node_error
    } else if m.tab == 13usize {
        let (node, node_error) = presentation_page(a, t, m)
        current = node
        page_error = node_error
    } else {
        let (node, node_error) = shell_page(a, t, m)
        current = node
        page_error = node_error
    }
    if page_error != ok { ret (zero, page_error) }
    pages[m.tab] = current
    let (view, view_error) = control.tab_view(a, 1000u64, t, labels[..], m.tab, tab_picks, pages[0usize..TABS])
    if view_error != ok { ret (zero, view_error) }
    let gap = m.tokens.spacing.md
    var root = style.defaults()
    root.width = style.Length { Percent: 100.0 }
    root.height = style.Length { Percent: 100.0 }
    root.background = paint.Brush { Solid: style.color(&m.tokens, .Background) }
    ret (widget.padded(0u64, gap, gap, gap, 0.0, root, slice_of(a, view)), ok)
}


// ---------------------------------------------------------------- shell plumbing

fn keep_dropped(m: *Model, value: str) {
    if m.dropped_count >= 12usize || m.drop_used + value.len > m.drop_bytes.len {
        m.dropped_count = 0usize
        m.drop_used = 0usize
    }
    let start = m.drop_used
    m.drop_used += copy_into(m.drop_bytes[start..m.drop_bytes.len], value)
    m.dropped[m.dropped_count] = m.drop_bytes[start..m.drop_used]
    m.dropped_count += 1usize
}

// What a drop carried -- its paths, or its text, or a promised file's name --
// copied into the model's own bytes, so the drop storage can be reused.
fn take_drop(m: *Model, landed: shell.Drop) {
    m.drops += 1usize
    var i = 0usize
    while i < landed.items.len {
        let item = landed.items[i]
        if item.kind == .Files {
            var j = 0usize
            while j < item.paths.len {
                keep_dropped(m, item.paths[j])
                j += 1usize
            }
        } else if item.kind == .Text || item.kind == .Promise {
            keep_dropped(m, item.text)
        }
        i += 1usize
    }
}

// A 16 by 16 tray icon: a blue tile with a white border and a white N.
fn tray_pixels(pixels: []u32) {
    let blue = 4281298902u32
    let white = 4294967295u32
    var y = 0usize
    while y < 16usize {
        var x = 0usize
        while x < 16usize {
            var c = blue
            if x == 0usize || y == 0usize || x == 15usize || y == 15usize { c = white }
            if y >= 3usize && y <= 12usize && (x == 4usize || x == 11usize) { c = white }
            if y >= 3usize && y <= 10usize && x == y + 1usize { c = white }
            pixels[y * 16usize + x] = c
            x += 1usize
        }
        y += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var font_path = "C:/Windows/Fonts/segoeui.ttf"
    if target.os == .Linux { font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf" }
    let (font_bytes, font_error) = fs.read_file(a, font_path, 16777216usize)
    if font_error != ok {
        try io.print("no UI font found\n")
        ret ok
    }
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 1usize)
    if fonts_error != ok { os.exit(1i32) }
    fonts[0usize] = shape.Font { id: 1u32, data: font_bytes, face_index: 0u32 }
    let (storage, storage_error) = mem.alloc[u8](a, 16777216usize)
    if storage_error != ok { os.exit(1i32) }
    let (models, models_error) = mem.alloc[Model](a, 1usize)
    if models_error != ok { os.exit(1i32) }
    var m: Model = zero
    m.tokens = style.reference(.Light)
    m.fonts = fonts
    m.storage = storage
    m.volume = 40.0
    m.low = 20.0
    m.high = 80.0
    m.count = 3i64
    m.angle = 90.0
    m.rating = 3u32
    m.split = 220.0
    m.section = 0usize
    // The first argument, one or two digits, is the tab to open on.
    if args.len > 1usize && args[1usize].len > 0usize && args[1usize].len <= 2usize {
        var n = 0usize
        var digits = true
        var i = 0usize
        while i < args[1usize].len {
            let c = args[1usize][i]
            if c < 48u8 || c > 57u8 { digits = false }
            if digits { n = n * 10usize + usize(c - 48u8) }
            i += 1usize
        }
        if digits && n < TABS { m.tab = n }
    }
    m.row = 2u64
    m.node = 10u64
    m.open_nodes[0usize] = 10u64
    m.open_count = 1usize
    m.date = time.Date { year: 2026i32, month: 9u8, day: 22u8 }
    m.shown = m.date
    m.clock = time.Time { hour: 9u8, minute: 30u8, second: 0u8, nanos: 0u32 }
    m.colour_value = paint.rgba(0.2, 0.5, 0.9, 1.0)
    m.reals[R_PANE] = 240.0
    m.reals[R_SPLIT] = 220.0
    m.font_size = 12i64
    m.values[V_BAR_MENU] = 99usize
    m.values[V_SELECTABLE] = copy_into(m.selectable[..], "Select this text with the pointer and copy it with Ctrl+C.")
    var k = 0usize
    while k < 5usize {
        m.order[k] = k
        k += 1usize
    }
    m.dock = navigation.DockSizes { left: 180.0, right: 180.0, bottom: 100.0 }
    m.range_from = m.date
    m.range_to = time.Date { year: 2026i32, month: 9u8, day: 26u8 }
    m.span = time.millis(5400000i64)
    m.shell_note = "Right-click the tray icon, or drop files here from Explorer."
    models[0usize] = m
    let model = &models[0usize]
    let (pick_slots, picks_error) = mem.alloc[Pick](a, PICK_SLOTS)
    if picks_error != ok { os.exit(1i32) }
    model.picks = pick_slots
    k = 0usize
    while k < 4usize {
        let at = k * 64usize
        model.pairs[k] = collection.Pair { name: model.pair_bytes[at..at + 32usize], name_len: 0usize, value: model.pair_bytes[at + 32usize..at + 64usize], value_len: 0usize }
        k += 1usize
    }
    model.pairs[0usize].name_len = copy_into(model.pairs[0usize].name, "Accept")
    model.pairs[0usize].value_len = copy_into(model.pairs[0usize].value, "text/html")
    model.pairs[1usize].name_len = copy_into(model.pairs[1usize].name, "Cache-Control")
    model.pairs[1usize].value_len = copy_into(model.pairs[1usize].value, "no-cache")
    model.pair_count = 2usize
    model.values[V_TOKEN_TEXT] = copy_into(model.token_text[..], "Earth")
    let seeded = on_token_add(mem.cast[*void](model))
    // `ui audit`: every tab audited without a window, the findings printed.
    if args.len > 1usize && str.eq(args[1usize], "audit") { ret audit_gallery(a, model) }
    let options = app.Options {
        window: window.Options { title: "Neper controls", width: 1280u32, height: 800u32, min_width: 480u32, min_height: 320u32, resizable: true, transparent: false, mode: .Windowed },
        widget_limits: widget.Limits { max_elements: 16384usize, max_states: 2048usize, state_bytes: 512usize, state_classes: 8u16, max_depth: 64u16, max_commands: 65536usize },
        frame_arena_bytes: 67108864usize,
        event_capacity: 256usize,
        backend: .Cpu,
    }
    let (application, init_error) = app.init[Model](a, options, app.Builder[Model] { ctx: model, build: build })
    if init_error != ok {
        try io.print("the host cannot open a window\n")
        os.exit(2i32)
    }
    var running = application
    let (host, host_error) = app.host_window(&running)
    if host_error != ok { os.exit(2i32) }
    let (scratch_bytes, scratch_error) = mem.alloc[u8](a, 1048576usize)
    if scratch_error != ok { os.exit(1i32) }
    let (drop_bytes, drop_bytes_error) = mem.alloc[u8](a, 4194304usize)
    if drop_bytes_error != ok { os.exit(1i32) }
    var scratch = mem.arena_from(scratch_bytes)
    var drop_arena = mem.arena_from(drop_bytes)

    // The tray icon and its menu.
    var pixels: [256]u32 = zero
    tray_pixels(pixels[..])
    var tray: app.Tray = zero
    var tray_opened = false
    var items: [5]shell.MenuItem = zero
    items[0usize] = shell.MenuItem { id: 1u32, label: "Show or hide the window", enabled: true, checked: false, separator: false }
    items[1usize] = shell.MenuItem { id: 2u32, label: "Send a notification", enabled: true, checked: false, separator: false }
    items[2usize] = shell.MenuItem { id: 3u32, label: "Open the Shell tab", enabled: true, checked: false, separator: false }
    items[3usize] = shell.MenuItem { id: 0u32, label: "", enabled: true, checked: false, separator: true }
    items[4usize] = shell.MenuItem { id: 4u32, label: "Quit", enabled: true, checked: false, separator: false }
    if app.tray_supported() {
        let (opened, open_error) = app.tray_open(a, TRAY_ID, shell.Icon { width: 16u32, height: 16u32, pixels: pixels[..] }, "Neper controls")
        if open_error == ok {
            tray = opened
            tray_opened = true
            app.tray_set_menu(&tray, items[..])
        } else {
            model.shell_note = "The tray refused the icon."
        }
    }

    // The jump list: each task starts the gallery on a tab.
    let (exe, exe_error) = fs.executable_path(a)
    if exe_error == ok && app.jump_list_supported() {
        var tasks: [4]shell.JumpTask = zero
        tasks[0usize] = shell.JumpTask { title: "Open on Buttons", program: exe, arguments: "0", description: "The gallery on its Buttons tab" }
        tasks[1usize] = shell.JumpTask { title: "Open on Data", program: exe, arguments: "10", description: "The gallery on its Data tab" }
        tasks[2usize] = shell.JumpTask { title: "Open on Navigation", program: exe, arguments: "11", description: "The gallery on its Navigation tab" }
        tasks[3usize] = shell.JumpTask { title: "Open on Shell", program: exe, arguments: "14", description: "The gallery on its Shell tab" }
        if app.jump_list(&scratch, tasks[..]) != ok { model.shell_note = "The jump list was refused." }
    }

    // Drops from Explorer and other programs land in drop_arena.
    var dropping = false
    if app.drop_target_supported() {
        if app.drop_target_open(a, &running, &drop_arena) == ok { dropping = true } else { model.shell_note = "The window could not become a drop target." }
    }

    // `step` waits up to 16 ms for input and presents a frame when one is due; a
    // step that presented one is timed, and the title shows that frame's cost.
    var run_error: err = ok
    var shown = 0u64
    var title_storage: [128]u8 = zero
    var hidden = false
    var badged = false
    var last_progress = 1000usize
    var quit = false
    while !quit {
        let (started, clock_error) = time.monotonic()
        let (more, step_error) = app.step(&running, time.millis(16i64))
        if step_error != ok {
            run_error = step_error
            break
        }
        if !more { break }
        scratch = mem.arena_from(scratch_bytes)
        var changed = false
        var show = false
        if tray_opened {
            while true {
                let (activation, any, poll_error) = app.tray_poll(&scratch, &tray)
                if poll_error != ok || !any { break }
                if activation.kind == .Select || activation.kind == .Open { show = true }
                if activation.kind == .NoticeSelect {
                    show = true
                    model.tab = SHELL_TAB
                }
                if activation.kind == .Command {
                    if activation.command == 1u32 {
                        if hidden { show = true } else { model.flags[F_HIDE] = true }
                    }
                    if activation.command == 2u32 { model.flags[F_NOTIFY] = true }
                    if activation.command == 3u32 {
                        show = true
                        model.tab = SHELL_TAB
                    }
                    if activation.command == 4u32 { quit = true }
                }
                changed = true
            }
        }
        if show && hidden {
            let shown_error = os.window_visible(host, true)
            hidden = false
        }
        if model.flags[F_HIDE] {
            model.flags[F_HIDE] = false
            if tray_opened {
                let hidden_error = os.window_visible(host, false)
                hidden = true
            } else {
                model.shell_note = "There is no tray to hide in."
            }
            changed = true
        }
        if model.flags[F_NOTIFY] {
            model.flags[F_NOTIFY] = false
            let body = counted(&scratch, "Hello from Neper. Notifications sent so far: ", model.notices + 1usize)
            let (notice_id, notify_error) = app.notify(&scratch, &tray, app.Notification { title: "Neper controls", body: body, silent: false })
            if notify_error == ok {
                model.notices += 1usize
                model.shell_note = "Notification sent: click it to come back to this tab."
            } else {
                model.shell_note = "The notification was refused."
            }
            changed = true
        }
        if tray_opened && model.flags[F_BADGE] != badged {
            badged = model.flags[F_BADGE]
            var count = 0u32
            if badged { count = 3u32 }
            let badge_error = app.tray_set_badge(&scratch, &tray, count)
        }
        if model.flags[F_CLEAR_DROPS] {
            model.flags[F_CLEAR_DROPS] = false
            model.dropped_count = 0usize
            model.drop_used = 0usize
            changed = true
        }
        if dropping {
            var landed_any = false
            while true {
                let (landed, any) = app.drop_take()
                if !any { break }
                take_drop(model, landed)
                landed_any = true
            }
            if landed_any {
                drop_arena = mem.arena_from(drop_bytes)
                model.shell_note = "Dropped: the list below shows what arrived."
                model.tab = SHELL_TAB
                changed = true
            }
        }
        let progress = usize(model.volume)
        if progress != last_progress && app.taskbar_supported() {
            last_progress = progress
            let progress_error = app.taskbar_progress(&scratch, &running, .Normal, u64(progress), 100u64)
        }
        if changed { let requested = app.request_frame(&running) }
        let frames = app.frames_of(&running)
        if frames != shown && clock_error == ok {
            shown = frames
            let spent = time.since(started)
            var millis = usize(spent.nanos / 1000000i64)
            if millis == 0usize { millis = 1usize }
            var title_arena = mem.arena_from(title_storage[..])
            let (b, b_error) = str.builder(&title_arena, 96usize)
            if b_error != ok { continue }
            var title = b
            if str.push(&title, "Neper controls - ") != ok || str.push_usize(&title, millis) != ok || str.push(&title, " ms/frame (") != ok || str.push_usize(&title, 1000usize / millis) != ok || str.push(&title, " fps, frame ") != ok || str.push_usize(&title, usize(frames)) != ok || str.push(&title, ")") != ok { continue }
            let titled = os.window_title(host, str.done(&title))
        }
    }
    if dropping { let unregistered = app.drop_target_close(a, &running) }
    if tray_opened { let untrayed = app.tray_close(a, &tray) }
    let closed = app.close(&running)
    if run_error != ok {
        if run_error == widget.DuplicateKey { try io.print("DuplicateKey\n") }
        if run_error == widget.InvalidTree { try io.print("InvalidTree\n") }
        if run_error == widget.TooDeep { try io.print("TooDeep\n") }
        if run_error == widget.TooLarge { try io.print("widget.TooLarge\n") }
        if run_error == widget.StateType { try io.print("StateType\n") }
        if run_error == control.TooLarge { try io.print("control.TooLarge\n") }
        if run_error == collection.TooLarge { try io.print("collection.TooLarge\n") }
        if run_error == navigation.TooLarge { try io.print("navigation.TooLarge\n") }
        if run_error == overlay.TooLarge { try io.print("overlay.TooLarge\n") }
        if run_error == ui_layout.Overflow { try io.print("Overflow\n") }
        if run_error == ui_layout.Invalid { try io.print("layout.Invalid\n") }
        try io.print("the gallery stopped on an error\n")
        os.exit(3i32)
    }
    ret ok
}

// ---------------------------------------------------------------- audit

// The page the audit builds: the gallery's own frame, on the model's current tab.
fn audit_build(ctx: *void, context: *widget.BuildContext) -> (widget.Node, err) {
    let (node, node_error) = build(mem.cast[*Model](ctx), context)
    ret (node, node_error)
}

// A finding as a line: palette, tab, check, role, name, bounds and its measure.
fn print_finding(palette: str, tab: usize, f: *const audit.Finding, scratch: []u8) {
    var arena = mem.arena_from(scratch)
    let (b, b_error) = str.builder(&arena, scratch.len - 16usize)
    if b_error != ok { ret }
    var sb = b
    let said = str.push(&sb, palette) == ok && str.push(&sb, "\t") == ok && str.push_usize(&sb, tab) == ok && str.push(&sb, "\t") == ok && str.push(&sb, audit.check_name(f.check)) == ok && str.push(&sb, "\t") == ok && str.push(&sb, audit.role_name(f.role)) == ok && str.push(&sb, "\t") == ok && str.push(&sb, f.label) == ok && str.push(&sb, "\t") == ok && str.push_f32(&sb, f.bounds.x) == ok && str.push(&sb, ",") == ok && str.push_f32(&sb, f.bounds.y) == ok && str.push(&sb, " ") == ok && str.push_f32(&sb, f.bounds.width) == ok && str.push(&sb, "x") == ok && str.push_f32(&sb, f.bounds.height) == ok && str.push(&sb, "\t") == ok && str.push_f32(&sb, f.measure) == ok && str.push(&sb, "\n") == ok
    if said { let printed = io.print(str.done(&sb)) }
}

// Every tab in the light, dark and high-contrast palettes: names, roles, targets
// and contrast in each, the Tab walk in the light one. The findings are printed a
// line each, then a count of each kind; the gallery exits 1 when there is any.
fn audit_gallery(a: *mem.Arena, model: *Model) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { ret open_error }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (r, renderer_error) = scene.renderer(a, device, q, 1280u32, 800u32)
    if renderer_error != ok { ret renderer_error }
    var renderer = r
    let limits = widget.Limits { max_elements: 16384usize, max_states: 2048usize, state_bytes: 512usize, state_classes: 8u16, max_depth: 64u16, max_commands: 65536usize }
    let (rt, runtime_error) = widget.runtime(a, &renderer, limits)
    if runtime_error != ok { ret runtime_error }
    var runtime = rt
    // One region reused by every run: the harness, the frame, the trees, the shots.
    let (region, region_error) = mem.alloc[u8](a, 201326592usize)
    if region_error != ok { ret region_error }
    let (findings, findings_error) = mem.alloc[audit.Finding](a, 512usize)
    if findings_error != ok { ret findings_error }
    var line: [512]u8 = zero
    var totals: [9]usize = zero
    let palettes: [3]style.Palette = [3]style.Palette{ .Light, .Dark, .HighContrast }
    let names: [3]str = [3]str{ "light", "dark", "contrast" }
    let gallery_page = audit.Page { ctx: mem.cast[*void](model), build: audit_build }
    var o = audit.options()
    o.frame_bytes = 67108864usize
    var p = 0usize
    while p < 3usize {
        model.tokens = style.reference(palettes[p])
        o.keyboard = p == 0usize
        var tab = 0usize
        while tab < TABS {
            model.tab = tab
            var run_arena = mem.arena_from(region)
            let (report, run_error) = audit.run(&run_arena, &runtime, gallery_page, o, findings)
            if run_error != ok { ret run_error }
            var i = 0usize
            while i < report.count {
                print_finding(names[p], tab, &findings[i], line[..])
                totals[usize(mem.bitcast[u8](findings[i].check))] += 1usize
                i += 1usize
            }
            tab += 1usize
        }
        p += 1usize
    }
    var any = 0usize
    var c = 0usize
    while c < 9usize {
        if totals[c] > 0usize {
            let check = mem.bitcast[audit.Check](u8(c))
            try io.print(counted(a, "", totals[c]))
            try io.print(" ")
            try io.print(audit.check_meaning(check))
            try io.print("\n")
            any += totals[c]
        }
        c += 1usize
    }
    try io.print(counted(a, "audit: ", any))
    try io.print(" findings\n")
    if any > 0usize { os.exit(1i32) }
    ret ok
}
