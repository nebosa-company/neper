use e.mem
use e.meta

// The phase (D463, H06): `meta.kind` is answered before the program runs, so the
// `if` in `width` folds in each instance -- the `phase` record says which arm
// stands, once per way it folded -- and the operand's aggregates come with their
// layouts on this target.
type Pair = struct { tag: u8, value: i64 }
type Choice = union enum u8 { None, Some: i64 }

fn width[T: type](v: T) -> usize {
    if meta.kind[T]() == .Int { ret 8usize } else { ret 0usize }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let numbers = width[i64](3i64)
    let words = width[str]("x")
    if numbers + words != 8usize { ret mem.Exhausted }
    ret ok
}
