use e.mem

// A signature change (D415, H29): the parameters reordered by index, every call's
// arguments re-rendered from what was written -- a nested parenthesis and all.
fn adjust(reading: f32, gain: f32, offset: f32) -> f32 {
    ret reading * gain + offset
}

fn main(a: *mem.Arena, args: []str) -> err {
    let first = adjust(41.8, 1.0, 0.25)
    let second = adjust(first, 2.0, (0.5 + 0.25))
    if second < 0.0 { ret mem.Exhausted }
    ret ok
}
