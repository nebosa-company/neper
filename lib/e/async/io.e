// Asynchronous operations over an `e.async` loop. An `Op` is one record in the caller's
// arena that moves from `Pending` to exactly one terminal state, observed with `state`,
// consumed with `take`. Submission never blocks: `accept` and `connect` put their socket
// in non-blocking mode and register it with the loop's poller under the record's own
// address as the token; `read` and `write` hold a caller's `io.Reader` or `io.Writer`,
// which is a blocking callback no loop can watch, so they run when the operation is
// driven -- by `wait` or `wait_any` on the calling thread -- and hold their buffers until
// then, as the fence says an uncancellable callback must.
//
// `wait` drives the loop until its operation settles: it polls, hands each event to the
// operation whose token it carries and ignores the rest, which a level-triggered poller
// reports again. `wait_any` does the same for a slice and answers the first settled
// operation in input order; a pending callback operation in the slice is run first,
// since nothing else can complete it. The control's token and deadline are checked
// before every attempt: a request wins as `Cancelled`, an expired deadline as
// `TimedOut`, and a completed operation wins over both. `cancel` marks a pending
// operation cancelled at once and answers whether it did. Bytes moved before a failure
// or a cancellation stay counted in `progress` and are never reported rolled back.
//
// `take` on an operation that is still pending, or was taken already, is `Closed`; a
// loop that refuses a registration (closed) is `Closed` at submission.

use e.async
use e.cancel as cancel_api
use e.io
use e.mem
use e.meta
use e.os
use e.time

type Op[T: type] = struct { state: *void }
type AnyOp = struct { state: *void }
type State = enum u8 { Pending, Succeeded, Failed, Cancelled, TimedOut }
error Cancelled
error Timeout
error Closed

type Kind = enum u8 { Read, Write, Accept, Connect }

type Record = struct {
    kind: Kind,
    state: State,
    control: cancel_api.Control,
    loop: *async.Loop,
    reader: io.Reader,
    writer: io.Writer,
    dst: []u8,
    src: []const u8,
    socket: os.Socket,
    address: os.SocketAddress,
    registered: bool,
    bytes: usize,
    accepted: os.Socket,
    connected: bool,
    failure: err,
    taken: bool,
}

fn new_record(a: *mem.Arena, loop: *async.Loop, control: cancel_api.Control, kind: Kind) -> (*Record, err) {
    let (records, alloc_error) = mem.alloc[Record](a, 1usize)
    if alloc_error != ok { ret (nil, alloc_error) }
    var blank: Record = zero
    blank.kind = kind
    blank.state = .Pending
    blank.control = control
    blank.loop = loop
    records[0usize] = blank
    ret (&records[0usize], ok)
}

fn token_of(r: *Record) -> async.Token {
    ret async.Token { value: mem.address_of(r) }
}

fn read(a: *mem.Arena, loop: *async.Loop, source: io.Reader, dst: []u8, control: cancel_api.Control) -> (Op[usize], err) {
    let (r, record_error) = new_record(a, loop, control, .Read)
    if record_error != ok { ret (zero, record_error) }
    r.reader = source
    r.dst = dst
    ret (Op[usize] { state: mem.cast[*void](r) }, ok)
}

fn write(a: *mem.Arena, loop: *async.Loop, sink: io.Writer, src: []const u8, control: cancel_api.Control) -> (Op[usize], err) {
    let (r, record_error) = new_record(a, loop, control, .Write)
    if record_error != ok { ret (zero, record_error) }
    r.writer = sink
    r.src = src
    ret (Op[usize] { state: mem.cast[*void](r) }, ok)
}

fn register(r: *Record, readable: bool) -> err {
    let register_error = async.register(r.loop, os.socket_handle(r.socket), token_of(r), async.Interest { readable: readable, writable: !readable })
    if register_error == async.Invalid { ret Closed }
    if register_error != ok { ret register_error }
    r.registered = true
    ret ok
}

