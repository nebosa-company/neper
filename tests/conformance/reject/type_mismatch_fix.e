use e.mem

// A mismatch of two numbers at a name (D444, H09): the diagnostic carries the
// conversion as a `maybe` fix, `i32(wide)` over the name's span.
fn main(a: *mem.Arena, args: []str) -> err {
    let wide: i64 = 7i64
    let narrow: i32 = wide
    if narrow != 7i32 { ret mem.Exhausted }
    ret ok
}
