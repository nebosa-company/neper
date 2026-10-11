// A generic object pool with idle eviction, after commons-pool2, as a state machine
// over caller storage (or an arena through `pool_in`): no threads, no clock and no
// factory. The caller creates and destroys the objects; the pool decides who may use
// which slot and when an idle one has outlived its welcome. Time is whatever `now`
// the caller passes, so eviction timing is exact and testable.
//
// A slot is `Empty`, `Pending` (reserved for a creation the caller owes: `acquire`
// answered `NeedsCreate`), `Idle` (in the pool) or `Borrowed`. `acquire` takes an idle
// object (the newest if `lifo`, else the oldest), else reserves an empty slot while
// fewer than `max_total` are live, else (with `wait`) queues the requester FIFO, else
// answers `Exhausted`. `release` returns an object: handed straight to the head
// waiter when one is queued (its `who` is in the answer), kept idle up to `max_idle`,
// or destroyed (`destroy`: the object is still readable in the slot until the slot is
// next reserved). A `healthy == false` return always destroys. `evict` retires idle
// objects idle for `idle_ticks` or more, oldest first, never below `min_idle`.
// `leaks` lists objects borrowed for `leak_ticks` or more; `reclaim` takes one back.
// A zero tick limit disables that rule.

use e.mem

type Config = struct { max_total: usize, max_idle: usize, min_idle: usize, idle_ticks: u64, leak_ticks: u64, lifo: bool, wait: bool }
type Pool[T: type] = struct { items: []T, state: []u8, since: []u64, uses: []u32, waiters: []u32, waiter_at: []u64, wait_head: usize, wait_len: usize, cfg: Config, created: u64, destroyed: u64, evicted: u64, leaked: u64 }
type Outcome = enum u8 { Reused, NeedsCreate, Queued, Exhausted }
type Grant = struct { outcome: Outcome, slot: u32 }
// `destroy`: dispose of the object in `slot` (readable until the slot is reserved
// again). `handoff`: waiter `who` now owns `slot`; `needs_create` says it must first
// create the object (the old one was unhealthy).
type Release = struct { destroy: bool, handoff: bool, who: u32, slot: u32, needs_create: bool }
error Invalid
error TooSmall

const EMPTY: u8 = 0u8
const PENDING: u8 = 1u8
const IDLE: u8 = 2u8
const BORROWED: u8 = 3u8
const NONE: u32 = 0xffffffffu32

// A pool over caller arrays: `items`, `state`, `since` and `uses` at least
// `cfg.max_total` long, `waiters` and `waiter_at` (same length, at least one) for the
// queue.
fn pool[T: type](items: []T, state: []u8, since: []u64, uses: []u32, waiters: []u32, waiter_at: []u64, cfg: Config) -> (Pool[T], err) {
    var p = Pool[T] { items: items, state: state, since: since, uses: uses, waiters: waiters, waiter_at: waiter_at, wait_head: 0usize, wait_len: 0usize, cfg: cfg, created: 0u64, destroyed: 0u64, evicted: 0u64, leaked: 0u64 }
    if cfg.max_total == 0usize { ret (p, Invalid) }
    if items.len < cfg.max_total || state.len < cfg.max_total || since.len < cfg.max_total || uses.len < cfg.max_total { ret (p, TooSmall) }
    if waiters.len == 0usize || waiter_at.len < waiters.len { ret (p, TooSmall) }
    var i = 0usize
    while i < cfg.max_total {
        state[i] = EMPTY
        i += 1usize
    }
    ret (p, ok)
}

