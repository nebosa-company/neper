use e.mem
use e.os

// Module-scope variables and a thread (D1556, H04): the one the thread writes is
// named here only after the join, and the one it never names at any time.
var hits: i64 = 0i64
var calls: i64 = 0i64

type Job = struct { n: i64 }

fn work(j: *Job) {
    hits = hits + j.n
}

fn main(a: *mem.Arena, args: []str) -> err {
    var job = Job { n: 1i64 }
    let (worker, started) = os.thread_create[Job](work, &job, 65536usize)
    if started != ok { ret started }
    calls = calls + 1i64
    try os.thread_join(worker)
    hits = hits + 1i64
    if hits != 2i64 || calls != 1i64 { ret mem.Exhausted }
    ret ok
}
