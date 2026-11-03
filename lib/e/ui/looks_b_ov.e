// Round 62 lane b: overlay-side drawing that needs the control module (looks_b.e cannot import it).

use e.mem
use e.ui.control
use e.ui.widget

// The Windows date range field: v3's drop-down face (win_head) 200 wide, so both dates fit; the date edit's 112 would clip them.
fn windows_range_head(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, shown: str, chosen: bool, open: bool, toggle: *const widget.Submit) -> (widget.Node, err) {
    var none: []const widget.Node = zero
    let (head, head_error) = control.win_head(a, key, t, label, shown, chosen, open, toggle, true, none, 200.0, 0.0, 0.0)
    ret (head, head_error)
}
