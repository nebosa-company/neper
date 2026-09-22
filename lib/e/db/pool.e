// A HikariCP-style connection pool as a pure state machine over caller storage:
// no threads, no sockets, no clock. A connection is an opaque `u64` handle the
// caller creates when `acquire` answers `NeedsCreate` and hands in with `attach`;
// time is whatever `now` the caller passes. Slots are `Closed` (empty), `Pending`
// (reserved, awaiting `attach`), `Free` (idle) or `InUse`. An idle connection is
// reused most-recently-used-first; when the pool is full a waiter is queued FIFO
// and `release` hands the connection to the head waiter directly. The housekeeper
// (`evict_expired`, `timeouts`) is a caller tick.

type Config = struct { min_idle: usize, max_size: usize, max_lifetime: u64, idle_timeout: u64, connection_timeout: u64, validation_interval: u64 }
type Pool = struct { handle: []u64, state: []u8, created_at: []u64, last_used: []u64, uses: []u32, waiters: []u32, waiter_since: []u64, wait_head: usize, wait_len: usize, min_idle: usize, max_size: usize, max_lifetime: u64, idle_timeout: u64, connection_timeout: u64, validation_interval: u64 }
type Outcome = enum u8 { Acquired, NeedsCreate, Queued, Timeout }
error Invalid
error Full
error TooSmall

const FREE: u8 = 0u8
const IN_USE: u8 = 1u8
const CLOSED: u8 = 2u8
const PENDING: u8 = 3u8
const NONE: u32 = 0xffffffffu32

// A pool over per-slot arrays of at least `max_size` entries and a waiter ring
// (`waiters`/`waiter_since`, same length). A zero timeout disables that rule.
fn pool(handle: []u64, state: []u8, created_at: []u64, last_used: []u64, uses: []u32, waiters: []u32, waiter_since: []u64, c: Config) -> (Pool, err) {
    var p = Pool { handle: handle, state: state, created_at: created_at, last_used: last_used, uses: uses, waiters: waiters, waiter_since: waiter_since, wait_head: 0usize, wait_len: 0usize, min_idle: c.min_idle, max_size: c.max_size, max_lifetime: c.max_lifetime, idle_timeout: c.idle_timeout, connection_timeout: c.connection_timeout, validation_interval: c.validation_interval }
    if c.max_size == 0usize || c.min_idle > c.max_size { ret (p, Invalid) }
    if handle.len < c.max_size || state.len < c.max_size || created_at.len < c.max_size || last_used.len < c.max_size || uses.len < c.max_size { ret (p, TooSmall) }
    if waiters.len == 0usize || waiter_since.len < waiters.len { ret (p, TooSmall) }
    var i = 0usize
    while i < c.max_size {
        state[i] = CLOSED
        handle[i] = 0u64
        i += 1usize
    }
    ret (p, ok)
}

fn count(p: *const Pool, s: u8) -> usize {
    var n = 0usize
    var i = 0usize
    while i < p.max_size {
        if p.state[i] == s { n += 1usize }
        i += 1usize
    }
    ret n
}

fn close_slot(p: *Pool, i: usize) {
    p.state[i] = CLOSED
    p.handle[i] = 0u64
}

// Drop `w` from the waiter ring if it is queued (compacting the ring).
fn unqueue(p: *Pool, w: u32) {
    var kept = 0usize
    var i = 0usize
    while i < p.wait_len {
        let from = (p.wait_head + i) % p.waiters.len
        if p.waiters[from] != w {
            let to = (p.wait_head + kept) % p.waiters.len
            p.waiters[to] = p.waiters[from]
            p.waiter_since[to] = p.waiter_since[from]
            kept += 1usize
        }
        i += 1usize
    }
    p.wait_len = kept
}

// The most recently used idle slot, or NONE.
fn mru_free(p: *const Pool) -> u32 {
    var best = NONE
    var i = 0usize
    while i < p.max_size {
        if p.state[i] == FREE && (best == NONE || p.last_used[i] > p.last_used[usize(best)]) { best = u32(i) }
        i += 1usize
    }
    ret best
}

// Waiter `w` asks for a connection: `Acquired` with the slot index; `NeedsCreate`
// with a reserved slot the caller must `attach`; `Queued` (index NONE) when the pool
// is full, and again while `w` stays queued; `Timeout` once `w` has waited
// `connection_timeout` (it is dequeued). `Full` when the waiter ring is full.
fn acquire(p: *Pool, w: u32, now: u64) -> (u32, Outcome, err) {
    let idle = mru_free(p)
    if idle != NONE {
        unqueue(p, w)
        p.state[usize(idle)] = IN_USE
        p.uses[usize(idle)] += 1u32
        p.last_used[usize(idle)] = now
        ret (idle, .Acquired, ok)
    }
    var i = 0usize
    while i < p.max_size {
        if p.state[i] == CLOSED {
            unqueue(p, w)
            p.state[i] = PENDING
            p.created_at[i] = now
            p.last_used[i] = now
            ret (u32(i), .NeedsCreate, ok)
        }
        i += 1usize
    }
    i = 0usize
    while i < p.wait_len {
        let at_ = (p.wait_head + i) % p.waiters.len
        if p.waiters[at_] == w {
            if now - p.waiter_since[at_] >= p.connection_timeout {
                unqueue(p, w)
                ret (NONE, .Timeout, ok)
            }
            ret (NONE, .Queued, ok)
        }
        i += 1usize
    }
    if p.wait_len >= p.waiters.len { ret (NONE, .Queued, Full) }
    let tail = (p.wait_head + p.wait_len) % p.waiters.len
    p.waiters[tail] = w
    p.waiter_since[tail] = now
    p.wait_len += 1usize
    ret (NONE, .Queued, ok)
}

