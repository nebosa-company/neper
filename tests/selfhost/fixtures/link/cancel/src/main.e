// `e.cancel` (SL03, D347): the acceptance list of stdlib-hardening.md -- an
// already-cancelled token, no deadline, a zero deadline, an expired one, one still
// ahead, a request that wins over an expired deadline at the same observation, a
// request that is idempotent, `requested(nil)`, and one token shared by threads,
// each of which stops at the request and none of which is joined by it.
use e.atomic
use e.cancel
use e.mem
use e.os
use e.time

type Worker = struct {
    token: *const cancel.Token,
    spins: u64,
    saw: bool,
}

fn spin(w: *Worker) {
    var control: cancel.Control = zero
    control.token = w.token
    let (now, now_error) = time.monotonic()
    while cancel.check(control, now) == ok {
        w.spins += 1u64
    }
    w.saw = true
}

fn main(a: *mem.Arena) -> err {
    var instant: time.Instant = zero
    instant.nanos = 1000i64
    var control: cancel.Control = zero
    // No token, no deadline: never cancelled.
    if cancel.check(control, instant) != ok { os.exit(10i32) }
    if cancel.requested(nil) { os.exit(11i32) }
    // A token, not yet requested.
    var t = cancel.token()
    control.token = &t
    if cancel.requested(&t) { os.exit(12i32) }
    if cancel.check(control, instant) != ok { os.exit(13i32) }
    // A zero deadline is a clock value: with `now` past it, a timeout; at it, a timeout;
    // with `now` before it, none.
    control.has_deadline = true
    control.deadline.nanos = 0i64
    if cancel.check(control, instant) != cancel.Timeout { os.exit(14i32) }
    var zero_now: time.Instant = zero
    if cancel.check(control, zero_now) != cancel.Timeout { os.exit(15i32) }
    control.deadline.nanos = 2000i64
    if cancel.check(control, instant) != ok { os.exit(16i32) }
    // Expired and requested at the same observation: the request wins.
    control.deadline.nanos = 500i64
    cancel.request(&t)
    if !cancel.requested(&t) { os.exit(17i32) }
    if cancel.check(control, instant) != cancel.Cancelled { os.exit(18i32) }
    // Idempotent: a second request changes nothing.
    cancel.request(&t)
    if cancel.check(control, instant) != cancel.Cancelled { os.exit(19i32) }
    // Already cancelled before an operation starts: it stops at its first check.
    control.has_deadline = false
    if cancel.check(control, instant) != cancel.Cancelled { os.exit(20i32) }
    // One token shared by four threads: each spins until the request, none is joined
    // by the request, and every one saw it.
    var common = cancel.token()
    var workers: [4]Worker = zero
    var threads: [4]os.Thread = zero
    var i = 0usize
    while i < 4usize {
        workers[i].token = &common
        let (thread, spawn_error) = os.thread_create[Worker](spin, &workers[i], 1048576usize)
        if spawn_error != ok { os.exit(21i32) }
        threads[i] = thread
        i += 1usize
    }
    var spun = 0u64
    while spun < 1000u64 { spun += 1u64 }
    cancel.request(&common)
    i = 0usize
    while i < 4usize {
        try os.thread_join(threads[i])
        if !workers[i].saw { os.exit(22i32) }
        i += 1usize
    }
    let (written, write_error) = os.write(os.stdout(), "cancel ok\n")
    ret write_error
}
