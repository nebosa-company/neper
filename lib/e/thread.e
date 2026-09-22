// A thread is the `e.os` primitive with one convenience: a stack size that may be left to the
// module. Nothing else is added, and nothing is hidden -- `Thread` is `os.Thread` by name, so
// a caller holding one can hand it to either module and be understood.
//
// Three calls, and the discipline they impose is `e.os`'s: a thread is joined or detached,
// once, and a detached one gives its stack back only when the host reclaims it (D-os_thread).

use e.mem
use e.os
use e.sync

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

// ---- fibers (algo 1336) -------------------------------------------------------
//
// Green threads over caller storage: a fiber is an index into the caller's `[]Fiber`,
// its body is the caller's `fn(*Ctx, u32)` at the same index, and the scheduler hands
// control from one fiber to the next so that exactly one of them runs at any instant.
// A switch is one `sync.Event` set and one waited -- the giver marks the receiver
// Running, sets its permit and parks on its own -- so the schedule is the program's
// and never the host's, and a fiber that never switches is never interrupted.
//
// This is the THREAD-BACKED form: every fiber is one OS thread from `spawn`, parked on
// its permit whenever it is not the one running. That is what gives a fiber a real
// stack without a stack switch, and it is also the ceiling.
//
// ponytail: a fiber costs an OS thread and its stack (`DEFAULT_STACK`, a megabyte), and
// a switch costs a wake and a park rather than a few stores. The upgrade is a stack
// switch in the runtime prefix (`src/runtime_pe_x64.e`, `src/runtime_elf_x64.e`): save
// the callee-saved registers, swap `rsp` to a slab the scheduler owns, and a fiber
// becomes a few hundred bytes on one thread. Only `switch_to`, `switch_to_host` and
// `dispatch` below know how control moves, so that is the whole change.

type FiberState = enum u8 { Ready, Running, Suspended, Done }
type Fiber = struct { permit: sync.Event, thread: Thread, owner: *void, id: u32, state: FiberState, started: bool, joined: bool }
type Scheduler[Ctx: type] = struct { ctx: *Ctx, fibers: []Fiber, bodies: []fn(*Ctx, u32), count: usize, limit: usize, running: u32, cursor: u32, done: usize, host: sync.Event }

error Invalid
error Full

// `current` answers this when the host thread -- the one inside `run` -- is the runner,
// which is every moment no fiber holds control.
const NO_FIBER: u32 = 4294967295u32

// The scheduler over the caller's storage: `fibers` and `bodies` are parallel arrays,
// `fibers.len` is the ceiling on live fibers and `worker_count` lowers it (zero means
// the storage). The scheduler is pointed at by every fiber it starts, so it must not be
// moved once `fiber` has been called on it.
fn scheduler[Ctx: type](ctx: *Ctx, fibers: []Fiber, bodies: []fn(*Ctx, u32), worker_count: usize) -> (Scheduler[Ctx], err) {
    var s: Scheduler[Ctx] = zero
    if fibers.len == 0usize || bodies.len < fibers.len { ret (s, Invalid) }
    var room = worker_count
    if room == 0usize || room > fibers.len { room = fibers.len }
    s.ctx = ctx
    s.fibers = fibers
    s.bodies = bodies
    s.count = 0usize
    s.limit = room
    s.running = NO_FIBER
    s.cursor = NO_FIBER
    s.done = 0usize
    s.host = sync.event(false, false)
    ret (s, ok)
}

// The parked thread behind one fiber: it waits for its first permit, runs the body once,
// marks itself Done and hands control back to the host, which is what makes a finished
// fiber unschedulable -- only a Ready one is ever picked.
fn fiber_main[Ctx: type](f: *Fiber) {
    sync.event_wait(&f.permit)
    let s = mem.cast[*Scheduler[Ctx]](f.owner)
    let body = s.bodies[usize(f.id)]
    body(s.ctx, f.id)
    f.state = .Done
    s.done += 1usize
    s.running = NO_FIBER
    sync.event_set(&s.host)
}

// A new fiber, Ready and parked, and its id; `Full` once `worker_count` is reached.
fn fiber[Ctx: type](s: *Scheduler[Ctx], body: fn(*Ctx, u32)) -> (u32, err) {
    if s.count >= s.limit { ret (NO_FIBER, Full) }
    let id = u32(s.count)
    let f = &s.fibers[s.count]
    f.permit = sync.event(false, false)
    f.owner = mem.cast[*void](s)
    f.id = id
    f.state = .Ready
    f.started = false
    f.joined = false
    s.bodies[s.count] = body
    let (started, start_error) = spawn[Fiber](fiber_main[Ctx], f, 0usize)
    if start_error != ok { ret (NO_FIBER, start_error) }
    f.thread = started
    f.started = true
    s.count += 1usize
    ret (id, ok)
}

// The first Ready fiber strictly after `from`, wrapping, so a switching fiber finds
// itself last and keeps running only when nobody else can.
fn next_ready_after[Ctx: type](s: *Scheduler[Ctx], from: u32) -> u32 {
    if s.count == 0usize { ret NO_FIBER }
    var start = 0usize
    if from != NO_FIBER { start = usize(from) + 1usize }
    var k = 0usize
    while k < s.count {
        let i = (start + k) % s.count
        if s.fibers[i].state == .Ready { ret u32(i) }
        k += 1usize
    }
    ret NO_FIBER
}

