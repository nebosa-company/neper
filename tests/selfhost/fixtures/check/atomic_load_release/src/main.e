// Section 8: a load may not take a release ordering, as C11 has it.
use e.atomic

type Counter = struct { hits: Atomic[u64] }

fn main() -> i64 {
    var c: Counter = zero
    let v = atomic.load(&c.hits, .Release)
    ret 0i64
}
