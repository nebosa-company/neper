use e.mem
use e.sync

// A guard released while a view of its data lives in the same block (D1555, H04):
// the pointer taken to the guard lives to the block's end, so the release is
// E-SAFETY-0004.
type Counter = struct { hits: i64 }

fn main(a: *mem.Arena, args: []str) -> err {
    var m: sync.Mutex = zero
    var counter: Counter = zero
    let g = sync.data_guard[Counter](&m, &counter)
    let p = sync.data_of[Counter](&g)
    p.hits = p.hits + 1i64
    sync.data_release(g)
    ret ok
}
