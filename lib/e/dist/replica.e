// Replicated storage as an in-process simulation over caller storage: a
// `Store` of `Replica` records (each a value, a vector clock from
// `e.dist.clock` and an up flag), `quorum` (is r + w > n), `quorum_write`
// reaching w replicas from the coordinator onwards (a down one in the way
// gets a hint), `quorum_read` from the first r reachable replicas picking the
// dominating version, `read_repair` bringing the stale ones among them up
// to it, and `hinted_handoff` with `handoff_replay` delivering queued
// writes to a replica that came back, in order.

use e.dist.clock

type Replica = struct { clock: []u64, value: i64, up: bool }
type Store = struct { replicas: []Replica, r: usize, w: usize }
// Hints queued by target; `clocks` is `target.len` rows of `width`.
type Handoff = struct { target: []u32, value: []i64, clocks: []u64, width: usize, len: usize }

error Invalid
error NoQuorum
error TooSmall

// Reads and writes overlap on at least one replica when r + w > n.
fn quorum(n: usize, r: usize, w: usize) -> (bool, err) {
    if n == 0usize || r == 0usize || w == 0usize || r > n || w > n { ret (false, Invalid) }
    ret (r + w > n, ok)
}

fn replica(stamp: []u64) -> Replica { ret Replica { clock: stamp, value: 0i64, up: true } }

fn store(replicas: []Replica, r: usize, w: usize) -> Store { ret Store { replicas: replicas, r: r, w: w } }

fn hinted_handoff(targets: []u32, values: []i64, clocks: []u64, width: usize) -> Handoff {
    ret Handoff { target: targets, value: values, clocks: clocks, width: width, len: 0usize }
}

fn handoff_store(h: *Handoff, to: u32, value: i64, stamp: []const u64) -> err {
    if h.len >= h.target.len || h.len >= h.value.len || (h.len + 1usize) * h.width > h.clocks.len { ret TooSmall }
    h.target[h.len] = to
    h.value[h.len] = value
    var i = 0usize
    while i < h.width {
        h.clocks[h.len * h.width + i] = stamp[i]
        i += 1usize
    }
    h.len += 1usize
    ret ok
}

fn copy_clock(dst: []u64, src: []const u64) {
    var i = 0usize
    while i < dst.len && i < src.len {
        dst[i] = src[i]
        i += 1usize
    }
}

// Write `value` coordinated by replica `coordinator` (which must be up):
// the version is the merge of every reachable clock ticked at the
// coordinator; the first w up replicas from the coordinator onwards take
// it at once, a down replica in the way gets a hint, and any further up
// replica is left behind (slow) until read repair. Answers the acks;
// fewer than w is NoQuorum (the replicas written keep the write).
fn quorum_write(s: *Store, coordinator: usize, value: i64, h: *Handoff) -> (usize, err) {
    let n = s.replicas.len
    let c = &s.replicas[coordinator]
    if !c.up { ret (0usize, Invalid) }
    var i = 0usize
    while i < n {
        if s.replicas[i].up && i != coordinator { clock.vector_merge(c.clock, s.replicas[i].clock) }
        i += 1usize
    }
    let _ = clock.vector_tick(c.clock, coordinator)
    var acks = 0usize
    var k = 0usize
    while k < n {
        i = (coordinator + k) % n
        if !s.replicas[i].up {
            let hint_error = handoff_store(h, u32(i), value, c.clock)
            if hint_error != ok { ret (acks, hint_error) }
        } else if acks < s.w {
            s.replicas[i].value = value
            if i != coordinator { copy_clock(s.replicas[i].clock, c.clock) }
            acks += 1usize
        }
        k += 1usize
    }
    if acks < s.w { ret (acks, NoQuorum) }
    ret (acks, ok)
}

// The first r reachable replicas and the one among them holding the
// dominating version; `conflict` when two of them are concurrent.
fn read_set(s: *const Store, chosen: []usize) -> (usize, bool, err) {
    var count = 0usize
    var i = 0usize
    while i < s.replicas.len && count < s.r {
        if s.replicas[i].up {
            chosen[count] = i
            count += 1usize
        }
        i += 1usize
    }
    if count < s.r { ret (0usize, false, NoQuorum) }
    var best = chosen[0usize]
    var conflict = false
    var k = 1usize
    while k < count {
        let order = clock.vector_cmp(s.replicas[chosen[k]].clock, s.replicas[best].clock)
        if order == .After { best = chosen[k] }
        if order == .Concurrent { conflict = true }
        k += 1usize
    }
    ret (best, conflict, ok)
}

// Answers the replica holding the latest of the r versions read (its value
// is `s.replicas[latest].value`) and whether a concurrent sibling exists.
fn quorum_read(s: *const Store) -> (usize, bool, err) {
    var chosen: [64]usize = zero
    if s.r > 64usize { ret (0usize, false, Invalid) }
    let (best, conflict, e) = read_set(s, chosen[..])
    ret (best, conflict, e)
}

// After a quorum read, the read replicas whose version is behind the
// latest take it; `stale` receives their indices, answers how many.
fn read_repair(s: *Store, stale: []usize) -> (usize, err) {
    var chosen: [64]usize = zero
    if s.r > 64usize { ret (0usize, Invalid) }
    let (best, _, e) = read_set(s, chosen[..])
    if e != ok { ret (0usize, e) }
    var count = 0usize
    var k = 0usize
    while k < s.r {
        let i = chosen[k]
        if clock.vector_cmp(s.replicas[i].clock, s.replicas[best].clock) == .Before {
            if count >= stale.len { ret (count, TooSmall) }
            stale[count] = i
            count += 1usize
            s.replicas[i].value = s.replicas[best].value
            copy_clock(s.replicas[i].clock, s.replicas[best].clock)
        }
        k += 1usize
    }
    ret (count, ok)
}

// Replica `to` is back: its hints apply in order (one already dominated by
// the replica's version is skipped) and leave the queue. Answers how many
// applied.
fn handoff_replay(h: *Handoff, s: *Store, to: u32) -> usize {
    let rep = &s.replicas[usize(to)]
    rep.up = true
    var applied = 0usize
    var kept = 0usize
    var i = 0usize
    while i < h.len {
        let row = h.clocks[i * h.width..(i + 1usize) * h.width]
        if h.target[i] == to {
            let order = clock.vector_cmp(row, rep.clock)
            if order == .After || order == .Concurrent {
                rep.value = h.value[i]
                clock.vector_merge(rep.clock, row)
                applied += 1usize
            }
        } else {
            h.target[kept] = h.target[i]
            h.value[kept] = h.value[i]
            copy_clock(h.clocks[kept * h.width..(kept + 1usize) * h.width], row)
            kept += 1usize
        }
        i += 1usize
    }
    h.len = kept
    ret applied
}
