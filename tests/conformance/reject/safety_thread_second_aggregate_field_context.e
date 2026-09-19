use e.mem
use e.os

// A thread context through the second aggregate pointer field lends that field's
// owner rather than the first field's owner or the aggregate itself (D695).
type Stable = struct { value: i64 }
type Counter = struct { hits: i64 }
type Context = struct { stable: *Stable, target: *Counter }

fn bump(hits: *i64) {
    *hits = *hits + 1i64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var stable = Stable { value: 1i64 }
    var counter = Counter { hits: 0i64 }
    let context = Context { stable: &stable, target: &counter }
    let worker = try os.thread_create[i64](bump, &context.target.hits, 65536usize)
    let seen = counter.hits
    try os.thread_join(worker)
    if seen != 0i64 { ret mem.Exhausted }
    ret ok
}
