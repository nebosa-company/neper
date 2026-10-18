// The Linux look's alert dialog against the real GTK 4.14 / libadwaita 1.5 one: docs/ui/looks/linux[-dark]/dialog.png. The library's
// picture is its 550 x 410 window with an AdwAlertDialog ("Delete file?", Cancel and a destructive Delete) over the dimmed window, so
// the sheet is that window: the frame the compositor gives it (five rings of a few levels), the window colour under the scrim, and the
// card overlay.linux_alert_card draws over it (the open dialog draws the same card over its scrim). Run from the repository root; see
// docs/ui/looks-howto.md. The strict compare is scripts/linux_cmp_l4.py.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.looks
use e.ui.overlay
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn one_of(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (one, one_error) = mem.alloc[widget.Node](a, 1usize)
    if one_error != ok { ret zero }
    one[0usize] = node
    ret one[0usize..1usize]
}

// A square box `side` x `high` painted `value`, padded `pad` all round, holding `inside`.
fn ring(a: *mem.Arena, side: f32, high: f32, value: u32, pad: f32, inside: widget.Node) -> widget.Node {
    var s = looks.size_style(side, high)
    s.background = paint.Brush { Solid: style.hex_raw(value) }
    s.padding = style.EdgeLengths { left: style.Length { Px: pad }, top: style.Length { Px: pad }, right: style.Length { Px: pad }, bottom: style.Length { Px: pad } }
    ret widget.box(0u64, s, one_of(a, inside))
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let (buttons, buttons_error) = mem.alloc[overlay.DialogButton](a, 2usize)
    if buttons_error != ok { ret (0usize, buttons_error) }
    buttons[0usize] = overlay.DialogButton { label: "Cancel", action: actions[0usize], kind: .Cancel }
    buttons[1usize] = overlay.DialogButton { label: "Delete", action: actions[0usize], kind: .Destructive }
    var words = control.text_options()
    words.role = .BodyMedium
    words.align = .Center
    let (body, body_error) = control.colored_text(a, 102u64, "This cannot be undone.", t, words, style.color(t.tokens, .OnSurface))
    if body_error != ok { ret (0usize, body_error) }
    let (card, card_error) = overlay.linux_alert_card(a, 100u64, t, "Delete file?", body, buttons[0usize..2usize])
    if card_error != ok { ret (0usize, card_error) }
    // The window's content (540 x 400) under the scrim, the card in its middle.
    var dim = looks.size_style(540.0, 400.0)
    dim.background = paint.Brush { Solid: paint.rgba(0.0, 0.0, 0.0, 0.136) }
    if t.tokens.palette == .Dark { dim.background = paint.Brush { Solid: paint.rgba(0.0, 0.0, 0.0, 0.5) } }
    var window_face = looks.size_style(540.0, 400.0)
    window_face.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
    if layers_error != ok { ret (0usize, layers_error) }
    layers[0usize] = widget.box(0u64, dim, zero)
    layers[1usize] = widget.aligned(0u64, .Center, .Center, looks.size_style(540.0, 400.0), one_of(a, card))
    let content = widget.stack(0u64, window_face, layers[0usize..2usize])
    // The frame: 1 px, two of the lightest, one, one.
    var rings = [4]u32{ 0xE2E2E2u32, 0xFFFFFFu32, 0xFCFCFCu32, 0xDCDCDCu32 }
    if t.tokens.palette == .Dark { rings = [4]u32{ 0x4E4E4Eu32, 0x303030u32, 0x323232u32, 0x3Eu32 * 65793u32 } }
    let d = ring(a, 542.0, 402.0, rings[3usize], 1.0, content)
    let c = ring(a, 544.0, 404.0, rings[2usize], 1.0, d)
    let b = ring(a, 548.0, 408.0, rings[1usize], 2.0, c)
    let window = ring(a, 550.0, 410.0, rings[0usize], 1.0, b)
    cells[0usize] = looks.Cell { caption: "alert", node: window, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "dialog", cells: 1usize, columns: 1usize, cell_w: 570.0, cell_h: 430.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
