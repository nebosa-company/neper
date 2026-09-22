// A fixed thread pool and the schedulers built on it. `pool` starts `workers` threads
// over an `e.concurrent.queue` of `u32` task ids; every worker pops an id and calls the
// pool's one `fn(*Ctx, u32)` with the pool's context, so a task is a number and what it
// means is the caller's. `run` submits a batch and waits for the pool to drain, `run_dag`
// releases a node's dependents as it finishes, and `edf` submits a batch in deadline
// order. `fork_join` and `work_stealing` are executors of their own over the arena: the
// first cuts a range into leaves and runs them through a pool, the second gives every
// worker a Chase-Lev deque and lets the idle ones steal.
//
// Completion is an atomic count of submitted-but-unfinished tasks; the worker that takes
// it to zero broadcasts `idle` under the pool's lock, and the waiter rechecks the count
// under the same lock, so a broadcast cannot slip between its check and its wait.

use e.atomic
use e.concurrent.queue as queue
use e.mem
use e.sync
use e.thread

type Pool[Ctx: type] = struct { state: *void }
error Invalid
error Full
error TooSmall

type State[Ctx: type] = struct { q: queue.Queue[u32], ctx: *Ctx, task: fn(*Ctx, u32), pending: Atomic[u32], lock: sync.Mutex, idle: sync.Condition, threads: []thread.Thread, started: usize, deps: []const u32, dep_starts: []const usize, indegree: []Atomic[u32], dag_nodes: usize }

fn state_of[Ctx: type](p: *Pool[Ctx]) -> *State[Ctx] {
    ret mem.cast[*State[Ctx]](p.state)
}

fn worker_main[Ctx: type](s: *State[Ctx]) {
    while true {
        let (id, pop_error) = queue.pop[u32](&s.q)
        if pop_error != ok { ret }
        s.task(s.ctx, id)
        if s.dag_nodes > 0usize { release_dependents[Ctx](s, id) }
        finish_one[Ctx](s)
    }
}

fn finish_one[Ctx: type](s: *State[Ctx]) {
    let before = atomic.sub(&s.pending, 1u32, .AcqRel)
    if before == 1u32 {
        sync.mutex_lock(&s.lock)
        sync.condition_broadcast(&s.idle)
        sync.mutex_unlock(&s.lock)
    }
}

// Every edge out of `id`: the dependent whose last edge this was is submitted here, by
// the worker that finished its predecessor, before that worker counts itself done.
fn release_dependents[Ctx: type](s: *State[Ctx], id: u32) {
    let u = usize(id)
    var i = s.dep_starts[u]
    let end = s.dep_starts[u + 1usize]
    while i < end {
        let v = s.deps[i]
        let before = atomic.sub(&s.indegree[usize(v)], 1u32, .AcqRel)
        if before == 1u32 { let ignored = submit_state[Ctx](s, v) }
        i += 1usize
    }
}

fn submit_state[Ctx: type](s: *State[Ctx], id: u32) -> err {
    let before = atomic.add(&s.pending, 1u32, .AcqRel)
    let push_error = queue.push[u32](&s.q, id)
    if push_error != ok {
        finish_one[Ctx](s)
        ret Invalid
    }
    ret ok
}

fn wait_idle[Ctx: type](s: *State[Ctx]) {
    sync.mutex_lock(&s.lock)
    while atomic.load(&s.pending, .Acquire) != 0u32 { sync.condition_wait(&s.idle, &s.lock) }
    sync.mutex_unlock(&s.lock)
}

// `workers` threads over a queue of `queue_capacity` ids, all from the arena; a start
// that fails part way shuts down what it started.
fn pool[Ctx: type](a: *mem.Arena, workers: usize, queue_capacity: usize, ctx: *Ctx, task: fn(*Ctx, u32)) -> (Pool[Ctx], err) {
    if workers == 0usize || queue_capacity == 0usize { ret (zero, Invalid) }
    let (states, state_error) = mem.alloc[State[Ctx]](a, 1usize)
    if state_error != ok { ret (zero, state_error) }
    let (q, queue_error) = queue.init[u32](a, queue_capacity)
    if queue_error != ok { ret (zero, queue_error) }
    let (threads, threads_error) = mem.alloc[thread.Thread](a, workers)
    if threads_error != ok { ret (zero, threads_error) }
    let s = &states[0usize]
    s.q = q
    s.ctx = ctx
    s.task = task
    s.pending = atomic.init(0u32)
    s.lock = sync.mutex()
    s.idle = sync.condition()
    s.threads = threads
    s.started = 0usize
    s.dag_nodes = 0usize
    var i = 0usize
    while i < workers {
        let (started, start_error) = thread.spawn[State[Ctx]](worker_main[Ctx], s, 0usize)
        if start_error != ok {
            var made = Pool[Ctx] { state: mem.cast[*void](s) }
            let closed = shutdown[Ctx](&made)
            ret (zero, start_error)
        }
        threads[i] = started
        s.started = i + 1usize
        i += 1usize
    }
    ret (Pool[Ctx] { state: mem.cast[*void](s) }, ok)
}