// Reserve a slot for a connection created outside `acquire` (see `warm`).
fn reserve(p: *Pool, now: u64) -> (u32, err) {
    var i = 0usize
    while i < p.max_size {
        if p.state[i] == CLOSED {
            p.state[i] = PENDING
            p.created_at[i] = now
            p.last_used[i] = now
            ret (u32(i), ok)
        }
        i += 1usize
    }
    ret (NONE, Full)
}

// Hand in the connection created for a `NeedsCreate`/`reserve` slot; it becomes idle.
fn attach(p: *Pool, index: u32, handle: u64, now: u64) -> err {
    if usize(index) >= p.max_size || p.state[usize(index)] != PENDING { ret Invalid }
    let i = usize(index)
    p.handle[i] = handle
    p.state[i] = FREE
    p.created_at[i] = now
    p.last_used[i] = now
    p.uses[i] = 0u32
    ret ok
}

// Give a connection back. A `broken` one, or one past `max_lifetime`, is closed
// (the next `acquire` says `NeedsCreate`). Otherwise the head waiter, if any, gets
// it directly and is answered; else NONE and the slot is idle.
fn release(p: *Pool, index: u32, now: u64, broken: bool) -> (u32, err) {
    if usize(index) >= p.max_size || p.state[usize(index)] != IN_USE { ret (NONE, Invalid) }
    let i = usize(index)
    p.last_used[i] = now
    if broken || (p.max_lifetime > 0u64 && now - p.created_at[i] >= p.max_lifetime) {
        close_slot(p, i)
        ret (NONE, ok)
    }
    if p.wait_len > 0usize {
        let w = p.waiters[p.wait_head]
        p.wait_head = (p.wait_head + 1usize) % p.waiters.len
        p.wait_len -= 1usize
        p.uses[i] += 1u32
        ret (w, ok)
    }
    p.state[i] = FREE
    ret (NONE, ok)
}

// The housekeeper: close idle connections past `max_lifetime`, then idle ones past
// `idle_timeout` (least recently used first) down to `min_idle`. Closed indexes go
// to `out_closed`; at most `out_closed.len` are evicted. Answers the count.
fn evict_expired(p: *Pool, now: u64, out_closed: []u32) -> usize {
    var n = 0usize
    var i = 0usize
    while i < p.max_size && n < out_closed.len {
        if p.state[i] == FREE && p.max_lifetime > 0u64 && now - p.created_at[i] >= p.max_lifetime {
            close_slot(p, i)
            out_closed[n] = u32(i)
            n += 1usize
        }
        i += 1usize
    }
    if p.idle_timeout == 0u64 { ret n }
    while n < out_closed.len && count(p, FREE) > p.min_idle {
        var oldest = NONE
        i = 0usize
        while i < p.max_size {
            if p.state[i] == FREE && now - p.last_used[i] >= p.idle_timeout && (oldest == NONE || p.last_used[i] < p.last_used[usize(oldest)]) { oldest = u32(i) }
            i += 1usize
        }
        if oldest == NONE { ret n }
        close_slot(p, usize(oldest))
        out_closed[n] = oldest
        n += 1usize
    }
    ret n
}

// Whether an attached connection has gone `validation_interval` since its last use
// and should be checked alive before handing out.
fn validate_due(p: *const Pool, index: u32, now: u64) -> bool {
    if usize(index) >= p.max_size || p.validation_interval == 0u64 { ret false }
    let s = p.state[usize(index)]
    if s == CLOSED || s == PENDING { ret false }
    ret now - p.last_used[usize(index)] >= p.validation_interval
}

// Dequeue every waiter past `connection_timeout` into `out_waiters`; answers the count.
fn timeouts(p: *Pool, now: u64, out_waiters: []u32) -> usize {
    var n = 0usize
    var kept = 0usize
    var i = 0usize
    while i < p.wait_len {
        let from = (p.wait_head + i) % p.waiters.len
        if now - p.waiter_since[from] >= p.connection_timeout && n < out_waiters.len {
            out_waiters[n] = p.waiters[from]
            n += 1usize
        } else {
            let to = (p.wait_head + kept) % p.waiters.len
            p.waiters[to] = p.waiters[from]
            p.waiter_since[to] = p.waiter_since[from]
            kept += 1usize
        }
        i += 1usize
    }
    p.wait_len = kept
    ret n
}

// (total attached or pending, idle, in use, waiting).
fn stats(p: *const Pool) -> (usize, usize, usize, usize) {
    let idle = count(p, FREE)
    let busy = count(p, IN_USE)
    ret (p.max_size - count(p, CLOSED), idle, busy, p.wait_len)
}

// How many connections to create (via `reserve` + `attach`) to reach `min_idle`.
fn warm(p: *const Pool) -> usize {
    let idle = count(p, FREE)
    let room = count(p, CLOSED)
    if idle >= p.min_idle { ret 0usize }
    let need = p.min_idle - idle
    if need < room { ret need }
    ret room
}

// Close every slot and drop every waiter; answers how many slots were open.
fn close_all(p: *Pool) -> usize {
    let open = p.max_size - count(p, CLOSED)
    var i = 0usize
    while i < p.max_size {
        close_slot(p, i)
        i += 1usize
    }
    p.wait_len = 0usize
    ret open
}
