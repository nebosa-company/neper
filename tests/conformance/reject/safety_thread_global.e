use e.mem
use e.os

// A module-scope variable the thread's entry function writes (D1556, H04): naming
// it in the parent before the join is E-SAFETY-0016.
var hits: i64 = 0i64

type Job = struct { n: i64 }

fn count(n: i64) {
    hits = hits + n
}

fn work(j: *Job) {
    count(j.n)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var job = Job { n: 1i64 }
    let (worker, started) = os.thread_create[Job](work, &job, 65536usize)
    if started != ok { ret started }
    hits = hits + 1i64
    try os.thread_join(worker)
    ret ok
}
