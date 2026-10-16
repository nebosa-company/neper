// The hint (tooltip) in its forms under every look: docs/ui/looks/<look>/hint.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.overlay
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

// An anchor button with its hint shown (the cell is tall enough to hold the overlay).
fn anchored(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, i: usize, rich: bool, text: str, subhead: str, shortcut: str) -> (widget.Node, err) {
    let anchor_key = u64(100usize + i)
    var options = control.button_options()
    let (button, button_error) = control.button(a, anchor_key, t, "Anchor", action, options)
    if button_error != ok { ret (zero, button_error) }
    var tip: widget.Node = zero
    if rich {
        let (items, items_error) = mem.alloc[overlay.MenuItem](a, 1usize)
        if items_error != ok { ret (zero, items_error) }
        items[0usize] = overlay.MenuItem { label: "Learn more", action: *action, enabled: true }
        var shown_items = items[0usize..1usize]
        shown_items = items[0usize..0usize]
        let (made, made_error) = overlay.rich_tooltip(a, u64(5000usize + i * 100usize), t, anchor_key, subhead, text, shown_items, true)
        if made_error != ok { ret (zero, made_error) }
        tip = made
    } else {
        let (made, made_error) = overlay.tooltip_of(a, u64(5000usize + i * 100usize), t, anchor_key, text, shortcut, true)
        if made_error != ok { ret (zero, made_error) }
        tip = made
    }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = button
    parts[1usize] = tip
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..2usize]), ok)
}

// Five cells, each an anchor with its hint shown: one line, wrapped lines, a shortcut, the rich
// hint with a subhead, and the v3 header hint's text. (The harness runtime holds 16384 paint
// commands: a sixth overlay makes the frame an InvalidTree.)
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let captions = [5]str{ "Plain", "Wrapped", "With shortcut", "Rich, subhead", "Short" }
    let texts = [5]str{ "Save the deck", "Cards that share a name are counted once,\nwhatever their edition or condition", "Save", "Prices are refreshed every night from TCGplayer.", "Edition" }
    var i = 0usize
    while i < 5usize {
        let rich = i == 3usize
        var subhead = ""
        if i == 3usize { subhead = "Price refresh" }
        var shortcut = ""
        if i == 2usize { shortcut = "Ctrl+S" }
        let (node, node_error) = anchored(a, t, &actions[0usize], i, rich, texts[i], subhead, shortcut)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (5usize, ok)
}

// The hint windows of the captures on their own (ref/windows/states/hover-hint-*, exact crops of the hint windows): `hint.exe T<n>`:
// 1 to 5 the toolbar hints (Add cards, Add Foil cards, Visit MTG Studio, incremental search, Filter), 6 the grid header's.
type Hinted = struct { name: str, text: str, width: f32, high: f32, grid: bool }

fn hinted_spec(n: usize) -> Hinted {
    if n == 1usize { ret Hinted { name: "hint_toolbar_cards_expand", text: "Add cards to your collection (Ins / +)", width: 210.0, high: 20.0, grid: false } }
    if n == 2usize { ret Hinted { name: "hint_toolbar_cards_f", text: "Add Foil cards to your collection", width: 180.0, high: 20.0, grid: false } }
    if n == 3usize { ret Hinted { name: "hint_toolbar_help_home", text: "Visit MTG Studio online resources", width: 188.0, high: 20.0, grid: false } }
    if n == 4usize { ret Hinted { name: "hint_toolbar_search_binoculars", text: "Start incremental search (Ctrl+F)", width: 185.0, high: 20.0, grid: false } }
    if n == 7usize { ret Hinted { name: "hint_native", text: "This is the tooltip text", width: 126.0, high: 20.0, grid: false } }
    if n == 5usize { ret Hinted { name: "hint_toolbar_search_filter", text: "Filter top grid cards by various properties (F3)", width: 255.0, high: 20.0, grid: false } }
    ret Hinted { name: "hint_grid_header_name", text: "Name - the card's name appears in the upper left corner.", width: 285.0, high: 25.0, grid: true }
}

fn build_hinted_n(a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, n: usize) -> (usize, err) {
    let o = hinted_spec(n)
    var node: widget.Node = zero
    var node_error: err = ok
    if n == 7usize && t.tokens.profile == .Windows {
        // round 11: the light look of the native tooltip (ref/windows-native/light/tooltip-rest)
        let (native, native_error) = control.win_native_tooltip(a, 100u64, t, o.text, o.width, o.high)
        node = native
        node_error = native_error
    } else {
        let (v3, v3_error) = control.win5_hint(a, 100u64, t, o.text, o.grid, o.width, o.high)
        node = v3
        node_error = v3_error
    }
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "", node: node, drive: .None }
    ret (1usize, ok)
}

fn build_t1(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_hinted_n(a, t, cells, 1usize)
    ret (m, e)
}
fn build_t2(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_hinted_n(a, t, cells, 2usize)
    ret (m, e)
}
fn build_t3(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_hinted_n(a, t, cells, 3usize)
    ret (m, e)
}
fn build_t4(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_hinted_n(a, t, cells, 4usize)
    ret (m, e)
}
fn build_t5(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_hinted_n(a, t, cells, 5usize)
    ret (m, e)
}
fn build_t6(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_hinted_n(a, t, cells, 6usize)
    ret (m, e)
}

fn build_t7(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_hinted_n(a, t, cells, 7usize)
    ret (m, e)
}

fn run_hinted(a: *mem.Arena, n: usize) -> err {
    let o = hinted_spec(n)
    var maker: looks.Build = build_t1
    if n == 2usize { maker = build_t2 }
    if n == 3usize { maker = build_t3 }
    if n == 4usize { maker = build_t4 }
    if n == 5usize { maker = build_t5 }
    if n == 6usize { maker = build_t6 }
    if n == 7usize { maker = build_t7 }
    let sheet = looks.Sheet { name: o.name, cells: 1usize, columns: 1usize, cell_w: o.width, cell_h: o.high, ctx: zero, build: maker }
    ret looks.run_all(a, &sheet)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len == 2usize && args[1usize][0usize] == 84u8 { ret run_hinted(a, usize(args[1usize][1usize]) - 48usize) }
    let sheet = looks.Sheet { name: "hint", cells: 5usize, columns: 3usize, cell_w: 260.0, cell_h: 110.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
