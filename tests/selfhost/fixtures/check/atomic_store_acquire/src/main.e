// Section 8: a store may not take an acquire ordering.
use e.atomic

type Counter = struct { hits: Atomic[u64] }

fn main() -> i64 {
    var c: Counter = zero
    atomic.store(&c.hits, 1u64, .Acquire)
    ret 0i64
}
