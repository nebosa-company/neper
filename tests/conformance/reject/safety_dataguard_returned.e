use e.mem
use e.sync

// A view of a guard's data returned past its deferred release (D1555, H04): the
// release runs as the `ret` leaves, so the return is E-SAFETY-0014.
type Counter = struct { hits: i64 }

fn grab(m: *sync.Mutex, c: *Counter) -> *Counter {
    let g = sync.data_guard[Counter](m, c)
    defer sync.data_release(g)
    let p = sync.data_of[Counter](&g)
    ret p
}

fn main(a: *mem.Arena, args: []str) -> err {
    var m: sync.Mutex = zero
    var counter: Counter = zero
    let p = grab(&m, &counter)
    p.hits = p.hits + 1i64
    ret ok
}
