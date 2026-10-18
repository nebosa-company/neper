// The Android look's dialogs, docs/ui/looks/material/dialog.png (basic: headline, supporting text, two text buttons) and
// dialog_icon.png (with an icon, centred headline). An open dialog is modal, so each sheet holds one. Run from the
// repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.overlay
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn buttons_of(a: *mem.Arena) -> ([]overlay.DialogButton, err) {
    let (buttons, buttons_error) = mem.alloc[overlay.DialogButton](a, 2usize)
    if buttons_error != ok { ret (zero, buttons_error) }
    let none = widget.Submit { ctx: zero, invoke: noop_submit }
    buttons[0usize] = overlay.DialogButton { label: "Cancel", action: none, kind: .Cancel }
    buttons[1usize] = overlay.DialogButton { label: "Accept", action: none, kind: .Default }
    ret (buttons[0usize..2usize], ok)
}

// A browser breaks a line at its advance width, the text layout here at its ink extent, which on a line of 300 is up to a pixel less:
// the paragraph box is 299 wide (and a pixel of margin) so that the same words fall on each line as in md-dialog's 300.
fn paragraph(a: *mem.Arena, body: widget.Node) -> widget.Node {
    var box = style.defaults()
    box.width = style.Length { Px: 299.0 }
    box.margin.right = style.Length { Px: 1.0 }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret body }
    held[0usize] = body
    ret widget.box(0u64, box, held[0usize..1usize])
}

// md.comp.dialog.supporting-text: body-medium in on-surface-variant.
fn supporting_options() -> control.TextOptions {
    var o = control.text_options()
    o.role = .BodyMedium
    o.color = .OnSurfaceVariant
    ret o
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (buttons, buttons_error) = buttons_of(a)
    if buttons_error != ok { ret (0usize, buttons_error) }
    let (body, body_error) = control.text(a, 102u64, "A dialog is a type of modal window that appears in front of app content to provide critical information, or prompt for a decision to be made.", t, supporting_options())
    if body_error != ok { ret (0usize, body_error) }
    let (dialog, dialog_error) = overlay.dialog(a, 100u64, t, "Basic dialog title", paragraph(a, body), buttons, true, true)
    if dialog_error != ok { ret (0usize, dialog_error) }
    cells[0usize] = looks.Cell { caption: "Basic", node: dialog, drive: .None }
    ret (1usize, ok)
}

fn build_icon(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (buttons, buttons_error) = buttons_of(a)
    if buttons_error != ok { ret (0usize, buttons_error) }
    let (body, body_error) = control.text(a, 102u64, "This will reset your app preferences back to their default settings. The following accounts will also be signed out:", t, supporting_options())
    if body_error != ok { ret (0usize, body_error) }
    let (dialog, dialog_error) = overlay.dialog_with_icon(a, 100u64, t, "Reset settings?", paragraph(a, body), buttons, .Search, false, true, true)
    if dialog_error != ok { ret (0usize, dialog_error) }
    cells[0usize] = looks.Cell { caption: "With icon", node: dialog, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let plain = looks.Sheet { name: "dialog", cells: 1usize, columns: 1usize, cell_w: 330.0, cell_h: 300.0, ctx: zero, build: build }
    try looks.run_material(a, &plain)
    let icon = looks.Sheet { name: "dialog_icon", cells: 1usize, columns: 1usize, cell_w: 330.0, cell_h: 340.0, ctx: zero, build: build_icon }
    ret looks.run_material(a, &icon)
}
