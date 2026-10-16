// The tree list (TcxTreeList) under every look: docs/ui/looks/<look>/tree_list.png.
// Run from the repository root; see docs/ui/looks-howto.md.
//
// Left: v3's Filter dialog list (tlAbilities in the Blocks / Formats / Editions page) as the live
// 100 % capture shows it: columns Abbr., ES, Block/Edition, Released, a plus box and an unchecked
// check box on every top-level node, rows 17 px, node names in their own colours, the first row
// selected (the control is not focused: the inactive cream selection). Reference:
// ref/windows/tree_list.png, cropped from dialogs/search-filter-top@1x.png at (21, 88), 305 x 319
// (the capture's 16 px scroll bar column is not part of the table here). Right: a three level tree
// with one column, branches open and shut, for the other looks.

use e.mem
use e.ui.collection
use e.gfx.paint
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.gridlook as gl
use e.ui.looks
use e.ui.widget

type Flags = struct { checked: bool }
var flags: Flags = zero
fn checked_two() -> bool { ret flags.checked }

fn noop_key(ctx: *void, value: widget.Key) -> err { ret ok }
fn noop_sort(ctx: *void, value: usize) -> err { ret ok }
fn noop_reorder(ctx: *void, value: collection.Reorder) -> err { ret ok }
fn noop_resize(ctx: *void, value: collection.ColumnResize) -> err { ret ok }

fn name_of(node: widget.Key) -> str {
    if node == 1u64 { ret "Expansions" }
    if node == 2u64 { ret "Core Sets" }
    if node == 3u64 { ret "Masters" }
    if node == 4u64 { ret "Draft Innovation" }
    if node == 5u64 { ret "Duel Decks" }
    if node == 6u64 { ret "Alchemy" }
    if node == 7u64 { ret "Archenemy" }
    if node == 8u64 { ret "Arsenal" }
    if node == 9u64 { ret "Box" }
    if node == 10u64 { ret "Commander" }
    if node == 11u64 { ret "From the Vault" }
    if node == 12u64 { ret "Funny" }
    if node == 13u64 { ret "Masterpiece" }
    if node == 14u64 { ret "Memorabilia" }
    if node == 15u64 { ret "Planechase" }
    if node == 16u64 { ret "Premium Deck" }
    if node == 17u64 { ret "Promo" }
    ret "Spellbook"
}

fn ink_of(node: widget.Key) -> u32 {
    if node == 1u64 { ret 0xFF0000u32 }
    if node == 2u64 { ret 0x000000u32 }
    if node == 3u64 { ret 0x9400D3u32 }
    if node == 4u64 { ret 0xFF1493u32 }
    if node == 5u64 { ret 0x4682B4u32 }
    if node == 6u64 { ret 0xDC143Cu32 }
    if node == 7u64 { ret 0x9400D3u32 }
    if node == 8u64 { ret 0xFF7F50u32 }
    if node == 9u64 { ret 0xCD853Fu32 }
    if node == 10u64 { ret 0x0000FFu32 }
    if node == 11u64 { ret 0x9932CCu32 }
    if node == 12u64 { ret 0xC42A38u32 }
    if node == 13u64 { ret 0xFF6347u32 }
    if node == 14u64 { ret 0xFF1493u32 }
    if node == 15u64 { ret 0x2E8B57u32 }
    if node == 16u64 { ret 0xD2691Eu32 }
    if node == 18u64 { ret 0xFF8C00u32 }
    ret 0xDC143Cu32
}

fn count_of(ctx: *void, parent: widget.Key) -> usize {
    if parent == 0u64 { ret 24usize }
    ret 1usize
}

fn key_of(ctx: *void, parent: widget.Key, index: usize) -> widget.Key {
    if parent == 0u64 { ret u64(index) + 1u64 }
    ret parent * 100u64 + u64(index)
}

fn has_children(ctx: *void, node: widget.Key) -> bool {
    ret node < 100u64
}

