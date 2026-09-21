// Distributed commit protocols as in-process state machines: nodes are
// indices (`parts.len` is the coordinator), a `Message` is a record the
// caller delivers through a `Pool`, and time is the caller's `now`.
// `two_phase` (Prepare/Vote/Commit/Abort; a participant left Prepared by a
// dead coordinator blocks), `three_phase` (PreCommit/Ack; a participant
// past PreCommit commits on timeout, one before it aborts, so nobody
// blocks), `saga_choreography` (each service triggers the next; a failure
// at step k compensates k-1..0 in reverse by events), `saga_orchestrate`
// (a coordinator sequences the same steps) and `tcc` (Try/Confirm/Cancel
// reservations that expire on the caller clock).

type Kind = enum u8 { None, Prepare, VoteYes, VoteNo, PreCommit, Ack, Commit, Abort, Execute, StepDone, StepFailed, Compensate, Compensated }
type Message = struct { from: u32, to: u32, kind: Kind, step: u32 }
type Pool = struct { items: []Message, len: usize }

type CoordState = enum u8 { Init, Waiting, PreCommitting, Committed, Aborted }
type PartState = enum u8 { Init, Prepared, PreCommitted, Committed, Aborted }
type Participant = struct { state: PartState, vote_yes: bool, deadline: u64 }
type Commit = struct { three: bool, state: CoordState, parts: []Participant, yes: u64, acks: u64, deadline: u64, timeout: u64 }

type SagaState = enum u8 { Running, Completed, Compensating, Aborted }
// `done[i]`: 0 pending, 1 done, 2 compensated, 3 failed.
type Saga = struct { orchestrated: bool, state: SagaState, done: []u8, fail_at: u32 }

type TccState = enum u8 { Free, Tried, Confirmed, Cancelled }
type Reservation = struct { state: TccState, expires: u64 }
type Tcc = struct { parts: []Reservation, ttl: u64, state: SagaState }

error TooSmall
error Invalid
error Expired

const NONE: u32 = 4294967295u32

fn pool(items: []Message) -> Pool { ret Pool { items: items, len: 0usize } }

fn pool_push(p: *Pool, m: Message) -> err {
    if p.len >= p.items.len { ret TooSmall }
    p.items[p.len] = m
    p.len += 1usize
    ret ok
}

// Remove and answer the oldest message.
fn pool_pop(p: *Pool) -> Message {
    let m = p.items[0usize]
    var i = 1usize
    while i < p.len {
        p.items[i - 1usize] = p.items[i]
        i += 1usize
    }
    p.len -= 1usize
    ret m
}

fn send(out: *Pool, from: u32, to: u32, kind: Kind, step: u32) -> err {
    ret pool_push(out, Message { from: from, to: to, kind: kind, step: step })
}

fn send_all(t: *const Commit, kind: Kind, out: *Pool) -> err {
    var i = 0usize
    while i < t.parts.len {
        try send(out, u32(t.parts.len), u32(i), kind, 0u32)
        i += 1usize
    }
    ret ok
}

fn all_mask(t: *const Commit) -> u64 { ret (1u64 << u32(t.parts.len)) - 1u64 }

// ---- 2PC / 3PC ----

// `parts[i].vote_yes` is participant i's vote; `timeout` bounds every wait.
fn two_phase(parts: []Participant, timeout: u64) -> Commit {
    ret Commit { three: false, state: .Init, parts: parts, yes: 0u64, acks: 0u64, deadline: 0u64, timeout: timeout }
}

fn three_phase(parts: []Participant, timeout: u64) -> Commit {
    ret Commit { three: true, state: .Init, parts: parts, yes: 0u64, acks: 0u64, deadline: 0u64, timeout: timeout }
}

// The coordinator opens the vote.
fn commit_begin(t: *Commit, now: u64, out: *Pool) -> err {
    if t.state != .Init { ret Invalid }
    t.state = .Waiting
    t.deadline = now + t.timeout
    ret send_all(t, .Prepare, out)
}

fn decide(t: *Commit, state: CoordState, kind: Kind, out: *Pool) -> err {
    t.state = state
    ret send_all(t, kind, out)
}

// Deliver `msg` (or a tick with `.None`) to `node`; `parts.len` is the coordinator.
fn commit_step(t: *Commit, node: usize, now: u64, msg: *const Message, out: *Pool) -> err {
    if node == t.parts.len {
        if msg.kind == .None {
            if now < t.deadline { ret ok }
            if t.state == .Waiting { ret decide(t, .Aborted, .Abort, out) }
            if t.state == .PreCommitting { ret decide(t, .Committed, .Commit, out) }
            ret ok
        }
        if msg.kind == .VoteNo {
            if t.state == .Waiting { ret decide(t, .Aborted, .Abort, out) }
            ret ok
        }
        if msg.kind == .VoteYes {
            if t.state != .Waiting { ret ok }
            t.yes |= 1u64 << msg.from
            if t.yes != all_mask(t) { ret ok }
            if !t.three { ret decide(t, .Committed, .Commit, out) }
            t.state = .PreCommitting
            t.deadline = now + t.timeout
            ret send_all(t, .PreCommit, out)
        }
        if msg.kind == .Ack {
            if t.state != .PreCommitting { ret ok }
            t.acks |= 1u64 << msg.from
            if t.acks == all_mask(t) { ret decide(t, .Committed, .Commit, out) }
            ret ok
        }
        ret Invalid
    }
    let p = &t.parts[node]
    let me = u32(node)
    let coord = u32(t.parts.len)
    if msg.kind == .None {
        if now < p.deadline { ret ok }
        // 2PC blocks in Prepared; 3PC aborts before PreCommit and commits after it.
        if t.three && p.state == .Prepared { p.state = .Aborted }
        if t.three && p.state == .PreCommitted { p.state = .Committed }
        ret ok
    }
    if msg.kind == .Prepare {
        if p.state != .Init { ret ok }
        p.deadline = now + t.timeout
        if p.vote_yes {
            p.state = .Prepared
            ret send(out, me, coord, .VoteYes, 0u32)
        }
        p.state = .Aborted
        ret send(out, me, coord, .VoteNo, 0u32)
    }
    if msg.kind == .PreCommit {
        if p.state != .Prepared { ret ok }
        p.state = .PreCommitted
        p.deadline = now + t.timeout
        ret send(out, me, coord, .Ack, 0u32)
    }
    if msg.kind == .Commit {
        if p.state == .Prepared || p.state == .PreCommitted { p.state = .Committed }
        ret ok
    }
    if msg.kind == .Abort {
        if p.state != .Committed { p.state = .Aborted }
        ret ok
    }
    ret Invalid
}

