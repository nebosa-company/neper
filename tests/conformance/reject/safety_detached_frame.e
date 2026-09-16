use e.mem
use e.os

// A thread started over the address of this frame's storage can only be joined
// here (D357): detaching it would leave it reading a frame that is gone,
// E-SAFETY-0015.
type Counter = struct { value: usize }

fn bump(counter: *Counter) {
    counter.value = counter.value + 1usize
}

fn main(a: *mem.Arena, args: []str) -> err {
    var counter: Counter = zero
    let worker = try os.thread_create[Counter](bump, &counter, 65536usize)
    ret os.thread_detach(worker)
}
