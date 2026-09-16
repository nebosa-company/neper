use e.mem
use e.os

// A pointer bound from `&counter` is `counter` by another name (D393): a store
// through it while the thread the counter was lent to runs is E-SAFETY-0016, as the
// store to `counter` itself is.
type Counter = struct { hits: i64 }

fn bump(c: *Counter) {
    c.hits = c.hits + 1i64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var counter = Counter { hits: 0i64 }
    let alias = &counter
    let (worker, started) = os.thread_create[Counter](bump, &counter, 65536usize)
    if started != ok { ret started }
    alias.hits = 5i64
    let joined = os.thread_join(worker)
    ret ok
}
