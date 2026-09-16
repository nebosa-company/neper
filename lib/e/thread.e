// A thread is the `e.os` primitive with one convenience: a stack size that may be left to the
// module. Nothing else is added, and nothing is hidden -- `Thread` is `os.Thread` by name, so
// a caller holding one can hand it to either module and be understood.
//
// Three calls, and the discipline they impose is `e.os`'s: a thread is joined or detached,
// once, and a detached one gives its stack back only when the host reclaims it (D-os_thread).

use e.os

type Thread = os.Thread

// One megabyte, which is what both hosts give a thread that does not say. Deep recursion
// wants more and a pool of thousands wants less; both know it and say so.
const DEFAULT_STACK: usize = 1048576usize

// `stack` may be zero, and zero means `DEFAULT_STACK` rather than a thread with nowhere to
// run -- the same reading of zero every other bound in `lib/e` has.
fn spawn[Ctx: type](entry: fn(*Ctx), ctx: *Ctx, stack: usize) -> (Thread, err) {
    var size = stack
    if size == 0usize { size = DEFAULT_STACK }
    let (started, start_error) = os.thread_create[Ctx](entry, ctx, size)
    ret (started, start_error)
}

fn join(thread: own Thread) -> err {
    ret os.thread_join(thread)
}

fn detach(thread: own Thread) -> err {
    ret os.thread_detach(thread)
}
