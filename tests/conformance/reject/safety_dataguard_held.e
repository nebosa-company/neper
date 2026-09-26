use e.mem
use e.sync

// A guard released while a view of its data is still used after it (D1555, D1561,
// H04): the pointer taken to the guard lives to its last use, so the release is
// E-SAFETY-0004.
type Counter = struct { hits: i64 }

fn main(a: *mem.Arena, args: []str) -> err {
    var m: sync.Mutex = zero
    var counter: Counter = zero
    let g = sync.data_guard[Counter](&m, &counter)
    let p = sync.data_of[Counter](&g)
    p.hits = p.hits + 1i64
    sync.data_release(g)
    if p.hits != 1i64 { ret mem.Exhausted }
    ret ok
}
