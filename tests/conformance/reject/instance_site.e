use e.mem

// A failure inside an instance's body (D466, H19): `widen` checks for `i32` and
// not for `bool`, and the diagnostic in the template body relates the site that
// asked for the failing instance -- the second call, not the first.
fn widen[T: type](v: T) -> i32 {
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let four = widen[i32](4i32)
    let never = widen[bool](true)
    if four != never { ret mem.Exhausted }
    ret ok
}