// The same, with every array allocated from `a`; `queue` is the waiter capacity.
fn pool_in[T: type](a: *mem.Arena, cfg: Config, queue: usize) -> (Pool[T], err) {
    var empty: Pool[T] = zero
    let (items, items_error) = mem.alloc[T](a, cfg.max_total)
    if items_error != ok { ret (empty, items_error) }
    let (state, state_error) = mem.alloc[u8](a, cfg.max_total)
    if state_error != ok { ret (empty, state_error) }
    let (since, since_error) = mem.alloc[u64](a, cfg.max_total)
    if since_error != ok { ret (empty, since_error) }
    let (uses, uses_error) = mem.alloc[u32](a, cfg.max_total)
    if uses_error != ok { ret (empty, uses_error) }
    let (waiters, waiters_error) = mem.alloc[u32](a, queue)
    if waiters_error != ok { ret (empty, waiters_error) }
    let (waiter_at, waiter_at_error) = mem.alloc[u64](a, queue)
    if waiter_at_error != ok { ret (empty, waiter_at_error) }
    let (made, made_error) = pool[T](items, state, since, uses, waiters, waiter_at, cfg)
    ret (made, made_error)
}

// How many slots are in state `s`.
fn count[T: type](p: *const Pool[T], s: u8) -> usize {
    var n = 0usize
    var i = 0usize
    while i < p.cfg.max_total {
        if p.state[i] == s { n += 1usize }
        i += 1usize
    }
    ret n
}

// The object in a borrowed (or idle) slot.
fn object[T: type](p: *Pool[T], slot: u32) -> *T {
    ret &p.items[usize(slot)]
}

// The idle slot to hand out: newest if `lifo`, else oldest; ties go to the lowest index.
fn pick_idle[T: type](p: *const Pool[T], newest: bool) -> u32 {
    var best = NONE
    var i = 0usize
    while i < p.cfg.max_total {
        if p.state[i] == IDLE {
            if best == NONE { best = u32(i) } else {
                if newest && p.since[i] > p.since[usize(best)] { best = u32(i) }
                if !newest && p.since[i] < p.since[usize(best)] { best = u32(i) }
            }
        }
        i += 1usize
    }
    ret best
}

fn acquire[T: type](p: *Pool[T], now: u64, who: u32) -> Grant {
    let idle = pick_idle[T](p, p.cfg.lifo)
    if idle != NONE {
        p.state[usize(idle)] = BORROWED
        p.since[usize(idle)] = now
        p.uses[usize(idle)] += 1u32
        ret Grant { outcome: .Reused, slot: idle }
    }
    var i = 0usize
    while i < p.cfg.max_total {
        if p.state[i] == EMPTY {
            p.state[i] = PENDING
            p.since[i] = now
            ret Grant { outcome: .NeedsCreate, slot: u32(i) }
        }
        i += 1usize
    }
    if p.cfg.wait && p.wait_len < p.waiters.len {
        let at = (p.wait_head + p.wait_len) % p.waiters.len
        p.waiters[at] = who
        p.waiter_at[at] = now
        p.wait_len += 1usize
        ret Grant { outcome: .Queued, slot: NONE }
    }
    ret Grant { outcome: .Exhausted, slot: NONE }
}

// The caller made the object for a `NeedsCreate` slot.
fn attach[T: type](p: *Pool[T], slot: u32, obj: T, now: u64) -> err {
    if usize(slot) >= p.cfg.max_total || p.state[usize(slot)] != PENDING { ret Invalid }
    p.items[usize(slot)] = obj
    p.state[usize(slot)] = BORROWED
    p.since[usize(slot)] = now
    p.uses[usize(slot)] = 1u32
    p.created += 1u64
    ret ok
}

// Give a slot's turn to the head waiter when there is one.
fn hand_to_waiter[T: type](p: *Pool[T], slot: u32, now: u64, needs_create: bool) -> Release {
    let who = p.waiters[p.wait_head]
    p.wait_head = (p.wait_head + 1usize) % p.waiters.len
    p.wait_len -= 1usize
    if needs_create {
        p.state[usize(slot)] = PENDING
        p.since[usize(slot)] = now
    } else {
        p.state[usize(slot)] = BORROWED
        p.since[usize(slot)] = now
        p.uses[usize(slot)] += 1u32
    }
    ret Release { destroy: needs_create, handoff: true, who: who, slot: slot, needs_create: needs_create }
}

