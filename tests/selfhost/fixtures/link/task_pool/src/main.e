// A bounded pool: typed tasks and futures through the trampoline instances, failure and
// cancellation outcomes, bounded waits, wait_any, a full ring, parallel_for with more
// ranges than records, and a closed pool.

use e.atomic
use e.cancel
use e.io
use e.mem
use e.os
use e.sync
use e.task
use e.thread
use e.time

error Boom

type Counter = struct { total: Atomic[u64], id: u64 }
type Gate = struct { open: sync.Event }
type Squares = struct { partial: [64]u64 }
type CloseRace = struct {
    pool: *task.Pool,
    token: *task.Cancel,
    worker_started: sync.Event,
    close_requested: sync.Event,
    releaser_ready: sync.Event,
    release_worker: sync.Event,
    parallel_returned: sync.Event,
    returned_before_release: Atomic[u32],
    worker_finished: Atomic[u32],
    close_failed: Atomic[u32],
}
type ReapRace = struct {
    worker_started: sync.Event,
    release_initial: sync.Event,
    initial_finished: sync.Event,
    settle_pause: sync.Event,
    third_started: sync.Event,
    after_reap: sync.Event,
    release_third: sync.Event,
    after_reap_before_release: Atomic[u32],
}
type Reentrant = struct { pool: *task.Pool, token: *task.Cancel, ranges: Atomic[u32] }
type StampedReentrant = struct {
    pool: *task.Pool,
    token: *task.Cancel,
    outer_started: sync.Event,
    foreign_queued: sync.Event,
    release_foreign: sync.Event,
    ranges: Atomic[u32],
}

fn add_id(c: *Counter, token: *const task.Cancel) -> err {
    let unused = token
    let previous = atomic.add(&c.total, c.id, .AcqRel)
    ret ok
}

fn fail(c: *Counter, token: *const task.Cancel) -> err {
    let unused = token
    let ignored = c
    ret Boom
}

fn square_id(c: *Counter, token: *const task.Cancel) -> (u64, err) {
    let unused = token
    ret (c.id * c.id, ok)
}

// Holds until the gate opens, unless cancelled first.
fn hold(g: *Gate, token: *const task.Cancel) -> err {
    while !sync.event_wait_for(&g.open, time.millis(5i64)) {
        if cancel.requested(token) { ret cancel.Cancelled }
    }
    ret ok
}

fn sum_squares(s: *Squares, lo: usize, hi: usize, token: *const task.Cancel) -> err {
    let unused = token
    var total = 0u64
    var i = lo
    while i < hi {
        total += u64(i) * u64(i)
        i += 1usize
    }
    s.partial[lo / 100usize] = total
    ret ok
}

fn race_probe(r: *CloseRace, token: *const task.Cancel) -> err {
    let unused = r
    let ignored = token
    ret ok
}

fn race_body(r: *CloseRace, lo: usize, hi: usize, token: *const task.Cancel) -> err {
    let unused = hi
    let ignored = token
    if lo == 0usize {
        sync.event_set(&r.worker_started)
        sync.event_wait(&r.release_worker)
        atomic.store(&r.worker_finished, 1u32, .SeqCst)
        ret ok
    }
    if lo == 1usize {
        sync.event_wait(&r.worker_started)
        sync.event_wait(&r.close_requested)
        sync.event_wait(&r.releaser_ready)
        // This only returns Closed after the closer has published the pool state.
        while true {
            let (_, probe_error) = task.submit[CloseRace](r.pool, r.token, r, race_probe)
            if probe_error == task.Closed { ret ok }
            if probe_error != task.Invalid { ret probe_error }
        }
    }
    ret ok
}

fn race_close(r: *CloseRace) {
    sync.event_wait(&r.worker_started)
    sync.event_set(&r.close_requested)
    if task.close(r.pool) != ok { atomic.store(&r.close_failed, 1u32, .SeqCst) }
}

fn race_release(r: *CloseRace) {
    sync.event_set(&r.releaser_ready)
    if sync.event_wait_for(&r.parallel_returned, time.millis(250i64)) {
        atomic.store(&r.returned_before_release, 1u32, .SeqCst)
    }
    sync.event_set(&r.release_worker)
}

