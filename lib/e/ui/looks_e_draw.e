// Round 62, worker e: drawing the navigation sheets need beyond the shared files. Kept apart from looks_e (which imports the harness).

use e.mem
use e.ui.control
use e.ui.widget

// The GTK header bar's back button: a 34 px flat icon button with the arrow, at the start of the bar (libadwaita draws
// go-previous-symbolic there). The action is copied into the frame arena so it outlives the caller's options.
fn linux_back(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, action: widget.Submit) -> (widget.Node, err) {
    let (held, held_error) = mem.alloc[widget.Submit](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = action
    let (made, made_error) = control.glyph_button(a, key, t, .ArrowBack, label, &held[0usize], 34.0, 16.0)
    ret (made, made_error)
}