// Return a borrowed object. `healthy == false` destroys it.
fn release[T: type](p: *Pool[T], slot: u32, now: u64, healthy: bool) -> (Release, err) {
    var r = Release { destroy: false, handoff: false, who: 0u32, slot: slot, needs_create: false }
    if usize(slot) >= p.cfg.max_total || p.state[usize(slot)] != BORROWED { ret (r, Invalid) }
    if p.wait_len > 0usize {
        if !healthy { p.destroyed += 1u64 }
        r = hand_to_waiter[T](p, slot, now, !healthy)
        ret (r, ok)
    }
    if healthy && count[T](p, IDLE) < p.cfg.max_idle {
        p.state[usize(slot)] = IDLE
        p.since[usize(slot)] = now
        ret (r, ok)
    }
    p.state[usize(slot)] = EMPTY
    p.destroyed += 1u64
    r.destroy = true
    ret (r, ok)
}

// A creation that failed: free the reserved slot (a waiter, if any, is handed the
// chance to create instead).
fn abort_create[T: type](p: *Pool[T], slot: u32, now: u64) -> (Release, err) {
    var r = Release { destroy: false, handoff: false, who: 0u32, slot: slot, needs_create: false }
    if usize(slot) >= p.cfg.max_total || p.state[usize(slot)] != PENDING { ret (r, Invalid) }
    if p.wait_len > 0usize {
        let who = p.waiters[p.wait_head]
        p.wait_head = (p.wait_head + 1usize) % p.waiters.len
        p.wait_len -= 1usize
        p.since[usize(slot)] = now
        r = Release { destroy: false, handoff: true, who: who, slot: slot, needs_create: true }
        ret (r, ok)
    }
    p.state[usize(slot)] = EMPTY
    ret (r, ok)
}

// Retire idle objects idle for `idle_ticks` or more, oldest first, keeping `min_idle`;
// the slots go into `out` (at most `out.len`) and are `Empty`, their objects still
// readable for the caller to destroy. Answers how many.
fn evict[T: type](p: *Pool[T], now: u64, out: []u32) -> usize {
    var n = 0usize
    if p.cfg.idle_ticks == 0u64 { ret 0usize }
    while n < out.len && count[T](p, IDLE) > p.cfg.min_idle {
        let oldest = pick_idle[T](p, false)
        if oldest == NONE { break }
        if now - p.since[usize(oldest)] < p.cfg.idle_ticks { break }
        p.state[usize(oldest)] = EMPTY
        p.evicted += 1u64
        p.destroyed += 1u64
        out[n] = oldest
        n += 1usize
    }
    ret n
}

// Borrowed objects held for `leak_ticks` or more, by slot, into `out`; answers how many.
fn leaks[T: type](p: *const Pool[T], now: u64, out: []u32) -> usize {
    var n = 0usize
    if p.cfg.leak_ticks == 0u64 { ret 0usize }
    var i = 0usize
    while i < p.cfg.max_total && n < out.len {
        if p.state[i] == BORROWED && now - p.since[i] >= p.cfg.leak_ticks {
            out[n] = u32(i)
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

// Take a leaked object back as if it had been returned unhealthy.
fn reclaim[T: type](p: *Pool[T], slot: u32, now: u64) -> (Release, err) {
    p.leaked += 1u64
    let (r, release_error) = release[T](p, slot, now, false)
    ret (r, release_error)
}

// Drop queued waiters that have waited `max_wait` or more, oldest first, into `out`;
// answers how many.
fn expire_waiters[T: type](p: *Pool[T], now: u64, max_wait: u64, out: []u32) -> usize {
    var dropped = 0usize
    var kept = 0usize
    var i = 0usize
    while i < p.wait_len {
        let from = (p.wait_head + i) % p.waiters.len
        if now - p.waiter_at[from] >= max_wait && dropped < out.len {
            out[dropped] = p.waiters[from]
            dropped += 1usize
        } else {
            let to = (p.wait_head + kept) % p.waiters.len
            p.waiters[to] = p.waiters[from]
            p.waiter_at[to] = p.waiter_at[from]
            kept += 1usize
        }
        i += 1usize
    }
    p.wait_len = kept
    ret dropped
}
