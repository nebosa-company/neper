// The vertical grid / property grid (TcxVerticalGrid) under every look:
// docs/ui/looks/<look>/vertical_grid.png. Run from the repository root; see docs/ui/looks-howto.md.
//
// Left: v3's Deck Properties grid as the live 100 % capture shows it (ref/windows/vertical_grid.png,
// cropped from ref/windows/dialogs/deck-properties@1x.png at (16, 79), 330 x 425): the General
// category with its nine rows (the Name row focused), the Computed category with the rows that are
// plain text (the capture's picture, bar and multi-cell rows are not reproduced). Right: the same
// grid with both categories shut. Row header 164 px, 330 px in all, as in the DFM.

use e.gfx.paint
use e.mem
use e.ui.gridlook as gl
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.widget
use e.gfx.geometry

const COUNT: usize = 12usize
const NAME_KEY: u64 = 101u64

type Pick = struct { selected: usize, shut: bool }
var pick: Pick = zero

// looks5-e: under the Windows look the Computed category has v3's six rows (Deck | Sideboard, Land | Crea | Spell, Colors,
// Archetype, Strategy, Legality), some with cell lines of their own and taller than the rest (ref/windows/vertical_grid.png)
var windows_rows: bool = false
var foot_pressed: bool = false
// the first sheet's capture (the dialog grab) shows another file name than the states grabs
var desktop: bool = false

fn shapes(on: bool) {
    windows_rows = on
    collection.property_shapes_clear()
    if !on { ret }
    collection.property_row_shape(9usize, 17.0, 96.0, 0.0, 247.0, 0.0, "Deck", "Sideboard", "")
    collection.property_row_shape(10usize, 17.0, 73.0, 119.0, 220.0, 275.0, "Land", "Crea", "Spell")
    collection.property_row_text_x(9usize, 49.0, 0.0, 0.0)
    collection.property_row_text_x(10usize, 45.0, 91.0, 137.0)
    collection.property_row_pics(10usize, 28.0, vg_land(), 74.0, vg_crea(), 120.0, vg_spell(), 17.0, 17.0)
    collection.property_row_shape(11usize, 17.0, 0.0, 0.0, 0.0, 0.0, "", "", "")
    collection.property_row_shape(12usize, 18.0, 0.0, 0.0, 0.0, 0.0, "", "", "")
    collection.property_row_shape(13usize, 24.0, 0.0, 0.0, 0.0, 0.0, "", "", "")
    collection.property_row_shape(14usize, 17.0, 0.0, 0.0, 0.0, 0.0, "", "", "")
}

// the row of Archetype: its index under the Windows look
fn archetype_index() -> usize {
    if windows_rows { ret 12usize }
    ret 9usize
}

fn noop_key(ctx: *void, value: widget.Key) -> err { ret ok }

fn names(index: usize) -> str {
    if index == 0usize { ret "Name" }
    if index == 1usize { ret "Author" }
    if index == 2usize { ret "e-mail" }
    if index == 3usize { ret "Created" }
    if index == 4usize { ret "Modified" }
    if index == 5usize { ret "Version" }
    if index == 6usize { ret "Description" }
    if index == 7usize { ret "File Name" }
    if index == 8usize { ret "File Type" }
    if windows_rows {
        if index == 9usize || index == 10usize { ret "" }
        if index == 11usize { ret "Colors" }
        if index == 12usize { ret "Archetype" }
        if index == 13usize { ret "Strategy" }
        ret "Legality"
    }
    if index == 9usize { ret "Archetype" }
    if index == 10usize { ret "Deck" }
    ret "Sideboard"
}

fn values(index: usize) -> str {
    if index == 0usize { ret "New Deck" }
    if index == 1usize { ret "gaddl" }
    if index == 3usize || index == 4usize { ret "10/11/2026" }
    if index == 5usize { ret "1.0" }
    if index == 7usize {
        if desktop { ret "C:\\Users\\gaddl\\Desktop\\New..." }
        ret "D:\\Temp\\claude\\v3run\\Probe ..."
    }
    if index == 8usize { ret "MTG Studio (Xml)" }
    if windows_rows {
        if index == 12usize { ret "Unspecified" }
        ret ""
    }
    if index == 9usize { ret "Unspecified" }
    if index == 10usize { ret "12" }
    if index == 11usize { ret "0" }
    ret ""
}

fn property_at(ctx: *void, index: usize) -> collection.Property {
    var group = "General"
    if index > 8usize { group = "Computed" }
    ret collection.Property { key: NAME_KEY + u64(index), name: names(index), group: group }
}

fn count_of(ctx: *void) -> usize {
    if windows_rows { ret 15usize }
    ret COUNT
}

// A text centred in a `w` x `h` cell (Tahoma, the Windows look).
fn centred(a: *mem.Arena, t: *const control.Theme, text: str, w: f32, h: f32) -> (widget.Node, err) {
    let (node, node_error) = control.text(a, 0u64, text, t, control.text_options())
    if node_error != ok { ret (zero, node_error) }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = node
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Center, cross: .Center, gap: 0.0 }, looks.size_style(w, h), held[0usize..1usize]), ok)
}

fn row_of(a: *mem.Arena, nodes: []const widget.Node, h: f32) -> widget.Node {
    ret widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, looks.size_style(330.0, h), nodes)
}

// A coloured box (a disc or a tag), `w` x `h`, `radius` rounded.
fn swatch(color: u32, w: f32, h: f32, radius: f32) -> widget.Node {
    var s = looks.size_style(w, h)
    s.background = paint.Brush { Solid: gl.rgb(color) }
    s.radius = radius
    ret widget.box(0u64, s, zero)
}

fn ramp_stops(a: *mem.Arena) -> []const paint.Stop {
    let (stops, stops_error) = mem.alloc[paint.Stop](a, 3usize)
    if stops_error != ok { ret zero }
    stops[0usize] = paint.Stop { offset: 0.0, color: style.hex(0xFF0000u32) }
    stops[1usize] = paint.Stop { offset: 0.5, color: style.hex(0x8A4A00u32) }
    stops[2usize] = paint.Stop { offset: 1.0, color: style.hex(0x007000u32) }
    ret stops[0usize..3usize]
}

// A tag of the Legality row: a coloured box with its letter.
fn tag(a: *mem.Arena, t: *const control.Theme, letter: str, color: u32) -> (widget.Node, err) {
    let (letter_node, letter_error) = control.colored_text(a, 0u64, letter, t, control.text_options(), gl.rgb(0xFFFFFFu32))
    if letter_error != ok { ret (zero, letter_error) }
    let (letter_held, letter_held_error) = mem.alloc[widget.Node](a, 1usize)
    if letter_held_error != ok { ret (zero, letter_held_error) }
    letter_held[0usize] = letter_node
    let text = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Center, cross: .Center, gap: 0.0 }, looks.size_style(15.0, 17.0), letter_held[0usize..1usize])
    let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
    if pair_error != ok { ret (zero, pair_error) }
    pair[0usize] = swatch(color, 15.0, 17.0, 0.0)
    pair[1usize] = text
    ret (widget.stack(0u64, looks.size_style(15.0, 17.0), pair[0usize..2usize]), ok)
}

