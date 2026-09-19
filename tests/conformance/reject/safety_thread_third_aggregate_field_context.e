use e.mem
use e.os

// A thread context through the third aggregate pointer field lends that field's
// owner rather than either earlier owner or the aggregate itself (D700).
type Stable = struct { value: i64 }
type Counter = struct { hits: i64 }
type Context = struct { first: *Stable, second: *Stable, target: *Counter }

fn bump(hits: *i64) {
    *hits = *hits + 1i64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var first = Stable { value: 1i64 }
    var second = Stable { value: 2i64 }
    var counter = Counter { hits: 0i64 }
    let context = Context { first: &first, second: &second, target: &counter }
    let worker = try os.thread_create[i64](bump, &context.target.hits, 65536usize)
    let seen = counter.hits
    try os.thread_join(worker)
    if seen != 0i64 { ret mem.Exhausted }
    ret ok
}
