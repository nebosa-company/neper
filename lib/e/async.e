// Readiness polling over `e.os`'s poller: a `Loop` is the host's registration set --
// epoll on Linux, the completion-port emulation on Windows -- and every call here is
// the matching `os.poller_*` call with the token and interest carried across in the
// fence's own types. A host without a poller answers `Unsupported` from `init`; a
// call on a closed loop is `Invalid`. Nothing more: no futures, no scheduler, no
// callbacks, as the fence says.
use e.mem
use e.os
use e.time

type Loop = struct { state: *void }
type Token = struct { value: usize }
type Interest = struct { readable: bool, writable: bool }
type Event = struct { token: Token, readable: bool, writable: bool, closed: bool, failed: bool }
error Unsupported
error Invalid

type State = struct { poller: os.Poller, open: bool }

fn init(a: *mem.Arena) -> (Loop, err) {
    let (storage, storage_error) = mem.alloc[State](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    let (poller, open_error) = os.poller_open(a)
    if open_error == os.Unsupported { ret (zero, Unsupported) }
    if open_error != ok { ret (zero, open_error) }
    storage[0].poller = poller
    storage[0].open = true
    var l: Loop = zero
    l.state = mem.cast[*void](&storage[0])
    ret (l, ok)
}

fn state_of(loop: *Loop) -> (*State, err) {
    let s = mem.cast[*State](loop.state)
    if loop.state == nil || !s.open { ret (s, Invalid) }
    ret (s, ok)
}

fn interest_of(interest: Interest) -> os.PollInterest {
    ret os.PollInterest { readable: interest.readable, writable: interest.writable }
}

fn register(loop: *Loop, handle: os.Handle, token: Token, interest: Interest) -> err {
    let (s, state_error) = state_of(loop)
    if state_error != ok { ret state_error }
    ret os.poller_register(s.poller, handle, token.value, interest_of(interest))
}

fn modify(loop: *Loop, handle: os.Handle, token: Token, interest: Interest) -> err {
    let (s, state_error) = state_of(loop)
    if state_error != ok { ret state_error }
    ret os.poller_modify(s.poller, handle, token.value, interest_of(interest))
}

fn unregister(loop: *Loop, handle: os.Handle) -> err {
    let (s, state_error) = state_of(loop)
    if state_error != ok { ret state_error }
    ret os.poller_unregister(s.poller, handle)
}

// Up to `events.len` ready handles; a negative duration waits without a limit.
fn poll(loop: *Loop, events: []Event, timeout: time.Duration) -> (usize, err) {
    let (s, state_error) = state_of(loop)
    if state_error != ok { ret (0usize, state_error) }
    var raw: [64]os.PollEvent = zero
    var room = events.len
    if room > 64usize { room = 64usize }
    let (count, wait_error) = os.poller_wait(s.poller, raw[..room], time.as_nanos(timeout))
    if wait_error != ok { ret (0usize, wait_error) }
    var i = 0usize
    while i < count {
        events[i] = Event { token: Token { value: raw[i].token }, readable: raw[i].readable, writable: raw[i].writable, closed: raw[i].closed, failed: raw[i].failed }
        i += 1usize
    }
    ret (count, ok)
}

fn wake(loop: *Loop) -> err {
    let (s, state_error) = state_of(loop)
    if state_error != ok { ret state_error }
    ret os.poller_wake(s.poller)
}

fn close(loop: *Loop) -> err {
    let (s, state_error) = state_of(loop)
    if state_error != ok { ret state_error }
    s.open = false
    ret os.poller_close(s.poller)
}
