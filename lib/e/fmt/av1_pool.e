// A pool of worker threads that live as long as the decoder, so a frame does not pay for creating threads. Work is a count of
// jobs and a function run as f(ctx, i) for each i below the count. `run` shares the jobs between the workers and the caller and
// returns when all are done; `submit` and `wait` are the two halves for jobs that run while the caller does something else.
// One batch at a time: a new batch starts only after the last one was waited for.

use e.mem
use e.os
use e.atomic
use e.thread

type Worker = struct { p: *Pool }

type Pool = struct {
    gen: Atomic[u32],
    next: Atomic[u32],
    remaining: Atomic[u32],
    stop: Atomic[u32],
    total: u32,
    f: fn(*void, usize),
    ctx: *void,
    n: usize,
    started: usize,
    workers: []Worker,
    threads: []thread.Thread,
}

// the index of the next unclaimed job, or `total` when there is none
fn claim(p: *Pool) -> u32 {
    while true {
        let cur = atomic.load(&p.next, .Acquire)
        let t = p.total
        if cur >= t { ret t }
        let (won, was) = atomic.cas(&p.next, cur, cur + 1u32, .AcqRel, .Acquire)
        if won { ret cur }
    }
    ret 0u32
}

fn done_one(p: *Pool) {
    while true {
        let cur = atomic.load(&p.remaining, .Acquire)
        let (won, was) = atomic.cas(&p.remaining, cur, cur - 1u32, .AcqRel, .Acquire)
        if won {
            if cur == 1u32 { os.wake_all_u32(&p.remaining) }
            ret
        }
    }
}

fn work_some(p: *Pool) {
    while true {
        let i = claim(p)
        if i >= p.total { ret }
        p.f(p.ctx, usize(i))
        done_one(p)
    }
}

fn worker_main(w: *Worker) {
    let p = w.p
    var seen = 0u32
    while true {
        var g = atomic.load(&p.gen, .Acquire)
        while g == seen {
            if atomic.load(&p.stop, .Acquire) == 1u32 { ret }
            let waited = os.wait_u32(&p.gen, seen, 2000000i64)
            g = atomic.load(&p.gen, .Acquire)
        }
        seen = g
        work_some(p)
    }
}

// n worker threads (n may be 0: everything then runs in the caller)
fn new_pool(a: *mem.Arena, n: usize) -> (*Pool, err) {
    var none: *Pool = zero
    let (ps, ps_error) = mem.alloc[Pool](a, 1usize)
    if ps_error != ok { ret (none, ps_error) }
    var blank: Pool = zero
    ps[0usize] = blank
    let p = &ps[0usize]
    let (workers, workers_error) = mem.alloc[Worker](a, n + 1usize)
    if workers_error != ok { ret (none, workers_error) }
    let (threads, threads_error) = mem.alloc[thread.Thread](a, n + 1usize)
    if threads_error != ok { ret (none, threads_error) }
    p.workers = workers
    p.threads = threads
    p.n = n
    atomic.store(&p.gen, 0u32, .Release)
    atomic.store(&p.next, 0u32, .Release)
    atomic.store(&p.remaining, 0u32, .Release)
    atomic.store(&p.stop, 0u32, .Release)
    var i = 0usize
    while i < n {
        workers[i].p = p
        let (th, spawn_error) = thread.spawn[Worker](worker_main, &workers[i], 4194304usize)
        if spawn_error != ok {
            let closed = close(p)
            ret (none, spawn_error)
        }
        threads[i] = th
        p.started = i + 1usize
        i += 1usize
    }
    ret (p, ok)
}

// Starts a batch of `count` jobs on the workers and returns at once.
fn submit(p: *Pool, count: usize, f: fn(*void, usize), ctx: *void) {
    p.f = f
    p.ctx = ctx
    p.total = u32(count)
    atomic.store(&p.remaining, u32(count), .Release)
    atomic.store(&p.next, 0u32, .Release)
    let g = atomic.load(&p.gen, .Relaxed)
    atomic.store(&p.gen, g + 1u32, .Release)
    os.wake_all_u32(&p.gen)
}

// The caller takes jobs of the running batch too.
fn help(p: *Pool) {
    work_some(p)
}

// Waits until every job of the batch has finished.
fn wait(p: *Pool) {
    while true {
        let r = atomic.load(&p.remaining, .Acquire)
        if r == 0u32 { ret }
        let waited = os.wait_u32(&p.remaining, r, 200000i64)
    }
}

fn run(p: *Pool, count: usize, f: fn(*void, usize), ctx: *void) {
    if count == 0usize { ret }
    if p.started == 0usize {
        var i = 0usize
        while i < count {
            f(ctx, i)
            i += 1usize
        }
        ret
    }
    submit(p, count, f, ctx)
    help(p)
    wait(p)
}

// Stops the workers and joins them.
fn close(p: *Pool) -> err {
    atomic.store(&p.stop, 1u32, .Release)
    os.wake_all_u32(&p.gen)
    var first = ok
    var i = 0usize
    while i < p.started {
        let joined = thread.join(p.threads[i])
        if joined != ok && first == ok { first = joined }
        i += 1usize
    }
    p.started = 0usize
    ret first
}
