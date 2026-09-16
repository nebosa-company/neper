use e.mem
use e.sync

// A guard is a resource owed to `sync.release` (D379, H04): an early return with the
// lock held is E-SAFETY-0002, the leak it would be.
fn take(m: *sync.Mutex, fail: bool) -> err {
    let g = sync.guard(m)
    if fail { ret mem.Exhausted }
    sync.release(g)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    var m = sync.mutex()
    ret take(&m, args.len > 3usize)
}