// A participant that voted yes, heard nothing, and cannot decide.
fn commit_blocked(t: *const Commit, node: usize, now: u64) -> bool {
    let p = &t.parts[node]
    ret !t.three && p.state == .Prepared && now >= p.deadline
}

// ---- Sagas ----

// Services are nodes 0..steps-1; `fail_at` is the step that fails (NONE
// for none). Choreography: each service's StepDone triggers the next
// service, a failure walks Compensated back to service 0.
fn saga_choreography(done: []u8, fail_at: u32) -> Saga {
    ret Saga { orchestrated: false, state: .Running, done: done, fail_at: fail_at }
}

// Orchestration: node `steps` is the coordinator sequencing Execute and
// Compensate.
fn saga_orchestrate(done: []u8, fail_at: u32) -> Saga {
    ret Saga { orchestrated: true, state: .Running, done: done, fail_at: fail_at }
}

fn saga_start(s: *Saga, out: *Pool) -> err {
    var from = NONE
    if s.orchestrated { from = u32(s.done.len) }
    ret send(out, from, 0u32, .Execute, 0u32)
}

fn saga_step(s: *Saga, node: usize, msg: *const Message, out: *Pool) -> err {
    let last = u32(s.done.len) - 1u32
    let coord = u32(s.done.len)
    if s.orchestrated && node == s.done.len {
        if msg.kind == .StepDone {
            if msg.step == last {
                s.state = .Completed
                ret ok
            }
            ret send(out, coord, msg.step + 1u32, .Execute, msg.step + 1u32)
        }
        if msg.kind == .StepFailed || msg.kind == .Compensated {
            if msg.step == 0u32 {
                s.state = .Aborted
                ret ok
            }
            s.state = .Compensating
            ret send(out, coord, msg.step - 1u32, .Compensate, msg.step - 1u32)
        }
        ret Invalid
    }
    let me = u32(node)
    if msg.kind == .Execute || (msg.kind == .StepDone && !s.orchestrated) {
        if s.done[node] != 0u8 { ret Invalid }
        if me == s.fail_at {
            s.done[node] = 3u8
            if s.orchestrated { ret send(out, me, coord, .StepFailed, me) }
            if me == 0u32 {
                s.state = .Aborted
                ret ok
            }
            s.state = .Compensating
            ret send(out, me, me - 1u32, .StepFailed, me)
        }
        s.done[node] = 1u8
        if s.orchestrated { ret send(out, me, coord, .StepDone, me) }
        if me == last {
            s.state = .Completed
            ret ok
        }
        ret send(out, me, me + 1u32, .StepDone, me)
    }
    if msg.kind == .Compensate || ((msg.kind == .StepFailed || msg.kind == .Compensated) && !s.orchestrated) {
        if s.done[node] != 1u8 { ret Invalid }
        s.done[node] = 2u8
        if s.orchestrated { ret send(out, me, coord, .Compensated, me) }
        if me == 0u32 {
            s.state = .Aborted
            ret ok
        }
        ret send(out, me, me - 1u32, .Compensated, me)
    }
    ret Invalid
}

// ---- TCC ----

fn tcc(parts: []Reservation, ttl: u64) -> Tcc { ret Tcc { parts: parts, ttl: ttl, state: .Running } }

// Try: reserve at `node` until `now + ttl`.
fn tcc_try(t: *Tcc, node: usize, now: u64) -> err {
    if t.state != .Running || t.parts[node].state != .Free { ret Invalid }
    t.parts[node].state = .Tried
    t.parts[node].expires = now + t.ttl
    ret ok
}

// Release every reservation still Tried whose ttl passed; answers how many.
fn tcc_expire(t: *Tcc, now: u64) -> usize {
    var count = 0usize
    var i = 0usize
    while i < t.parts.len {
        if t.parts[i].state == .Tried && now >= t.parts[i].expires {
            t.parts[i].state = .Cancelled
            count += 1usize
        }
        i += 1usize
    }
    ret count
}

// Confirm every reservation, or cancel them all if one is missing or expired.
fn tcc_confirm(t: *Tcc, now: u64) -> err {
    if t.state != .Running { ret Invalid }
    var good = true
    var i = 0usize
    while i < t.parts.len {
        if t.parts[i].state != .Tried || now >= t.parts[i].expires { good = false }
        i += 1usize
    }
    if !good {
        tcc_cancel(t)
        ret Expired
    }
    i = 0usize
    while i < t.parts.len {
        t.parts[i].state = .Confirmed
        i += 1usize
    }
    t.state = .Completed
    ret ok
}

fn tcc_cancel(t: *Tcc) {
    var i = 0usize
    while i < t.parts.len {
        if t.parts[i].state == .Tried { t.parts[i].state = .Cancelled }
        i += 1usize
    }
    t.state = .Aborted
}
