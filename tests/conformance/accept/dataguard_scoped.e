use e.mem
use e.sync

// The data a guard protects is a view of the guard (D1555, H04): taken in an inner
// block, or under a deferred release, it lives no longer than the guard.
type Counter = struct { hits: i64 }

fn bump(m: *sync.Mutex, c: *Counter) {
    let g = sync.data_guard[Counter](m, c)
    defer sync.data_release(g)
    let p = sync.data_of[Counter](&g)
    p.hits = p.hits + 1i64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var m: sync.Mutex = zero
    var counter: Counter = zero
    let g = sync.data_guard[Counter](&m, &counter)
    if args.len != 99usize {
        let p = sync.data_of[Counter](&g)
        p.hits = p.hits + 1i64
    }
    sync.data_release(g)
    bump(&m, &counter)
    if counter.hits != 2i64 { ret mem.Exhausted }
    ret ok
}
