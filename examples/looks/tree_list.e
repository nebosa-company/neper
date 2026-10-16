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

type Flags = struct { checked: bool, expanded: bool }
var flags: Flags = zero
fn checked_two() -> bool { ret flags.checked }

fn noop_key(ctx: *void, value: widget.Key) -> err { ret ok }
fn noop_sort(ctx: *void, value: usize) -> err { ret ok }
fn noop_reorder(ctx: *void, value: collection.Reorder) -> err { ret ok }
fn noop_resize(ctx: *void, value: collection.ColumnResize) -> err { ret ok }

// looks5-e: the sixteen editions of Core Sets as the live captures show them (states/tree-list-expander-pressed-filter): the
// children are keys 200 to 215 (`key_of`: parent * 100 + index)
fn child_name(index: usize) -> str {
    if index == 0usize { ret "Foundations" }
    if index == 1usize { ret "Core Set 2021" }
    if index == 2usize { ret "Core Set 2020" }
    if index == 3usize { ret "Core Set 2019" }
    if index == 4usize { ret "Magic Origins" }
    if index == 5usize { ret "Magic 2015" }
    if index == 6usize { ret "Magic 2014" }
    if index == 7usize { ret "Magic 2013" }
    if index == 8usize { ret "Magic 2012" }
    if index == 9usize { ret "Magic 2011" }
    if index == 10usize { ret "Magic 2010" }
    if index == 11usize { ret "Tenth Edition" }
    if index == 12usize { ret "Ninth Edition" }
    if index == 13usize { ret "Eighth Edition" }
    if index == 14usize { ret "Seventh Edition" }
    if index == 15usize { ret "Sixth Edition" }
    ret "Fifth Edition"
}

fn child_abbr(index: usize) -> str {
    if index == 0usize { ret "FDN" }
    if index == 1usize { ret "M21" }
    if index == 2usize { ret "M20" }
    if index == 3usize { ret "M19" }
    if index == 4usize { ret "ORI" }
    if index == 5usize { ret "M15" }
    if index == 6usize { ret "M14" }
    if index == 7usize { ret "M13" }
    if index == 8usize { ret "M12" }
    if index == 9usize { ret "M11" }
    if index == 10usize { ret "M10" }
    if index == 11usize { ret "10E" }
    if index == 12usize { ret "9ED" }
    if index == 13usize { ret "8ED" }
    if index == 14usize { ret "7ED" }
    if index == 15usize { ret "6ED" }
    ret "5ED"
}

fn child_date(index: usize) -> str {
    if index == 0usize { ret "2024-11-15" }
    if index == 1usize { ret "2020-08-08" }
    if index == 2usize { ret "2019-07-12" }
    if index == 3usize { ret "2018-07-13" }
    if index == 4usize { ret "2015-07-17" }
    if index == 5usize { ret "2014-07-18" }
    if index == 6usize { ret "2013-07-19" }
    if index == 7usize { ret "2012-07-13" }
    if index == 8usize { ret "2011-07-15" }
    if index == 9usize { ret "2010-07-16" }
    if index == 10usize { ret "2009-07-17" }
    if index == 11usize { ret "2007-07-13" }
    if index == 12usize { ret "2005-07-29" }
    if index == 13usize { ret "2003-07-28" }
    if index == 14usize { ret "2001-04-11" }
    if index == 15usize { ret "1999-04-28" }
    ret "1997-03-24"
}

fn name_of(node: widget.Key) -> str {
    if node >= 200u64 && node < 224u64 { ret child_name(usize(node - 200u64)) }
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
    if node >= 200u64 && node < 224u64 { ret 0x000000u32 }
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
    if parent == 2u64 && flags.expanded { ret 24usize }
    ret 1usize
}

fn key_of(ctx: *void, parent: widget.Key, index: usize) -> widget.Key {
    if parent == 0u64 { ret u64(index) + 1u64 }
    ret parent * 100u64 + u64(index)
}

fn has_children(ctx: *void, node: widget.Key) -> bool {
    if node >= 200u64 { ret false }
    ret node < 100u64
}

