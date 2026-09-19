use e.mem
use e.os

// A thread context through a later fixed-array pointer element lends that
// element's owner rather than the first element's owner or the array (D710).
type Counter = struct { hits: i64 }

fn bump(hits: *i64) {
    *hits = *hits + 1i64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var first = Counter { hits: 0i64 }
    var second = Counter { hits: 0i64 }
    let contexts = [2usize]*Counter{ &first, &second }
    let worker = try os.thread_create[i64](bump, &contexts[1usize].hits, 65536usize)
    let seen = second.hits
    try os.thread_join(worker)
    if seen != 0i64 { ret mem.Exhausted }
    ret ok
}
