use e.mem
use e.os

// A thread context holding a slice that came from a parameter (D1556, H04): the
// slice is lent with the context, so reading it before the join is E-SAFETY-0016.
type Job = struct { data: []u8 }

fn work(j: *Job) {
    j.data[0usize] = 7u8
}

fn run(items: []u8) -> err {
    var job = Job { data: items }
    let (worker, started) = os.thread_create[Job](work, &job, 65536usize)
    if started != ok { ret started }
    let seen = items[0usize]
    try os.thread_join(worker)
    if seen == 99u8 { ret mem.Exhausted }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (bytes, alloc_error) = mem.alloc[u8](a, 4usize)
    if alloc_error != ok { ret alloc_error }
    ret run(bytes)
}
