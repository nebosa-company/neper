// The check boxes, radio buttons and group boxes of the Filter window's Cards tab as the live v3 capture shows them
// (docs/ui/looks/ref/windows/states/tab-selected-filter-cards@1x.png): the Search Fields group with its five check boxes,
// the Match group with three radios, the colour check boxes, the three "Whole Words" check boxes and the top left corners
// (caption and frame) of the Search for Text and Additional groups. The tab page is #F9F9F9. Cells are crops of the
// capture (scripts/looks_refs_b.py, sheet choices_filter); every control stands at its rectangle of the capture.

use e.mem
use e.gfx.paint
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget
use e.ui.winbutton

fn plain(a: *mem.Arena, label: str) -> str {
    let (shown, mark, shown_error) = winbutton.mnemonic(a, label)
    if shown_error != ok { ret label }
    ret shown
}

fn noop_submit(ctx: *void) -> err { ret ok }

fn at(a: *mem.Arena, node: widget.Node, x: f32, y: f32) -> (widget.Node, err) {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = node
    ret (widget.positioned(0u64, x, y, style.defaults(), held[0usize..1usize]), ok)
}

// A check box (21 tall) at (x, y).
fn box(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, key: u64, label: str, x: f32, y: f32) -> (widget.Node, err) {
    var made: widget.Node = zero
    if t.tokens.profile == .Windows {
        let (drawn, drawn_error) = control.windows_checkbox_phase(a, key, t, label, false, false, action, true, 21.0, false, 1u32, 0.0 - 1.0, 0.0 - 1.0)
        if drawn_error != ok { ret (zero, drawn_error) }
        made = drawn
    } else {
        let (drawn, drawn_error) = control.checkbox(a, key, t, plain(a, label), false, false, action, true)
        if drawn_error != ok { ret (zero, drawn_error) }
        made = drawn
    }
    let (placed, placed_error) = at(a, made, x, y)
    ret (placed, placed_error)
}

fn radio(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, key: u64, label: str, selected: bool, x: f32, y: f32, window_y: f32) -> (widget.Node, err) {
    var made: widget.Node = zero
    if t.tokens.profile == .Windows {
        let (drawn, drawn_error) = control.windows_radio_phase(a, key, t, label, selected, action, true, 17.0, 5u32, 0.0 - 1.0, window_y)
        if drawn_error != ok { ret (zero, drawn_error) }
        made = drawn
    } else {
        let (drawn, drawn_error) = control.radio(a, key, t, label, selected, action, true)
        if drawn_error != ok { ret (zero, drawn_error) }
        made = drawn
    }
    let (placed, placed_error) = at(a, made, x, y)
    ret (placed, placed_error)
}

// The group `label` of `w` x `h` on the page, its body `kids`; another look draws a plain stack of the body.
fn group(a: *mem.Arena, t: *const control.Theme, key: u64, label: str, w: f32, h: f32, kids: []const widget.Node) -> (widget.Node, err) {
    if t.tokens.profile == .Windows {
        let (framed, framed_error) = control.windows_group_on(a, key, t, label, true, w, h, 0.0, 6.35, w, h - 0.65, style.hex(16382457u32), kids)
        ret (framed, framed_error)
    }
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    ret (widget.stack(0u64, s, kids), ok)
}

