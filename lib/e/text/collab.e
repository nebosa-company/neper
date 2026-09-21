// Collaborative text over caller storage. `transform` is operational
// transformation of one `Op` (an insert of a string or a delete of a range)
// against a concurrent one so that `apply(apply(t, a), transform(b, a,
// !a_wins)) == apply(apply(t, b), transform(a, b, a_wins))`: inserts at the
// same position are ordered by `a_wins`, an insert inside a concurrent
// deletion is lost (the deletion grows over it: one `Op` cannot split), and
// overlapping deletions remove the union. The CRDT is RGA: a `Doc` is a
// linked list of bytes with `Id`s of `(site, counter)` where `counter` is
// the site's Lamport clock, deleted bytes stay as tombstones, and
// `crdt_insert(doc, after, id, byte)` places the byte after `after` behind
// every concurrent successor with a greater id, so two replicas that apply
// the same ops in any causal order read the same `crdt_text`. Slot 0 is the
// head with id `(0, 0)`. `order_key_between` is fractional indexing over
// base-62 digit strings: the shortest key strictly between two neighbours,
// an empty neighbour standing for the open end; a key never ends in `0`.

use e.mem
use e.str

type Kind = enum u8 { Insert, Delete }
type Op = struct { kind: Kind, pos: usize, len: usize, text: str }
type Id = struct { site: u32, counter: u32 }
type CrdtOp = struct { insert: bool, after: Id, id: Id, byte: u8 }
type Doc = struct { site: []u32, counter: []u32, byte: []u8, dead: []u8, link: []u32, used: usize }
error TooSmall
error Invalid

fn digits() -> str { ret "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz" }

fn insert(pos: usize, text: str) -> Op { ret Op { kind: .Insert, pos: pos, len: text.len, text: text } }
fn delete(pos: usize, len: usize) -> Op { ret Op { kind: .Delete, pos: pos, len: len, text: "" } }

fn shift(x: usize, lo: usize, hi: usize) -> usize {
    if x <= lo { ret x }
    if x >= hi { ret x - (hi - lo) }
    ret lo
}

// `a` transformed against the concurrent `b`; `a_wins` breaks the tie of two
// inserts at one position (the winner stays first).
fn transform(a: Op, b: Op, a_wins: bool) -> Op {
    var r = a
    if b.kind == .Insert {
        if a.kind == .Insert {
            if a.pos > b.pos || (a.pos == b.pos && !a_wins) { r.pos = a.pos + b.len }
        } else if b.pos <= a.pos {
            r.pos = a.pos + b.len
        } else if b.pos < a.pos + a.len {
            r.len = a.len + b.len
        }
        ret r
    }
    let b_end = b.pos + b.len
    if a.kind == .Insert {
        if a.pos >= b_end {
            r.pos = a.pos - b.len
        } else if a.pos > b.pos {
            r.pos = b.pos
            r.len = 0usize
            r.text = ""
        }
        ret r
    }
    let lo = shift(a.pos, b.pos, b_end)
    let hi = shift(a.pos + a.len, b.pos, b_end)
    r.pos = lo
    r.len = hi - lo
    ret r
}

// `text` with `op` applied into `out` (distinct from `text`); answers the length.
fn apply(text: []const u8, op: Op, out: []u8) -> (usize, err) {
    if op.kind == .Insert {
        if op.pos > text.len { ret (0usize, Invalid) }
        let n = text.len + op.text.len
        if out.len < n { ret (0usize, TooSmall) }
        mem.copy[u8](out[..op.pos], text[..op.pos])
        var i = 0usize
        while i < op.text.len {
            out[op.pos + i] = op.text[i]
            i += 1usize
        }
        mem.copy[u8](out[op.pos + op.text.len..n], text[op.pos..])
        ret (n, ok)
    }
    if op.pos + op.len > text.len { ret (0usize, Invalid) }
    let n = text.len - op.len
    if out.len < n { ret (0usize, TooSmall) }
    mem.copy[u8](out[..op.pos], text[..op.pos])
    mem.copy[u8](out[op.pos..n], text[op.pos + op.len..])
    ret (n, ok)
}

// An empty document over parallel arrays; slot 0 is the head.
fn doc(site: []u32, counter: []u32, byte: []u8, dead: []u8, link: []u32) -> Doc {
    if site.len > 0usize { site[0usize] = 0u32 }
    if counter.len > 0usize { counter[0usize] = 0u32 }
    if dead.len > 0usize { dead[0usize] = 1u8 }
    if link.len > 0usize { link[0usize] = 0u32 }
    ret Doc { site: site, counter: counter, byte: byte, dead: dead, link: link, used: 1usize }
}

fn id_less(a: Id, b: Id) -> bool {
    if a.counter != b.counter { ret a.counter < b.counter }
    ret a.site < b.site
}

// The slot holding `id`, or `d.used` when absent.
// ponytail: a linear scan; a hash map over ids when documents outgrow a page.
fn crdt_find(d: *const Doc, id: Id) -> usize {
    var i = 0usize
    while i < d.used {
        if d.site[i] == id.site && d.counter[i] == id.counter { ret i }
        i += 1usize
    }
    ret d.used
}

