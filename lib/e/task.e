// A bounded thread pool: `workers` threads over a ring of `queue_capacity` task records,
// every record and thread taken from the caller's arena at `pool` and nothing after.
// A submission fills a free record with the caller's context and function and answers
// its handle; a full ring refuses with `Invalid` rather than growing or blocking, so a
// producer that is faster than the pool sees it and waits on what it has. A future is a
// task whose record also points at a result slot, one `T` taken from the pool's arena
// when it is made.
//
// The typed function a caller hands in is called through `run_job[Ctx]`, the instance
// of one trampoline per context type named as a value (D772); the record holds the
// trampoline as `fn(*void, *const Cancel) -> err` and the typed pair inline, so a worker
// needs no knowledge of the types it runs.
//
// Cancellation is `e.cancel`'s: a task whose token is requested before a worker takes
// it becomes `Cancelled` without running; one already running is handed the token and
// stops when it looks. `close` refuses new work, cancels what is queued and joins every
// worker; a task waited after `close` still answers. A handle is done with once waited
// (`wait`, a completed `wait_for`, `wait_all`, `future_get`): the record goes back to
// the ring, so a waited handle must not be read again. `wait_any` and `status` release
// nothing. `wait_all` answers the first error in input order.
//
// `parallel_for` cuts `[begin, end)` into ranges of `grain` (the last one shorter),
// submits them and waits; when the ring is full the calling thread runs the range
// itself, so the loop always completes and never needs more records than the ring
// has. Scheduling order is not observable; shared state is the caller's to guard.

use e.atomic
use e.cancel
use e.mem
use e.sync
use e.thread
use e.time

type Pool = struct { state: *void }
type Task = struct { state: *void }
type Future[T: type] = struct { state: *void }
type Cancel = cancel.Token
type Status = enum u8 { Pending, Running, Succeeded, Failed, Cancelled }
type Options = struct { workers: u32, queue_capacity: usize, stack_size: usize }
error Cancelled
error Closed
error Invalid

const FREE: u32 = 255u32
const JOB_BYTES: usize = 48usize

type Record = struct {
    pool: *PoolState,
    entry: fn(*void, *const Cancel) -> err,
    token: *Cancel,
    result: *void,
    status: u32,
    failure: err,
    stamp: usize,
    job: [48]u8,
}

type PoolState = struct {
    lock: sync.Mutex,
    work: sync.Condition,
    finished: sync.Condition,
    records: []Record,
    ring: []usize,
    head: usize,
    count: usize,
    threads: []thread.Thread,
    started: usize,
    closed: bool,
    arena: *mem.Arena,
    next_stamp: usize,
}

type Worker = struct { pool: *PoolState }

type Job[Ctx: type] = struct { ctx: *Ctx, run: fn(*Ctx, *const Cancel) -> err }
type FutureJob[T: type, Ctx: type] = struct { ctx: *Ctx, run: fn(*Ctx, *const Cancel) -> (T, err), result: *T }
type RangeJob[Ctx: type] = struct { ctx: *Ctx, body: fn(*Ctx, usize, usize, *const Cancel) -> err, lo: usize, hi: usize }

fn run_job[Ctx: type](p: *void, token: *const Cancel) -> err {
    let j = mem.cast[*Job[Ctx]](p)
    ret j.run(j.ctx, token)
}

fn run_future[T: type, Ctx: type](p: *void, token: *const Cancel) -> err {
    let j = mem.cast[*FutureJob[T, Ctx]](p)
    let (value, run_error) = j.run(j.ctx, token)
    if run_error != ok { ret run_error }
    *j.result = value
    ret ok
}

fn run_range[Ctx: type](p: *void, token: *const Cancel) -> err {
    let j = mem.cast[*RangeJob[Ctx]](p)
    ret j.body(j.ctx, j.lo, j.hi, token)
}

fn finish(r: *Record, outcome: err) {
    if outcome == ok {
        r.status = 2u32
    } else if outcome == Cancelled || outcome == cancel.Cancelled {
        r.status = 4u32
        r.failure = Cancelled
    } else {
        r.status = 3u32
        r.failure = outcome
    }
}

