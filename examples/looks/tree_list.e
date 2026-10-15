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
use e.ui.control
use e.ui.gridlook as gl
use e.ui.looks
use e.ui.widget

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
    let (box, box_error) = gl.mark(a, .TreeBox, gl.rgb(0u32), gl.rgb(0u32), 13.0, 13.0)
    if box_error != ok { ret box_error }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret held_error }
    held[0usize] = box
    *out = widget.padded(0u64, 3.0, 3.0, 0.0, 0.0, control.sized_style(16.0, 17.0), held[0usize..1usize])
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

fn filter_list(a: *mem.Arena, t: *const control.Theme, key: widget.Key) -> (widget.Node, err) {
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
    var held = t
    if t.tokens.profile == .Windows { held = &copies[0usize] }
    let source = collection.TreeSource { ctx: mem.cast[*void](held), count: count_of, key: key_of, has_children: has_children, build: build_row }
    let cells = collection.CellSource { ctx: mem.cast[*void](held), cell: build_cell }
    var none: []const widget.Key = zero
    var options: collection.TreeOptions = zero
    options.height = 300.0
    let (node, node_error) = collection.tree_table_with(a, key, held, "Blocks", columns[0usize..4usize], source, cells, none, picked[0usize..1usize], widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, 99usize, false, widget.Change[usize] { ctx: zero, invoke: noop_sort }, widget.Change[collection.Reorder] { ctx: zero, invoke: noop_reorder }, widget.Change[collection.ColumnResize] { ctx: zero, invoke: noop_resize }, 17.0, options)
    ret (node, node_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (left, left_error) = filter_list(a, t, 1000u64)
    if left_error != ok { ret (0usize, left_error) }
    cells[0usize] = looks.Cell { caption: "Filter dialog list: Abbr., ES, Block/Edition, Released", node: left, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "tree_list", cells: 1usize, columns: 1usize, cell_w: 305.0, cell_h: 319.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