// The first column: the node's check box, 3 px in (the plus box takes the first 14).
fn build_row(ctx: *void, a: *mem.Arena, node: widget.Key, out: *widget.Node) -> err {
    // v3's check box, cut from the live capture (the Windows look; the others keep the drawn box); node 2 is checked in the check sheet
    let t = mem.cast[*const control.Theme](ctx)
    var pic = gl.gx_tree_check()
    if node == 2u64 && checked_two() { pic = gl.gx_tree_check_on() }
    let (box, box_error) = gl.pixels(a, pic, gl.gx_tree_check_w(), gl.gx_tree_check_h())
    if box_error != ok { ret box_error }
    var shown = box
    // Neper dark: the capture's check box is light-only pixels; draw a box in the theme's colours instead
    if t.tokens.palette == .Dark && t.tokens.profile == .Neper {
        var face = control.sized_style(13.0, 13.0)
        face.background = paint.Brush { Solid: style.color(t.tokens, .Surface) }
        face.border = style.Border { width: 1.0, color: style.color(t.tokens, .Border) }
        face.radius = 2.0
        shown = widget.box(0u64, face, zero)
    }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret held_error }
    held[0usize] = shown
    *out = widget.padded(0u64, 2.0, 3.0, 0.0, 0.0, control.sized_style(17.0, 17.0), held[0usize..1usize])
    ret ok
}

fn build_cell(ctx: *void, a: *mem.Arena, node: widget.Key, column: usize, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    if column != 2usize {
        *out = widget.spacer(0u64, 1.0)
        ret ok
    }
    let (made, made_error) = control.colored_text(a, 0u64, name_of(node), t, control.text_options(), gl.rgb(ink_of(node)))
    if made_error != ok { ret made_error }
    *out = made
    ret ok
}

fn filter_list(a: *mem.Arena, t: *const control.Theme, key: widget.Key, focus_two: bool) -> (widget.Node, err) {
    let (tahoma, tahoma_error) = control.windows_tahoma_theme(a, t, 11.0)
    if tahoma_error != ok { ret (zero, tahoma_error) }
    let (copies, copies_error) = mem.alloc[control.Theme](a, 1usize)
    if copies_error != ok { ret (zero, copies_error) }
    copies[0usize] = tahoma
    let (columns, columns_error) = mem.alloc[collection.Column](a, 4usize)
    if columns_error != ok { ret (zero, columns_error) }
    columns[0usize] = collection.Column { title: "        Abbr.", width: 85.0 }
    columns[1usize] = collection.Column { title: "ES", width: 20.0 }
    columns[2usize] = collection.Column { title: "Block/Edition", width: 119.0 }
    columns[3usize] = collection.Column { title: "Released", width: 65.0 }
    let (picked, picked_error) = mem.alloc[widget.Key](a, 1usize)
    if picked_error != ok { ret (zero, picked_error) }
    picked[0usize] = 1u64
    if flags.checked || focus_two { picked[0usize] = 2u64 }
    var held = t
    if t.tokens.profile == .Windows { held = &copies[0usize] }
    let source = collection.TreeSource { ctx: mem.cast[*void](held), count: count_of, key: key_of, has_children: has_children, build: build_row }
    let cells = collection.CellSource { ctx: mem.cast[*void](held), cell: build_cell }
    var none: []const widget.Key = zero
    var options: collection.TreeOptions = zero
    options.height = 300.0
    if focus_two { options.height = 71.0 }
    let (node, node_error) = collection.tree_table_with(a, key, held, "Blocks", columns[0usize..4usize], source, cells, none, picked[0usize..1usize], widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, 99usize, false, widget.Change[usize] { ctx: zero, invoke: noop_sort }, widget.Change[collection.Reorder] { ctx: zero, invoke: noop_reorder }, widget.Change[collection.ColumnResize] { ctx: zero, invoke: noop_resize }, 17.0, options)
    ret (node, node_error)
}

fn none_of(ctx: *void, parent: widget.Key) -> usize { ret 0usize }