// The cells of the Computed rows as the capture shows them; the pictures (the Land, Crea and Spell icons, the colour discs) are
// artwork and stand in as plain discs.
fn computed_editor(a: *mem.Arena, t: *const control.Theme, index: usize, out: *widget.Node) -> err {
    let (tahoma, tahoma_error) = control.windows_tahoma_theme(a, t, 11.0)
    if tahoma_error != ok { ret tahoma_error }
    let (copies, copies_error) = mem.alloc[control.Theme](a, 1usize)
    if copies_error != ok { ret copies_error }
    copies[0usize] = tahoma
    let tt = &copies[0usize]
    let (parts, parts_error) = mem.alloc[widget.Node](a, 8usize)
    if parts_error != ok { ret parts_error }
    if index == 9usize || index == 10usize {
        // the value cells' numbers, each centred where the capture centres it (x of the capture, the editor starts at 169)
        let (kids, kids_error) = mem.alloc[widget.Node](a, 3usize)
        if kids_error != ok { ret kids_error }
        var n = 0usize
        var texts = [3]str{ "12", "0", "" }
        var centres = [3]f32{ 206.0, 287.5, 0.0 }
        var count = 2usize
        if index == 10usize {
            texts = [3]str{ "2", "8", "2" }
            centres = [3]f32{ 192.5, 247.5, 301.5 }
            count = 3usize
        }
        var at = 0usize
        while at < count {
            let (num, num_error) = centred(a, tt, texts[at], 40.0, 17.0)
            if num_error != ok { ret num_error }
            kids[n] = widget.positioned(0u64, centres[at] - 169.0 - 20.0, 0.0, style.defaults(), mem_one_node(a, num))
            n += 1usize
            at += 1usize
        }
        *out = widget.stack(0u64, looks.size_style(160.0, 17.0), kids[0usize..n])
        ret ok
    }
    if index == 11usize {
        // v3's four colour icons, the capture's pixels (artwork)
        let (icons, icons_error) = gl.pixels(a, vg_colors(), vg_colors_w(), vg_colors_h())
        if icons_error != ok { ret icons_error }
        *out = widget.stack(0u64, looks.size_style(160.0, 17.0), mem_one_node(a, widget.positioned(0u64, 0.0, 1.0, style.defaults(), mem_one_node(a, icons))))
        ret ok
    }
    if index == 13usize {
        // "Very Aggressive" centred over a bar that runs from red to green
        let (word, word_error) = centred(a, tt, "Very Aggressive", 153.0, 17.0)
        if word_error != ok { ret word_error }
        // v3's red-to-green bar with its marker, the capture's pixels (artwork), under the word
        let (strip, strip_error) = gl.pixels(a, vg_strip(), vg_strip_w(), vg_strip_h())
        if strip_error != ok { ret strip_error }
        let (col, col_error) = mem.alloc[widget.Node](a, 2usize)
        if col_error != ok { ret col_error }
        col[0usize] = word
        col[1usize] = widget.positioned(0u64, 0.0, 15.0, style.defaults(), mem_one_node(a, strip))
        *out = widget.stack(0u64, looks.size_style(160.0, 24.0), col[0usize..2usize])
        ret ok
    }
    if index == 14usize {
        // v3's five tags S M E L V, the capture's pixels (artwork)
        let (tags, tags_error) = gl.pixels(a, vg_legality(), vg_legality_w(), vg_legality_h())
        if tags_error != ok { ret tags_error }
        // the tags' last pixel row lies on the row's hairline, under the tags only
        let (foot, foot_error) = gl.pixels(a, foot_pixels(), vg_legality_foot_w(), vg_legality_foot_h())
        if foot_error != ok { ret foot_error }
        let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
        if pair_error != ok { ret pair_error }
        pair[0usize] = widget.positioned(0u64, 0.0, 1.0, style.defaults(), mem_one_node(a, tags))
        pair[1usize] = widget.positioned(0u64, 41.0, 18.0, style.defaults(), mem_one_node(a, foot))
        *out = widget.stack(0u64, looks.size_style(160.0, 17.0), pair[0usize..2usize])
        ret ok
    }
    *out = widget.spacer(0u64, 1.0)
    ret ok
}

// The idle cell: plain text, in Tahoma under the Windows look (v3 draws an editor only in the
// focused row).
fn editor_of(ctx: *void, a: *mem.Arena, index: usize, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    if windows_rows && (index == 9usize || index == 10usize || index == 11usize || index == 13usize || index == 14usize) { ret computed_editor(a, t, index, out) }
    var made: widget.Node = zero
    var made_error: err = ok
    if t.tokens.profile == .Windows {
        let (tahoma, tahoma_error) = control.windows_tahoma_theme(a, t, 11.0)
        if tahoma_error != ok { ret tahoma_error }
        let (copies, copies_error) = mem.alloc[control.Theme](a, 1usize)
        if copies_error != ok { ret copies_error }
        copies[0usize] = tahoma
        let (node, node_error) = control.text(a, 0u64, values(index), &copies[0usize], control.text_options())
        made = node
        made_error = node_error
    } else {
        let (node, node_error) = control.text(a, 0u64, values(index), t, control.text_options())
        made = node
        made_error = node_error
    }
    if made_error != ok { ret made_error }
    *out = made
    ret ok
}

fn grid(a: *mem.Arena, t: *const control.Theme, key: widget.Key, collapsed: []const widget.Key) -> (widget.Node, err) {
    foot_pressed = false
    let source = collection.PropertySource { ctx: mem.cast[*void](t), count: count_of, property: property_at, editor: editor_of }
    var options = collection.property_grid_options()
    options.selected = NAME_KEY + u64(pick.selected)
    options.height = 425.0
    let (made, made_error) = collection.property_grid_of(a, key, t, "Deck properties", source, collapsed, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, 164.0, 330.0, options)
    ret (made, made_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    shapes(t.tokens.profile == .Windows)
    desktop = t.tokens.profile == .Windows
    let (shut, shut_error) = mem.alloc[widget.Key](a, 2usize)
    if shut_error != ok { ret (0usize, shut_error) }
    shut[0usize] = collection.property_group_key("General")
    shut[1usize] = collection.property_group_key("Computed")
    let (left, left_error) = grid(a, t, 1000u64, shut[0usize..0usize])
    if left_error != ok { ret (0usize, left_error) }
    let (right, right_error) = grid(a, t, 2000u64, shut[0usize..2usize])
    if right_error != ok { ret (0usize, right_error) }
    cells[0usize] = looks.Cell { caption: "Deck Properties: all categories open, Name focused", node: left, drive: .None }
    cells[1usize] = looks.Cell { caption: "General and Computed shut", node: right, drive: .None }
    ret (2usize, ok)
}

// ---- sheet 2: vertical_grid_states, the five interaction states of Deck Properties ---------------------------------
// ref/windows/vertical_grid_states.png: crops of states/vertical-grid-*-deck-properties-*@1x.png at (16, 79), 330 x 425,
// laid out as the sheet lays out its cells (three to a row). Name focused (its text selected), Author selected, Description
// selected with the open editor's ellipsis button, Archetype selected (the combo editor shows no button at rest), and the
// General category pressed (shut, with the focus rectangle on its caption).

type StateCtx = struct { t: *const control.Theme, mode: usize }

fn state_editor(ctx: *void, a: *mem.Arena, index: usize, out: *widget.Node) -> err {
    let c = mem.cast[*const StateCtx](ctx)
    var plain: widget.Node = zero
    let plain_error = editor_of(mem.cast[*void](c.t), a, index, &plain)
    if plain_error != ok { ret plain_error }
    *out = plain
    if c.t.tokens.profile != .Windows { ret ok }
    if c.mode == 0usize && index == 0usize {
        // the text selected: #0078D7 under white text, 2 in and 2 down
        let (tahoma, tahoma_error) = control.windows_tahoma_theme(a, c.t, 11.0)
        if tahoma_error != ok { ret tahoma_error }
        let (copies, copies_error) = mem.alloc[control.Theme](a, 1usize)
        if copies_error != ok { ret copies_error }
        copies[0usize] = tahoma
        let (white, white_error) = control.colored_text(a, 0u64, values(0usize), &copies[0usize], control.text_options(), gl.raw(0xFFFFFFu32))
        if white_error != ok { ret white_error }
        var mark = style.defaults()
        mark.background = paint.Brush { Solid: gl.rgb(0x0078D7u32) }
        mark.height = style.Length { Px: 13.0 }
        mark.width = style.Length { Px: 52.04 }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret held_error }
        held[0usize] = white
        *out = widget.padded(0u64, 2.0, 2.0, 0.0, 0.0, style.defaults(), held[0usize..1usize])
        let (marked, marked_error) = mem.alloc[widget.Node](a, 1usize)
        if marked_error != ok { ret marked_error }
        marked[0usize] = widget.padded(0u64, 2.0, 0.0, 1.0, 0.0, mark, held[0usize..1usize])
        *out = widget.padded(0u64, 0.0, 0.76, 0.0, 0.0, style.defaults(), marked[0usize..1usize])
    }
    if c.mode == 2usize && index == 6usize {
        let (button, button_error) = gl.pixels(a, gl.gx_ellipsis_button(), gl.gx_ellipsis_button_w(), gl.gx_ellipsis_button_h())
        if button_error != ok { ret button_error }
        let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
        if pair_error != ok { ret pair_error }
        pair[0usize] = widget.spacer(0u64, 1.0)
        pair[1usize] = widget.padded(0u64, 0.0, 1.0, 2.0, 0.0, style.defaults(), mem_one_node(a, button))
        var row = style.defaults()
        row.width = style.Length { Percent: 100.0 }
        *out = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, row, pair[0usize..2usize])
    }
    ret ok
}

fn mem_one_node(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (nodes, nodes_error) = mem.alloc[widget.Node](a, 1usize)
    if nodes_error != ok { ret zero }
    nodes[0usize] = node
    ret nodes[0usize..1usize]
}

