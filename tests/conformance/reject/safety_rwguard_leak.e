use e.mem
use e.sync

// A read guard is a resource owed to `sync.read_release` (D433, H04): an early
// return with the lock held is E-SAFETY-0002, as a mutex guard's is.
fn read(l: *sync.RwLock, fail: bool) -> err {
    let g = sync.read_guard(l)
    if fail { ret mem.Exhausted }
    sync.read_release(g)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    var l = sync.rwlock()
    ret read(&l, args.len > 3usize)
}
