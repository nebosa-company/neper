// Round 62 lane b: drawing helpers for the gauge, level and activity indicator that differ by look.

use e.gfx.paint
use e.ui.style

// The rest colour of a gauge track or a level bar. Libadwaita's window is the same colour as SurfaceContainerHighest, so the
// Linux look draws the progress bar's trough instead (the text colour at 11.6 %, 15 % Dark).
fn track_color(tokens: *const style.ThemeTokens) -> paint.Color {
    if tokens.profile == .Linux {
        if tokens.palette == .Dark { ret paint.rgba(1.0, 1.0, 1.0, 0.15) }
        ret paint.rgba(0.0, 0.0, 0.0, 0.116)
    }
    ret style.color(tokens, .SurfaceContainerHighest)
}
