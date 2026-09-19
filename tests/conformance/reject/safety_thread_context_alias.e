use e.mem
use e.os

// Starting through a pointer alias lends the underlying frame local (D674).
type Counter = struct { value: usize }

fn bump(counter: *Counter) {
    counter.value = counter.value + 1usize
}

fn main(a: *mem.Arena, args: []str) -> err {
    var counter: Counter = zero
    let context = &counter
    let worker = try os.thread_create[Counter](bump, context, 65536usize)
    let seen = counter.value
    try os.thread_join(worker)
    if seen != 0usize { ret mem.Exhausted }
    ret ok
}
