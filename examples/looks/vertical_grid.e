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

const COUNT: usize = 12usize
const NAME_KEY: u64 = 101u64

type Pick = struct { selected: usize, shut: bool }
var pick: Pick = zero

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
    if index == 9usize { ret "Archetype" }
    if index == 10usize { ret "Deck" }
    ret "Sideboard"
}

fn values(index: usize) -> str {
    if index == 0usize { ret "New Deck" }
    if index == 1usize { ret "gaddl" }
    if index == 3usize || index == 4usize { ret "10/11/2026" }
    if index == 5usize { ret "1.0" }
    if index == 7usize { ret "C:\\Users\\gaddl\\Desktop\\New..." }
    if index == 8usize { ret "MTG Studio (Xml)" }
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

fn count_of(ctx: *void) -> usize { ret COUNT }

// The idle cell: plain text, in Tahoma under the Windows look (v3 draws an editor only in the
// focused row).
fn editor_of(ctx: *void, a: *mem.Arena, index: usize, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
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
    let source = collection.PropertySource { ctx: mem.cast[*void](t), count: count_of, property: property_at, editor: editor_of }
    var options = collection.property_grid_options()
    options.selected = NAME_KEY + u64(pick.selected)
    options.height = 425.0
    let (made, made_error) = collection.property_grid_of(a, key, t, "Deck properties", source, collapsed, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, 164.0, 330.0, options)
    ret (made, made_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
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
        let (white, white_error) = control.colored_text(a, 0u64, values(0usize), &copies[0usize], control.text_options(), gl.rgb(0xFFFFFFu32))
        if white_error != ok { ret white_error }
        var mark = style.defaults()
        mark.background = paint.Brush { Solid: gl.rgb(0x0078D7u32) }
        mark.height = style.Length { Px: 14.0 }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret held_error }
        held[0usize] = white
        *out = widget.padded(0u64, 2.0, 2.0, 0.0, 0.0, style.defaults(), held[0usize..1usize])
        let (marked, marked_error) = mem.alloc[widget.Node](a, 1usize)
        if marked_error != ok { ret marked_error }
        marked[0usize] = widget.padded(0u64, 0.0, 0.0, 0.0, 0.0, mark, held[0usize..1usize])
        *out = widget.padded(0u64, 2.0, 2.0, 0.0, 0.0, style.defaults(), marked[0usize..1usize])
    }
    if c.mode == 2usize && index == 6usize {
        let (button, button_error) = gl.pixels(a, gl.gx_ellipsis_button(), gl.gx_ellipsis_button_w(), gl.gx_ellipsis_button_h())
        if button_error != ok { ret button_error }
        let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
        if pair_error != ok { ret pair_error }
        pair[0usize] = widget.spacer(0u64, 1.0)
        pair[1usize] = widget.padded(0u64, 0.0, 2.0, 0.0, 0.0, style.defaults(), mem_one_node(a, button))
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
    let source = collection.PropertySource { ctx: mem.cast[*void](&ctxs[0usize]), count: count_of, property: property_at, editor: state_editor }
    var options = collection.property_grid_options()
    options.height = 425.0
    var selected = NAME_KEY
    if mode == 1usize { selected = NAME_KEY + 1u64 }
    if mode == 2usize { selected = NAME_KEY + 6u64 }
    if mode == 3usize { selected = NAME_KEY + 9u64 }
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
    if args.len > 1usize && args[1usize][0usize] == 104u8 {
        let hover = looks.Sheet { name: "vertical_grid_hover", cells: 5usize, columns: 3usize, cell_w: 330.0, cell_h: 425.0, ctx: zero, build: build_hover }
        ret looks.run_all(a, &hover)
    }
    if args.len > 1usize { ret main_states(a) }
    if args.len > 1usize {
        // `vertical_grid.exe states`: the states sheet alone
        let states = looks.Sheet { name: "vertical_grid_states", cells: 5usize, columns: 3usize, cell_w: 330.0, cell_h: 425.0, ctx: zero, build: build_states }
        ret looks.run_all(a, &states)
    }
    let sheet = looks.Sheet { name: "vertical_grid", cells: 2usize, columns: 2usize, cell_w: 330.0, cell_h: 425.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