// Queues one task, waiting for room; `Invalid` once the pool is shut down.
fn submit[Ctx: type](p: *Pool[Ctx], id: u32) -> err {
    ret submit_state[Ctx](state_of[Ctx](p), id)
}

// Queues one task or answers `Full` at once.
fn try_submit[Ctx: type](p: *Pool[Ctx], id: u32) -> err {
    let s = state_of[Ctx](p)
    let before = atomic.add(&s.pending, 1u32, .AcqRel)
    let (pushed, push_error) = queue.try_push[u32](&s.q, id)
    if push_error != ok || !pushed {
        finish_one[Ctx](s)
        if push_error != ok { ret Invalid }
        ret Full
    }
    ret ok
}

// Submits every id and returns when the pool has run all of them (and anything else
// it held): the plan's thread-pool worker loop, seen from the caller.
fn run[Ctx: type](p: *Pool[Ctx], ids: []const u32) -> err {
    let s = state_of[Ctx](p)
    var i = 0usize
    while i < ids.len {
        try submit_state[Ctx](s, ids[i])
        i += 1usize
    }
    wait_idle[Ctx](s)
    ret ok
}

// Closes the queue -- what is buffered still runs -- and joins every worker.
fn shutdown[Ctx: type](p: *Pool[Ctx]) -> err {
    let s = state_of[Ctx](p)
    let closed = queue.close[u32](&s.q)
    var first = ok
    var i = 0usize
    while i < s.started {
        let joined = thread.join(s.threads[i])
        if joined != ok && first == ok { first = joined }
        i += 1usize
    }
    s.started = 0usize
    ret first
}

// ---- fork/join -------------------------------------------------------------
//
// ponytail: one level of forking -- `[lo, hi)` is cut into ceil(len / grain) leaves up
// front and every leaf is a task; the join is the pool draining. A recursive split
// where a task forks halves and joins them needs workers that run other tasks while
// they wait (a blocked worker on a bounded pool deadlocks); add that help-while-waiting
// loop if leaves of very uneven cost show up.

type Fork[Ctx: type] = struct { ctx: *Ctx, leaf: fn(*Ctx, usize, usize), lo: usize, hi: usize, grain: usize }

fn fork_task[Ctx: type](f: *Fork[Ctx], id: u32) {
    let start = f.lo + usize(id) * f.grain
    var end = start + f.grain
    if end > f.hi { end = f.hi }
    f.leaf(f.ctx, start, end)
}

// Runs `leaf` over every `grain`-sized piece of `[lo, hi)` on `workers` threads of a
// pool made here and shut down before it answers.
fn fork_join[Ctx: type](a: *mem.Arena, workers: usize, ctx: *Ctx, lo: usize, hi: usize, grain: usize, leaf: fn(*Ctx, usize, usize)) -> err {
    if grain == 0usize || hi < lo || workers == 0usize { ret Invalid }
    if hi == lo { ret ok }
    let count = (hi - lo + grain - 1usize) / grain
    var f = Fork[Ctx] { ctx: ctx, leaf: leaf, lo: lo, hi: hi, grain: grain }
    let (ids, ids_error) = mem.alloc[u32](a, count)
    if ids_error != ok { ret ids_error }
    var i = 0usize
    while i < count {
        ids[i] = u32(i)
        i += 1usize
    }
    let (made, pool_error) = pool[Fork[Ctx]](a, workers, count, &f, fork_task[Ctx])
    if pool_error != ok { ret pool_error }
    var p = made
    let run_error = run[Fork[Ctx]](&p, ids)
    let stop_error = shutdown[Fork[Ctx]](&p)
    if run_error != ok { ret run_error }
    ret stop_error
}

// ---- work stealing -----------------------------------------------------------
//
// One Chase-Lev deque per worker over a power-of-two buffer: the owner takes at the
// bottom, thieves take at the top, and with one item left the compare-and-swap on
// `top` decides. Indices are `i64` because a take moves `bottom` below `top` for a
// moment. Tasks here spawn no tasks, so the deques are filled round-robin before the
// workers start and never grow; the termination protocol is one atomic count of tasks
// not yet run.
//
// ponytail: an idle worker spins on that count and on its victims; park it on
// `os.wait_u32` if pools sit idle for long.

