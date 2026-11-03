// Round 87, lane z: where a Material sheet's driven cell puts the pointer. `looks.aim` is process-wide and the sheet apps run every
// look in one process, so every look sets it: the Android look the given offset, all others none (their pictures are unchanged).
use e.ui.control
use e.ui.looks

fn aim(t: *const control.Theme, i: usize, dx: f32, dy: f32) {
    if t.tokens.profile == .MaterialLike {
        looks.aim(i, dx, dy)
    } else {
        looks.aim(i, 0.0, 0.0)
    }
}
