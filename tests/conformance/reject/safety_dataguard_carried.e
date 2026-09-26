use e.mem
use e.sync

// A view of a guard's data carried out of its block in another local (D1555, H04):
// the release ends every view of the guard, so the later use is E-SAFETY-0014.
type Counter = struct { hits: i64 }

fn main(a: *mem.Arena, args: []str) -> err {
    var m: sync.Mutex = zero
    var counter: Counter = zero
    var other: Counter = zero
    var kept = &other
    let g = sync.data_guard[Counter](&m, &counter)
    if args.len != 99usize {
        let p = sync.data_of[Counter](&g)
        kept = p
    }
    sync.data_release(g)
    kept.hits = kept.hits + 1i64
    ret ok
}
