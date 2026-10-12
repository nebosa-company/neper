// The loop that carries out gRFC A6 over `e.net.grpc` (L164): a call is a set of attempts, each an HTTP/2 stream of one
// `Conn`, and `Call` decides what the transport does next. It owns no sockets and no clock: the caller reads the clock,
// opens and cancels streams, and feeds back what the connection reported, so a simulated transport and a socket drive the
// same machine.
//
//   * retry mode: one attempt at a time. An uncommitted failure goes through `e.net.grpcretry.decide` (retryable codes,
//     `grpc-retry-pushback-ms`, attempts, the throttle bucket, the deadline) and the next attempt starts after the delay it
//     gives; a response whose headers arrived is committed and final; success and a non-retryable code end the call;
//   * hedging mode (A6's `hedgingPolicy`): the first attempt starts at once and each further one `delay_ns` after the
//     previous start, up to `max_attempts` (at most 5), without waiting for the earlier ones. A response with headers
//     wins and every other attempt is cancelled; `OK` wins likewise; a code in `nonfatal` starts the next hedge
//     immediately; any other code is fatal, cancels the rest and ends the call; a pushback that does not parse stops
//     further hedges and one that does delays the next to `now + pushback`; a hedge is sent only while the throttle has more
//     than half its tokens; when the last attempt has failed and no more can start, the call ends with that status;
//   * `per_attempt_ns` (the per-attempt receive timeout, which A6 does not define): an attempt with no headers by then is
//     cancelled and fails with `DEADLINE_EXCEEDED` through the same path as any other failure of its mode;
//   * `deadline_ns` (absolute, 0 for none): at or past it everything is cancelled and the call ends `DEADLINE_EXCEEDED`.
//
// Use: `call_poll(now, jitter)` answers the next thing to do: START (open a stream, then `call_opened`), CANCEL (a stream
// to reset), WAIT (nothing until `at_ns`, or an event, whichever is first) or DONE (the call's status and winning stream).
// `call_event` turns `e.net.grpc` events into `call_headers` and `call_status`. `jitter` is the caller's uniform draw in
// [0, 1) for the backoff.
//
// Memory: nothing is allocated; the throttle is shared by the calls of a channel and is the caller's.

use e.net.grpc as grpc
use e.net.grpcretry as retry

const MODE_RETRY: u8 = 0u8
const MODE_HEDGE: u8 = 1u8

const ACTION_START: u8 = 1u8
const ACTION_CANCEL: u8 = 2u8
const ACTION_WAIT: u8 = 3u8
const ACTION_DONE: u8 = 4u8

const SLOT_FREE: u8 = 0u8
const SLOT_OPENING: u8 = 1u8
const SLOT_LIVE: u8 = 2u8
const SLOT_CANCEL: u8 = 3u8
const SLOT_ENDED: u8 = 4u8

type Hedging = struct { max_attempts: u32, delay_ns: u64, nonfatal: u32 }
type Slot = struct { state: u8, attempt: u32, stream: u32, started_ns: u64, committed: bool }
type Action = struct { kind: u8, attempt: u32, stream: u32, at_ns: u64, code: u32 }
type Call = struct { mode: u8, policy: retry.Policy, hedge: Hedging, throttle: *retry.Throttle, per_attempt_ns: u64, deadline_ns: u64, slots: [5]Slot, started: u32, pending: bool, next_ns: u64, stop: bool, done: bool, code: u32, winner: u32 }

fn max_hedges() -> u32 { ret 5u32 }

fn empty_slot() -> Slot { ret Slot { state: SLOT_FREE, attempt: 0u32, stream: 0u32, started_ns: 0u64, committed: false } }

fn new_call(mode: u8, policy: retry.Policy, hedge: Hedging, throttle: *retry.Throttle, per_attempt_ns: u64, deadline_ns: u64, now_ns: u64) -> Call {
    var slots: [5]Slot = zero
    var i = 0usize
    while i < 5usize {
        slots[i] = empty_slot()
        i += 1usize
    }
    var h = hedge
    if h.max_attempts > max_hedges() { h.max_attempts = max_hedges() }
    if h.max_attempts < 1u32 { h.max_attempts = 1u32 }
    ret Call { mode: mode, policy: policy, hedge: h, throttle: throttle, per_attempt_ns: per_attempt_ns, deadline_ns: deadline_ns, slots: slots, started: 0u32, pending: true, next_ns: now_ns, stop: false, done: false, code: 0u32, winner: 0u32 }
}

// A retrying call under `policy`.
fn call_retry(policy: retry.Policy, throttle: *retry.Throttle, per_attempt_ns: u64, deadline_ns: u64, now_ns: u64) -> Call {
    let none = Hedging { max_attempts: 1u32, delay_ns: 0u64, nonfatal: 0u32 }
    ret new_call(MODE_RETRY, policy, none, throttle, per_attempt_ns, deadline_ns, now_ns)
}

