// A dialog (v3's Options window) under every look: docs/ui/looks/<look>/dialog.png.
// One dialog fills the sheet: a dialog is a modal overlay, centred in whatever it is shown over.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.overlay
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

// The Options dialog's chrome: a body line, then OK (the default), Cancel and Apply.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (buttons, buttons_error) = mem.alloc[overlay.DialogButton](a, 3usize)
    if buttons_error != ok { ret (0usize, buttons_error) }
    let none = widget.Submit { ctx: zero, invoke: noop_submit }
    buttons[0usize] = overlay.DialogButton { label: "OK", action: none, kind: .Default }
    buttons[1usize] = overlay.DialogButton { label: "Cancel", action: none, kind: .Cancel }
    buttons[2usize] = overlay.DialogButton { label: "Apply", action: none, kind: .Plain }
    var words = control.text_options()
    let (body, body_error) = control.text(a, 0u64, "Hide splash screen on start", t, words)
    if body_error != ok { ret (0usize, body_error) }
    let (dialog, dialog_error) = overlay.dialog(a, 100u64, t, "Options", body, buttons[0usize..3usize], true, false)
    if dialog_error != ok { ret (0usize, dialog_error) }
    // The dialog's overlay centres in the whole sheet; the cell only reserves the room.
    cells[0usize] = looks.Cell { caption: "Options", node: dialog, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "dialog", cells: 1usize, columns: 1usize, cell_w: 480.0, cell_h: 280.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
