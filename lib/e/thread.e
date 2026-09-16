// A thread is the `e.os` primitive with one convenience: a stack size that may be left to the
// module. Nothing else is added, and nothing is hidden -- `Thread` is `os.Thread` by name, so
// a caller holding one can hand it to either module and be understood.
//
// Three calls, and the discipline they impose is `e.os`'s: a thread is joined or detached,
// once, and a detached one gives its stack back only when the host reclaims it (D-os_thread).

use e.mem
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

// A group of threads started together (D434, H04): one resource owed to `join_all`,
// so H01's exit audit holds the joins of an array of threads as it holds one
// thread's, and a start that fails part way joins what it started before it
// answers -- the K-th failure owes the K-1 joins, and the caller is owed nothing.
type Group = resource(join_all) struct { threads: []Thread, count: usize }

// One thread per context, each given the address of its own element, so the
// contexts are lent to the group until `join_all` (D365).
fn spawn_all[Ctx: type](a: *mem.Arena, entry: fn(*Ctx), contexts: []Ctx, stack: usize) -> (Group, err) {
    var g: Group = zero
    let (threads, threads_error) = mem.alloc[Thread](a, contexts.len)
    if threads_error != ok { ret (g, threads_error) }
    g.threads = threads
    var at = 0usize
    while at < contexts.len {
        let (started, start_error) = spawn[Ctx](entry, &contexts[at], stack)
        if start_error != ok {
            let abandoned = join_all(g)
            ret (g, start_error)
        }
        threads[at] = started
        g.count = at + 1usize
        at += 1usize
    }
    ret (g, ok)
}

// Every thread of the group, in start order; the first join error is the answer,
// and the rest are joined regardless.
fn join_all(g: own Group) -> err {
    var first = ok
    var at = 0usize
    while at < g.count {
        let joined = join(g.threads[at])
        if joined != ok && first == ok { first = joined }
        at += 1usize
    }
    ret first
}