type Deque = struct { items: []u32, top: Atomic[i64], bottom: Atomic[i64], mask: usize }
type Steal[Ctx: type] = struct { ctx: *Ctx, task: fn(*Ctx, u32), deques: []Deque, remaining: Atomic[u32], counts: []u32 }
type Thief[Ctx: type] = struct { pool: *Steal[Ctx], index: usize }

// Owner only, and here only before the workers start.
fn deque_push(d: *Deque, v: u32) {
    let b = atomic.load(&d.bottom, .Relaxed)
    d.items[usize(b) & d.mask] = v
    atomic.store(&d.bottom, b + 1i64, .Release)
}

fn deque_take(d: *Deque) -> (u32, bool) {
    let b = atomic.load(&d.bottom, .Relaxed) - 1i64
    atomic.store(&d.bottom, b, .Relaxed)
    atomic.fence(.SeqCst)
    let t = atomic.load(&d.top, .Relaxed)
    if t > b {
        atomic.store(&d.bottom, b + 1i64, .Relaxed)
        ret (0u32, false)
    }
    let v = d.items[usize(b) & d.mask]
    if t < b { ret (v, true) }
    let (won, seen) = atomic.cas(&d.top, t, t + 1i64, .SeqCst, .Relaxed)
    atomic.store(&d.bottom, b + 1i64, .Relaxed)
    if won { ret (v, true) }
    ret (0u32, false)
}

fn deque_steal(d: *Deque) -> (u32, bool) {
    let t = atomic.load(&d.top, .Acquire)
    atomic.fence(.SeqCst)
    let b = atomic.load(&d.bottom, .Acquire)
    if t >= b { ret (0u32, false) }
    let v = d.items[usize(t) & d.mask]
    let (won, seen) = atomic.cas(&d.top, t, t + 1i64, .SeqCst, .Relaxed)
    if !won { ret (0u32, false) }
    ret (v, true)
}

fn steal_run[Ctx: type](s: *Steal[Ctx], index: usize, id: u32) {
    s.task(s.ctx, id)
    s.counts[index] += 1u32
    let before = atomic.sub(&s.remaining, 1u32, .AcqRel)
}

fn steal_main[Ctx: type](w: *Thief[Ctx]) {
    let s = w.pool
    let n = s.deques.len
    var victim = w.index
    while atomic.load(&s.remaining, .Acquire) > 0u32 {
        let (own_id, found) = deque_take(&s.deques[w.index])
        if found {
            steal_run[Ctx](s, w.index, own_id)
            continue
        }
        victim += 1usize
        if victim >= n { victim = 0usize }
        if victim == w.index { continue }
        let (stolen, got) = deque_steal(&s.deques[victim])
        if got { steal_run[Ctx](s, w.index, stolen) }
    }
}

// Runs every id once on `workers` threads that steal from each other; `counts[k]` is
// how many tasks worker `k` ran, so `counts.len` must reach `workers`.
fn work_stealing[Ctx: type](a: *mem.Arena, workers: usize, ctx: *Ctx, task: fn(*Ctx, u32), ids: []const u32, counts: []u32) -> err {
    if workers == 0usize || ids.len > 4294967295usize { ret Invalid }
    if counts.len < workers { ret TooSmall }
    let per = (ids.len + workers - 1usize) / workers
    var cap = 1usize
    while cap < per { cap *= 2usize }
    let (states, state_error) = mem.alloc[Steal[Ctx]](a, 1usize)
    if state_error != ok { ret state_error }
    let (deques, deques_error) = mem.alloc[Deque](a, workers)
    if deques_error != ok { ret deques_error }
    let (thieves, thieves_error) = mem.alloc[Thief[Ctx]](a, workers)
    if thieves_error != ok { ret thieves_error }
    let s = &states[0usize]
    s.ctx = ctx
    s.task = task
    s.deques = deques
    s.remaining = atomic.init(u32(ids.len))
    s.counts = counts
    var k = 0usize
    while k < workers {
        let (items, items_error) = mem.alloc[u32](a, cap)
        if items_error != ok { ret items_error }
        deques[k] = Deque { items: items, top: atomic.init(0i64), bottom: atomic.init(0i64), mask: cap - 1usize }
        thieves[k] = Thief[Ctx] { pool: s, index: k }
        counts[k] = 0u32
        k += 1usize
    }
    var i = 0usize
    while i < ids.len {
        deque_push(&deques[i % workers], ids[i])
        i += 1usize
    }
    let (g, spawn_error) = thread.spawn_all[Thief[Ctx]](a, steal_main[Ctx], thieves, 0usize)
    if spawn_error != ok { ret spawn_error }
    ret thread.join_all(g)
}

