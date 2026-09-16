use e.mem
use e.os

// What a thread was given is the thread's until the join (D365): the parent reading
// it in between races with the thread, E-SAFETY-0016; an atomic through its address
// would not.
type Counter = struct { value: usize }

fn bump(counter: *Counter) {
    counter.value = counter.value + 1usize
}

fn main(a: *mem.Arena, args: []str) -> err {
    var counter: Counter = zero
    let worker = try os.thread_create[Counter](bump, &counter, 65536usize)
    let seen = counter.value
    try os.thread_join(worker)
    if seen != 0usize { ret mem.Exhausted }
    ret ok
}
