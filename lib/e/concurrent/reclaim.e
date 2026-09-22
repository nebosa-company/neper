// Safe memory reclamation for lock-free structures, over caller storage and with a
// node as a `u32` index rather than a pointer, so a test can see exactly which node
// was freed when. Two schemes: epoch-based reclamation (`Epoch`: a global epoch, one
// word per thread holding its epoch and an active bit, three retire buckets; a node
// retired in epoch e is freed on the advance to e+2) and hazard pointers (`Hazards`:
// K slots per thread naming the nodes it reads; a retired node is freed by `scan`
// once no slot names it, and a thread's list is scanned when it grows past
// R = 2 * threads * K). A freed node lands on the caller's `freed` list of the `Sink`
// and, when `on_free` was set, in the hook -- called by the freeing thread at the
// moment of the free. `List` is the lock-free stack over node indices both protect.
// `NONE` is the null index.
//
// Discipline: `retire` and `list_pop_front` are called between `pin` and `unpin`;
// under hazards the head is read through `protect_validated` and popped with
// `list_try_pop`, and the slot is cleared only after the last read of the node.

use e.atomic
use e.mem

type Sink = struct { freed: []u32, freed_count: Atomic[u64], on_free: fn(*void, u32), ctx: *void, hooked: bool }
type Epoch = struct { global: Atomic[u64], local: []Atomic[u64], retired: []u32, retired_count: []Atomic[u64], bucket_cap: usize, threads: usize, sink: Sink }
type Hazards = struct { slots: []Atomic[u32], retired: []u32, retired_count: []usize, retire_cap: usize, threshold: usize, threads: usize, k: usize, sink: Sink }
type List = struct { head: Atomic[u32], next: []Atomic[u32] }
error Full
error Invalid
error TooSmall

const NONE: u32 = 4294967295u32

// ---- Sink -----------------------------------------------------------------

// A node the caller may reuse: appended to `freed` while it fits and handed to the hook.
// ponytail: `freed_count` keeps counting past `freed.len` and the surplus nodes are only
// reported through the hook; size `freed` for every node that can be retired.
fn sink_free(s: *Sink, node: u32) {
    let slot = usize(atomic.add(&s.freed_count, 1u64, .AcqRel))
    if slot < s.freed.len { s.freed[slot] = node }
    if s.hooked { s.on_free(s.ctx, node) }
}

fn on_free(s: *Sink, f: fn(*void, u32), ctx: *void) {
    s.on_free = f
    s.ctx = ctx
    s.hooked = true
}

fn freed_count(s: *Sink) -> usize {
    ret usize(atomic.load(&s.freed_count, .Acquire))
}

// ---- Epoch-based reclamation ----------------------------------------------
//
// `local[t]` is `epoch << 1 | active`. `retired` is three buckets of `retired.len / 3`,
// bucket `e % 3` holding what was retired while the global epoch was e; `retired_count[b]` is claimed by
// an atomic add, saturating past the capacity (a slot at or past it is `Full` and is
// never written), and taken whole by the advance that frees the bucket.

fn epoch(local: []Atomic[u64], retired: []u32, retired_count: []Atomic[u64], freed: []u32, threads: usize) -> (Epoch, err) {
    if threads == 0usize { ret (zero, Invalid) }
    if local.len < threads || retired_count.len < 3usize || retired.len < 3usize { ret (zero, TooSmall) }
    var e: Epoch = zero
    e.local = local[..threads]
    e.retired = retired
    e.retired_count = retired_count[..3usize]
    e.bucket_cap = retired.len / 3usize
    e.threads = threads
    e.sink.freed = freed
    var at = 0usize
    while at < threads {
        atomic.store(&e.local[at], 0u64, .Relaxed)
        at += 1usize
    }
    at = 0usize
    while at < 3usize {
        atomic.store(&e.retired_count[at], 0u64, .Relaxed)
        at += 1usize
    }
    ret (e, ok)
}

// Enters a critical section: the thread's word takes the global epoch and the active
// bit, and the `SeqCst` store fences it before the thread's first read of the structure.
fn pin(e: *Epoch, thread: usize) {
    let g = atomic.load(&e.global, .SeqCst)
    atomic.store(&e.local[thread], (g << 1u32) | 1u64, .SeqCst)
}

