// `os.thread_create` / `thread_join` / `thread_detach`. The context type is bound at
// the call and the entry point checked against it; after that both are pointers.
//
// Linux has no implementation yet -- the ELF output is static with no libc, so a
// thread there means `clone(2)` with a stack of its own and a futex join -- and says
// so with `Unsupported` rather than failing to link. The early return goes away when
// that lands, and the assertions below start applying there too.

use e.mem
use e.os

error Failed

type Counter = struct {
    value: usize,
}

fn bump(c: *Counter) {
    c.value = 7usize
}

fn main(a: *mem.Arena) -> err {
    var counter: Counter = zero
    let (worker, create_error) = os.thread_create[Counter](bump, &counter, 1048576usize)
    if create_error == os.Unsupported { ret ok }
    if create_error != ok { ret create_error }

    // `join` is what makes the write visible: without it the read below races.
    let join_error = os.thread_join(worker)
    if join_error != ok { ret join_error }
    if counter.value != 7usize { ret Failed }

    // A detached thread is one nothing waits for, so it only has to be startable --
    // over storage that outlives this frame (D357), since nothing joins it here.
    let (spares, spares_error) = mem.alloc[Counter](a, 1usize)
    if spares_error != ok { ret spares_error }
    let (loose, loose_error) = os.thread_create[Counter](bump, &spares[0usize], 1048576usize)
    if loose_error != ok { ret loose_error }
    let detach_error = os.thread_detach(loose)
    if detach_error != ok { ret detach_error }
    ret ok
}
