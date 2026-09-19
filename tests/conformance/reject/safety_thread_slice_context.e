use e.mem
use e.os

// A thread started over a slice element lends the slice's backing array (D679).
type Counter = struct { value: usize }

fn bump(counter: *Counter) {
    counter.value = counter.value + 1usize
}

fn main(a: *mem.Arena, args: []str) -> err {
    var counters: [2]Counter = zero
    let window = counters[0usize..]
    let worker = try os.thread_create[Counter](bump, &window[0usize], 65536usize)
    let seen = counters[0usize].value
    try os.thread_join(worker)
    if seen != 0usize { ret mem.Exhausted }
    ret ok
}