// A hedged call.
fn call_hedge(hedge: Hedging, throttle: *retry.Throttle, per_attempt_ns: u64, deadline_ns: u64, now_ns: u64) -> Call {
    let policy = retry.Policy { max_attempts: 1u32, initial_ns: 0u64, max_ns: 0u64, multiplier: 1.0f64, codes: 0u32 }
    ret new_call(MODE_HEDGE, policy, hedge, throttle, per_attempt_ns, deadline_ns, now_ns)
}

fn slot_of_stream(c: *Call, stream: u32) -> usize {
    var i = 0usize
    while i < 5usize {
        if (c.slots[i].state == SLOT_LIVE || c.slots[i].state == SLOT_OPENING) && c.slots[i].stream == stream { ret i }
        i += 1usize
    }
    ret 5usize
}

fn outstanding(c: *const Call) -> u32 {
    var n = 0u32
    var i = 0usize
    while i < 5usize {
        if c.slots[i].state == SLOT_LIVE || c.slots[i].state == SLOT_OPENING { n += 1u32 }
        i += 1usize
    }
    ret n
}

fn cancel_others(c: *Call, keep: usize) {
    var i = 0usize
    while i < 5usize {
        if i != keep && (c.slots[i].state == SLOT_LIVE || c.slots[i].state == SLOT_OPENING) {
            c.slots[i].state = SLOT_CANCEL
        }
        i += 1usize
    }
}

fn finish(c: *Call, code: u32, winner: u32) {
    c.done = true
    c.code = code
    c.winner = winner
    c.pending = false
}

fn code_in(mask: u32, code: u32) -> bool {
    if code > 16u32 { ret false }
    ret (mask & (1u32 << code)) != 0u32
}

// The stream of an attempt was opened.
fn call_opened(c: *Call, attempt: u32, stream: u32, now_ns: u64) {
    var i = 0usize
    while i < 5usize {
        if c.slots[i].state == SLOT_OPENING && c.slots[i].attempt == attempt {
            c.slots[i].stream = stream
            c.slots[i].state = SLOT_LIVE
            c.slots[i].started_ns = now_ns
        }
        i += 1usize
    }
}

// The attempt's response headers arrived: it is committed and the call is bound to it.
fn call_headers(c: *Call, stream: u32) {
    if c.done { ret }
    let s = slot_of_stream(c, stream)
    if s == 5usize { ret }
    c.slots[s].committed = true
    cancel_others(c, s)
    c.pending = false
    c.stop = true
}

// An attempt failed or finished with `code` (0 for OK); `pushback` is `grpc-retry-pushback-ms` when `has_pushback`.
fn fail_slot(c: *Call, s: usize, code: u32, pushback: str, has_pushback: bool, now_ns: u64, jitter: f64) {
    let attempt_stream = c.slots[s].stream
    let was_committed = c.slots[s].committed
    c.slots[s].state = SLOT_ENDED
    if c.mode == MODE_RETRY {
        let d = retry.decide(&c.policy, c.throttle, c.started, code, was_committed, pushback, has_pushback, jitter, now_ns, c.deadline_ns)
        if code == 0u32 || !d.retry {
            finish(c, code, attempt_stream)
            ret
        }
        c.pending = true
        c.next_ns = now_ns + d.delay_ns
        ret
    }
    // hedging
    if code == 0u32 {
        retry.throttle_success(c.throttle)
        cancel_others(c, s)
        finish(c, 0u32, attempt_stream)
        ret
    }
    if was_committed {
        finish(c, code, attempt_stream)
        ret
    }
    var pushback_ok = true
    var delay = 0u64
    if has_pushback {
        let (pushed, push_error) = retry.pushback_parse(pushback)
        if push_error != ok {
            pushback_ok = false
        } else {
            delay = pushed
        }
    }
    let nonfatal = code_in(c.hedge.nonfatal, code)
    if !nonfatal {
        cancel_others(c, s)
        finish(c, code, attempt_stream)
        ret
    }
    // a non-fatal code, or a pushback: a failure of the throttle, and the next hedge is sent sooner or not at all
    retry.throttle_failure(c.throttle)
    if !pushback_ok {
        c.stop = true
        c.pending = false
    } else if has_pushback {
        c.next_ns = now_ns + delay
        if c.started < c.hedge.max_attempts && !c.stop { c.pending = true }
    } else {
        c.next_ns = now_ns
        if c.started < c.hedge.max_attempts && !c.stop { c.pending = true }
    }
    if outstanding(c) == 0u32 && !c.pending {
        finish(c, code, attempt_stream)
    }
}