// The hand-off, and the only place control moves: the giver publishes the receiver's
// state before it sets the permit, and parks on its own before the receiver can run, so
// the two are never running at once and what the giver wrote is what the receiver reads.
fn switch_to[Ctx: type](s: *Scheduler[Ctx], from: u32, to: u32) {
    s.fibers[usize(to)].state = .Running
    s.running = to
    s.cursor = to
    sync.event_set(&s.fibers[usize(to)].permit)
    sync.event_wait(&s.fibers[usize(from)].permit)
}

// Control back to the thread inside `run`, for a fiber with nowhere else to send it.
fn switch_to_host[Ctx: type](s: *Scheduler[Ctx], from: u32) {
    s.running = NO_FIBER
    sync.event_set(&s.host)
    sync.event_wait(&s.fibers[usize(from)].permit)
}

// The host's half of the same hand-off.
fn dispatch[Ctx: type](s: *Scheduler[Ctx], to: u32) {
    s.fibers[usize(to)].state = .Running
    s.running = to
    s.cursor = to
    sync.event_set(&s.fibers[usize(to)].permit)
    sync.event_wait(&s.host)
}

// The running fiber, or `NO_FIBER` on the host thread.
fn current[Ctx: type](s: *Scheduler[Ctx]) -> u32 {
    ret s.running
}

// The state of one fiber; `Invalid` for an id no `fiber` call handed out.
fn fiber_state[Ctx: type](s: *Scheduler[Ctx], id: u32) -> (FiberState, err) {
    var unknown: FiberState = .Done
    if usize(id) >= s.count { ret (unknown, Invalid) }
    ret (s.fibers[usize(id)].state, ok)
}

// Round-robin: the running fiber stays Ready and the next Ready one after it runs.
// `Invalid` from the host, which has no fiber to yield.
fn yield_now[Ctx: type](s: *Scheduler[Ctx]) -> err {
    let me = s.running
    if me == NO_FIBER { ret Invalid }
    s.fibers[usize(me)].state = .Ready
    let pick = next_ready_after[Ctx](s, me)
    if pick == NO_FIBER || pick == me {
        s.fibers[usize(me)].state = .Running
        ret ok
    }
    switch_to[Ctx](s, me, pick)
    ret ok
}

// Hands control to one named fiber, which must be Ready; yielding to oneself is `ok`
// and does nothing. `Invalid` for an unknown id, for a target that cannot take control,
// and from the host.
fn yield_to[Ctx: type](s: *Scheduler[Ctx], id: u32) -> err {
    if usize(id) >= s.count { ret Invalid }
    let me = s.running
    if me == NO_FIBER { ret Invalid }
    if id == me { ret ok }
    if s.fibers[usize(id)].state != .Ready { ret Invalid }
    s.fibers[usize(me)].state = .Ready
    switch_to[Ctx](s, me, id)
    ret ok
}

// The running fiber steps out of the schedule until someone `resume`s it: control goes
// to the next Ready fiber, or back to the host when there is none.
fn suspend[Ctx: type](s: *Scheduler[Ctx]) -> err {
    let me = s.running
    if me == NO_FIBER { ret Invalid }
    s.fibers[usize(me)].state = .Suspended
    let pick = next_ready_after[Ctx](s, me)
    if pick == NO_FIBER {
        switch_to_host[Ctx](s, me)
        ret ok
    }
    switch_to[Ctx](s, me, pick)
    ret ok
}

// Puts a suspended fiber back in the schedule; it runs when its turn comes, not now.
// `Invalid` for an unknown id or a fiber that is not suspended.
fn resume[Ctx: type](s: *Scheduler[Ctx], id: u32) -> err {
    if usize(id) >= s.count { ret Invalid }
    if s.fibers[usize(id)].state != .Suspended { ret Invalid }
    s.fibers[usize(id)].state = .Ready
    ret ok
}

// Drives the schedule until every fiber is Done. `Invalid` when nothing is Ready and
// fibers remain -- every one of them suspended -- so a `resume` and another `run`
// finish what is left; calling it from inside a fiber is `Invalid` too.
fn run[Ctx: type](s: *Scheduler[Ctx]) -> err {
    if s.running != NO_FIBER { ret Invalid }
    while s.done < s.count {
        let pick = next_ready_after[Ctx](s, s.cursor)
        if pick == NO_FIBER { ret Invalid }
        dispatch[Ctx](s, pick)
    }
    ret ok
}

// Returns once fiber `id` is Done, driving the schedule to get it there: from the host
// by dispatching, from another fiber by yielding. `Invalid` when the target cannot be
// reached -- nothing else is Ready -- and the thread behind a Done fiber is joined here,
// once, so a joined scheduler leaves nothing parked.
fn join_fiber[Ctx: type](s: *Scheduler[Ctx], id: u32) -> err {
    if usize(id) >= s.count { ret Invalid }
    while s.fibers[usize(id)].state != .Done {
        let me = s.running
        if me == NO_FIBER {
            let pick = next_ready_after[Ctx](s, s.cursor)
            if pick == NO_FIBER { ret Invalid }
            dispatch[Ctx](s, pick)
        } else {
            let pick = next_ready_after[Ctx](s, me)
            if pick == NO_FIBER || pick == me { ret Invalid }
            try yield_now[Ctx](s)
        }
    }
    let f = &s.fibers[usize(id)]
    if f.started && !f.joined {
        f.joined = true
        ret join(f.thread)
    }
    ret ok
}
