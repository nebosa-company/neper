// Round 78, lane n: Android and macOS / iOS completion. New code lives here; shared files carry only the hooks.

use e.ui.control
use e.ui.style

// The time picker's digits: M3 and Flutter use display-large (57) in the Android look, the other looks keep display-small.
fn time_digit_role(t: *const control.Theme) -> style.TextRole {
    if t.tokens.profile == .MaterialLike { ret .DisplayLarge }
    ret .DisplaySmall
}
