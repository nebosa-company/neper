use e.mem
use e.os

// A thread context through a later recursively nested pointer field lends that
// field's owner rather than the first nested owner or carrier (D705).
type Stable = struct { value: i64 }
type Counter = struct { hits: i64 }
type Inner = struct { stable: *Stable, target: *Counter }
type Middle = struct { inner: Inner }
type Context = struct { middle: Middle }

fn bump(hits: *i64) {
    *hits = *hits + 1i64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var stable = Stable { value: 1i64 }
    var counter = Counter { hits: 0i64 }
    let context = Context { middle: Middle { inner: Inner { stable: &stable, target: &counter } } }
    let worker = try os.thread_create[i64](bump, &context.middle.inner.target.hits, 65536usize)
    let seen = counter.hits
    try os.thread_join(worker)
    if seen != 0i64 { ret mem.Exhausted }
    ret ok
}
