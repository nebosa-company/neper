// Section 8: a compare-and-swap failure ordering may not be stronger than its
// success ordering.
use e.atomic

type Counter = struct { hits: Atomic[u64] }

fn main() -> i64 {
    var c: Counter = zero
    let (won, seen) = atomic.cas(&c.hits, 1u64, 2u64, .Relaxed, .SeqCst)
    ret 0i64
}