fn reap_body(r: *ReapRace, lo: usize, hi: usize, token: *const task.Cancel) -> err {
    let unused = hi
    let ignored = token
    if lo == 0usize {
        sync.event_set(&r.worker_started)
        sync.event_wait(&r.release_initial)
        sync.event_set(&r.initial_finished)
        ret ok
    }
    if lo == 1usize {
        sync.event_wait(&r.worker_started)
        sync.event_set(&r.release_initial)
        sync.event_wait(&r.initial_finished)
        let paused = sync.event_wait_for(&r.settle_pause, time.millis(50i64))
        if paused { ret ok }
        ret ok
    }
    if lo == 2usize {
        sync.event_set(&r.third_started)
        sync.event_wait(&r.release_third)
        ret ok
    }
    sync.event_set(&r.after_reap)
    ret ok
}

fn reap_release(r: *ReapRace) {
    sync.event_wait(&r.third_started)
    if sync.event_wait_for(&r.after_reap, time.millis(250i64)) {
        atomic.store(&r.after_reap_before_release, 1u32, .SeqCst)
    }
    sync.event_set(&r.release_third)
}

fn reentrant_range(r: *Reentrant, lo: usize, hi: usize, token: *const task.Cancel) -> err {
    let unused_lo = lo
    let unused_hi = hi
    let unused_token = token
    let previous = atomic.add(&r.ranges, 1u32, .AcqRel)
    ret ok
}

fn reentrant_outer(r: *Reentrant, token: *const task.Cancel) -> err {
    let unused_token = token
    ret task.parallel_for[Reentrant](r.pool, r.token, 0usize, 2usize, 1usize, r, reentrant_range)
}

fn stamped_range(r: *StampedReentrant, lo: usize, hi: usize, token: *const task.Cancel) -> err {
    let unused_lo = lo
    let unused_hi = hi
    let unused_token = token
    let previous = atomic.add(&r.ranges, 1u32, .AcqRel)
    ret ok
}

fn stamped_foreign(r: *StampedReentrant, token: *const task.Cancel) -> err {
    let unused_token = token
    sync.event_wait(&r.release_foreign)
    ret ok
}

