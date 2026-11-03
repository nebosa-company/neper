// Round 84, lane z: the Android disabled field's outline. M3 draws a disabled outlined field's outline at on-surface 12 % and its
// content at 38 %; the image combo box dims the whole field at 38 %, so while it builds the head the outline asks for 12 / 38 of
// on-surface (which the 38 % dim brings to 12 %). control.e carries only the two calls.
var dimmed: bool = false

fn set(value: bool) { dimmed = value }

fn on() -> bool { ret dimmed }


// A sheet that cannot wait for an indeterminate indicator to sweep asks for it drawn at a fixed progress, in percent (-1: as the
// library draws it).
var ring_pct: i32 = -1i32

fn set_ring(percent: i32) { ring_pct = percent }

fn ring() -> f32 {
    if ring_pct < 0i32 { ret -1.0 }
    ret f32(ring_pct) / 100.0
}