// ---- DAG -----------------------------------------------------------------------

// Nodes `0..n` with `n = dep_starts.len - 1`; the dependents of `u` are
// `deps[dep_starts[u]..dep_starts[u + 1]]`. `indegree` is scratch of at least `n`
// and the queue must hold `n` ids, since workers submit dependents and must never block
// on a full queue. Every node's task runs after all of its predecessors'; a cycle leaves
// nodes unrun and is `Invalid` once everything runnable has finished.
fn run_dag[Ctx: type](p: *Pool[Ctx], deps: []const u32, dep_starts: []const usize, indegree: []Atomic[u32]) -> err {
    let s = state_of[Ctx](p)
    if dep_starts.len == 0usize { ret Invalid }
    let n = dep_starts.len - 1usize
    if indegree.len < n || queue.capacity[u32](&s.q) < n { ret TooSmall }
    if dep_starts[0usize] != 0usize || dep_starts[n] != deps.len { ret Invalid }
    // Every node starts one above its in-degree: the caller is a predecessor of every
    // node and releases that edge below, so a node the workers release meanwhile is
    // submitted by whichever decrement reaches zero and never by both.
    var i = 0usize
    while i < n {
        if dep_starts[i] > dep_starts[i + 1usize] { ret Invalid }
        atomic.store(&indegree[i], 1u32, .Relaxed)
        i += 1usize
    }
    i = 0usize
    while i < deps.len {
        if usize(deps[i]) >= n { ret Invalid }
        let before = atomic.add(&indegree[usize(deps[i])], 1u32, .Relaxed)
        i += 1usize
    }
    s.deps = deps
    s.dep_starts = dep_starts
    s.indegree = indegree
    s.dag_nodes = n
    i = 0usize
    while i < n {
        if atomic.sub(&indegree[i], 1u32, .AcqRel) == 1u32 {
            let submit_error = submit_state[Ctx](s, u32(i))
            if submit_error != ok {
                s.dag_nodes = 0usize
                ret submit_error
            }
        }
        i += 1usize
    }
    wait_idle[Ctx](s)
    s.dag_nodes = 0usize
    i = 0usize
    while i < n {
        if atomic.load(&indegree[i], .Acquire) != 0u32 { ret Invalid }
        i += 1usize
    }
    ret ok
}

// ---- earliest deadline first -----------------------------------------------------

fn later(deadlines: []const u64, x: u32, y: u32) -> bool {
    let dx = deadlines[usize(x)]
    let dy = deadlines[usize(y)]
    if dx != dy { ret dx > dy }
    ret x > y
}

fn sift(deadlines: []const u64, out: []u32, root: usize, end: usize) {
    var i = root
    while true {
        let l = 2usize * i + 1usize
        if l >= end { ret }
        var big = l
        if l + 1usize < end && later(deadlines, out[l + 1usize], out[l]) { big = l + 1usize }
        if !later(deadlines, out[big], out[i]) { ret }
        let held = out[i]
        out[i] = out[big]
        out[big] = held
        i = big
    }
}

// The indices of `deadlines` by deadline, ties by index: a binary heap over `out`
// (heapsort), so `out.len` must reach `deadlines.len`.
fn edf_order(deadlines: []const u64, out: []u32) -> err {
    let n = deadlines.len
    if out.len < n || n > 4294967295usize { ret TooSmall }
    var i = 0usize
    while i < n {
        out[i] = u32(i)
        i += 1usize
    }
    var k = n / 2usize
    while k > 0usize {
        k -= 1usize
        sift(deadlines, out, k, n)
    }
    var end = n
    while end > 1usize {
        end -= 1usize
        let top = out[0usize]
        out[0usize] = out[end]
        out[end] = top
        sift(deadlines, out, 0usize, end)
    }
    ret ok
}

// Submits `ids[k]` in order of `deadlines[k]` and waits for the pool to drain; `order`
// is the scratch `edf_order` fills.
//
// ponytail: the batch is known up front, so the heap is drained once here and the
// queue keeps the order; a task arriving while others run wants the heap under the
// pool's lock with the workers popping from it -- add that when deadlines arrive live.
fn edf[Ctx: type](p: *Pool[Ctx], deadlines: []const u64, ids: []const u32, order: []u32) -> err {
    if ids.len != deadlines.len { ret Invalid }
    try edf_order(deadlines, order)
    let s = state_of[Ctx](p)
    var k = 0usize
    while k < ids.len {
        try submit_state[Ctx](s, ids[usize(order[k])])
        k += 1usize
    }
    wait_idle[Ctx](s)
    ret ok
}
