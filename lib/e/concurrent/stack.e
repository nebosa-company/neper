// A lock-free Treiber stack over a fixed pool of nodes the caller supplies. Nodes are
// `u32` indexes into `next`/`value`, never pointers, so a head word packs the index in
// its low 32 bits and a version counter in its high 32 bits: the counter moves on every
// successful compare-and-swap, so a head that was popped and pushed back between a
// thread's load and its swap no longer compares equal -- the ABA case a bare index
// would miss. The free list is a second Treiber stack over the same nodes, with the
// same tagged word.
//
// `next[i]` is written by the thread that owns node `i` (won it off a list) before it
// publishes the node with a compare-and-swap, and a reader that saw a stale `next[i]`
// also sees a stale head and its own swap fails; that is the same benign race the
// pointer version has.
use e.atomic

type Stack = struct { head: Atomic[u64], free: Atomic[u64], count: Atomic[u64], next: []u32, value: []u64 }
error Invalid
error Full

const NIL: u32 = 4294967295u32

fn pack(index: u32, version: u64) -> u64 {
    ret (((version + 1u64) & 4294967295u64) << 32u32) | u64(index)
}

fn index_of(word: u64) -> u32 {
    ret u32(word & 4294967295u64)
}

fn version_of(word: u64) -> u64 {
    ret word >> 32u32
}

// Every node starts on the free list; the two slices must be the same length, and
// `NIL` is reserved so the pool holds at most 2^32 - 1 nodes.
fn stack(next: []u32, value: []u64) -> (Stack, err) {
    if next.len != value.len || next.len >= 4294967295usize { ret (zero, Invalid) }
    var i = 0usize
    while i < next.len {
        if i + 1usize == next.len {
            next[i] = NIL
        } else {
            next[i] = u32(i + 1usize)
        }
        i += 1usize
    }
    var first = NIL
    if next.len > 0usize { first = 0u32 }
    ret (Stack { head: atomic.init(u64(NIL)), free: atomic.init(u64(first)), count: atomic.init(0u64), next: next, value: value }, ok)
}

// Takes the top node of the list at `list`, or `NIL` when it is empty.
fn take(s: *Stack, list: *Atomic[u64]) -> u32 {
    while true {
        let h = atomic.load(list, .Acquire)
        let i = index_of(h)
        if i == NIL { ret NIL }
        let n = s.next[usize(i)]
        let (won, seen) = atomic.cas(list, h, pack(n, version_of(h)), .AcqRel, .Relaxed)
        if won { ret i }
    }
    ret NIL
}

fn give(s: *Stack, list: *Atomic[u64], i: u32) {
    while true {
        let h = atomic.load(list, .Acquire)
        s.next[usize(i)] = index_of(h)
        let (won, seen) = atomic.cas(list, h, pack(i, version_of(h)), .Release, .Relaxed)
        if won { ret }
    }
}

// `Full` when no node is free.
fn push(s: *Stack, v: u64) -> err {
    let i = take(s, &s.free)
    if i == NIL { ret Full }
    s.value[usize(i)] = v
    give(s, &s.head, i)
    let ignored = atomic.add(&s.count, 1u64, .Relaxed)
    ret ok
}

fn pop(s: *Stack) -> (u64, bool) {
    let i = take(s, &s.head)
    if i == NIL { ret (0u64, false) }
    let ignored = atomic.sub(&s.count, 1u64, .Relaxed)
    let v = s.value[usize(i)]
    give(s, &s.free, i)
    ret (v, true)
}

// A count of completed pushes less completed pops: exact once every thread is quiet.
fn len(s: *Stack) -> usize {
    ret usize(atomic.load(&s.count, .Relaxed))
}

fn is_empty(s: *Stack) -> bool {
    ret index_of(atomic.load(&s.head, .Acquire)) == NIL
}

fn capacity(s: *const Stack) -> usize {
    ret s.next.len
}
