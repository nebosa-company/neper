use e.mem
use e.os

// A slice bound from `counts[0..2]` views `counts` (D395): a store through it while
// the thread `counts` was lent to runs is E-SAFETY-0016, as `counts[0] = 5` is.
type Counts = struct { hits: [4]i64 }

fn bump(c: *Counts) {
    c.hits[0usize] = c.hits[0usize] + 1i64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var counts: Counts = zero
    let head = counts.hits[0usize..2usize]
    let (worker, started) = os.thread_create[Counts](bump, &counts, 65536usize)
    if started != ok { ret started }
    head[0usize] = 5i64
    let joined = os.thread_join(worker)
    ret ok
}
