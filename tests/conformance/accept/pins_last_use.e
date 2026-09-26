use e.mem
use e.os
use e.sync

// A pin lives to its pointer's last use, not to the block's end (D1561, H02): a
// guard's data view used and then the guard released, and a file's pointer used
// and then the file closed, in the same block. Inside a loop the block's end still
// rules.
type Counter = struct { hits: i64 }

fn peek(f: *os.File) -> bool {
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var m: sync.Mutex = zero
    var counter: Counter = zero
    let g = sync.data_guard[Counter](&m, &counter)
    let p = sync.data_of[Counter](&g)
    p.hits = p.hits + 1i64
    sync.data_release(g)
    let flags = os.OpenFlags { read: false, write: true, create: true, truncate: true, append: false }
    var f = try os.open(a, "np-pins-last-use.txt", flags)
    let held = &f
    let seen = peek(held)
    try os.close(f)
    if counter.hits != 1i64 || !seen { ret mem.Exhausted }
    ret ok
}
