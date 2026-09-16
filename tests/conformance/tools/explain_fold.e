use e.mem
use e.meta

// The phase (D463, H06): `meta.kind` is answered before the program runs, so the
// `if` in `width` folds in each instance -- the `phase` record says which arm
// stands, once per way it folded -- and the operand's aggregates come with their
// layouts on this target.
// A `const` is settled before the program runs too (D468): its `phase` record
// carries the type and the value the checker computed.
const LIMIT: i64 = 3i64 * 7i64
const NEGATIVE = -LIMIT
const READY = LIMIT > 20i64

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
