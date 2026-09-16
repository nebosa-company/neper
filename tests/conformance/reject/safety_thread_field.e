use e.mem
use e.os

// A struct holding `&counter` in a field aliases `counter` through that field (D413):
// a store through `ctx.target` while the thread `counter` was lent to runs is
// E-SAFETY-0016; `ctx.rounds`, a field of the struct's own, is not.
type Counter = struct { hits: i64 }
type Context = struct { target: *Counter, rounds: i64 }

fn bump(c: *Counter) {
    c.hits = c.hits + 1i64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var counter = Counter { hits: 0i64 }
    var ctx = Context { target: &counter, rounds: 0i64 }
    let (worker, started) = os.thread_create[Counter](bump, &counter, 65536usize)
    if started != ok { ret started }
    ctx.rounds = ctx.rounds + 1i64
    ctx.target.hits = 5i64
    let joined = os.thread_join(worker)
    ret ok
}
