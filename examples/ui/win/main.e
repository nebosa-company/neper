// examples/ui/win/main.e — a Windows desktop gallery of every control the Neper
// UI chain offers, one tab per family, each control live: the model behind the
// page keeps what a tap, a keystroke or a drag changes and the next frame shows it.
//
//   build\windows\tests\selfhost\neper-self.exe emit-executable examples\ui\win\main.e . x64 windows build\examples\ui-win.exe
//   build\examples\ui-win.exe [tab 0-7]
//
// The text is set in Segoe UI from C:\Windows\Fonts; with no font the page is
// silent boxes, so the program says so and stops.

use e.fs
use e.io
use e.mem
use e.os
use e.str
use e.time
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.text.shape
use e.ui.app
use e.ui.collection
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.navigation
use e.ui.overlay
use e.ui.style
use e.ui.widget
use e.ui.window

const TABS: usize = 8usize
const MAX_NODES: usize = 64usize

type Pick = struct { model: *Model, index: usize }

type Model = struct {
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
        m.picks[first + i] = Pick { model: m, index: i }
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
    let labels: [TABS]str = [TABS]str{ "Buttons", "Choice", "Range", "Fields", "Surfaces", "Feedback", "Collections", "Overlays" }
    let (tab_picks, picks_error) = picks(a, m, 0usize, TABS, on_tab)
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
    } else {
        let (node, node_error) = overlays_page(a, t, m)
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

fn main(a: *mem.Arena, args: []str) -> err {
    let (font_bytes, font_error) = fs.read_file(a, "C:/Windows/Fonts/segoeui.ttf", 16777216usize)
    if font_error != ok {
        try io.print("no font at C:/Windows/Fonts/segoeui.ttf\n")
        ret ok
    }
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 1usize)
    if fonts_error != ok { os.exit(1i32) }
    fonts[0usize] = shape.Font { id: 1u32, data: font_bytes, face_index: 0u32 }
    let (storage, storage_error) = mem.alloc[u8](a, 4194304usize)
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
    // The first argument, a digit, is the tab to open on.
    if args.len > 1usize && args[1usize].len == 1usize && args[1usize][0usize] >= 48u8 && args[1usize][0usize] < 56u8 { m.tab = usize(args[1usize][0usize] - 48u8) }
    m.row = 2u64
    m.node = 10u64
    m.open_nodes[0usize] = 10u64
    m.open_count = 1usize
    m.date = time.Date { year: 2026i32, month: 9u8, day: 22u8 }
    m.shown = m.date
    m.clock = time.Time { hour: 9u8, minute: 30u8, second: 0u8, nanos: 0u32 }
    m.colour_value = paint.rgba(0.2, 0.5, 0.9, 1.0)
    models[0usize] = m
    let model = &models[0usize]
    let (pick_slots, picks_error) = mem.alloc[Pick](a, 64usize)
    if picks_error != ok { os.exit(1i32) }
    model.picks = pick_slots
    let options = app.Options {
        window: window.Options { title: "Neper controls", width: 1000u32, height: 700u32, min_width: 480u32, min_height: 320u32, resizable: true, transparent: false, mode: .Windowed },
        widget_limits: widget.Limits { max_elements: 4096usize, max_states: 512usize, state_bytes: 512usize, state_classes: 8u16, max_depth: 48u16, max_commands: 16384usize },
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
    // `step` waits up to 16 ms for input and presents a frame when one is due; a
    // step that presented one is timed, and the title shows that frame's cost.
    var run_error: err = ok
    var shown = 0u64
    var title_storage: [128]u8 = zero
    while true {
        let (started, clock_error) = time.monotonic()
        let (more, step_error) = app.step(&running, time.millis(16i64))
        if step_error != ok {
            run_error = step_error
            break
        }
        if !more { break }
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
    let closed = app.close(&running)
    if run_error != ok {
        try io.print("the gallery stopped on an error\n")
        os.exit(3i32)
    }
    ret ok
}