// Place `byte` with `id` after the element `after` (the head is `(0, 0)`).
// A local insert takes the site's next clock tick as `counter`; a remote one
// carries the id it was made with.
fn crdt_insert(d: *Doc, after: Id, id: Id, byte: u8) -> err {
    if d.used >= d.site.len || d.used >= d.counter.len || d.used >= d.byte.len || d.used >= d.dead.len || d.used >= d.link.len { ret TooSmall }
    let p = crdt_find(d, after)
    if p == d.used || crdt_find(d, id) != d.used { ret Invalid }
    var prev = p
    var scanning = true
    while scanning && d.link[prev] != 0u32 {
        let n = usize(d.link[prev])
        if id_less(id, Id { site: d.site[n], counter: d.counter[n] }) { prev = n } else { scanning = false }
    }
    let slot = d.used
    d.used += 1usize
    d.site[slot] = id.site
    d.counter[slot] = id.counter
    d.byte[slot] = byte
    d.dead[slot] = 0u8
    d.link[slot] = d.link[prev]
    d.link[prev] = u32(slot)
    ret ok
}

// Tombstone the element `id` (deleting twice is fine).
fn crdt_delete(d: *Doc, id: Id) -> err {
    let p = crdt_find(d, id)
    if p == d.used || p == 0usize { ret Invalid }
    d.dead[p] = 1u8
    ret ok
}

// Apply a remote op.
fn crdt_apply(d: *Doc, op: CrdtOp) -> err {
    if op.insert { ret crdt_insert(d, op.after, op.id, op.byte) }
    ret crdt_delete(d, op.id)
}

// The visible bytes in order; answers the length.
fn crdt_text(d: *const Doc, out: []u8) -> (usize, err) {
    var n = 0usize
    var i = usize(d.link[0usize])
    while i != 0usize {
        if d.dead[i] == 0u8 {
            if n >= out.len { ret (n, TooSmall) }
            out[n] = d.byte[i]
            n += 1usize
        }
        i = usize(d.link[i])
    }
    ret (n, ok)
}

fn crdt_len(d: *const Doc) -> usize {
    var n = 0usize
    var i = usize(d.link[0usize])
    while i != 0usize {
        if d.dead[i] == 0u8 { n += 1usize }
        i = usize(d.link[i])
    }
    ret n
}

// The id of the `index`-th visible byte (`index == len` is the head, so an
// insert at visible position `k` goes after `crdt_id_at(d, k - 1)` and one at
// 0 after the head).
fn crdt_id_at(d: *const Doc, index: usize) -> (Id, err) {
    var n = 0usize
    var i = usize(d.link[0usize])
    while i != 0usize {
        if d.dead[i] == 0u8 {
            if n == index { ret (Id { site: d.site[i], counter: d.counter[i] }, ok) }
            n += 1usize
        }
        i = usize(d.link[i])
    }
    ret (Id { site: 0u32, counter: 0u32 }, Invalid)
}

fn digit_value(b: u8) -> (usize, bool) {
    var i = 0usize
    while i < 62usize {
        if digits()[i] == b { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn valid_key(k: str) -> bool {
    var i = 0usize
    while i < k.len {
        let (_, known) = digit_value(k[i])
        if !known { ret false }
        i += 1usize
    }
    ret k.len == 0usize || k[k.len - 1usize] != digits()[0usize]
}

fn tail(k: str, from: usize) -> str {
    if from >= k.len { ret "" }
    ret k[from..]
}

// The midpoint of `a` (empty: the low end) and `b` (empty: the high end).
fn between(a: str, b: str, out: []u8) -> (usize, err) {
    if out.len == 0usize { ret (0usize, TooSmall) }
    if b.len > 0usize {
        var n = 0usize
        var same = true
        while same && n < b.len {
            var da = digits()[0usize]
            if n < a.len { da = a[n] }
            if da == b[n] { n += 1usize } else { same = false }
        }
        if n > 0usize {
            if out.len < n + 1usize { ret (0usize, TooSmall) }
            var i = 0usize
            while i < n {
                out[i] = b[i]
                i += 1usize
            }
            let (m, e) = between(tail(a, n), tail(b, n), out[n..])
            ret (n + m, e)
        }
    }
    var da = 0usize
    if a.len > 0usize {
        let (v, _) = digit_value(a[0usize])
        da = v
    }
    var db = 62usize
    if b.len > 0usize {
        let (v, _) = digit_value(b[0usize])
        db = v
    }
    if db - da > 1usize {
        out[0usize] = digits()[(da + db) / 2usize]
        ret (1usize, ok)
    }
    if b.len > 1usize {
        out[0usize] = b[0usize]
        ret (1usize, ok)
    }
    out[0usize] = digits()[da]
    let (m, e) = between(tail(a, 1usize), "", out[1usize..])
    ret (1usize + m, e)
}

// A key strictly between `a` and `b` (empty means unbounded on that side)
// into `out`; answers its length. `a >= b`, a non-digit or a trailing `0`
// is `Invalid`.
fn order_key_between(a: str, b: str, out: []u8) -> (usize, err) {
    if !valid_key(a) || !valid_key(b) { ret (0usize, Invalid) }
    if b.len > 0usize && str.compare(a, b) >= 0i32 { ret (0usize, Invalid) }
    let (n, e) = between(a, b, out)
    ret (n, e)
}
