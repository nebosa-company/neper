// `e.thread` over `e.os`'s three intrinsics. What is the module's own is small -- the stack
// that may be left to it, and the name -- so what the fixture pins is that a thread spawned
// through it runs, is joined, and did its work in the context it was given; that a zero stack
// is the default and not a thread with nowhere to run; and that `Thread` is `os.Thread` in
// every respect, so one module's handle is the other's.

use e.mem
use e.os
use e.atomic
use e.thread

// `Atomic[T]` stands as a field rather than as a bare local, which is the shape
// `link/os_futex` already uses.
type Counter = struct { hits: Atomic[u32], seen: usize }

fn bump(c: *Counter) {
    var round = 0usize
    while round < 1000usize {
        let previous = atomic.add(&c.hits, 1u32, .SeqCst)
        round += 1usize
    }
    c.seen = 1000usize
}

fn main(a: *mem.Arena) -> err {
    // --- Spawned, joined, and the work is there. Two threads on one counter, so the total says
    // that both ran rather than one running twice.
    var counter: Counter = zero
    let (first, first_error) = thread.spawn[Counter](bump, &counter, thread.DEFAULT_STACK)
    if first_error != ok { os.exit(10i32) }
    let (second, second_error) = thread.spawn[Counter](bump, &counter, thread.DEFAULT_STACK)
    if second_error != ok { os.exit(11i32) }
    if thread.join(first) != ok { os.exit(12i32) }
    if thread.join(second) != ok { os.exit(13i32) }
    if atomic.load(&counter.hits, .SeqCst) != 2000u32 { os.exit(14i32) }
    if counter.seen != 1000usize { os.exit(15i32) }

    // --- A zero stack is the default. A thread with no stack would not get as far as writing
    // `seen`.
    var lazy: Counter = zero
    let (defaulted, defaulted_error) = thread.spawn[Counter](bump, &lazy, 0usize)
    if defaulted_error != ok { os.exit(20i32) }
    if thread.join(defaulted) != ok { os.exit(21i32) }
    if lazy.seen != 1000usize { os.exit(22i32) }

    // --- `Thread` is `os.Thread`: one spawned here is joined there, and the other way round.
    var crossed: Counter = zero
    let (ours, ours_error) = thread.spawn[Counter](bump, &crossed, 0usize)
    if ours_error != ok { os.exit(30i32) }
    if os.thread_join(ours) != ok { os.exit(31i32) }
    let (theirs, theirs_error) = os.thread_create[Counter](bump, &crossed, thread.DEFAULT_STACK)
    if theirs_error != ok { os.exit(32i32) }
    if thread.join(theirs) != ok { os.exit(33i32) }
    if atomic.load(&crossed.hits, .SeqCst) != 2000u32 { os.exit(34i32) }

    // --- Detached: accepted, and never joined. The work is not waited for, so it is not
    // checked -- what is checked is that detaching is not an error.
    var loose: Counter = zero
    let (detached, detached_error) = thread.spawn[Counter](bump, &loose, 0usize)
    if detached_error != ok { os.exit(40i32) }
    if thread.detach(detached) != ok { os.exit(41i32) }
    ret ok
}