// A cell: `node` at (4, 4) of a clipped `w` x `h` page.
fn cell(a: *mem.Arena, t: *const control.Theme, caption: str, node: widget.Node, w: f32, h: f32) -> (looks.Cell, err) {
    let (placed, placed_error) = at(a, node, 4.0, 4.0)
    if placed_error != ok { ret (zero, placed_error) }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = placed
    var page = looks.size_style(w, h)
    page.overflow = .Clip
    if t.tokens.profile == .Windows { page.background = paint.Brush { Solid: style.hex(16382457u32) } }
    ret (looks.Cell { caption: caption, node: widget.stack(0u64, page, held[0usize..1usize]), drive: .None }, ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let action = &actions[0usize]
    let (kids, kids_error) = mem.alloc[widget.Node](a, 8usize)
    if kids_error != ok { ret (0usize, kids_error) }
    // Search Fields: group at (24,67) 175 x 174, check boxes at +8 / +20, +44, +68, +92, +116.
    let (s0, f0) = box(a, t, action, 1u64, "Te&xt", 8.0, 20.0)
    if f0 != ok { ret (0usize, f0) }
    let (s1, f1) = box(a, t, action, 2u64, "Card &Name", 8.0, 44.0)
    if f1 != ok { ret (0usize, f1) }
    let (s2, f2) = box(a, t, action, 3u64, "&Type", 8.0, 68.0)
    if f2 != ok { ret (0usize, f2) }
    let (s3, f3) = box(a, t, action, 4u64, "&Flavor", 8.0, 92.0)
    if f3 != ok { ret (0usize, f3) }
    let (s4, f4) = box(a, t, action, 5u64, "&Artist", 8.0, 116.0)
    if f4 != ok { ret (0usize, f4) }
    kids[0usize] = s0
    kids[1usize] = s1
    kids[2usize] = s2
    kids[3usize] = s3
    kids[4usize] = s4
    let (fields, fields_error) = group(a, t, 10u64, "Search Fields ", 175.0, 174.0, kids[0usize..5usize])
    if fields_error != ok { ret (0usize, fields_error) }
    let (c0, ce0) = cell(a, t, "Search Fields group", fields, 220.0, 190.0)
    if ce0 != ok { ret (0usize, ce0) }
    cells[0usize] = c0
    // Match: group at (468,302) 203 x 100, radios at +9 / +21, +48, +75.
    let (r0, g0) = radio(a, t, action, 21u64, "All Selected", true, 9.0, 21.0, 323.0)
    if g0 != ok { ret (0usize, g0) }
    let (r1, g1) = radio(a, t, action, 22u64, "Any of the Selected", false, 9.0, 48.0, 350.0)
    if g1 != ok { ret (0usize, g1) }
    let (r2, g2) = radio(a, t, action, 23u64, "Exactly the Selected", false, 9.0, 75.0, 377.0)
    if g2 != ok { ret (0usize, g2) }
    kids[5usize] = r0
    kids[6usize] = r1
    kids[7usize] = r2
    let (match_group, match_error) = group(a, t, 20u64, "&Match", 203.0, 100.0, kids[5usize..8usize])
    if match_error != ok { ret (0usize, match_error) }
    let (c1, ce1) = cell(a, t, "Match group", match_group, 220.0, 190.0)
    if ce1 != ok { ret (0usize, ce1) }
    cells[1usize] = c1
    // The colour check boxes of the Additional group: (53,300 + 24 k), crop origin (49,296).
    let (parts, parts_error) = mem.alloc[widget.Node](a, 16usize)
    if parts_error != ok { ret (0usize, parts_error) }
    let labels = [5]str{ "&White", "Bl&ue", "&Black", "&Red", "&Green" }
    var k = 0usize
    while k < 5usize {
        let (made, made_error) = box(a, t, action, 31u64 + u64(k), labels[k], 0.0, 24.0 * f32(k))
        if made_error != ok { ret (0usize, made_error) }
        parts[k] = made
        k += 1usize
    }
    let (c2, ce2) = cell(a, t, "Colour check boxes", stack_of(a, 60.0, 122.0, parts[0usize..5usize]), 220.0, 190.0)
    if ce2 != ok { ret (0usize, ce2) }
    cells[2usize] = c2
    // Multicolor (222,300) and Colorless (221,324): crop origin (217,296).
    let (m0, mm0) = box(a, t, action, 41u64, "&Multicolor (Gold)", 1.0, 0.0)
    if mm0 != ok { ret (0usize, mm0) }
    let (m1, mm1) = box(a, t, action, 42u64, "Colorless", 0.0, 24.0)
    if mm1 != ok { ret (0usize, mm1) }
    parts[5usize] = m0
    parts[6usize] = m1
    let (c3, ce3) = cell(a, t, "Multicolor, Colorless", stack_of(a, 110.0, 46.0, parts[5usize..7usize]), 220.0, 190.0)
    if ce3 != ok { ret (0usize, ce3) }
    cells[3usize] = c3
    // Whole Words at (598,87), (598,135), (598,188).
    let (n0, nn0) = box(a, t, action, 51u64, "&Whole Words", 0.0, 0.0)
    if nn0 != ok { ret (0usize, nn0) }
    let (n1, nn1) = box(a, t, action, 52u64, "Whole Words", 0.0, 0.0)
    if nn1 != ok { ret (0usize, nn1) }
    parts[7usize] = n0
    parts[8usize] = n1
    let (c4, ce4) = cell(a, t, "Whole Words (mnemonic)", stack_of(a, 88.0, 21.0, parts[7usize..8usize]), 220.0, 190.0)
    if ce4 != ok { ret (0usize, ce4) }
    cells[4usize] = c4
    let (c5, ce5) = cell(a, t, "Whole Words", stack_of(a, 88.0, 21.0, parts[8usize..9usize]), 220.0, 190.0)
    if ce5 != ok { ret (0usize, ce5) }
    cells[5usize] = c5
    // The Search for Text group at (210,67) 477 x 174 and the Additional group at (21,247) 665 x 183: only the top left
    // corners (caption and frame) are shown, the rest of both holds other controls.
    let (top, top_error) = group(a, t, 60u64, "Search for Text ", 477.0, 174.0, parts[0usize..0usize])
    if top_error != ok { ret (0usize, top_error) }
    let (c6, ce6) = cell(a, t, "Search for Text group, top left", top, 220.0, 190.0)
    if ce6 != ok { ret (0usize, ce6) }
    cells[6usize] = c6
    let (extra, extra_error) = group(a, t, 70u64, "Additional ", 665.0, 183.0, parts[0usize..0usize])
    if extra_error != ok { ret (0usize, extra_error) }
    let (c7, ce7) = cell(a, t, "Additional group, top left", extra, 220.0, 190.0)
    if ce7 != ok { ret (0usize, ce7) }
    cells[7usize] = c7
    ret (8usize, ok)
}

fn stack_of(a: *mem.Arena, w: f32, h: f32, kids: []const widget.Node) -> widget.Node {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    ret widget.stack(0u64, s, kids)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "choices_filter", cells: 8usize, columns: 4usize, cell_w: 220.0, cell_h: 190.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