fn unpin(e: *Epoch, thread: usize) {
    atomic.store(&e.local[thread], 0u64, .Release)
}

fn is_pinned(e: *Epoch, thread: usize) -> bool {
    ret (atomic.load(&e.local[thread], .Relaxed) & 1u64) != 0u64
}

// Into the bucket of the current global epoch g -- not the retirer's own, which may
// still be g-1: a thread pinned at g can hold the node, and only the advance to g+2
// proves it has left. `Invalid` when not pinned, because an unpinned retirer's slot
// write could race the free of its bucket.
fn retire(e: *Epoch, thread: usize, node: u32) -> err {
    let mine = atomic.load(&e.local[thread], .Relaxed)
    if (mine & 1u64) == 0u64 { ret Invalid }
    let bucket = usize(atomic.load(&e.global, .SeqCst) % 3u64)
    let slot = usize(atomic.add(&e.retired_count[bucket], 1u64, .AcqRel))
    if slot >= e.bucket_cap { ret Full }
    e.retired[bucket * e.bucket_cap + slot] = node
    ret ok
}

// Every active thread is at epoch `g`.
fn all_at(e: *Epoch, g: u64) -> bool {
    var at = 0usize
    while at < e.threads {
        let seen = atomic.load(&e.local[at], .SeqCst)
        if (seen & 1u64) != 0u64 && (seen >> 1u32) != g { ret false }
        at += 1usize
    }
    ret true
}

fn free_bucket(e: *Epoch, bucket: usize) {
    var n = usize(atomic.xchg(&e.retired_count[bucket], 0u64, .AcqRel))
    if n > e.bucket_cap { n = e.bucket_cap }
    var at = 0usize
    while at < n {
        sink_free(&e.sink, e.retired[bucket * e.bucket_cap + at])
        at += 1usize
    }
}

// Advances the global epoch from g to g+1 when every active thread is at g, and the
// winner of that step frees bucket (g-1) % 3: what was retired at g-1 has been left
// behind by every thread twice. The advancer is pinned for the duration (pinning
// itself if the caller had not), which is what keeps the bucket it frees from becoming
// the current one -- two more advances -- while it is still copying it out.
fn try_advance(e: *Epoch, thread: usize) -> bool {
    let was_pinned = is_pinned(e, thread)
    if !was_pinned { pin(e, thread) }
    let g = atomic.load(&e.global, .SeqCst)
    var advanced = false
    if all_at(e, g) {
        let (won, seen) = atomic.cas(&e.global, g, g + 1u64, .AcqRel, .Relaxed)
        if won {
            free_bucket(e, usize((g + 2u64) % 3u64))
            advanced = true
        }
    }
    if !was_pinned { unpin(e, thread) }
    ret advanced
}

fn global_epoch(e: *Epoch) -> u64 {
    ret atomic.load(&e.global, .Acquire)
}

// Drains every bucket while no other thread is pinned: three advances flush what was
// retired at g-1, g and (if a thread retired after the second) g+1. The count freed so far.
fn collect(e: *Epoch, thread: usize) -> usize {
    var rounds = 0usize
    while rounds < 3usize {
        let ignored = try_advance(e, thread)
        rounds += 1usize
    }
    ret freed_count(&e.sink)
}

// ---- Hazard pointers ------------------------------------------------------

fn hazards(slots: []Atomic[u32], retired: []u32, retired_count: []usize, freed: []u32, threads: usize, k: usize) -> (Hazards, err) {
    if threads == 0usize || k == 0usize { ret (zero, Invalid) }
    let total = threads * k
    if slots.len < total || retired_count.len < threads || retired.len < threads { ret (zero, TooSmall) }
    var h: Hazards = zero
    h.slots = slots[..total]
    h.retired = retired
    h.retired_count = retired_count[..threads]
    h.retire_cap = retired.len / threads
    h.threshold = 2usize * total
    h.threads = threads
    h.k = k
    h.sink.freed = freed
    var at = 0usize
    while at < total {
        atomic.store(&h.slots[at], NONE, .Relaxed)
        at += 1usize
    }
    at = 0usize
    while at < threads {
        h.retired_count[at] = 0usize
        at += 1usize
    }
    ret (h, ok)
}

