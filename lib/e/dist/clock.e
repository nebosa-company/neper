// Logical clocks for ordering events across nodes without a shared wall
// clock: `Lamport` scalar clocks (`lamport_tick`, `lamport_send` stamps a
// message, `lamport_receive` folds a stamp in), vector clocks over a caller
// `[]u64` with one entry per node (`vector_tick`, `vector_merge`,
// `vector_receive`, and `vector_cmp` answering Before/After/Equal/Concurrent),
// and hybrid logical clocks (`Hlc`: the largest physical time seen plus a
// logical counter that breaks ties, `hlc_now` for a local event, `hlc_receive`
// for a remote stamp, `hlc_cmp` for the total order). Nothing here talks to a
// network: a "message" is whatever the caller carries the stamp in.

type Lamport = struct { time: u64 }
type Hlc = struct { physical: u64, logical: u64 }
type Order = enum u8 { Before, After, Equal, Concurrent }

fn lamport() -> Lamport { ret Lamport { time: 0u64 } }

// A local event; answers the new time.
fn lamport_tick(c: *Lamport) -> u64 {
    c.time += 1u64
    ret c.time
}

// The stamp to carry on an outgoing message.
fn lamport_send(c: *Lamport) -> u64 { ret lamport_tick(c) }

// Fold a received `stamp` in: max of both, then one tick.
fn lamport_receive(c: *Lamport, stamp: u64) -> u64 {
    if stamp > c.time { c.time = stamp }
    c.time += 1u64
    ret c.time
}

// A local event at `node`; answers its new entry.
fn vector_tick(v: []u64, node: usize) -> u64 {
    v[node] += 1u64
    ret v[node]
}

// `dst` becomes the entrywise max of itself and `src` (over the shorter length).
fn vector_merge(dst: []u64, src: []const u64) {
    var n = dst.len
    if src.len < n { n = src.len }
    var i = 0usize
    while i < n {
        if src[i] > dst[i] { dst[i] = src[i] }
        i += 1usize
    }
}

// A message stamped `src` arrives at `node`: merge, then tick.
fn vector_receive(v: []u64, src: []const u64, node: usize) -> u64 {
    vector_merge(v, src)
    ret vector_tick(v, node)
}

// Before: a <= b entrywise and a != b; After: the reverse; Equal; else Concurrent.
fn vector_cmp(a: []const u64, b: []const u64) -> Order {
    var less = false
    var greater = false
    var n = a.len
    if b.len < n { n = b.len }
    var i = 0usize
    while i < n {
        if a[i] < b[i] { less = true }
        if a[i] > b[i] { greater = true }
        i += 1usize
    }
    // A missing entry is zero.
    while i < a.len {
        if a[i] > 0u64 { greater = true }
        i += 1usize
    }
    while i < b.len {
        if b[i] > 0u64 { less = true }
        i += 1usize
    }
    if less && greater { ret .Concurrent }
    if less { ret .Before }
    if greater { ret .After }
    ret .Equal
}

fn hlc() -> Hlc { ret Hlc { physical: 0u64, logical: 0u64 } }

// A local or send event at wall time `physical`; answers the stamp.
fn hlc_now(c: *Hlc, physical: u64) -> Hlc {
    if physical > c.physical {
        c.physical = physical
        c.logical = 0u64
    } else {
        c.logical += 1u64
    }
    ret Hlc { physical: c.physical, logical: c.logical }
}

// A message stamped `remote` arrives at wall time `physical`; answers the stamp.
fn hlc_receive(c: *Hlc, physical: u64, remote: Hlc) -> Hlc {
    let old = c.physical
    var top = old
    if remote.physical > top { top = remote.physical }
    if physical > top { top = physical }
    if top == old && top == remote.physical {
        var l = c.logical
        if remote.logical > l { l = remote.logical }
        c.logical = l + 1u64
    } else if top == old {
        c.logical += 1u64
    } else if top == remote.physical {
        c.logical = remote.logical + 1u64
    } else {
        c.logical = 0u64
    }
    c.physical = top
    ret Hlc { physical: c.physical, logical: c.logical }
}

// -1, 0 or 1: physical first, logical breaks ties.
fn hlc_cmp(a: Hlc, b: Hlc) -> i32 {
    if a.physical < b.physical { ret 0i32 - 1i32 }
    if a.physical > b.physical { ret 1i32 }
    if a.logical < b.logical { ret 0i32 - 1i32 }
    if a.logical > b.logical { ret 1i32 }
    ret 0i32
}

// A vector clock of `n` entries (at most `storage.len`) over `storage`, all
// zero; the planned entry point for the `vector_*` family.
fn vector(storage: []u64, n: usize) -> []u64 {
    var m = n
    if m > storage.len { m = storage.len }
    var i = 0usize
    while i < m {
        storage[i] = 0u64
        i += 1usize
    }
    ret storage[..m]
}