fn worker_main(w: *Worker) {
    let p = w.pool
    while true {
        sync.mutex_lock(&p.lock)
        while p.count == 0usize && !p.closed { sync.condition_wait(&p.work, &p.lock) }
        if p.count == 0usize {
            sync.mutex_unlock(&p.lock)
            ret
        }
        let index = p.ring[p.head]
        p.head = (p.head + 1usize) % p.ring.len
        p.count -= 1usize
        let r = &p.records[index]
        var skip = false
        if cancel.requested(r.token) {
            r.status = 4u32
            r.failure = Cancelled
            skip = true
        } else {
            r.status = 1u32
        }
        sync.mutex_unlock(&p.lock)
        if skip {
            sync.condition_broadcast(&p.finished)
            continue
        }
        let outcome = r.entry(mem.cast[*void](&r.job[0usize]), r.token)
        sync.mutex_lock(&p.lock)
        finish(r, outcome)
        sync.mutex_unlock(&p.lock)
        sync.condition_broadcast(&p.finished)
    }
}

fn pool(a: *mem.Arena, options: Options) -> (Pool, err) {
    if options.workers == 0u32 || options.queue_capacity == 0usize { ret (zero, Invalid) }
    let (states, state_error) = mem.alloc[PoolState](a, 1usize)
    if state_error != ok { ret (zero, state_error) }
    let (records, records_error) = mem.alloc[Record](a, options.queue_capacity)
    if records_error != ok { ret (zero, records_error) }
    let (ring, ring_error) = mem.alloc[usize](a, options.queue_capacity)
    if ring_error != ok { ret (zero, ring_error) }
    let (threads, threads_error) = mem.alloc[thread.Thread](a, usize(options.workers))
    if threads_error != ok { ret (zero, threads_error) }
    let (workers, workers_error) = mem.alloc[Worker](a, usize(options.workers))
    if workers_error != ok { ret (zero, workers_error) }
    let p = &states[0usize]
    p.lock = sync.mutex()
    p.work = sync.condition()
    p.finished = sync.condition()
    p.records = records
    p.ring = ring
    p.head = 0usize
    p.count = 0usize
    p.threads = threads
    p.started = 0usize
    p.closed = false
    p.arena = a
    p.next_stamp = 1usize
    var i = 0usize
    while i < records.len {
        var blank: Record = zero
        blank.pool = p
        blank.status = FREE
        records[i] = blank
        i += 1usize
    }
    i = 0usize
    while i < usize(options.workers) {
        workers[i] = Worker { pool: p }
        let (started, start_error) = thread.spawn[Worker](worker_main, &workers[i], options.stack_size)
        if start_error != ok {
            var made = Pool { state: mem.cast[*void](p) }
            let closed = close(&made)
            ret (zero, start_error)
        }
        threads[i] = started
        p.started = i + 1usize
        i += 1usize
    }
    ret (Pool { state: mem.cast[*void](p) }, ok)
}

// A free record, marked pending and queued; the lock is held by the caller.
fn take_record(p: *PoolState, token: *Cancel) -> (usize, err) {
    if p.closed { ret (0usize, Closed) }
    if p.count >= p.ring.len { ret (0usize, Invalid) }
    var i = 0usize
    while i < p.records.len {
        if p.records[i].status == FREE {
            p.records[i].status = 0u32
            p.records[i].failure = ok
            p.records[i].token = token
            p.records[i].result = nil
            p.records[i].stamp = 0usize
            p.ring[(p.head + p.count) % p.ring.len] = i
            p.count += 1usize
            ret (i, ok)
        }
        i += 1usize
    }
    ret (0usize, Invalid)
}