// The first column: the node's check box, 3 px in (the plus box takes the first 14).
fn build_row(ctx: *void, a: *mem.Arena, node: widget.Key, out: *widget.Node) -> err {
    // v3's check box, cut from the live capture (the Windows look; the others keep the drawn box); node 2 is checked in the check sheet
    var pic = gl.gx_tree_check()
    if node == 2u64 && checked_two() { pic = gl.gx_tree_check_on() }
    let (box, box_error) = gl.pixels(a, pic, gl.gx_tree_check_w(), gl.gx_tree_check_h())
    if box_error != ok { ret box_error }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret held_error }
    held[0usize] = box
    let boxed = widget.padded(0u64, 2.0, 3.0, 0.0, 0.0, control.sized_style(17.0, 17.0), held[0usize..1usize])
    if node < 200u64 {
        *out = boxed
        ret ok
    }
    // an edition: the checked box, then its abbreviation
    let t = mem.cast[*const control.Theme](ctx)
    let (checked, checked_error) = gl.pixels(a, gl.gx_tree_check_on(), gl.gx_tree_check_on_w(), gl.gx_tree_check_h())
    if checked_error != ok { ret checked_error }
    let (label, label_error) = control.text(a, 0u64, child_abbr(usize(node - 200u64)), t, control.text_options())
    if label_error != ok { ret label_error }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret parts_error }
    let (check_held, check_held_error) = mem.alloc[widget.Node](a, 1usize)
    if check_held_error != ok { ret check_held_error }
    check_held[0usize] = checked
    // the tree indents a level by 20, the capture by 14: the box and the text lean back 6 px
    parts[0usize] = widget.positioned(0u64, 6.0, 1.0, style.defaults(), check_held[0usize..1usize])
    parts[1usize] = widget.positioned(0u64, 24.0, 1.0, style.defaults(), one_of(a, label))
    *out = widget.stack(0u64, control.sized_style(80.0, 17.0), parts[0usize..2usize])
    ret ok
}

fn one_of(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (nodes, nodes_error) = mem.alloc[widget.Node](a, 1usize)
    if nodes_error != ok { ret zero }
    nodes[0usize] = node
    ret nodes[0usize..1usize]
}

fn build_cell(ctx: *void, a: *mem.Arena, node: widget.Key, column: usize, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    if node >= 200u64 && column == 3usize {
        let (date, date_error) = control.text(a, 0u64, child_date(usize(node - 200u64)), t, control.text_options())
        if date_error != ok { ret date_error }
        *out = date
        ret ok
    }
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
    var opened: []const widget.Key = zero
    if flags.expanded {
        let (open_keys, open_error) = mem.alloc[widget.Key](a, 1usize)
        if open_error != ok { ret (zero, open_error) }
        open_keys[0usize] = 2u64
        opened = open_keys[0usize..1usize]
    }
    var options: collection.TreeOptions = zero
    options.height = 300.0
    if focus_two { options.height = 71.0 }
    let (node, node_error) = collection.tree_table_with(a, key, held, "Blocks", columns[0usize..4usize], source, cells, opened, picked[0usize..1usize], widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, 99usize, false, widget.Change[usize] { ctx: zero, invoke: noop_sort }, widget.Change[collection.Reorder] { ctx: zero, invoke: noop_reorder }, widget.Change[collection.ColumnResize] { ctx: zero, invoke: noop_resize }, 17.0, options)
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

// looks5-e: Core Sets open (its sixteen editions, checked) and selected, with the expander pressed and with the bar's thumb
// pressed (states/tree-list-expander-pressed-filter and scroll-bar-thumb-pressed-filter-tree, 305 x 319 at (21, 88))
fn build_expanded(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    var k = 0usize
    while k < 2usize {
        let (node, node_error) = filter_list(a, t, u64(1000 + k * 10000), false)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .Focus
        var caption = "Expander pressed (Core Sets)"
        looks.aim(k, 0.0, 45.0 - 159.5)
        if k == 1usize {
            caption = "Scroll thumb pressed"
            drive = .Press
            looks.aim(k, 297.0 - 152.5, 70.0 - 159.5)
        }
        cells[k] = looks.Cell { caption: caption, node: node, drive: drive }
        k += 1usize
    }
    ret (2usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // `tree_list.exe states` renders the two state sheets (the arena holds only so many sheets)
    if args.len > 1usize && args[1usize][0usize] == 101u8 {
        flags.checked = true
        flags.expanded = true
        let expanded = looks.Sheet { name: "tree_list_expanded", cells: 2usize, columns: 2usize, cell_w: 305.0, cell_h: 319.0, ctx: zero, build: build_expanded }
        ret looks.run_all(a, &expanded)
    }
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