fn state_grid(a: *mem.Arena, t: *const control.Theme, key: widget.Key, mode: usize) -> (widget.Node, err) {
    let (ctxs, ctxs_error) = mem.alloc[StateCtx](a, 1usize)
    if ctxs_error != ok { ret (zero, ctxs_error) }
    ctxs[0usize] = StateCtx { t: t, mode: mode }
    foot_pressed = mode == 4usize
    let source = collection.PropertySource { ctx: mem.cast[*void](&ctxs[0usize]), count: count_of, property: property_at, editor: state_editor }
    var options = collection.property_grid_options()
    options.height = 425.0
    var selected = NAME_KEY
    if mode == 1usize { selected = NAME_KEY + 1u64 }
    if mode == 2usize { selected = NAME_KEY + 6u64 }
    if mode == 3usize { selected = NAME_KEY + u64(archetype_index()) }
    if mode == 4usize { selected = collection.property_group_key("General") }
    options.selected = selected
    let (shut, shut_error) = mem.alloc[widget.Key](a, 1usize)
    if shut_error != ok { ret (zero, shut_error) }
    shut[0usize] = collection.property_group_key("General")
    var closed = shut[0usize..0usize]
    if mode == 4usize { closed = shut[0usize..1usize] }
    let (made, made_error) = collection.property_grid_of(a, key, t, "Deck properties", source, closed, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, 164.0, 330.0, options)
    ret (made, made_error)
}