fn submit[Ctx: type](p: *Pool, cancel_token: *Cancel, ctx: *Ctx, f: fn(*Ctx, *const Cancel) -> err) -> (Task, err) {
    let state = mem.cast[*PoolState](p.state)
    if p.state == nil { ret (zero, Invalid) }
    sync.mutex_lock(&state.lock)
    let (index, take_error) = take_record(state, cancel_token)
    if take_error != ok {
        sync.mutex_unlock(&state.lock)
        ret (zero, take_error)
    }
    let r = &state.records[index]
    let job = mem.cast[*Job[Ctx]](&r.job[0usize])
    job.ctx = ctx
    job.run = f
    r.entry = run_job[Ctx]
    sync.mutex_unlock(&state.lock)
    sync.condition_signal(&state.work)
    ret (Task { state: mem.cast[*void](r) }, ok)
}

fn future[T: type, Ctx: type](p: *Pool, cancel_token: *Cancel, ctx: *Ctx, f: fn(*Ctx, *const Cancel) -> (T, err)) -> (Future[T], err) {
    let state = mem.cast[*PoolState](p.state)
    if p.state == nil { ret (zero, Invalid) }
    sync.mutex_lock(&state.lock)
    let (slot, slot_error) = mem.alloc[T](state.arena, 1usize)
    if slot_error != ok {
        sync.mutex_unlock(&state.lock)
        ret (zero, slot_error)
    }
    let (index, take_error) = take_record(state, cancel_token)
    if take_error != ok {
        sync.mutex_unlock(&state.lock)
        ret (zero, take_error)
    }
    let r = &state.records[index]
    let job = mem.cast[*FutureJob[T, Ctx]](&r.job[0usize])
    job.ctx = ctx
    job.run = f
    job.result = &slot[0usize]
    r.entry = run_future[T, Ctx]
    r.result = mem.cast[*void](&slot[0usize])
    sync.mutex_unlock(&state.lock)
    sync.condition_signal(&state.work)
    ret (Future[T] { state: mem.cast[*void](r) }, ok)
}

fn status_code(code: u32) -> Status {
    if code == 0u32 { ret .Pending }
    if code == 1u32 { ret .Running }
    if code == 2u32 { ret .Succeeded }
    if code == 3u32 { ret .Failed }
    ret .Cancelled
}

fn status(t: *const Task) -> Status {
    let r = mem.cast[*Record](t.state)
    sync.mutex_lock(&r.pool.lock)
    let code = r.status
    sync.mutex_unlock(&r.pool.lock)
    ret status_code(code)
}

fn settled(code: u32) -> bool {
    ret code == 2u32 || code == 3u32 || code == 4u32
}

// Waits for the record to settle, then releases it and answers its outcome; a bounded
// wait answers false when the deadline passes first and releases nothing.
fn wait_record(r: *Record, bounded: bool, timeout: time.Duration) -> (bool, err) {
    let p = r.pool
    let deadline = sync.deadline_for(timeout)
    sync.mutex_lock(&p.lock)
    while !settled(r.status) {
        if bounded {
            let left = sync.remaining_for(deadline)
            if left <= 0i64 {
                sync.mutex_unlock(&p.lock)
                ret (false, ok)
            }
            let woke = sync.condition_wait_for(&p.finished, &p.lock, time.Duration { nanos: left })
        } else {
            sync.condition_wait(&p.finished, &p.lock)
        }
    }
    let outcome = r.failure
    r.status = FREE
    sync.mutex_unlock(&p.lock)
    ret (true, outcome)
}

fn wait(t: *Task) -> err {
    let (_, outcome) = wait_record(mem.cast[*Record](t.state), false, time.Duration { nanos: 0i64 })
    ret outcome
}

fn wait_for(t: *Task, timeout: time.Duration) -> (bool, err) {
    let (done, outcome) = wait_record(mem.cast[*Record](t.state), true, timeout)
    ret (done, outcome)
}

fn future_get[T: type](f: *Future[T]) -> (T, err) {
    let r = mem.cast[*Record](f.state)
    let slot = mem.cast[*T](r.result)
    let (_, outcome) = wait_record(r, false, time.Duration { nanos: 0i64 })
    if outcome != ok { ret (zero, outcome) }
    ret (*slot, ok)
}

