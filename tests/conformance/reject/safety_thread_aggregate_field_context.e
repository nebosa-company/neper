use e.mem
use e.os

// An address reached through an aggregate's pointer field lends the pointed-to
// storage, not the aggregate that carries the pointer (D686).
type Counter = struct { hits: i64 }
type Context = struct { target: *Counter }

fn bump(hits: *i64) {
    *hits = *hits + 1i64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var counter = Counter { hits: 0i64 }
    let context = Context { target: &counter }
    let worker = try os.thread_create[i64](bump, &context.target.hits, 65536usize)
    let seen = counter.hits
    try os.thread_join(worker)
    if seen != 0i64 { ret mem.Exhausted }
    ret ok
}