// Publishes `node` in the thread's slot. The caller must then re-read the reference it
// took `node` from and retry when it moved, or use `protect_validated`.
fn protect(h: *Hazards, thread: usize, slot: usize, node: u32) {
    atomic.store(&h.slots[thread * h.k + slot], node, .SeqCst)
}

// Loads through `load`, publishes, and loads again until the two agree: the node is
// then both protected and still reachable.
fn protect_validated[Ctx: type](h: *Hazards, thread: usize, slot: usize, load: fn(*Ctx) -> u32, ctx: *Ctx) -> u32 {
    var seen = load(ctx)
    while true {
        protect(h, thread, slot, seen)
        let again = load(ctx)
        if again == seen { ret seen }
        seen = again
    }
    ret NONE
}

fn clear(h: *Hazards, thread: usize, slot: usize) {
    atomic.store(&h.slots[thread * h.k + slot], NONE, .Release)
}

fn is_protected(h: *Hazards, node: u32) -> bool {
    var at = 0usize
    while at < h.slots.len {
        if atomic.load(&h.slots[at], .SeqCst) == node { ret true }
        at += 1usize
    }
    ret false
}

// Onto the thread's own retired list, scanning it once it holds more than R nodes.
// `Full` when the list is at its capacity even so.
fn retire_hazard(h: *Hazards, thread: usize, node: u32) -> err {
    let n = h.retired_count[thread]
    if n >= h.retire_cap { ret Full }
    h.retired[thread * h.retire_cap + n] = node
    h.retired_count[thread] = n + 1usize
    if n + 1usize > h.threshold { let ignored = scan(h, thread) }
    ret ok
}

// Frees every node of the thread's retired list that no slot names; the rest stay.
// ponytail: each node is checked against every slot, O(R * H) per scan. Sort the slots
// and bisect if H grows past a few dozen.
fn scan(h: *Hazards, thread: usize) -> usize {
    let base = thread * h.retire_cap
    let n = h.retired_count[thread]
    var kept = 0usize
    var freed = 0usize
    var at = 0usize
    while at < n {
        let node = h.retired[base + at]
        if is_protected(h, node) {
            h.retired[base + kept] = node
            kept += 1usize
        } else {
            sink_free(&h.sink, node)
            freed += 1usize
        }
        at += 1usize
    }
    h.retired_count[thread] = kept
    ret freed
}

// ---- The client: a lock-free stack over node indices -------------------------

fn list(next: []Atomic[u32]) -> List {
    ret List { head: atomic.init(NONE), next: next }
}

fn list_head(l: *List) -> u32 {
    ret atomic.load(&l.head, .Acquire)
}

fn list_push_front(l: *List, node: u32) {
    while true {
        let h = atomic.load(&l.head, .Acquire)
        atomic.store(&l.next[usize(node)], h, .Relaxed)
        let (won, seen) = atomic.cas(&l.head, h, node, .Release, .Relaxed)
        if won { ret }
    }
}

// Unlinks `h` when it is still the head: the read of `next[h]` is the one a reclamation
// scheme must cover, so `h` is a pinned thread's or a protected node.
fn list_try_pop(l: *List, h: u32) -> bool {
    let nx = atomic.load(&l.next[usize(h)], .Acquire)
    let (won, seen) = atomic.cas(&l.head, h, nx, .AcqRel, .Relaxed)
    ret won
}

// The head or `NONE`; for a pinned thread, whose epoch keeps every node it can see.
fn list_pop_front(l: *List) -> u32 {
    while true {
        let h = atomic.load(&l.head, .Acquire)
        if h == NONE { ret NONE }
        if list_try_pop(l, h) { ret h }
    }
    ret NONE
}

// The hazard-pointer scheme under its planned name: `hazards`.
fn hazard(slots: []Atomic[u32], retired: []u32, retired_count: []usize, freed: []u32, threads: usize, k: usize) -> (Hazards, err) {
    let (h, e) = hazards(slots, retired, retired_count, freed, threads, k)
    ret (h, e)
}
