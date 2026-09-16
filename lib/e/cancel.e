// The common cancellation primitive (stdlib-hardening.md SL03, D347): a `Token` is one
// word of shared state that any thread may set once and every thread may read; a
// `Control` borrows a token for one operation and carries that operation's explicit
// deadline, when it has one. Nothing here allocates, registers a timer, joins work or
// knows the clock: `check` is given the monotonic `now` it observes, so the caller
// decides when time is looked at, and a test can hand it any instant.
use e.atomic
use e.mem
use e.time

error Cancelled
error Timeout

// Shared, non-copyable once shared: every reader holds a pointer to the one word.
type Token = struct { state: Atomic[u32] }

// A borrowed token and an optional monotonic deadline. `has_deadline: false` is no
// deadline; a zero instant is a clock value like any other, never a sentinel.
type Control = struct { token: *const Token, deadline: time.Instant, has_deadline: bool }

fn token() -> Token {
    var t: Token = zero
    ret t
}

// Thread-safe and idempotent: the first request and every later one leave the same
// word set. Requesting joins nothing and releases nothing; the operation that reads
// the token decides when it is done.
fn request(t: *Token) {
    atomic.store(&t.state, 1u32, .Release)
}

// `requested(nil)` is false: a control with no token is never cancelled. The load
// goes through a mutable view of the word: an atomic read is a read, and the
// atomic surface takes its pointer one way.
fn requested(t: *const Token) -> bool {
    if t == nil { ret false }
    let word = mem.cast[*Token](t)
    ret atomic.load(&word.state, .Acquire) != 0u32
}

// The operation's question at a point it can stop: `Cancelled` when the token is
// set, else `Timeout` when the deadline is at or before `now`, else `ok`. A request
// wins over an expired deadline at the same observation, so a caller that cancels
// sees its cancellation and not a timeout that happened to coincide.
fn check(control: Control, now: time.Instant) -> err {
    if requested(control.token) { ret Cancelled }
    if control.has_deadline && time.instant_cmp(control.deadline, now) <= 0i32 { ret Timeout }
    ret ok
}