fn stamped_outer(r: *StampedReentrant, token: *const task.Cancel) -> err {
    let unused_token = token
    sync.event_set(&r.outer_started)
    sync.event_wait(&r.foreign_queued)
    let outcome = task.parallel_for[StampedReentrant](r.pool, r.token, 0usize, 2usize, 1usize, r, stamped_range)
    sync.event_set(&r.release_foreign)
    ret outcome
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (made, pool_error) = task.pool(a, task.Options { workers: 3u32, queue_capacity: 8usize, stack_size: 0usize })
    if pool_error != ok { os.exit(1i32) }
    var p = made
    var token = cancel.token()

    // Six tasks add their ids; every one succeeds and the handles are released by wait_all.
    var counters: [6]Counter = zero
    var handles: [6]task.Task = zero
    var pointers: [6]*task.Task = zero
    var i = 0usize
    while i < 6usize {
        counters[i].id = u64(i + 1usize)
        counters[i].total = atomic.init(0u64)
        let (t, submit_error) = task.submit[Counter](&p, &token, &counters[i], add_id)
        if submit_error != ok { os.exit(2i32) }
        handles[i] = t
        pointers[i] = &handles[i]
        i += 1usize
    }
    if task.wait_all(pointers[0..]) != ok { os.exit(3i32) }
    var sum = 0u64
    i = 0usize
    while i < 6usize {
        sum += atomic.load(&counters[i].total, .Acquire)
        i += 1usize
    }
    if sum != 21u64 { os.exit(4i32) }

    // A future carries a typed result; a failing task carries its error.
    var seven = Counter { total: atomic.init(0u64), id: 7u64 }
    let (f, future_error) = task.future[u64, Counter](&p, &token, &seven, square_id)
    if future_error != ok { os.exit(5i32) }
    var fut = f
    let (squared, get_error) = task.future_get[u64](&fut)
    if get_error != ok || squared != 49u64 { os.exit(6i32) }
    let (failing, failing_error) = task.submit[Counter](&p, &token, &seven, fail)
    if failing_error != ok { os.exit(7i32) }
    var failed = failing
    let (was_done, outcome) = task.wait_for(&failed, time.seconds(5i64))
    if !was_done || outcome != Boom { os.exit(8i32) }

    // A held task: a bounded wait times out, the gate lets it finish; a second held task
    // is cancelled while running; a task queued behind a requested token never runs.
    var gate = Gate { open: sync.event(true, false) }
    let (held, held_error) = task.submit[Gate](&p, &token, &gate, hold)
    if held_error != ok { os.exit(9i32) }
    var holding = held
    let (early, early_error) = task.wait_for(&holding, time.millis(20i64))
    if early_error != ok || early { os.exit(10i32) }
    let seen = task.status(&holding)
    if seen != .Running && seen != .Pending { os.exit(11i32) }
    sync.event_set(&gate.open)
    if task.wait(&holding) != ok { os.exit(12i32) }
    var stop = cancel.token()
    var gate_two = Gate { open: sync.event(true, false) }
    let (cancellable, cancellable_error) = task.submit[Gate](&p, &stop, &gate_two, hold)
    if cancellable_error != ok { os.exit(13i32) }
    var cancelling = cancellable
    cancel.request(&stop)
    if task.wait(&cancelling) != task.Cancelled { os.exit(14i32) }
    var never = cancel.token()
    cancel.request(&never)
    let (skipped, skipped_error) = task.submit[Counter](&p, &never, &seven, add_id)
    if skipped_error != ok { os.exit(15i32) }
    var skipping = skipped
    if task.wait(&skipping) != task.Cancelled || atomic.load(&seven.total, .Acquire) != 0u64 { os.exit(16i32) }

    // wait_any answers the first settled task in input order.
    var gate_three = Gate { open: sync.event(true, false) }
    let (slow, slow_error) = task.submit[Gate](&p, &token, &gate_three, hold)
    let (quick, quick_error) = task.submit[Counter](&p, &token, &seven, add_id)
    if slow_error != ok || quick_error != ok { os.exit(17i32) }
    var slow_task = slow
    var quick_task = quick
    var pair: [2]*task.Task = [2]*task.Task{ &slow_task, &quick_task }
    let (which, any_done, any_error) = task.wait_any(pair[0..], time.seconds(5i64))
    if !any_done || any_error != ok || which != 1usize { os.exit(18i32) }
    sync.event_set(&gate_three.open)
    if task.wait(&slow_task) != ok || task.wait(&quick_task) != ok { os.exit(19i32) }

    // A full ring refuses; parallel_for still completes with more ranges than records.
    let (small, small_error) = task.pool(a, task.Options { workers: 1u32, queue_capacity: 2usize, stack_size: 0usize })
    if small_error != ok { os.exit(20i32) }
    var narrow = small
    var gate_four = Gate { open: sync.event(true, false) }
    let (first, first_error) = task.submit[Gate](&narrow, &token, &gate_four, hold)
    let (second, second_error) = task.submit[Gate](&narrow, &token, &gate_four, hold)
    let (_, third_error) = task.submit[Gate](&narrow, &token, &gate_four, hold)
    if first_error != ok || second_error != ok || third_error != task.Invalid { os.exit(21i32) }
    let full_future_mark = mem.mark(a)
    let (_, full_future_error) = task.future[u64, Counter](&narrow, &token, &seven, square_id)
    if full_future_error != task.Invalid || mem.mark(a) != full_future_mark { os.exit(29i32) }
    sync.event_set(&gate_four.open)
    var first_task = first
    var second_task = second
    if task.wait(&first_task) != ok || task.wait(&second_task) != ok { os.exit(22i32) }
    var squares: Squares = zero
    if task.parallel_for[Squares](&narrow, &token, 0usize, 1000usize, 100usize, &squares, sum_squares) != ok { os.exit(23i32) }
    var expected = 0u64
    i = 0usize
    while i < 1000usize {
        expected += u64(i) * u64(i)
        i += 1usize
    }
    var got = 0u64
    i = 0usize
    while i < 10usize {
        got += squares.partial[i]
        i += 1usize
    }
    if got != expected { os.exit(24i32) }
    if task.parallel_for[Squares](&narrow, &token, 0usize, 10usize, 0usize, &squares, sum_squares) != task.Invalid { os.exit(25i32) }
    var one_chunk: Squares = zero
    if task.parallel_for[Squares](&narrow, &token, 3usize, 10usize, 18446744073709551615usize, &one_chunk, sum_squares) != ok { os.exit(30i32) }
    var chunk_expected = 0u64
    i = 3usize
    while i < 10usize {
        chunk_expected += u64(i) * u64(i)
        i += 1usize
    }
    if one_chunk.partial[0usize] != chunk_expected { os.exit(31i32) }

    // A task on a one-worker pool must help its own queued parallel range rather
    // than wait for that same worker.  The bounded wait makes the old deadlock a
    // deterministic fixture failure instead of a hung suite.
    let (reentrant_made, reentrant_pool_error) = task.pool(a, task.Options { workers: 1u32, queue_capacity: 2usize, stack_size: 0usize })
    if reentrant_pool_error != ok { os.exit(47i32) }
    var reentrant_pool = reentrant_made
    var reentrant = Reentrant { pool: &reentrant_pool, token: &token, ranges: atomic.init(0u32) }
    let (nested, nested_error) = task.submit[Reentrant](&reentrant_pool, &token, &reentrant, reentrant_outer)
    if nested_error != ok { os.exit(48i32) }
    var nested_task = nested
    let (nested_done, nested_outcome) = task.wait_for(&nested_task, time.seconds(2i64))
    if !nested_done || nested_outcome != ok || atomic.load(&reentrant.ranges, .Acquire) != 2u32 { os.exit(49i32) }
    if task.close(&reentrant_pool) != ok { os.exit(50i32) }

    // The nested range may sit behind unrelated queued work.  It must select its
    // own stamped record instead of running that work, which is blocked until the
    // outer task returns from parallel_for.
    let (stamped_made, stamped_pool_error) = task.pool(a, task.Options { workers: 1u32, queue_capacity: 3usize, stack_size: 0usize })
    if stamped_pool_error != ok { os.exit(51i32) }
    var stamped_pool = stamped_made
    var stamped = StampedReentrant {
        pool: &stamped_pool,
        token: &token,
        outer_started: sync.event(true, false),
        foreign_queued: sync.event(true, false),
        release_foreign: sync.event(true, false),
        ranges: atomic.init(0u32),
    }
    let (stamped_outer_task, stamped_outer_error) = task.submit[StampedReentrant](&stamped_pool, &token, &stamped, stamped_outer)
    if stamped_outer_error != ok { os.exit(52i32) }
    sync.event_wait(&stamped.outer_started)
    let (stamped_foreign_task, stamped_foreign_error) = task.submit[StampedReentrant](&stamped_pool, &token, &stamped, stamped_foreign)
    if stamped_foreign_error != ok { os.exit(53i32) }
    sync.event_set(&stamped.foreign_queued)
    var stamped_outer_running = stamped_outer_task
    let (stamped_done, stamped_outcome) = task.wait_for(&stamped_outer_running, time.seconds(2i64))
    if !stamped_done || stamped_outcome != ok || atomic.load(&stamped.ranges, .Acquire) != 2u32 { os.exit(54i32) }
    var stamped_foreign_running = stamped_foreign_task
    if task.wait(&stamped_foreign_running) != ok { os.exit(55i32) }
    if task.close(&stamped_pool) != ok { os.exit(56i32) }

    // `wait_any` waits on one pool's condition, so mixed pools are explicitly
    // rejected before it observes either record under the wrong mutex.
    let (left_pool_task, left_pool_error) = task.submit[Counter](&p, &token, &seven, add_id)
    let (right_pool_task, right_pool_error) = task.submit[Counter](&narrow, &token, &seven, add_id)
    if left_pool_error != ok || right_pool_error != ok { os.exit(32i32) }
    var left_task = left_pool_task
    var right_task = right_pool_task
    var mixed: [2]*task.Task = zero
    mixed[0usize] = &left_task
    mixed[1usize] = &right_task
    let (_, mixed_done, mixed_error) = task.wait_any(mixed[..], time.millis(20i64))
    if mixed_error != task.Invalid || mixed_done { os.exit(33i32) }
    if task.wait(&left_task) != ok || task.wait(&right_task) != ok { os.exit(34i32) }

    // Once the first queued range settles, the next submission must reap it and
    // use the worker again instead of leaving every remaining range to this thread.
    let (reap_made, reap_pool_error) = task.pool(a, task.Options { workers: 1u32, queue_capacity: 1usize, stack_size: 0usize })
    if reap_pool_error != ok { os.exit(35i32) }
    var reap_pool = reap_made
    var reap = ReapRace {
        worker_started: sync.event(true, false),
        release_initial: sync.event(true, false),
        initial_finished: sync.event(true, false),
        settle_pause: sync.event(true, false),
        third_started: sync.event(true, false),
        after_reap: sync.event(true, false),
        release_third: sync.event(true, false),
        after_reap_before_release: atomic.init(0u32),
    }
    let (reap_releaser, reap_releaser_error) = thread.spawn[ReapRace](reap_release, &reap, 0usize)
    if reap_releaser_error != ok { os.exit(36i32) }
    let reap_outcome = task.parallel_for[ReapRace](&reap_pool, &token, 0usize, 4usize, 1usize, &reap, reap_body)
    if thread.join(reap_releaser) != ok { os.exit(37i32) }
    if reap_outcome != ok || atomic.load(&reap.after_reap_before_release, .SeqCst) != 1u32 { os.exit(38i32) }
    if task.close(&reap_pool) != ok { os.exit(39i32) }

    // A closer marks the pool closed only after the worker has started range zero.
    // The second range confirms that state before the third submission observes it;
    // therefore parallel_for must wait for range zero before it may return Closed.
    let (race_made, race_pool_error) = task.pool(a, task.Options { workers: 1u32, queue_capacity: 1usize, stack_size: 0usize })
    if race_pool_error != ok { os.exit(40i32) }
    var race_pool = race_made
    var race = CloseRace {
        pool: &race_pool,
        token: &token,
        worker_started: sync.event(true, false),
        close_requested: sync.event(true, false),
        releaser_ready: sync.event(true, false),
        release_worker: sync.event(true, false),
        parallel_returned: sync.event(true, false),
        returned_before_release: atomic.init(0u32),
        worker_finished: atomic.init(0u32),
        close_failed: atomic.init(0u32),
    }
    let (closer, closer_error) = thread.spawn[CloseRace](race_close, &race, 0usize)
    if closer_error != ok { os.exit(41i32) }
    let (releaser, releaser_error) = thread.spawn[CloseRace](race_release, &race, 0usize)
    if releaser_error != ok { os.exit(42i32) }
    let race_outcome = task.parallel_for[CloseRace](&race_pool, &token, 0usize, 3usize, 1usize, &race, race_body)
    sync.event_set(&race.parallel_returned)
    if thread.join(closer) != ok || thread.join(releaser) != ok { os.exit(43i32) }
    if race_outcome != task.Closed || atomic.load(&race.close_failed, .SeqCst) != 0u32 { os.exit(44i32) }
    if atomic.load(&race.worker_finished, .SeqCst) != 1u32 || atomic.load(&race.returned_before_release, .SeqCst) != 0u32 { os.exit(45i32) }

    // Closing refuses new work and closes once.
    if task.close(&narrow) != ok || task.close(&narrow) != task.Closed { os.exit(26i32) }
    let (_, after_close) = task.submit[Counter](&narrow, &token, &seven, add_id)
    if after_close != task.Closed { os.exit(27i32) }
    let closed_future_mark = mem.mark(a)
    let (_, closed_future_error) = task.future[u64, Counter](&narrow, &token, &seven, square_id)
    if closed_future_error != task.Closed || mem.mark(a) != closed_future_mark { os.exit(46i32) }
    if task.close(&p) != ok { os.exit(28i32) }

    try io.print("task pool ok\n")
    ret ok
}