// The attempt on `stream` ended with trailers carrying `code`.
fn call_status(c: *Call, stream: u32, code: u32, pushback: str, has_pushback: bool, now_ns: u64, jitter: f64) {
    if c.done { ret }
    let s = slot_of_stream(c, stream)
    if s == 5usize { ret }
    fail_slot(c, s, code, pushback, has_pushback, now_ns, jitter)
}

// RST_STREAM from the server: the status gRPC gives each HTTP/2 error code.
fn reset_status(h2_code: u32) -> u32 {
    if h2_code == 7u32 { ret grpc.UNAVAILABLE }
    if h2_code == 8u32 { ret grpc.CANCELLED }
    if h2_code == 11u32 { ret grpc.RESOURCE_EXHAUSTED }
    if h2_code == 12u32 { ret grpc.PERMISSION_DENIED }
    ret grpc.INTERNAL
}

fn call_event(c: *Call, ev: *const grpc.Event, now_ns: u64, jitter: f64) {
    if ev.kind == grpc.EVENT_HEADERS {
        call_headers(c, ev.stream)
    } else if ev.kind == grpc.EVENT_TRAILERS {
        let (pushback, has_pushback) = grpc.find_header(ev.headers, "grpc-retry-pushback-ms")
        call_status(c, ev.stream, ev.code, pushback, has_pushback, now_ns, jitter)
    } else if ev.kind == grpc.EVENT_RESET {
        call_status(c, ev.stream, reset_status(ev.code), "", false, now_ns, jitter)
    }
}

fn min_nonzero(x: u64, y: u64) -> u64 {
    if x == 0u64 { ret y }
    if y == 0u64 { ret x }
    if y < x { ret y }
    ret x
}

// What the transport does next at `now_ns`.
fn call_poll(c: *Call, now_ns: u64, jitter: f64) -> Action {
    // streams to reset come first, whatever else has happened
    var i = 0usize
    while i < 5usize {
        if c.slots[i].state == SLOT_CANCEL {
            c.slots[i].state = SLOT_ENDED
            ret Action { kind: ACTION_CANCEL, attempt: c.slots[i].attempt, stream: c.slots[i].stream, at_ns: 0u64, code: 0u32 }
        }
        i += 1usize
    }
    if c.done { ret Action { kind: ACTION_DONE, attempt: 0u32, stream: c.winner, at_ns: 0u64, code: c.code } }
    if c.deadline_ns > 0u64 && now_ns >= c.deadline_ns {
        cancel_others(c, 5usize)
        finish(c, grpc.DEADLINE_EXCEEDED, 0u32)
        ret call_poll(c, now_ns, jitter)
    }
    // per-attempt receive timeouts
    i = 0usize
    while i < 5usize {
        if c.per_attempt_ns > 0u64 && c.slots[i].state == SLOT_LIVE && !c.slots[i].committed && now_ns >= c.slots[i].started_ns + c.per_attempt_ns {
            // the attempt is given up: its failure is processed as if the stream had ended, and the stream is reset
            fail_slot(c, i, grpc.DEADLINE_EXCEEDED, "", false, now_ns, jitter)
            c.slots[i].state = SLOT_CANCEL
            ret call_poll(c, now_ns, jitter)
        }
        i += 1usize
    }
    if c.pending && now_ns >= c.next_ns {
        if c.mode == MODE_HEDGE && c.started > 0u32 && !retry.throttle_allows(c.throttle) {
            // a hedge is sent only while the bucket is above half
            c.stop = true
            c.pending = false
            if outstanding(c) == 0u32 { finish(c, grpc.UNAVAILABLE, 0u32) }
            ret call_poll(c, now_ns, jitter)
        }
        var free = 5usize
        i = 0usize
        while i < 5usize {
            if free == 5usize && c.slots[i].state == SLOT_FREE { free = i }
            i += 1usize
        }
        if free < 5usize {
            c.started += 1u32
            c.slots[free] = Slot { state: SLOT_OPENING, attempt: c.started, stream: 0u32, started_ns: now_ns, committed: false }
            c.pending = false
            if c.mode == MODE_HEDGE && c.started < c.hedge.max_attempts && !c.stop {
                c.pending = true
                c.next_ns = now_ns + c.hedge.delay_ns
            }
            ret Action { kind: ACTION_START, attempt: c.started, stream: 0u32, at_ns: 0u64, code: 0u32 }
        }
    }
    // nothing due: the earliest instant something will be
    var wake = 0u64
    if c.pending { wake = c.next_ns }
    i = 0usize
    while i < 5usize {
        if c.per_attempt_ns > 0u64 && c.slots[i].state == SLOT_LIVE && !c.slots[i].committed {
            wake = min_nonzero(wake, c.slots[i].started_ns + c.per_attempt_ns)
        }
        i += 1usize
    }
    wake = min_nonzero(wake, c.deadline_ns)
    ret Action { kind: ACTION_WAIT, attempt: 0u32, stream: 0u32, at_ns: wake, code: 0u32 }
}
