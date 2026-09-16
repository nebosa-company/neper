use e.mem
use e.os

// A pointer assigned `&other` after its binding aliases `other` from then on
// (D416): a store through it while `other` is lent to a running thread is
// E-SAFETY-0016, naming `other`; the local it was bound from is not the one.
type Counter = struct { hits: i64 }

fn bump(c: *Counter) {
    c.hits = c.hits + 1i64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var first = Counter { hits: 0i64 }
    var other = Counter { hits: 0i64 }
    var alias = &first
    alias = &other
    let (worker, started) = os.thread_create[Counter](bump, &other, 65536usize)
    if started != ok { ret started }
    alias.hits = 5i64
    let joined = os.thread_join(worker)
    ret ok
}
