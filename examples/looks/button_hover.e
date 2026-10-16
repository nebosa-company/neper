// Every captured button hover of the live v3 grabs (docs/ui/looks/ref/windows/states/hover-button-*), one cell each, in the
// Windows look: the box is cropped from the grab with 5 px of its dialog around it, and the cell holds the same
// surroundings (the dialog's own face: the Filter page is #F9F9F9, the others #F0F0F0) so a soft ring row that blends
// with the dialog shows the same pixels. Every cell is driven with the pointer on it (Drive.Hover; a pressed one with the button held). The tables below are generated from the capture list by
// scripts/looks_ref_a/genbs.py and mkbs.py: caption, caption word, control rect size, drive, default, enabled, dialog face, picture,
// focused, and the sub-pixel shift (dx, dy) of the four DPI-scaled forms (Options, Deck Properties, Deck Legality, About), whose
// buttons v3 draws resampled by that offset: the phase fitted to each capture (scripts/looks_ref_a/fitshift.py), a crisp button moved by it.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn margin_px() -> f32 { ret 5.0 }
fn noop_submit(ctx: *void) -> err { ret ok }

fn t_captions() -> [28]str { ret [28]str{ "hot opt ok", "hot opt cancel", "hot opt apply", "hot opt pw change", "hot opt sc set", "hot opt sc reset", "hot search ok", "hot search cancel", "hot sort ok", "hot sort clear", "hot filter ok", "hot filter clear", "hot filter all", "hot filter invert", "hot msc ok", "hot af ok", "hot af open", "hot cf ok", "hot cf apply", "hot cf edit rule disable", "hot cf new rule", "hot stats close", "hot about ok", "hot opt art validate", "hot dp ok", "hot dl close", "hot dl standard", "hot dl modern" } }
fn t_words() -> [28]str { ret [28]str{ "OK", "Cancel", "&Apply", "C&hange", "&Set", "&Reset", "OK", "Cancel", "OK", "Clear", "OK", "C&lear", "All", "Invert", "OK", "OK", "&Open...", "OK", "&Apply", "&Edit Rule...", "&New Rule...", "Close", "OK", "&Validate", "OK", "Close", "&Standard", "&Modern" } }
fn t_widths() -> [28]f32 { ret [28]f32{ 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 85.0, 85.0, 125.0, 125.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0 } }
fn t_heights() -> [28]f32 { ret [28]f32{ 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0 } }
fn t_drives() -> [28]u8 { ret [28]u8{ 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8 } }
fn t_defaults() -> [28]bool { ret [28]bool{ true, false, false, false, false, false, true, false, true, false, true, false, false, false, true, true, false, true, false, false, false, false, true, false, true, true, false, false } }
fn t_enabled() -> [28]bool { ret [28]bool{ true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, false, false, true, true, true, true, true, true, true, true } }
fn t_faces() -> [28]u32 { ret [28]u32{ 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF9F9F9u32, 0xF9F9F9u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32 } }
fn t_focused() -> [28]bool { ret [28]bool{ false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false } }
fn t_glyphs() -> [28]bool { ret [28]bool{ false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, false, false, false, false, false, false, false } }
fn t_shift_x() -> [28]f32 { ret [28]f32{ 0.36, 0.42, 0.48, 0.18, 0.42, 0.48, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.38, 0.34, 0.14, 0.36, 0.04, 0.12 } }
fn t_shift_y() -> [28]f32 { ret [28]f32{ 0.48, 0.48, 0.48, 0.20, 0.42, 0.42, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.50, 0.42, 0.48, 0.46, 0.04, 0.04 } }

// The holder of a cell: odd wide and even tall (so the cell centres it on whole pixels in 133 x 40), the dialog face
// behind, the visible box (the control rect less 2 wide, 1 tall) at (margin, margin).
fn holder_of(a: *mem.Arena, t: *const control.Theme, node: widget.Node, vis_w: f32, vis_h: f32, face: u32) -> (widget.Node, err) {
    var hw = vis_w + margin_px() * 2.0
    if u32(hw) % 2u32 == 0u32 { hw += 1.0 }
    var hh = vis_h + margin_px() * 2.0
    if u32(hh) % 2u32 == 1u32 { hh += 1.0 }
    var holder = control.sized_style(hw, hh)
    if t.tokens.profile == .Windows { holder.background = paint.Brush { Solid: style.hex(face) } }
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = widget.positioned(0u64, margin_px(), margin_px(), style.defaults(), control.mem_one_node(a, node))
    ret (widget.stack(0u64, holder, inner[0usize..1usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let action = &actions[0usize]
    let captions = t_captions()
    let words = t_words()
    let widths = t_widths()
    let heights = t_heights()
    let drives = t_drives()
    let defaults = t_defaults()
    let enabled = t_enabled()
    let faces = t_faces()
    let glyphs = t_glyphs()
    let focused = t_focused()
    let shift_x = t_shift_x()
    let shift_y = t_shift_y()
    var i = 0usize
    while i < 28 {
        var options = control.button_options()
        options.width = widths[i]
        options.height = heights[i]
        options.enabled = enabled[i]
        options.shift_x = shift_x[i]
        options.shift_y = shift_y[i]
        options.focused = focused[i]
        if defaults[i] { options.variant = .Default }
        var node: widget.Node = zero
        var node_error: err = ok
        if glyphs[i] {
            let (picture, picture_error) = control.button_with_glyph(a, u64(i + 1usize), t, .Refresh, words[i], action, options)
            node = picture
            node_error = picture_error
        } else {
            let (plain, plain_error) = control.button(a, u64(i + 1usize), t, words[i], action, options)
            node = plain
            node_error = plain_error
        }
        if node_error != ok { ret (0usize, node_error) }
        let (held, held_error) = holder_of(a, t, node, widths[i] - 2.0, heights[i] - 1.0, faces[i])
        if held_error != ok { ret (0usize, held_error) }
        var drive: looks.Drive = .None
        if drives[i] == 1u8 { drive = .Press }
        if drives[i] == 2u8 { drive = .Focus }
        if drives[i] == 3u8 { drive = .Hover }
        cells[i] = looks.Cell { caption: captions[i], node: held, drive: drive }
        i += 1usize
    }
    ret (28, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "button_hover", cells: 28usize, columns: 4usize, cell_w: 133.0, cell_h: 40.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