fn build_states(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    shapes(t.tokens.profile == .Windows)
    let captions = [5]str{ "Name focused, text selected", "Author selected", "Description selected, editor button", "Archetype selected", "General pressed" }
    var i = 0usize
    while i < 5usize {
        let (node, node_error) = state_grid(a, t, u64(3000usize + 1000usize * i), i)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (5usize, ok)
}

// The states of the captures (states/vertical-grid-*): the Author row selected, and General shut with Computed open (what the
// press on the General caption leaves). One cell each, 330 x 425, the grid as in the first sheet.
fn build_state(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    shapes(t.tokens.profile == .Windows)
    let (shut, shut_error) = mem.alloc[widget.Key](a, 2usize)
    if shut_error != ok { ret (0usize, shut_error) }
    shut[0usize] = collection.property_group_key("General")
    var closed = 0usize
    if pick.shut { closed = 1usize }
    let (one, one_error) = grid(a, t, 1000u64, shut[0usize..closed])
    if one_error != ok { ret (0usize, one_error) }
    cells[0usize] = looks.Cell { caption: "State", node: one, drive: .None }
    ret (1usize, ok)
}

fn main_states(a: *mem.Arena) -> err {
    control.set_dx_text(true)
    pick.selected = 1usize
    let author = looks.Sheet { name: "vertical_grid_author", cells: 1usize, columns: 1usize, cell_w: 330.0, cell_h: 425.0, ctx: zero, build: build_state }
    try looks.run_all(a, &author)
    pick.selected = 0usize
    pick.shut = true
    let shutg = looks.Sheet { name: "vertical_grid_shut", cells: 1usize, columns: 1usize, cell_w: 330.0, cell_h: 425.0, ctx: zero, build: build_state }
    ret looks.run_all(a, &shutg)
}

// looks5-e: the five hover captures of Deck Properties (states/hover-vertical-grid-*: caption of Author, the General category's
// collapse button, the Archetype value cell, the Description value cell, the Name value cell); v3 shows no hover look on any of
// them (all five are pixel-identical to the rest grab), so the grid at rest with the pointer over those places must not change.
fn build_hover(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    shapes(t.tokens.profile == .Windows)
    let captions = [5]str{ "Hover: caption of Author", "Hover: General category button", "Hover: Archetype value", "Hover: Description value", "Hover: Name value" }
    var k = 0usize
    while k < 5usize {
        let (shut, shut_error) = mem.alloc[widget.Key](a, 1usize)
        if shut_error != ok { ret (0usize, shut_error) }
        shut[0usize] = collection.property_group_key("General")
        let (node, node_error) = grid(a, t, u64(1000 + k * 1000), shut[0usize..0usize])
        if node_error != ok { ret (0usize, node_error) }
        var px: f32 = 80.0
        var py: f32 = 50.0
        if k == 1usize {
            px = 318.0
            py = 11.0
        }
        if k == 2usize {
            px = 250.0
            py = 283.0
        }
        if k == 3usize {
            px = 250.0
            py = 145.0
        }
        if k == 4usize {
            px = 250.0
            py = 31.0
        }
        looks.aim(k, px - 165.0, py - 212.5)
        cells[k] = looks.Cell { caption: captions[k], node: node, drive: .Hover }
        k += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    control.set_dx_text(true)
    if args.len > 1usize && args[1usize][0usize] == 104u8 {
        let hover = looks.Sheet { name: "vertical_grid_hover", cells: 5usize, columns: 3usize, cell_w: 330.0, cell_h: 425.0, ctx: zero, build: build_hover }
        ret looks.run_all(a, &hover)
    }
    // `vertical_grid.exe a` renders the Author and shut sheets, `s` the states sheet
    if args.len > 1usize && args[1usize][0usize] == 97u8 { ret main_states(a) }
    if args.len > 1usize {
        // `vertical_grid.exe states`: the states sheet alone
        let states = looks.Sheet { name: "vertical_grid_states", cells: 5usize, columns: 3usize, cell_w: 330.0, cell_h: 425.0, ctx: zero, build: build_states }
        ret looks.run_all(a, &states)
    }
    let sheet = looks.Sheet { name: "vertical_grid", cells: 2usize, columns: 2usize, cell_w: 330.0, cell_h: 425.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}

// v3 artwork of the Computed rows, cut from the Deck Properties grab (states/vertical-grid-author-deck-properties, at (16, 79)); RGB per pixel.
fn vg_colors() -> str { ret "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEF8E6FAE9B5F6DC8AF7D875F7D975F6DA7DF6DA7FF6D976F6D772F6DB81F9E5A7FDF5DAFFFEFBFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEAEAEAB9BBBE8F9398777D846D757C697078676F776B737971787F858B90AAADB1DDDEDFFBFBFBFFFFFFFFFFFFFFFFFFFFFFFFFFFEFEFDF8F8F5E1DFE8B7B3DD928CDA7F76DA7C73DA837BDA847CDA7D75D97C73DB8982E3A9A4F1D2CFFAF1F0FEFCFCFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE8F7E8B6E4B789D48970CD6F6BCB696FCC6F70CB706BCB6A6BCB697DD07DA5DEA6DAF2D9FAFDFAFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEF8E6F7DF94F5D56EF7DC84FBE79FFEEEB1FFF2BEF2E6B5FCEDB0FCE89FF7DE85F5D469F6DA82FCF3D4FFFEFAFFFFFFFFFFFFFFFFFFFFFFFFEAEAEA999DA06E747B6F777E8C939AA3A9AEAEB2B5AEB1B5A7ABAF92999F747B83676F76858A8FD7D8D9FBFBFBFFFFFFFFFFFFFFFEFEFCF7F7F4DCD9E2A49FDB8880E0938CE8A199EEADA5F1B8B0F2B8B0EFAEA5EAA198E19189DA827ADD938DEFCBC8FAF1F0FEFDFDFFFFFFFFFFFFFFFFFFE8F7E896D99768C96776CF738EDB889FE2969AD192A0D7989FE19690DC8978D17462C8617ED07FD1EFD1FAFDFAFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEF8E6F7DF94F5D56CFAE495FEF0B8FFF2BBFFF1B8BFB58BCCC091F8E9AEFFF0B0FFEEAEFBE593F6D468F6DA81FCF3D4FFFEFBFFFFFFFFFFFFEAEAEA999DA1697178848B929CA0A4848689707273707172707171747576999B9DA3A7AB8A9198666E7684898DD7D8D9FBFBFBFFFFFFFDF9F8F4DDDBE1A09BDB827AE69990EAAEA7D9A39BBE8E87AE817A946D67A67872D3968EEBA69DE6958BDA7D74DD908AEFCECBFBF3F3FFFEFEFFFFFFE8F7E896D89764C86385D77EA6E59CA5E29B749E6D4B66474D694878A9708CC68297D98C85D97C5FC75C7CCF7DD1EFD1FAFDFAFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF9E39DF4D265FCE593D8CB94F8E9AAFFEFACD9CB924A4532978C63F2E19CFFEDA1FFEC9FFFEC9DFDE58BF4D15EF7DC84FEFAEEFFFFFFFFFFFFA5A8AA656D74899096A0A4A7868687383838101010080808060606121212484848939394A6A9AC8F969D6169718A8F93EDEEEEFFFFFFF8ECEBE4ABA6D87D75E6958CDD9C938E6661825C56A8736B8056503E29265E3D396D4944BB7B71DB8E83E48C80D8766CDF9892F3DCDAFEFBFBFFFFFFA2DDA25EC55E83D87A87C37D6E9C66638E5C1F2C1C0304030000002637233A5636537C4B81CA7580D97356C45480D180E9F7E9FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDF6DFF3D164F9DF82FEEBA093895EADA06EC7B87DCCBC7C1E1C1247412BE5D286A69862968A58C9B872F8E289FBDF79F2CD54FBEFC4FFFDF9E3E4E4696F757B838A9A9EA268696A4040410E0E0E0101010000000000000000000505053A3A3A6F6F709B9EA2858C93596068C6C9CAF9FAFAEFCCC9D7817AE18A80EC9D92B2766D5C3A368A564FCE8378B16F6571453F9B5D5551302B583631A9645ADB8174E07D71D5756CE7B3AFFBF4F3E1F5E064C66674D26E92E0854567401A2617141E120405030000000000000000000000000B120A4C7E437ACF6B6FD3644EBF4FBEE8BFF8FDF8FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF9E39BF4D264FDE68FFFEA9570674138342149432BAB9D61423C23332E1AB5A360322D1B3D371EB7A55BF7DF7AFFE47CF4D059F7DC82FEFAEDA5A8AB676F778D949A727375141414111111090909010101000000000000000000050505010101151515858586969B9F626A738A8F93EDEEEEE19D97D7776EE78E83EC9285BE7367BC6F64E48779D87E71A15D5470413AB7675C7E463E1A0E0C753F37AB5B51DC7668D66E63D9847DF8EAE9A1DDA05EC55D81D97687D9781C2D190101010000000000000000000000000000000000000000001424125CAA4F72D56152C34E80D27FE9F7E9FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF4D56EF9DA6DFEE686FFE787AE9D5963593039331B4D452737321C332E1A685D3224201087783CDDC563FCE06EFFE26DF9D75FF3CE56FDF7E4757A7F777F879DA1A52F30300B0B0B2828281919190303030000000000000000001A1A1A2424240808084848489093967880885F666CE3E5E6D67D76DB746AE88476EB8475EB8272EB8070EA7E6EEA7C6CAF5A4E954B40C060527C3E35130908331A165A2C25CD6152DA675BCF635AF6E3E172CA7363CB5D7AD96C55924A111D0F0101010000000000000D190B0306021428100509040000000000002951225DBF4C58CB4D54C254DEF3DFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF1CE61FCDE6EE5CE6EFBE077C6B15E8C7D426C6031252111040302000000242010272210897938766831C3AB4CF8D95CFCDA59F1C949FDF6E261686F838A90A4A6A81D1D1D4C4C4C7E7E7E6B6B6B2121210303030000002525256565657676764646461C1C1C868889878F954F575FE0E1E2D1726BDE7063E77868E97666E97463E87261DD6B5ADB6858E56B59DC6554A84E41903F3455231C0D05042F1310C55141DC5C4DCB574DF5E1DF60C26663CD596CCD5C1D37190204020000000C190909140810210E030703204219070F060000000000000305024AAB3955CE4342BB43DAF1DBFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0CD5FFCDE68C8B15590803F473E1F322C144B421E0C0A050000000000000000001513082F291127220C6D5E24DEC047FBD94FF0C746FCF6E25C636A858C93A2A3A51D1E1E878787A6A6A6A6A6A64B4B4B0B0B0B000000606060999999A0A0A07979791D1D1D8182838E959A4B545DDFE0E2D07069DD6B5CE56B59E76956E16552A3493C73342B6C302779352B6E2F2653211A7F3226732D22130706441712C84735DB5241C9544AF5E0DF5CBF635ECC535EC44D13280F0001000000001A3A14142D100307020000000E200A0E240A0307020000000000003C9D2B4CCB383DB83FD9F0DAFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF1CE61FBD95AE1C5525F53204A4018655720584D1C0D0B040000000000000000002C260D534718907B2AA0892EDCBD40F8D448F1C846FCF6E260676E7E868D9A9C9E3333344747475656565757573030302A2A2A1212124040405252525353533F3F3F373737858889868D944E565EDFE1E2D1726AD95F50E25D4AE45B47A743343415100502020000000000001607057B2A1E551D15250D09150705862C1FD44632D94D3CCA544AF5E1DF60C26552C84751BC3F11270D00010003090310290D15370F040A03000000060F04173D1013340D0F2B0A040C0334922445C5333FB940DAF1DBFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF4D46CF7D24FFEDB50D3B641CCAF3E8875294B4117362E10211C091D19081D19083D3411937E2ADDBE40FBD849F8D548F7D147F3CD52FDF7E473787E6F777F9094996D6E6E4D4D4D4040400B0B0B0404044949493C3C3C0909090B0B0B3E3E3E4B4B4B737373909397737C845C636AE3E4E5D67B74D5594CDE523FE24F3A4D1B140803020000000000000000006A2319AA372732100C1407055C1E15963123D34633D55143CE5E55F6E3E170CA724AC34146BC331944110A1B061C4E142364181C4C13050D030000000F2C0B29731C349224339023276D1B3EAE2B43C3364FC04EDEF3DEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF9E297F3CD50FDD84AFFDB4AF9D548463C143830108D7929342D0F41381366581D1D19083C3412BBA136F8D548FEDA4AF4CB46F7DA7CFEFAECA1A4A75F6870888E949395969898989090901B1B1B0606063737373939390909091C1C1C85858599999995969690959B5D666F858A8EECEDEDE09A94D3655ADB4F3DE04A352C0E0A0100000000000000000000005F1F16531B130D04031306045A1E15832B1FCD4635D25B4FD87E77F8E9E89DDC9C4CC04947C934379A262D7E1F3DAD2A48C9312C7C1E07130500000024661944BE2E49CD3249CD3249CD3249CC3240BF3A7AD078E8F7E8FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDF5DBF3CF5EF9D349F2CF46C3A739493E15867327CDB03B26200B383010B79D35897628453B14B79E35F7D548FAD448F2CA4AFBEDBFFFFDF8E0E1E1656B71747C838E92969596979898981D1D1D0505051414140F0F0F0808082121218686869797979396997B828A545C64C2C4C6F9F9F9EEC9C6D67C75D65648DD4C394C1912080302000000000000000000000000200B0732100B3E140E612017B73E2DD34F40D26A61E6B0ACFBF3F3DDF3DD5FC46045C43948CB3349CD3249CD3244BE2F3088210817060000002B781D45C22F49CD3249CD3249CD3246C83544BC44BBE6BAF7FCF7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF8E197F3CD4FEBC744C1A538A48D30D4B63DEBCA44564A19443A14E3C342FFDB4AB89E36E3C342F9D448F4CC46F6D97BFEFAECFFFFFFFFFFFF9EA2A55E666D787F879094979596971818181B1B1B1313131C1C1C1A1A1A24242483848593969982898F5B636C83888CECECEDFFFFFFF8EBEAE3A7A2D36A61D75444993628280E0A03010100000000000000000040150F802A1DAC3928D04633D8503ED25E53DD9089F2D9D7FDFBFBFFFFFF9BDB9C4CC04A45C53648CC3342BA2D3391241C4F13061104000100174210318A2240B42C47C93147C93441BE3C78CE78E8F7E8FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEF8E3F6DD8CF3CD4FF9D348FED949FFDB4AF9D5489C862DA58D30F2D046FFDB4AF0CE46F8D248F4CC46F5D776FCF2D0FFFEFAFFFFFFFFFFFFE7E7E89195995F666F767E858B90953C3E405556574849496061614E4E504F5052868A8D7D838B5C666E7B8186D3D4D5FAFAFAFFFFFFFCF8F8F3DBD8E09C96D3695FD05243893126591F174E1A134D1912531B13832B1FB83D2CD84936D85040D25E52DB8881EEC9C6FAF1F0FEFDFDFFFFFFE5F6E58DD58F4BC04944C53740B52D379A2628701B1D52141F56151A4B122B771D3AA42943C13441BE3B71CB71CDEDCDF9FDF9FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEF8E3F6DD8DF4CE53F6CF47F9D348F5D147D8B93FF8D448FDD849FAD448F7D147F4CD4AF5D777FCF2D0FFFEFAFFFFFFFFFFFFFFFFFFFFFFFFE7E7E891959A62697167707961686E797E837E81868E9296797E8370777E6C747C5D656D7B8186D3D4D5FAFAFAFFFFFFFFFFFFFFFEFEFCF6F6F3D9D6E09D98D46F66D45B4EC44C3EBD4334BE4131C54332D74B39D85040D55749D3655BDB8C86EEC8C5FAEFEEFEFCFCFFFFFFFFFFFFFFFFFFE5F6E48ED59052C24F43C13A44C63643BE323FB32C45C1303DAD2C3FB5313EB53545BC4172CB73CCEDCCF9FDF9FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEF8E3F9E6AAF5D87CF4D058F5CF4AF6CF47F6CF47F5CE48F4CE51F4D570F7E19BFDF3D5FFFEFAFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE7E7E8AFB1B482878C686F76636B73676E77686F78636B73626A72767C829DA1A5D8D9DAFAFAFAFFFFFFFFFFFFFFFFFFFFFFFFFFFEFEFCF6F6F3DCD9E5B1ACDA8982D3665DD05549D05144D05043D05346D15F54D77C75E1A29DF1D1CEFBF1F0FEFCFCFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE6F6E5ACE0AD7CCF7C56C45446C04142C03A41C03944C03D4DC14A6CC96C97D898D4F0D3F9FDF9FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF" }
fn vg_colors_w() -> f32 { ret 160.0 }
fn vg_colors_h() -> f32 { ret 17.0 }
fn vg_strip() -> str { ret "909090909090909090909090909090909090909090F2F2F2FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDCB685AFCFE9F2F9FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDCB6867F786F6F6F6F6F6F9FC5E7F1F8FFFFDCB7867F786F6F6F6F6F6F9FC4E7F0F8FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF6F6F626F6F626F6F626F6F626F6F626F6F620D0D0CE0E0E0FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE1FFFFE1FFFFE1FFFFE1FFFFE19D9D8B737371EEEEEEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF2F2D6FFFFE1FFFFE1FFFFE1FFFFE11E1E1AE0E0E0FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE1E1C7FFFFE1FFFFE1FFFFE19D9D8B737371EEEEEEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF8D8071F2F2D6FFFFE1FFFFE11E1E1ADC8380F99491F99591F79591F79591F69691F69691F59691F49791F49791F39791F39791F29891F19991F19991F09991EE9A91EE9A91ED9A91ED9A91EC9B91EB9B91EB9B91EA9C91EA9C91E99D91E89D91E89D91E79D91E69E91E69E91E59F91E49F91E49F91E2A091E2A091E1A091E1A091E0A191DFA191DFA191DEA291DEA291DDA391DCA391DCA391DBA491D9A491D9A491D8A591D8A591D7A591D6A691D6A691D5A691D5A691D4A791D3A891D3A891D2A891D1A991D1A991D0A991CFA991CFAA91CDAA91CDAA91CCAB91CCAB91CBAB91CAAC91CAAC91C9AC91C9AC91C8AD91C7AE91C7AE91C6AE91C4AF91C4AF91C3AF91C3B091C2B091C1B091C1B091C0B191C0B191BFB291BEB291BEB291BDB391BCB391BCB391BAB491BAB491BAB491B8B591B8B591B7B591B7B691B6B691B5B791B5B791B4B791B3B891B3B891B2B891B2B991B1B991B0B991B0B991AEBA91AEBA91ADBB91ACBB91ACBB91ABBB91ABBC91AABC91A9BD91A9BD91A8BD91A7BE91A6BE91A5BE91A5BF91A5BF91A3BF91A3BF91A2C091A2C091A1C191A0C191A0C1919FC1919EC2919DC2919DC3919DC3919CC3919BC4919AC49199C49199C59198C59197C69197C69196C69195C79195C79194C79194C79193C89192C89191C8911E0000E1E1C7FFFFE19E9E8C6E130FE20600F20600F00800ED0900ED0900EA0A00EA0A00E80C00E50D00E50D00E30E00E30E00E01000DE1100DE1100DB1200D81300D81300D61500D61500D31600D11700D11700CE1900CE1900CB1A00C91B00C91B00C61C00C41E00C41E00C11F00C11F00BF2000BC2200BC2200B92300B92300B72400B42500B42500B22700B22700AF2800AD2900AD2900AA2B00A72C00A72C00A52D00A52D00A22F00A03000A030009D31009D31009B32009834009834009535009336009336009038009038008E39008B3A008B3A00893B00893B00863D00833E00833E00813F00813F007F41007C42007C42007A43007745007645007446007446007247006F48006F48006D4A006C4A006A4B00684C00674C00654E00624F00624F006050005F50005D51005B53005A53005854005854005655005357005257005058004E59004D59004B5B004B5B00495C00465D00465D00445E00435E004160003E61003E61003C62003B62003964003765003665003466003267003167002F69002E69002C6A002A6B00296B00276D00276D00256E00226F00216F001F70001D72001C72001A73001A73001874001576001576001377001277001078000D7A000D7A000B7B00087C00087C00067D00057D00037F000180000080007C01008D8171F2F2D61E1E1AD80400F20600F20600F00800ED0900ED0900EA0A00EA0A00E80C00E50D00E50D00E30E00E30E00E01000DE1100DE1100DB1200D81300D81300D61500D61500D31600D11700D11700CE1900CE1900CB1A00C91B00C91B00C61C00C41E00C41E00C11F00C11F00BF2000BC2200BC2200B92300B92300B72400B42500B42500B22700B22700AF2800AD2900AD2900AA2B00A72C00A72C00A52D00A52D00A22F00A03000A030009D31009D31009B32009834009834009535009336009336009038009038008E39008B3A008B3A00893B00893B00863D00833E00833E00813F00813F007F41007C42007C42007A43007745007645007446007446007247006F48006F48006D4A006C4A006A4B00684C00674C00654E00624F00624F006050005F50005D51005B53005A53005854005854005655005357005257005058004E59004D59004B5B004B5B00495C00465D00465D00445E00435E004160003E61003E61003C62003B62003964003765003665003466003267003167002F69002E69002C6A002A6B00296B00276D00276D00256E00226F00216F001F70001D72001C72001A73001A73001874001576001576001377001277001078000D7A000D7A000B7B00087C00087C00067D00057D00037F00018000008000FA03001D00008080716F130FE50500F20600F20600F00800ED0900ED0900EA0A00EA0A00E80C00E50D00E50D00E30E00E30E00E01000DE1100DE1100DB1200D81300D81300D61500D61500D31600D11700D11700CE1900CE1900CB1A00C91B00C91B00C61C00C41E00C41E00C11F00C11F00BF2000BC2200BC2200B92300B92300B72400B42500B42500B22700B22700AF2800AD2900AD2900AA2B00A72C00A72C00A52D00A52D00A22F00A03000A030009D31009D31009B32009834009834009535009336009336009038009038008E39008B3A008B3A00893B00893B00863D00833E00833E00813F00813F007F41007C42007C42007A43007745007645007446007446007247006F48006F48006D4A006C4A006A4B00684C00674C00654E00624F00624F006050005F50005D51005B53005A53005854005854005655005357005257005058004E59004D59004B5B004B5B00495C00465D00465D00445E00435E004160003E61003E61003C62003B62003964003765003665003466003267003167002F69002E69002C6A002A6B00296B00276D00276D00256E00226F00216F001F70001D72001C72001A73001A73001874001576001576001377001277001078000D7A000D7A000B7B00087C00087C00067D00057D00037F00018000008000FA03007C01000D0000DA0400F50500F20600F20600F00800ED0900ED0900EA0A00EA0A00E80C00E50D00E50D00E30E00E30E00E01000DE1100DE1100DB1200D81300D81300D61500D61500D31600D11700D11700CE1900CE1900CB1A00C91B00C91B00C61C00C41E00C41E00C11F00C11F00BF2000BC2200BC2200B92300B92300B72400B42500B42500B22700B22700AF2800AD2900AD2900AA2B00A72C00A72C00A52D00A52D00A22F00A03000A030009D31009D31009B32009834009834009535009336009336009038009038008E39008B3A008B3A00893B00893B00863D00833E00833E00813F00813F007F41007C42007C42007A43007745007645007446007446007247006F48006F48006D4A006C4A006A4B00684C00674C00654E00624F00624F006050005F50005D51005B53005A53005854005854005655005357005257005058004E59004D59004B5B004B5B00495C00465D00465D00445E00435E004160003E61003E61003C62003B62003964003765003665003466003267003167002F69002E69002C6A002A6B00296B00276D00276D00256E00226F00216F001F70001D72001C72001A73001A73001874001576001576001377001277001078000D7A000D7A000B7B00087C00087C00067D00057D00037F00018000008000D34646D34646554546C14746D14846CF4846CF4846CE4946CC4A46CC4A46CA4A46CA4A46C94B46C84C46C74C46C64D46C64D46C54E46C34E46C34E46C24F46C05046C05046BF5146BF5146BD5146BC5246BC5246BA5346BA5346B95346B85446B75446B65546B55646B55646B35646B35646B25746B05846B05846AE5946AE5946AD5946AC5A46AB5A46AA5B46AA5B46A95B46A85C46A75C46A65D46A45E46A45E46A35E46A35E46A15F46A06046A060469F61469E61469D61469C62469B62469A63469963469964469765469765469665469466469466469366469366469167469068468F68468F69468E69468D6A468C6A468B6A468A6B46886C46886C46876D46876D46856D46846E46846E46836F46826F46816F468070467F70467E71467D72467D72467B72467B72467A73467874467874467775467775467675467476467476467377467177467178467078467079466E79466D7A466D7A466B7A466B7A466A7B46687C46687C46677D46667D46657E46647E46647E46637F46617F46617F465F80465F81465E81465C82465C82465B83465B83465A83465884465884465785465586465586465486465486465287465188465188464F88464F89464E89464C8A464C8A464B8B464A8B46498B46488C46488C46478D46458E46458E46" }
fn vg_strip_w() -> f32 { ret 160.0 }
fn vg_strip_h() -> f32 { ret 11.0 }
fn vg_land() -> str { ret "FFFFFFFFFFFFFFFFFFFFFFFFF9F9F8ECEBE6E3E2DBE0DFD8E0DFD8E2E1DAEAE9E3F7F7F5FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFBFBFAEEEEE9E0DFD7D6D5C9D4D3C7D5D4C8D6D5C9D3D2C6D4D4C8DDDCD3EBEBE5F9F9F8FEFEFEFFFFFFFFFFFFFFFFFFFCFBFAEAE9E3D7D5CAD7D6CBDFDED4E4E3DBEBEBE3EDEDE5E8E8DFE0E0D6D6D5C9D4D3C6E6E5DEF8F8F7FEFEFEFFFFFFFFFFFFEBEAE4D6D5C9DAD9CDE7E7DDDAD9D1C0BFB9DEDDD5E9E9E0E9E9E0E9E8DFE5E5DAD9D8CBD4D2C6E5E5DEFCFCFBFFFFFFF9F9F7D3D2C6D8D6CAE6E5DAE5E5DBB0AFA8726F6DB7B5AFE5E4D9E5E5DAE5E4D9E4E4D8E1E1D5D5D4C7D1D0C4F3F3EFFFFFFFE6E5DECCCBBDE1E0D4E5E4D9D9D8CE84827C3935357F7D79DBD9CDE0DFD3DADACDDAD9CDDEDED1DCDBCDCBCABCE1DFD7FEFEFED0CEC1D4D3C4E1E0D3E1E0D3C5C3B8615F5A2824254A4745B5B4AAD4D3C5ACAAA0B0AEA3D4D3C4DAD9C9D0CEBFCDCBBEFDFDFDC4C2B3D9D8C9DDDCCED9D8C9A3A19644403E2420212A26276E6C669D9A915F5C586E6B65BFBDAED5D4C3D2D1C0C4C2B3FDFDFCC0BFB0D8D7C8D9D8C8C2C1B36F6C662D2929231F20231F2034302F4A45432E2A2A413E3C9A988CCDCCBAD1D0BDC2C0B0FDFDFCC2C0B2D1D0C0C6C4B589867D3D3A38232020231F20231F20231F20241F21231F202A2727625F59ADAB9CC9C7B5C3C1B2FDFDFCCCCABDC7C6B6A09E924C4945282425232021231F20231F20231F20231F20231F20241F2036323177756DB9B7A9CBC9BAFDFDFDE1E1D9C2C0B19D9B8F5D5A54423E3C3531312F2B2B2A26272825252C2828322D2D3A36344B464478766EB4B3A5DCDBD1FEFEFDF7F7F5CDCBBEBAB9A9A4A2938B897D76736C6966605D5A555956506360596F6B647F7C73969287ADAB9CC7C5B7F0F0ECFFFFFEFFFFFFE5E4DDCDCCBFC7C5B4C3C2B0BBBAA9B4B3A2ADAB9CAAA999B1AF9FB8B6A5BFBEADC3C2B1CBC9BAE2E0D8FBFBFAFFFFFFFFFFFFF9F8F7E4E4DDCFCDC0C9C8B6CBC9B7CECDB9CFCEBAD0CFBBCECDB9CBCAB8C9C8B6CCCBBCE1DFD7F6F6F4FEFEFEFFFFFFFFFFFFFEFEFEF9F9F7E8E8E2D9D8CDCCCBBDC9C7B6C8C7B5C8C7B5C8C6B5CBCABBD5D5C9E6E5DEF7F7F4FEFEFEFFFFFFFFFFFFFFFFFFFFFFFFFEFEFEFDFDFCF6F6F3E8E8E1E1E0D8DEDDD5DEDDD5E0DFD7E7E6DFF3F3F0FDFDFBFEFEFEFFFFFFFFFFFFFFFFFF" }
fn vg_land_w() -> f32 { ret 17.0 }
fn vg_land_h() -> f32 { ret 17.0 }
fn vg_crea() -> str { ret "FAFAFAFFFFFFFFFFFFFFFFFFFAFAF8ECECE6E4E3DCE0DFD8E0DFD8E2E1DAE9E9E3F7F7F4FFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFAFAFAFFFFFFFBFBFAEEEEE9E0E0D7D7D6CAD4D3C7D5D4C8D6D5C9D3D2C6D4D4C8DDDCD3EBEAE5F9F9F7FEFEFEFFFFFFFFFFFFFAFAFAFCFBFAEBEAE4D7D6CBD7D6CBE0E0D6E8E7DFECECE4EDEDE5E6E6DDDADAD1D1D0C5D3D2C6E5E4DDF8F8F6FEFEFEFFFFFFFAFAFAECEAE5D7D5CADAD9CDE7E7DDEBEBE2EBEAE2EAEAE1DCDCD4D1D0C9CAC9C2D1D0C7D5D4C8D2D0C4E4E4DDFBFBFAFFFFFFF4F4F3D5D3C7D7D6CAE5E4DAE8E8DEE7E7DCDAD9D0C5C4BBAAA8A1B1B0A9C0BEB6CDCBC1CCCBC1C3C2B6CCCBBFF2F1EEFEFEFEE2E1DACDCCBEE0DFD4E5E4D9E3E3D8CDCCC19B999286847E98958FBCBBB1BAB9AFB0AEA5AEACA3BBBAB0C5C3B6E0DED6FDFDFDCCCABED3D2C4E0DFD2E0DFD2C9C8BD87847E696663908D85B9B8ADA4A2998A898198968EB3B2A6CAC9BBCDCBBDCDCBBEFCFCFBC0BEB0D9D8C9DDDCCDCDCCBF87857E5B5754908E86B5B3A789877F65615D8E8C83BAB8ABC8C7B7C6C5B5CDCCBBC4C2B3FBFBFABDBBADD7D6C7D2D1C296958C4E4B487F7C74ABAA9D78756E4A47448A877DC0BEAEB9B7A9A9A79AB0AFA1C8C7B6C2C0B0FBFBFABFBDAFD2D1BFC4C3B36C6963413E3B87857C7270684D4A4787857BBDBBABA5A395959387A19F93BDBBABCAC9B7C3C1B2FBFBFAC8C7BACBCAB8C7C5B4918E8354504C514E4A5855508A897DAEAC9D8C897F89877CA8A798C6C5B2CFCEBBCAC9B6CBC9BAFCFCFBDDDCD5C7C5B5CECDBAC1C0AF726F68524E498D8C80979588706D657B7870B1AFA0CDCCB9D0CFBBCFCEBAC7C5B4DCDBD1FDFDFCF2F2F0CFCDC0C9C8B7C7C6B3969488959286ABA99B68655E706D66B3B1A1CFCDBAD0CFBBCFCEBACAC9B6CCCABCEFEFEBFEFEFEFAFAFAE6E5DECECDC0C7C5B4BDBCABC5C3B1B4B2A2807E74B4B2A2CFCEBAD0CFBBCFCEBACAC9B6CCCBBBE1E0D7FAFAF9FFFFFFFAFAFAF9F9F8E5E4DECFCEC0C9C8B7CBC9B7C6C4B2BDBCABCECDBACECDB9CBCAB8C9C8B6CCCBBCE0DFD6F6F6F3FEFEFEFFFFFFFAFAFAFEFEFEF9F9F8E9E8E2D9D8CECDCBBDC9C7B6C8C7B5C8C7B5C8C6B5CBCABBD5D4C9E5E5DDF6F6F4FEFEFEFFFFFFFFFFFFFAFAFAFFFFFFFEFEFEFDFDFCF6F6F3E9E8E2E1E0D8DEDDD5DEDDD5E0DFD7E6E6DFF3F3EFFCFCFBFEFEFEFFFFFFFFFFFFFFFFFF" }
fn vg_crea_w() -> f32 { ret 17.0 }
fn vg_crea_h() -> f32 { ret 17.0 }
fn vg_spell() -> str { ret "F7F7F8FFFFFFFFFFFFFFFFFFFAFAF8ECECE7E4E3DCE1E0D8E0DFD8E2E1DAE9E9E2F7F6F4FEFEFEFFFFFFFFFFFFFFFFFFFFFFFFF7F7F8FFFFFFFBFBFAEFEEEAE1E0D8D7D6CAD5D3C7D5D4C8D6D4C9D4D2C6D4D4C8DCDCD2EAEAE4F8F8F7FEFEFEFFFFFFFFFFFFF7F7F8FCFBFBEBEBE5D8D6CBD7D6CBDFDED4E1E1D8E2E2DAE3E2DBDEDED5D7D7CDD3D2C7D4D2C6E5E4DCF7F7F5FEFEFEFFFFFFF7F7F8ECEBE6D7D6CBDAD9CDE6E6DDDDDCD4B6B5B0A4A39EA3A19DA3A19CAEACA7D2D1C8D8D7CBD4D3C6E4E4DDFAFAF9FFFFFFF2F2F0D6D4C9D7D6CAE5E4DAE2E1D8B0AFA86561604B47474A464553504F86837FCBC9C0E0DFD3D6D5C8D1D0C4F1F0EDFEFEFEE0DFD9CECDBFE0DFD3E5E4D9D3D2C87E7B773430312520212C28285E5C57A9A79ED5D4C8DFDED1DCDBCDCCCBBDDFDED5FCFCFBCBC9BDD3D2C4E0DFD2E1E0D3CBCABE6E6A662D292A2B27285B5955A7A69BD2D1C3DBDACCDBDBCBDAD9C9D0CEC0CECCBEFAFAF9BFBDB0D8D7C8DDDCCDDCDCCDBBBAAE605C583632325F5D59A8A69BCCCBBCD7D6C6D7D7C6D7D6C5D6D5C4D2D1C0C4C3B4F9F9F8BCBBADD6D5C6D9D8C8D0CFC08E8C833D39384743418D8B82A09E929E9B90C1BFB0D0D0BED3D2BFD2D1BED1D0BDC2C1B1F9F9F8BEBCAFD1D0BFD1D0BEACAA9D5B58542E2A2A44403E65635D5B57534D4845817F75BAB8A8CFCEBAD0CFBBCECDB9C4C2B2F9F9F8C7C6BACBCAB8C7C6B4918F835F5B565C595365635C706D656C69613B3635615E58AEAD9DCECDB9D0CFBBCAC9B7CBC9BAFAFAF9DBDBD3C7C6B6C7C6B3AAA99AA19F91ABA99BB4B2A2B4B2A288867B605D57929084C2C1AFCFCEBACFCEBAC7C5B4DBDAD0FCFCFBEFEFEED1CFC2C8C7B5C9C8B5CCCBB7CFCEBACDCCB9B2B0A17E7C72979689C3C2B0CFCEBACFCEBACBC9B7CCCABCEEEEE9FEFEFDF7F7F8E7E6DFCFCEC0CAC9B7CECDB9CFCEBAC7C6B3A6A598A1A092C3C2B0CFCEBACFCEBACAC9B7CCCABBE0DFD6F9F9F8FFFFFFF7F7F8F9F9F8E5E5DFD0CEC1CAC8B7CBC9B7C5C3B2BABAAAC7C6B3CDCCB9CBCAB8C9C8B6CCCBBCDFDED5F5F5F2FEFEFEFFFFFFF7F7F8FFFFFFF9F9F8E9E9E3DAD9CECDCCBEC7C5B5C5C4B3C8C7B5C8C6B5CBCABBD5D4C8E5E4DDF6F6F3FEFEFEFFFFFFFFFFFFF7F7F8FFFFFFFFFFFFFDFDFDF6F6F4E9E8E2E1E0D8DEDDD6DEDDD5E0DFD7E6E6DFF2F2EFFCFCFBFEFEFEFFFFFFFFFFFFFFFFFF" }
fn vg_spell_w() -> f32 { ret 17.0 }
fn vg_spell_h() -> f32 { ret 17.0 }
fn vg_legality() -> str { ret "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEECECEEBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6EBC6C6CDE0BAC7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8C7E6B8F4FAF1FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFECC6C6E9BDBDE9BDBDE9BDBDE8BDBDE8BDBDE8BDBDE7BCBCE7BCBCE7BCBCE7BDBDE8BDBDE8BDBDE9BDBDE9BDBDE9BDBDE8BDBDE8BDBDE7BDBDE7BDBDE7BDBDE8BDBDE8BDBDE8BDBDE7BDBDE7BCBCE7BDBDE8BDBDE8BDBDE9BDBDE9BDBDE9BDBDE9BDBDE8BDBDE8BDBDE7BDBDE7BCBCE6BCBCE6BCBCE7BCBCE7BDBDE8BDBDE8BDBDE9BDBDE9BDBDC5DCB0BEE2ADBEE2ADBEE2ADBEE2ADBEE1ADBEE1ADBEE1ADBEE2ADBEE2ADBEE2ADBEE2ADBEE2ADBEE2ADBEE2ADBEE2ADBEE2ADBEE2ADBEE2ADBEE1ADBEE1ADBEE2ADBEE2ADBEE2ADBEE2ADBEE1ADBEE1ADBEE2ADBEE2ADBEE2ADF3FAEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE9BFBFE6B4B4E6B4B4E5B4B4E4B4B4E1B3B3DEB2B2DBB1B1DAB0B0DBB0B0DEB2B2E2B3B3E4B4B4E5B4B4E6B4B4E6B4B4E5B3B3E2B3B3DEB2B2DEB1B1DFB2B2E2B3B3E3B3B3E1B3B3DEB2B2DDB1B1DFB2B2E2B3B3E4B4B4E5B4B4E6B4B4E6B4B4E6B4B4E5B3B3E2B3B3DEB2B2DCB1B1DAB0B0DAB0B0DBB0B0DDB1B1E1B3B3E4B3B3E5B4B4E6B4B4BED7A5B6DEA2B6DEA2B5DEA2B4DBA1B3D9A1B3D8A1B4DAA1B5DDA2B6DEA2B6DEA2B6DEA2B6DEA2B6DEA2B6DEA2B6DEA2B6DEA2B5DDA2B4DBA1B3D9A1B3D9A1B4DBA2B5DDA2B5DCA2B4DAA1B3D9A1B4DAA1B5DCA2B5DEA2B6DEA2F1F9EDFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE7B7B7E3ABABE2ABABE1ABABDCA9A9D6A9A9D7B4B4DCC1C1DCC2C2DCBEBEDAB6B6DAAAAADFAAAAE2ABABE3ABABE3ABABE0AAAAD9A8A8E2C3C3E3C7C7DCB9B9D9AAAADAA9A9D6A7A7E1C2C2E3C7C7DFBFBFDAACACDFAAAAE2ABABE3ABABE3ABABE3ABABE0AAAAD9A8A8E2C2C2E1C7C7E0C6C6DFC6C6E1C7C7E3C8C8DBAEAEDEAAAAE2ABABE3ABABB6D39BADDB97ADDB97ACD896A9D296C4DFB7CAE1BEB1D5A0ACD697ADDA97ADDB97ADDB97ADDB97ADDB97ADDB97ADDB97ADDA97ACD896B1D69FC5DFB9C1DCB4ADD49BAAD596AAD396BBD9ACC8E0BCB7D8A7ACD798ADDA97ADDB97EFF8EBFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE4AFAFE0A2A2DFA2A2DAA1A1D19F9FDABDBDE8DBDBF1EBEBEEE8E8F1E9E9ECDEDED5A7A7D9A0A0DFA2A2E0A2A2E0A2A2DAA0A0CE9D9DF3E8E8F9F6F6EEE1E1CFA5A5CD9C9CCEA6A6F2EAEAF9F6F6EEE4E4D3A8A8D9A0A0DFA2A2E0A2A2E0A2A2E0A2A2DAA0A0CE9D9DF2E7E7F9F6F6F9F6F6F9F6F6F9F6F6FAF6F6D8ADADD9A1A1DFA2A2E0A2A2AFCE90A5D78CA5D78CA2D28B9EC88AE7F1E2F6F9F5B5D3A7A3CF8DA4D58CA5D78CA5D78CA5D78CA5D78CA5D78CA5D78CA5D68CA2D28BA9CE98E9F2E4EBF2E7ABCD9A9FCA8B9DC68ADAE8D3F4F8F2B9D6ACA4D08EA4D58CA5D78CEEF7E9FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE2A8A8DD9A9ADC9A9AD39696CDA3A3F0E8E8F9F7F7D9CFCFD1BFBFDDCCCCF0E6E6D1A1A1D59898DC9999DD9A9ADD9A9AD69898C59292F6EEEEFFFFFFFFFFFFCBADADBC9191DBC6C6FAF8F8FFFFFFF4F0F0CDA0A0D39797DC9999DD9A9ADD9A9ADD9A9AD69898C59292F5EDEDFFFFFFE2D9D9D9CBCBDDCCCCE2CECED19E9ED69898DC9999DD9A9AA8C9869DD3829DD38299CD8194BE7FECF3E8FFFFFFB3CEA59AC8839BD1829CD3829DD3829DD3829DD3829DD3829DD3829DD3829ACD8196C181E9F1E4FEFFFEAECAA195BE819BBE89ECF3E9FCFDFCA9CB9898C9819CD1829DD382ECF7E7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDFA1A1DA9292D89191CD8D8DCDA9A9F8F3F3F8F7F7BEACACAC8E8EAE8686C9A6A6C99191D29090D99191DA9292DA9292D18F8FBE8888F5EDEDFFFFFFFEFEFEE1D5D5B39393EFE8E8FDFDFDFFFFFFF3EEEEC69898CE8E8ED89191DA9292DA9292DA9292D18F8FBE8888F4EBEBFFFFFFCABABAB89D9DBE9D9DC59999CA8F8FD39090D99191DA9292A0C57C94CF7794CF7791C8778AB774EAF2E7FFFFFFABC89E91C37992CD7794CF7794CF7794CF7794CF7794CF7794CF7794CF7792CB778DBD75CCDEC3F8FAF7C5D6BD8FB27EAEC7A3F2F6F0E2EADD9AC38790C77694CE7794CF77EBF6E5FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDC9A9AD78989D58888CB8585C39393EFE6E6FEFDFDE6E0E0D5C7C7CBB2B2C29B9BC18484CD8686D58888D78989D78989CD8686B87E7EF4EBEBFFFFFFE7E2E2F9F8F8D1C2C2F7F4F4EAE7E7FBFAFAF2EDEDC28F8FCA8585D58989D78989D78989D78989CE8686B97E7EF3EAEAFFFFFFEDE8E8E4DADAE7D9D9E1C9C9CD8F8FD18787D68989D7898998C0718BCC6C8BCC6C88C46C80B169E8F1E5FFFFFFA5C39688BD6E8AC86C8BCB6C8BCC6C8BCC6C8BCC6C8BCC6C8BCC6C8BCC6C8AC96C85BD6B98BD86EDF3EAE9EFE78BA87DD0DCCAFAFBF9AFC9A289BB7189C66C8BCB6C8BCC6CE9F5E3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDA9292D48080D37F7FCA7D7DBB7A7ACCABABE2D4D4F0EBEBFDFCFCFCFAFAE8DCDCC08D8DC67D7DD17F7FD48080D48080CA7D7DB37575F3EAEAFFFFFFB7A3A3F2EEEEFBFAFAEFEAEACCC0C0F6F4F4F1ECECBD8787C67B7BD28080D48080D48080D48080CA7D7DB47575F2E8E8FFFFFFE6DEDEDBCBCBDFCACADDBEBEC98686CE7E7ED38080D4808091BC6783C86183C8617FBF6177AB5EE7F0E3FFFFFF9DBD8E7EB56380C16182C66182C76183C86183C86183C86183C86183C86183C7617FBE6079AD60E2ECDEFEFEFE95AB8CE7ECE4FBFCFB91B97D7DB96082C56183C86183C861E7F5E1FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFD78A8AD17777CF7676C77474BD7979AB7171AD8484B89E9EC6B7B7F0EDEDFEFEFEC8A4A4BF7676CC7575D07777D17777C67474AE6B6BF2E8E8FFFFFF9D7979E0D2D2FDFBFBC4ACACC0ABABF5F2F2F0EAEAB97F7FC27272CF7777D17777D17777D17777C67474AE6B6BF1E7E7FFFFFFB7A0A0A07575AA7474B47373BF7272CA7575D07777D1777789B75C7AC4567AC45677BB566EA653E5EFE1FFFFFF93B18570A55773B25476BA5578C0567AC3567AC4567AC4567AC4567AC4567AC45678BE5671AD53BFD5B5F7F9F6CCD5C9F3F5F2DAE5D581B36976B9557AC2567AC4567AC456E6F4DFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFD07575C85F5FC55D5DB95A5AC18585C49B9BAA7F7F8B5E5E8E6E6EE5DFDFFDFDFDBF9696B35E5EC25D5DC85E5EC85F5FBD5B5BA25151F0E4E4FFFFFF9B6565B47F7FD1A5A59B5C5CB79494F5F0F0EEE7E7AD6868B85959C65E5EC85F5FC85F5FC85F5FBD5B5BA25151EFE2E2FFFFFFC7B5B5B69696BD9595C69898B66262BF5C5CC75E5EC85F5F74AA3F62BA3862BA385EAF37549834E1ECDBFFFFFFB8C9B09ABB8B9BC2887BB55F62B03D61B63862B93862BA3862BA3862BA3862BA3861B6385AA73670A358E6EEE2FFFFFFFFFFFF8FB57E5EA43D5FB23762B93862BA3862BA38E1F2D9FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC85E5EBF4444BA4242AC3D3DBD8282EADCDCDDCCCCBEA5A5CAB9B9F4F0F0E1CFCFA45B5BAA3F3FBA4242BF4444BF4444B440409A3636EFE0E0FFFFFF9D51519B3737A33A3A983636B88787F5EEEEEEE4E4A75252AF3E3EBD4343BF4444BF4444BF4444B440409A3636EEDEDEFFFFFFF9F7F7F2EDEDF2ECECF4ECECB15858B34040BD4343BF44445C9C1F48AE1748AE1744A4163A8D12DCEAD5FFFFFFF8F9F7EEF2ECECF2E99AC3874FA32646A91748AD1748AE1748AE1748AE1748AE1748AC1742A0153B8916D6E5CEFEFEFEFAFCF95D9B4040991546A91748AE1748AE1748AE17DCEFD3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC85E5EBF4444BC4343B13F3FB05D5DC89999D4B5B5D7BCBCD8BDBDCCA5A5AC6868A44040B34040BD4343BF4444BF4444B84141A63B3BD09B9BD8ADADAA4B4BAF3E3EB54040AC3D3DB66969D2A2A2CF9D9DAC4A4AB44040BE4444BF4444BF4444BF4444B84141A73B3BCD9999D2AAAACFA9A9CFA9A9D1AAAAD6ACACB04F4FB54040BE4444BF44445C9C1F48AE1748AE1745A7163F98149AC584ABCC9CABCA9CABCB9CACCE9C7FB7644CA42146A91748AE1748AE1748AE1748AE1748AE1748AE1745A6163F981491C07BABCD9AA6CB94519F2C43A21547AC1748AE1748AE1748AE17DCEFD3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC85E5EBF4444BE4444B84242AC3E3EA03939A04848A15050A352529C3B3BA63B3BB34040BB4343BF4444BF4444BF4444BC4343B44040AC3D3DAA3D3DB23F3FBA4242BD4343B84242AF3E3EA83C3CAA3D3DB23F3FBA4242BE4444BF4444BF4444BF4444BC4343B44040A83C3C9F38389B37379B37379E3838A63B3BB23F3FBA4242BE4444BF44445C9C1F48AE1748AE1747AB1744A4164099143C91133B8D133B8E133D9413419C1545A51647AB1748AE1748AE1748AE1748AE1748AE1748AE1747AB1744A516409A143D95133E971443A11546A91648AD1748AE1748AE1748AE17DCEFD3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC85E5EBF4444BE4444BD4444BA4242B54141B03F3FAE3E3EAF3E3EB34040B84141BC4343BE4444BF4444BF4444BF4444BF4444BC4343BA4242BA4242BC4343BE4343BE4444BD4444BB4242B94242BA4242BC4343BE4343BF4444BF4444BF4444BF4444BF4444BC4343B94242B64141B54141B54141B64141B84141BB4343BE4343BF4444BF44445C9C1F48AE1748AE1748AE1747AB1746A91645A61645A51645A51645A71646A91647AC1748AD1748AE1748AE1748AE1748AE1748AE1748AE1748AE1747AC1746A91645A71646A81647AB1647AD1748AE1748AE1748AE1748AE17DCEFD3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC85E5EBF4444BF4444BF4444BF4444BE4444BD4444BD4343BD4343BE4343BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF44445C9C1F48AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE17DCEFD3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC85E5EBF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF4444BF44445C9C1F48AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE1748AE17DCEFD3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF" }
fn vg_legality_w() -> f32 { ret 160.0 }
fn vg_legality_h() -> f32 { ret 17.0 }
fn vg_legality_foot() -> str { ret "B77A7BB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6CB26A6C789E566CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA8516CA851" }
// round 17: the General-pressed capture's tag foot row (one pixel row, blended another way)
fn vg_legality_foot_pressed() -> str { ret "B38183AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577AF7577809E6576A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A76176A761" }
fn foot_pixels() -> str {
    if foot_pressed { ret vg_legality_foot_pressed() }
    ret vg_legality_foot()
}
fn vg_legality_foot_w() -> f32 { ret 75.0 }
fn vg_legality_foot_h() -> f32 { ret 1.0 }
