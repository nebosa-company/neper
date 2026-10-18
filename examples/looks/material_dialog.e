// The Android look's dialogs, docs/ui/looks/material/dialog.png (basic: headline, supporting text, two text buttons) and
// dialog_icon.png (with an icon, centred headline). An open dialog is modal, so each sheet holds one. Run from the
// repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.overlay
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
    let (dialog, dialog_error) = overlay.dialog(a, 100u64, t, "Basic dialog title", body, buttons, true, true)
    if dialog_error != ok { ret (0usize, dialog_error) }
    cells[0usize] = looks.Cell { caption: "Basic", node: dialog, drive: .None }
    ret (1usize, ok)
}

fn build_icon(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (buttons, buttons_error) = buttons_of(a)
    if buttons_error != ok { ret (0usize, buttons_error) }
    let (body, body_error) = control.text(a, 102u64, "This will reset your app preferences back to their default settings. The following accounts will also be signed out:", t, supporting_options())
    if body_error != ok { ret (0usize, body_error) }
    let (dialog, dialog_error) = overlay.dialog_with_icon(a, 100u64, t, "Reset settings?", body, buttons, .Refresh, false, true, true)
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
