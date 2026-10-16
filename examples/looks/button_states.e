// Every captured button state of the live v3 grabs (docs/ui/looks/ref/windows/states/button-*), one cell each, in the
// Windows look: the box is cropped from the grab with 5 px of its dialog around it, and the cell holds the same
// surroundings (the dialog's own face: the Filter dialog is #F9F9F9, the others #F0F0F0) so a soft ring row that blends
// with the dialog shows the same pixels. Pressed and focused cells are driven (Drive.Press / Drive.Focus); the rest
// are plain. The tables below are generated from the capture list by scripts/looks_ref_a/genbs.py and mkbs.py: caption,
// caption word, control rect size, drive, default, enabled, dialog face, picture, and the sub-pixel shift (dx, dy) of the
// four DPI-scaled forms (Options, Deck Properties, Deck Legality, About), whose buttons v3 draws resampled by that offset:
// the phase fitted to each capture (scripts/looks_ref_a/fitshift.py), a crisp button moved by it. Hover has no capture.
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

fn t_captions() -> [42]str { ret [42]str{ "search rest", "pressed search ok", "pressed search cancel", "pressed sort ok", "pressed sort clear", "pressed filter ok", "pressed filter clear", "pressed filter all", "focused filter invert", "pressed msc ok", "pressed af ok", "pressed af open", "pressed cf ok", "focused cf apply", "disabled cf edit rule", "pressed stats close", "pressed about ok", "pressed opt ok", "pressed opt cancel", "pressed opt apply", "focused opt cancel", "focused opt apply", "pressed opt pw change", "focused opt pw change", "pressed opt sc set", "pressed opt sc reset", "pressed opt art validate", "pressed dp ok", "pressed dl close", "pressed dl standard", "focused dl modern", "hover opt ok", "hover opt cancel", "hover opt apply", "hover opt pw change", "hover opt sc set", "hover opt sc reset", "75x32 rest", "75x32 default", "75x32 focus", "75x32 pressed", "125x40 default" } }
fn t_words() -> [42]str { ret [42]str{ "OK", "OK", "Cancel", "OK", "Clear", "OK", "C&lear", "All", "Invert", "OK", "OK", "&Open...", "OK", "OK", "&Edit Rule...", "Close", "OK", "OK", "Cancel", "&Apply", "Cancel", "&Apply", "C&hange", "C&hange", "&Set", "&Reset", "&Validate", "OK", "Close", "&Standard", "&Modern", "OK", "Cancel", "&Apply", "C&hange", "&Set", "&Reset", "Cancel", "OK", "Cancel", "OK", "Apply" } }
fn t_widths() -> [42]f32 { ret [42]f32{ 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 85.0, 85.0, 125.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 75.0, 125.0 } }
fn t_heights() -> [42]f32 { ret [42]f32{ 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 25.0, 25.0, 25.0, 25.0, 25.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 32.0, 32.0, 32.0, 32.0, 40.0 } }
fn t_drives() -> [42]u8 { ret [42]u8{ 0u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 2u8, 1u8, 1u8, 1u8, 1u8, 2u8, 0u8, 1u8, 1u8, 1u8, 1u8, 1u8, 2u8, 2u8, 1u8, 2u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 2u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 0u8, 0u8, 2u8, 1u8, 0u8 } }
fn t_defaults() -> [42]bool { ret [42]bool{ true, true, false, true, false, true, false, false, false, true, true, false, true, true, false, false, true, true, false, false, false, false, false, false, false, false, false, true, true, false, false, true, false, false, false, false, false, false, true, false, true, true } }
fn t_enabled() -> [42]bool { ret [42]bool{ true, true, true, true, true, true, true, true, true, true, true, true, true, true, false, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true } }
fn t_faces() -> [42]u32 { ret [42]u32{ 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF9F9F9u32, 0xF9F9F9u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32, 0xF0F0F0u32 } }
fn t_glyphs() -> [42]bool { ret [42]bool{ false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false } }
fn t_shift_x() -> [42]f32 { ret [42]f32{ 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.38, 0.36, 0.42, 0.48, 0.44, 0.48, 0.18, 0.18, 0.42, 0.48, 0.36, 0.14, 0.36, 0.04, 0.10, 0.36, 0.42, 0.48, 0.18, 0.42, 0.48, 0.00, 0.00, 0.00, 0.00, 0.00 } }
fn t_shift_y() -> [42]f32 { ret [42]f32{ 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.46, 0.48, 0.48, 0.48, 0.50, 0.50, 0.26, 0.26, 0.44, 0.46, 0.44, 0.48, 0.48, 0.06, 0.06, 0.48, 0.48, 0.48, 0.20, 0.42, 0.42, 0.00, 0.00, 0.00, 0.00, 0.00 } }

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
    let shift_x = t_shift_x()
    let shift_y = t_shift_y()
    var i = 0usize
    while i < 42 {
        var options = control.button_options()
        options.width = widths[i]
        options.height = heights[i]
        options.enabled = enabled[i]
        options.shift_x = shift_x[i]
        options.shift_y = shift_y[i]
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
    ret (42, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "button_states", cells: 42usize, columns: 4usize, cell_w: 133.0, cell_h: 40.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