fn accept(a: *mem.Arena, loop: *async.Loop, listener: os.Socket, control: cancel_api.Control) -> (Op[os.Socket], err) {
    let (r, record_error) = new_record(a, loop, control, .Accept)
    if record_error != ok { ret (zero, record_error) }
    r.socket = listener
    let mode_error = os.socket_set_nonblocking(listener, true)
    if mode_error != ok { ret (zero, mode_error) }
    let register_error = register(r, true)
    if register_error != ok { ret (zero, register_error) }
    ret (Op[os.Socket] { state: mem.cast[*void](r) }, ok)
}

fn connect(a: *mem.Arena, loop: *async.Loop, socket: os.Socket, address: os.SocketAddress, control: cancel_api.Control) -> (Op[bool], err) {
    let (r, record_error) = new_record(a, loop, control, .Connect)
    if record_error != ok { ret (zero, record_error) }
    r.socket = socket
    r.address = address
    let mode_error = os.socket_set_nonblocking(socket, true)
    if mode_error != ok { ret (zero, mode_error) }
    let connect_error = os.socket_connect(socket, address)
    if connect_error == ok {
        r.connected = true
        r.state = .Succeeded
    } else if connect_error == os.WouldBlock {
        let register_error = register(r, false)
        if register_error != ok { ret (zero, register_error) }
    } else {
        r.failure = connect_error
        r.state = .Failed
    }
    ret (Op[bool] { state: mem.cast[*void](r) }, ok)
}

fn terminal(r: *Record) -> bool {
    ret r.state != .Pending
}

fn settle(r: *Record, outcome: State, failure: err) {
    r.state = outcome
    r.failure = failure
    if r.registered {
        let ignored = async.unregister(r.loop, os.socket_handle(r.socket))
        r.registered = false
    }
}

// One attempt at the operation, after the control's checks; `failed` is the poller's
// verdict on the socket, which is how a refused connection arrives.
fn attempt(r: *Record, failed: bool) {
    if terminal(r) { ret }
    let (now, now_error) = time.monotonic()
    if now_error == ok {
        let verdict = cancel_api.check(r.control, now)
        if verdict == cancel_api.Cancelled {
            settle(r, .Cancelled, Cancelled)
            ret
        }
        if verdict == cancel_api.Timeout {
            settle(r, .TimedOut, Timeout)
            ret
        }
    }
    if r.kind == .Read {
        let (got, read_error) = r.reader.read(r.reader.ctx, r.dst)
        r.bytes = got
        if read_error != ok { settle(r, .Failed, read_error) } else { settle(r, .Succeeded, ok) }
        ret
    }
    if r.kind == .Write {
        while r.bytes < r.src.len {
            let (put, write_error) = r.writer.write(r.writer.ctx, r.src[r.bytes..])
            r.bytes += put
            if write_error != ok {
                settle(r, .Failed, write_error)
                ret
            }
            if put == 0usize {
                settle(r, .Failed, io.NoProgress)
                ret
            }
        }
        let flush_error = r.writer.flush(r.writer.ctx)
        if flush_error != ok { settle(r, .Failed, flush_error) } else { settle(r, .Succeeded, ok) }
        ret
    }
    if r.kind == .Accept {
        let (taken, peer, accept_error) = os.socket_accept(r.socket)
        if accept_error == os.WouldBlock { ret }
        if accept_error != ok {
            settle(r, .Failed, accept_error)
            ret
        }
        r.accepted = taken
        settle(r, .Succeeded, ok)
        ret
    }
    if failed {
        settle(r, .Failed, os.Failed)
        ret
    }
    r.connected = true
    settle(r, .Succeeded, ok)
}

// How long a poll may wait for the control: to its deadline, or without limit.
fn poll_limit(control: cancel_api.Control) -> time.Duration {
    if !control.has_deadline { ret time.Duration { nanos: -1i64 } }
    let (now, now_error) = time.monotonic()
    if now_error != ok { ret time.Duration { nanos: 0i64 } }
    var left = control.deadline.nanos - now.nanos
    if left < 0i64 { left = 0i64 }
    ret time.Duration { nanos: left }
}

