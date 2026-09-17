use e.mem

// A failure inside an instance asked for by another instance (D543, H09): `widen`
// fails for `bool`, asked for by `lift[bool]`, asked for by `main` -- the
// diagnostic relates the request in `lift`'s body and then `lift`'s own request,
// the chain up to the program's own code.
fn widen[T: type](v: T) -> i32 {
    ret v
}

fn lift[T: type](v: T) -> i32 {
    ret widen[T](v)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let four = lift[i32](4i32)
    let never = lift[bool](true)
    if four != never { ret mem.Exhausted }
    ret ok
}
