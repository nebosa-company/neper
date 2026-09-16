use e.mem

// A parameter removed by a change-signature plan (D439, H17): `scale` is left out
// of the order and the body never names it, so it goes from the declaration and
// its argument from every call; `gain`, which the body reads, cannot go.
fn adjust(reading: f32, gain: f32, scale: f32) -> f32 {
    ret reading * gain
}

fn main(a: *mem.Arena, args: []str) -> err {
    let first = adjust(41.8, 1.0, 0.25)
    let second = adjust(first, 2.0, (0.5 + 0.25))
    if second < 0.0 { ret mem.Exhausted }
    ret ok
}
