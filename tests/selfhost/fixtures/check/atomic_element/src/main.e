// Section 8: `Atomic[T]` is legal for an integer or a pointer `T`, and nothing else.
use e.atomic

fn main() -> i64 {
    var bad: Atomic[f64] = zero
    ret 0i64
}
