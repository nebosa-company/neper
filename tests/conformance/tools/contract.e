use e.mem
use e.os

// The caller's contract `context-file` states from a signature (D396, H11): `bump`
// mutates what it is given (the caller's views dangle), `first` borrows it (a view
// comes back), `main` allocates from its arena, is fallible, starts a thread and
// names `bump` as a value.
type Counter = struct { hits: [4]i64 }

fn bump(c: *Counter) {
    c.hits[0usize] = c.hits[0usize] + 1i64
}

fn first(c: *Counter) -> *i64 {
    ret &c.hits[0usize]
}

fn total(c: *const Counter) -> i64 {
    ret c.hits[0usize] + c.hits[1usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    var counter: Counter = zero
    let (worker, started) = os.thread_create[Counter](bump, &counter, 65536usize)
    if started != ok { ret started }
    try os.thread_join(worker)
    let head = first(&counter)
    if *head != total(&counter) { ret mem.Exhausted }
    ret ok
}
