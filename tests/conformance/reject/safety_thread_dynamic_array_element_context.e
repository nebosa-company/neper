use e.mem
use e.os

// A runtime-selected thread context may lend either pointer element, so every
// possible owner is unavailable to the parent until the join (D714).
type Counter = struct { hits: i64 }

fn bump(hits: *i64) {
    *hits = *hits + 1i64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var first = Counter { hits: 0i64 }
    var second = Counter { hits: 0i64 }
    let contexts = [2usize]*Counter{ &first, &second }
    let which = args.len % 2usize
    let worker = try os.thread_create[i64](bump, &contexts[which].hits, 65536usize)
    let seen = second.hits
    try os.thread_join(worker)
    if seen != 0i64 { ret mem.Exhausted }
    ret ok
}