// The first settled task in input order, waiting up to `timeout` for one to settle.
fn wait_any(tasks: []*Task, timeout: time.Duration) -> (usize, bool, err) {
    if tasks.len == 0usize { ret (0usize, false, Invalid) }
    let p = mem.cast[*Record](tasks[0].state).pool
    let deadline = sync.deadline_for(timeout)
    sync.mutex_lock(&p.lock)
    while true {
        var i = 0usize
        while i < tasks.len {
            let r = mem.cast[*Record](tasks[i].state)
            if settled(r.status) {
                let outcome = r.failure
                sync.mutex_unlock(&p.lock)
                ret (i, true, outcome)
            }
            i += 1usize
        }
        let left = sync.remaining_for(deadline)
        if left <= 0i64 {
            sync.mutex_unlock(&p.lock)
            ret (0usize, false, ok)
        }
        let woke = sync.condition_wait_for(&p.finished, &p.lock, time.Duration { nanos: left })
    }
    sync.mutex_unlock(&p.lock)
    ret (0usize, false, ok)
}

fn wait_all(tasks: []*Task) -> err {
    var first = ok
    var i = 0usize
    while i < tasks.len {
        let outcome = wait(tasks[i])
        if outcome != ok && first == ok { first = outcome }
        i += 1usize
    }
    ret first
}

fn parallel_for[Ctx: type](p: *Pool, cancel_token: *Cancel, begin: usize, end: usize, grain: usize, ctx: *Ctx, body: fn(*Ctx, usize, usize, *const Cancel) -> err) -> err {
    if grain == 0usize || end < begin { ret Invalid }
    let state = mem.cast[*PoolState](p.state)
    if p.state == nil { ret Invalid }
    var first = ok
    sync.mutex_lock(&state.lock)
    let stamp = state.next_stamp
    state.next_stamp += 1usize
    sync.mutex_unlock(&state.lock)
    var lo = begin
    while lo < end {
        var hi = lo + grain
        if hi > end { hi = end }
        sync.mutex_lock(&state.lock)
        let (index, take_error) = take_record(state, cancel_token)
        if take_error == ok {
            let r = &state.records[index]
            let job = mem.cast[*RangeJob[Ctx]](&r.job[0usize])
            job.ctx = ctx
            job.body = body
            job.lo = lo
            job.hi = hi
            r.entry = run_range[Ctx]
            r.stamp = stamp
            sync.mutex_unlock(&state.lock)
            sync.condition_signal(&state.work)
        } else {
            sync.mutex_unlock(&state.lock)
            if take_error == Closed { ret Closed }
            // The ring is full: this thread takes the range itself.
            var outcome = ok
            if cancel.requested(cancel_token) {
                outcome = Cancelled
            } else {
                outcome = body(ctx, lo, hi, cancel_token)
            }
            if outcome != ok && first == ok { first = outcome }
        }
        lo = hi
    }
    // Every range this call queued, known by its stamp: wait for each and release it.
    sync.mutex_lock(&state.lock)
    var i = 0usize
    while i < state.records.len {
        let r = &state.records[i]
        if r.status != FREE && r.stamp == stamp {
            while !settled(r.status) { sync.condition_wait(&state.finished, &state.lock) }
            if r.failure != ok && first == ok { first = r.failure }
            r.status = FREE
        }
        i += 1usize
    }
    sync.mutex_unlock(&state.lock)
    ret first
}

fn close(p: *Pool) -> err {
    let state = mem.cast[*PoolState](p.state)
    if p.state == nil { ret Invalid }
    sync.mutex_lock(&state.lock)
    if state.closed {
        sync.mutex_unlock(&state.lock)
        ret Closed
    }
    state.closed = true
    while state.count > 0usize {
        let index = state.ring[state.head]
        state.head = (state.head + 1usize) % state.ring.len
        state.count -= 1usize
        state.records[index].status = 4u32
        state.records[index].failure = Cancelled
    }
    sync.mutex_unlock(&state.lock)
    sync.condition_broadcast(&state.work)
    sync.condition_broadcast(&state.finished)
    var first = ok
    var i = 0usize
    while i < state.started {
        let joined = thread.join(state.threads[i])
        if joined != ok && first == ok { first = joined }
        i += 1usize
    }
    state.started = 0usize
    ret first
}
