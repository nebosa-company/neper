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
use e.time

error Boom

type Counter = struct { total: Atomic[u64], id: u64 }
type Gate = struct { open: sync.Event }
type Squares = struct { partial: [64]u64 }

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

    // Closing refuses new work and closes once.
    if task.close(&narrow) != ok || task.close(&narrow) != task.Closed { os.exit(26i32) }
    let (_, after_close) = task.submit[Counter](&narrow, &token, &seven, add_id)
    if after_close != task.Closed { os.exit(27i32) }
    if task.close(&p) != ok { os.exit(28i32) }

    try io.print("task pool ok\n")
    ret ok
}