// Drives `r` to a terminal state: a callback runs now; a socket waits on the loop.
fn drive(loop: *async.Loop, r: *Record) -> err {
    if r.kind == .Read || r.kind == .Write {
        attempt(r, false)
        ret ok
    }
    var events: [16]async.Event = zero
    while !terminal(r) {
        let (count, poll_error) = async.poll(loop, events[0..], poll_limit(r.control))
        if poll_error == async.Invalid { ret Closed }
        if poll_error != ok { ret poll_error }
        var i = 0usize
        var mine = false
        var failed = false
        while i < count {
            if events[i].token.value == token_of(r).value {
                mine = true
                if events[i].failed || events[i].closed { failed = true }
            }
            i += 1usize
        }
        if mine || count == 0usize { attempt(r, failed) }
    }
    ret ok
}

fn state[T: type](op: *const Op[T]) -> State {
    let r = mem.cast[*Record](op.state)
    ret r.state
}

fn erase[T: type](op: *Op[T]) -> AnyOp {
    ret AnyOp { state: op.state }
}

fn take[T: type](op: *Op[T]) -> (T, err) {
    let r = mem.cast[*Record](op.state)
    if !terminal(r) || r.taken { ret (zero, Closed) }
    r.taken = true
    if r.state != .Succeeded { ret (zero, r.failure) }
    // The result's type says which field holds it (D138 folds the other branches away):
    // the accepted socket, the connect flag, or the byte count.
    if meta.kind[T]() == .Struct { ret (r.accepted, ok) }
    if meta.kind[T]() == .Bool { ret (r.connected, ok) }
    if meta.kind[T]() == .Int { ret (r.bytes, ok) }
    ret (zero, Closed)
}

fn wait[T: type](loop: *async.Loop, op: *Op[T]) -> (T, err) {
    let r = mem.cast[*Record](op.state)
    let drive_error = drive(loop, r)
    if drive_error != ok { ret (zero, drive_error) }
    let (value, take_error) = take[T](op)
    ret (value, take_error)
}

fn wait_any(loop: *async.Loop, ops: []AnyOp, timeout: time.Duration) -> (usize, bool, err) {
    if ops.len == 0usize { ret (0usize, false, ok) }
    let (start, start_error) = time.monotonic()
    if start_error != ok { ret (0usize, false, start_error) }
    var events: [16]async.Event = zero
    while true {
        var i = 0usize
        while i < ops.len {
            let r = mem.cast[*Record](ops[i].state)
            if terminal(r) { ret (i, true, ok) }
            i += 1usize
        }
        // A callback operation completes only when run, so the first one runs now.
        i = 0usize
        while i < ops.len {
            let r = mem.cast[*Record](ops[i].state)
            if r.kind == .Read || r.kind == .Write {
                attempt(r, false)
                ret (i, true, ok)
            }
            i += 1usize
        }
        let (now, now_error) = time.monotonic()
        if now_error != ok { ret (0usize, false, now_error) }
        var left = timeout.nanos - (now.nanos - start.nanos)
        if timeout.nanos < 0i64 { left = -1i64 }
        if timeout.nanos >= 0i64 && left <= 0i64 { ret (0usize, false, ok) }
        let (count, poll_error) = async.poll(loop, events[0..], time.Duration { nanos: left })
        if poll_error == async.Invalid { ret (0usize, false, Closed) }
        if poll_error != ok { ret (0usize, false, poll_error) }
        i = 0usize
        while i < ops.len {
            let r = mem.cast[*Record](ops[i].state)
            var mine = false
            var failed = false
            var e = 0usize
            while e < count {
                if events[e].token.value == token_of(r).value {
                    mine = true
                    if events[e].failed || events[e].closed { failed = true }
                }
                e += 1usize
            }
            if mine || count == 0usize { attempt(r, failed) }
            i += 1usize
        }
    }
    ret (0usize, false, ok)
}

fn cancel[T: type](op: *Op[T]) -> (bool, err) {
    let r = mem.cast[*Record](op.state)
    if terminal(r) { ret (false, ok) }
    settle(r, .Cancelled, Cancelled)
    ret (true, ok)
}

type Progress = struct { bytes: u64, known: bool }

fn progress[T: type](op: *const Op[T]) -> Progress {
    let r = mem.cast[*Record](op.state)
    if r.kind == .Read || r.kind == .Write { ret Progress { bytes: u64(r.bytes), known: true } }
    ret Progress { bytes: 0u64, known: false }
}
