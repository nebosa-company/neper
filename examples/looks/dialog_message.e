// A message box (an alert with an icon and an OK button) under every look:
// docs/ui/looks/<look>/dialog_message.png. Part of the dialog control (see dialog.e).
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.overlay
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (buttons, buttons_error) = mem.alloc[overlay.DialogButton](a, 2usize)
    if buttons_error != ok { ret (0usize, buttons_error) }
    let none = widget.Submit { ctx: zero, invoke: noop_submit }
    buttons[0usize] = overlay.DialogButton { label: "Yes", action: none, kind: .Default }
    buttons[1usize] = overlay.DialogButton { label: "No", action: none, kind: .Cancel }
    var words = control.text_options()
    let (body, body_error) = control.text(a, 102u64, "Delete the deck Mono Red Burn?", t, words)
    if body_error != ok { ret (0usize, body_error) }
    let (dialog, dialog_error) = overlay.dialog_with_icon(a, 100u64, t, "Confirm", body, buttons[0usize..2usize], .Warning, false, true, true)
    if dialog_error != ok { ret (0usize, dialog_error) }
    cells[0usize] = looks.Cell { caption: "Message box", node: dialog, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "dialog_message", cells: 1usize, columns: 1usize, cell_w: 480.0, cell_h: 280.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
