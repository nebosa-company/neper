// Chandy-Lamport global snapshots simulated over `n` processes that each
// hold a quantity (`Proc.state`) and move parts of it over FIFO channels:
// `snapshot_send` moves `amount` from one process into a message, the
// caller delivers messages in sending order through `snapshot_step`, and
// the recorded global state is consistent (the quantity is conserved).
// `snapshot_initiate` records the initiator, starts recording its incoming
// channels and sends a marker on every outgoing channel; a process seeing
// its first marker does the same and stops recording the channel it came
// on; messages arriving on a recording channel count as in flight. The
// messages land in a caller `Sent` pool in sending order.

type Message = struct { from: u32, to: u32, marker: bool, amount: u64 }
type Sent = struct { out: []Message, count: usize }
type Proc = struct { state: u64, recorded: bool, snapshot: u64, markers: usize }
type Channel = struct { recording: bool, count: usize, total: u64 }
type Snapshot = struct { procs: []Proc, channels: []Channel }
error TooSmall
error Invalid

fn sent(out: []Message) -> Sent { ret Sent { out: out, count: 0usize } }

fn push(s: *Sent, from: usize, to: usize, marker: bool, amount: u64) {
    if s.count < s.out.len { s.out[s.count] = Message { from: u32(from), to: u32(to), marker: marker, amount: amount } }
    s.count += 1usize
}

// `initial[i]` is process i's starting quantity; `channels` holds n*n records.
fn snapshot(procs: []Proc, channels: []Channel, initial: []const u64) -> (Snapshot, err) {
    let n = procs.len
    let s = Snapshot { procs: procs, channels: channels }
    if initial.len != n || channels.len < n * n { ret (s, TooSmall) }
    var i = 0usize
    while i < n {
        procs[i] = Proc { state: initial[i], recorded: false, snapshot: 0u64, markers: 0usize }
        i += 1usize
    }
    i = 0usize
    while i < n * n {
        channels[i] = Channel { recording: false, count: 0usize, total: 0u64 }
        i += 1usize
    }
    ret (s, ok)
}

// Move `amount` out of `from` into a message to `to`; Invalid when `from`
// lacks it or the endpoints are wrong.
fn snapshot_send(s: *Snapshot, from: usize, to: usize, amount: u64, out: *Sent) -> err {
    let n = s.procs.len
    if from >= n || to >= n || from == to || s.procs[from].state < amount { ret Invalid }
    s.procs[from].state -= amount
    push(out, from, to, false, amount)
    ret ok
}

// Record `i`'s state, record every incoming channel but `except` (n means
// none excepted), and send markers on every outgoing channel.
fn record(s: *Snapshot, i: usize, except: usize, out: *Sent) {
    let n = s.procs.len
    s.procs[i].recorded = true
    s.procs[i].snapshot = s.procs[i].state
    var j = 0usize
    while j < n {
        if j != i {
            if j != except { s.channels[j * n + i].recording = true }
            push(out, i, j, true, 0u64)
        }
        j += 1usize
    }
}

// Process `i` starts the snapshot; Invalid when one is already under way there.
fn snapshot_initiate(s: *Snapshot, i: usize, out: *Sent) -> err {
    if i >= s.procs.len || s.procs[i].recorded { ret Invalid }
    record(s, i, s.procs.len, out)
    ret ok
}

// Deliver `m` to its `to` process; answers whether it was a marker.
fn snapshot_step(s: *Snapshot, m: Message, out: *Sent) -> bool {
    let n = s.procs.len
    let i = usize(m.to)
    let j = usize(m.from)
    let c = j * n + i
    if m.marker {
        s.procs[i].markers += 1usize
        if !s.procs[i].recorded { record(s, i, j, out) }
        s.channels[c].recording = false
        ret true
    }
    s.procs[i].state += m.amount
    if s.channels[c].recording {
        s.channels[c].count += 1usize
        s.channels[c].total += m.amount
    }
    ret false
}

// Every process recorded and no channel still recording.
fn snapshot_complete(s: *const Snapshot) -> bool {
    let n = s.procs.len
    var i = 0usize
    while i < n {
        if !s.procs[i].recorded { ret false }
        i += 1usize
    }
    i = 0usize
    while i < n * n {
        if s.channels[i].recording { ret false }
        i += 1usize
    }
    ret true
}

// The recorded quantity: process snapshots plus what was in flight.
fn snapshot_total(s: *const Snapshot) -> u64 {
    let n = s.procs.len
    var t = 0u64
    var i = 0usize
    while i < n {
        t += s.procs[i].snapshot
        i += 1usize
    }
    i = 0usize
    while i < n * n {
        t += s.channels[i].total
        i += 1usize
    }
    ret t
}

// The live quantity held by the processes (what the pool carries is not counted).
fn snapshot_live(s: *const Snapshot) -> u64 {
    var t = 0u64
    var i = 0usize
    while i < s.procs.len {
        t += s.procs[i].state
        i += 1usize
    }
    ret t
}

// ---- planned one-call form ------------------------------------------------

// A scripted computation: Send moves `amount` from `from` to `to`, Deliver
// hands the oldest undelivered message to its process, Initiate starts the
// snapshot at `from`.
type OpKind = enum u8 { Send, Deliver, Initiate }
type Op = struct { kind: OpKind, from: u32, to: u32, amount: u64 }

// Chandy-Lamport in one call: run `script` over fresh processes holding
// `initial`; answers (recorded total, snapshot complete, error). The
// process and channel records hold the recorded states afterwards. A
// Deliver with nothing pending is Invalid, as is a bad send or a second
// initiation.
fn chandy_lamport(procs: []Proc, channels: []Channel, initial: []const u64, script: []const Op, out: *Sent) -> (u64, bool, err) {
    let (s0, e0) = snapshot(procs, channels, initial)
    if e0 != ok { ret (0u64, false, e0) }
    var s = s0
    var head = 0usize
    var i = 0usize
    while i < script.len {
        let op = script[i]
        if op.kind == .Send {
            let e = snapshot_send(&s, usize(op.from), usize(op.to), op.amount, out)
            if e != ok { ret (0u64, false, e) }
        } else if op.kind == .Initiate {
            let e = snapshot_initiate(&s, usize(op.from), out)
            if e != ok { ret (0u64, false, e) }
        } else {
            if head >= out.count { ret (0u64, false, Invalid) }
            if head >= out.out.len { ret (0u64, false, TooSmall) }
            let _ = snapshot_step(&s, out.out[head], out)
            head += 1usize
        }
        i += 1usize
    }
    ret (snapshot_total(&s), snapshot_complete(&s), ok)
}