// The Conditional Formatting Rules Manager's list (view-conditional-formatting@1x.png): no rules,
// five columns, a TcxGrid-style frame (1 px #828790, #A7AAB0 over #D5D7DA at the top). Reference:
// ref/windows/tree_list_rules.png, 664 x 257.
fn rules_list(a: *mem.Arena, t: *const control.Theme, key: widget.Key) -> (widget.Node, err) {
    let (tahoma, tahoma_error) = control.windows_tahoma_theme(a, t, 11.0)
    if tahoma_error != ok { ret (zero, tahoma_error) }
    let (copies, copies_error) = mem.alloc[control.Theme](a, 1usize)
    if copies_error != ok { ret (zero, copies_error) }
    copies[0usize] = tahoma
    let (columns, columns_error) = mem.alloc[collection.Column](a, 5usize)
    if columns_error != ok { ret (zero, columns_error) }
    columns[0usize] = collection.Column { title: "Rule (applied in order shown)", width: 257.0 }
    columns[1usize] = collection.Column { title: "Format", width: 105.0 }
    columns[2usize] = collection.Column { title: "Applies to", width: 103.0 }
    columns[3usize] = collection.Column { title: "Apply to the record", width: 112.0 }
    columns[4usize] = collection.Column { title: "Stop If True", width: 85.0 }
    var held = t
    if t.tokens.profile == .Windows { held = &copies[0usize] }
    let source = collection.TreeSource { ctx: mem.cast[*void](held), count: none_of, key: key_of, has_children: has_children, build: build_row }
    let cells = collection.CellSource { ctx: mem.cast[*void](held), cell: build_cell }
    var none: []const widget.Key = zero
    var options: collection.TreeOptions = zero
    options.height = 237.0
    let (node, node_error) = collection.tree_table_with(a, key, held, "Rules", columns[0usize..5usize], source, cells, none, none, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, 99usize, false, widget.Change[usize] { ctx: zero, invoke: noop_sort }, widget.Change[collection.Reorder] { ctx: zero, invoke: noop_reorder }, widget.Change[collection.ColumnResize] { ctx: zero, invoke: noop_resize }, 17.0, options)
    if node_error != ok { ret (zero, node_error) }
    // the frame
    let (held_nodes, held_error) = mem.alloc[widget.Node](a, 3usize)
    if held_error != ok { ret (zero, held_error) }
    var top_a = looks.size_style(662.0, 1.0)
    top_a.background = paint.Brush { Solid: gl.rgb(0xA7AAB0u32) }
    var top_b = looks.size_style(662.0, 1.0)
    top_b.background = paint.Brush { Solid: gl.rgb(0xD5D7DAu32) }
    held_nodes[0usize] = widget.box(0u64, top_a, zero)
    held_nodes[1usize] = widget.box(0u64, top_b, zero)
    held_nodes[2usize] = node
    var inner = looks.size_style(662.0, 256.0)
    inner.background = paint.Brush { Solid: gl.rgb(0xFFFFFFu32) }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, column_error) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, inner, held_nodes[0usize..3usize])
    var wrap = looks.size_style(664.0, 257.0)
    wrap.background = paint.Brush { Solid: gl.rgb(0x828790u32) }
    wrap.padding = style.EdgeLengths { left: style.Length { Px: 1.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 1.0 }, bottom: style.Length { Px: 1.0 } }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, wrap, column[0usize..1usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (left, left_error) = filter_list(a, t, 1000u64, false)
    if left_error != ok { ret (0usize, left_error) }
    cells[0usize] = looks.Cell { caption: "Filter dialog list: Abbr., ES, Block/Edition, Released", node: left, drive: .None }
    ret (1usize, ok)
}

fn build_rules(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (right, right_error) = rules_list(a, t, 2000u64)
    if right_error != ok { ret (0usize, right_error) }
    cells[0usize] = looks.Cell { caption: "Conditional Formatting Rules list (empty)", node: right, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // `tree_list.exe states` renders the two state sheets (the arena holds only so many sheets)
    if args.len > 1usize { ret main_states(a) }
    let sheet = looks.Sheet { name: "tree_list", cells: 1usize, columns: 1usize, cell_w: 305.0, cell_h: 319.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    let second = looks.Sheet { name: "tree_list_rules", cells: 1usize, columns: 1usize, cell_w: 664.0, cell_h: 257.0, ctx: zero, build: build_rules }
    ret looks.run_all(a, &second)
}

// The same list in the states of the captures: the second node selected with the keyboard focus (the harness taps the middle of
// a 305 x 90 cell, which is that row), and with its check box on (v3 sets the check on the button going down).
fn build_focus(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (node, node_error) = filter_list(a, t, 1000u64, true)
    if node_error != ok { ret (0usize, node_error) }
    var face = looks.size_style(305.0, 90.0)
    face.overflow = .Clip
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (0usize, held_error) }
    held[0usize] = node
    cells[0usize] = looks.Cell { caption: "Selected focused row", node: widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, face, held[0usize..1usize]), drive: .Focus }
    ret (1usize, ok)
}

fn main_states(a: *mem.Arena) -> err {
    let focus = looks.Sheet { name: "tree_list_focus", cells: 1usize, columns: 1usize, cell_w: 305.0, cell_h: 90.0, ctx: zero, build: build_focus }
    try looks.run_all(a, &focus)
    flags.checked = true
    let check = looks.Sheet { name: "tree_list_check", cells: 1usize, columns: 1usize, cell_w: 305.0, cell_h: 90.0, ctx: zero, build: build_focus }
    ret looks.run_all(a, &check)
}
