// State-based CRDTs over caller storage, one replica per site index. Every
// `*_merge` is commutative, associative and idempotent, so replicas that have
// seen the same updates in any order agree. `GCounter` is one `u64` per site
// (`gcounter_increment` at a site, `gcounter_merge` is the entrywise max,
// `gcounter_value` the sum); `PnCounter` is two of them; `Lww` is a
// last-writer-wins register ordered by stamp then site; `OrSet` is an
// observed-remove set whose adds carry a unique (site, counter) tag and whose
// removes tombstone the tags the remover has seen, so a concurrent add wins.
// `merge(a, b)` dispatches on a `Crdt` record's kind.

type GCounter = struct { counts: []u64 }
type PnCounter = struct { pos: []u64, neg: []u64 }
type Lww = struct { value: u64, stamp: u64, site: u32 }
type Tag = struct { site: u32, counter: u32 }
type OrElem = struct { element: u64, tag: Tag, removed: bool }
type OrSet = struct { elems: []OrElem, count: usize, site: u32, counter: u32 }
type Kind = enum u8 { GCounter, PnCounter, Lww, OrSet }
type Crdt = struct { kind: Kind, gcounter: GCounter, pncounter: PnCounter, lww: Lww, orset: OrSet }
error TooSmall

fn fill(xs: []u64) {
    var i = 0usize
    while i < xs.len {
        xs[i] = 0u64
        i += 1usize
    }
}

fn max_into(dst: []u64, src: []const u64) {
    var i = 0usize
    while i < dst.len && i < src.len {
        if src[i] > dst[i] { dst[i] = src[i] }
        i += 1usize
    }
}

fn sum(xs: []const u64) -> u64 {
    var t = 0u64
    var i = 0usize
    while i < xs.len {
        t += xs[i]
        i += 1usize
    }
    ret t
}

fn gcounter(counts: []u64) -> GCounter {
    fill(counts)
    ret GCounter { counts: counts }
}

fn gcounter_increment(c: *GCounter, site: usize, by: u64) { c.counts[site] += by }

fn gcounter_merge(dst: *GCounter, src: *const GCounter) { max_into(dst.counts, src.counts) }

fn gcounter_value(c: *const GCounter) -> u64 { ret sum(c.counts) }

fn pncounter(pos: []u64, neg: []u64) -> PnCounter {
    fill(pos)
    fill(neg)
    ret PnCounter { pos: pos, neg: neg }
}

fn pncounter_increment(c: *PnCounter, site: usize, by: u64) { c.pos[site] += by }

fn pncounter_decrement(c: *PnCounter, site: usize, by: u64) { c.neg[site] += by }

fn pncounter_merge(dst: *PnCounter, src: *const PnCounter) {
    max_into(dst.pos, src.pos)
    max_into(dst.neg, src.neg)
}

fn pncounter_value(c: *const PnCounter) -> i64 { ret i64(sum(c.pos)) - i64(sum(c.neg)) }

fn lww() -> Lww { ret Lww { value: 0u64, stamp: 0u64, site: 0u32 } }

fn lww_wins(stamp: u64, site: u32, over: *const Lww) -> bool {
    if stamp != over.stamp { ret stamp > over.stamp }
    ret site > over.site
}

// A write at `stamp` from `site`; answers whether it took (a stale write is dropped).
fn lww_set(r: *Lww, value: u64, stamp: u64, site: u32) -> bool {
    if !lww_wins(stamp, site, r) { ret false }
    r.value = value
    r.stamp = stamp
    r.site = site
    ret true
}

fn lww_merge(dst: *Lww, src: *const Lww) -> bool { ret lww_set(dst, src.value, src.stamp, src.site) }

fn orset(elems: []OrElem, site: u32) -> OrSet { ret OrSet { elems: elems, count: 0usize, site: site, counter: 0u32 } }

fn orset_add(s: *OrSet, element: u64) -> err {
    if s.count >= s.elems.len { ret TooSmall }
    s.counter += 1u32
    s.elems[s.count] = OrElem { element: element, tag: Tag { site: s.site, counter: s.counter }, removed: false }
    s.count += 1usize
    ret ok
}

// Tombstone every live tag of `element` this replica has seen; answers how many.
fn orset_remove(s: *OrSet, element: u64) -> usize {
    var n = 0usize
    var i = 0usize
    while i < s.count {
        if s.elems[i].element == element && !s.elems[i].removed {
            s.elems[i].removed = true
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

fn orset_contains(s: *const OrSet, element: u64) -> bool {
    var i = 0usize
    while i < s.count {
        if s.elems[i].element == element && !s.elems[i].removed { ret true }
        i += 1usize
    }
    ret false
}

fn orset_find(s: *const OrSet, tag: Tag) -> (usize, bool) {
    var i = 0usize
    while i < s.count {
        if s.elems[i].tag.site == tag.site && s.elems[i].tag.counter == tag.counter { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// ponytail: tag lookup is a linear scan, so a merge is O(|dst| * |src|); index the tags when sets grow past a few thousand.
fn orset_merge(dst: *OrSet, src: *const OrSet) -> err {
    var i = 0usize
    while i < src.count {
        let (at, found) = orset_find(dst, src.elems[i].tag)
        if found {
            if src.elems[i].removed { dst.elems[at].removed = true }
        } else {
            if dst.count >= dst.elems.len { ret TooSmall }
            dst.elems[dst.count] = src.elems[i]
            dst.count += 1usize
        }
        i += 1usize
    }
    ret ok
}

fn merge(a: *Crdt, b: *const Crdt) -> err {
    if a.kind == .GCounter { gcounter_merge(&a.gcounter, &b.gcounter) }
    if a.kind == .PnCounter { pncounter_merge(&a.pncounter, &b.pncounter) }
    if a.kind == .Lww { let _ = lww_merge(&a.lww, &b.lww) }
    if a.kind == .OrSet { ret orset_merge(&a.orset, &b.orset) }
    ret ok
}
