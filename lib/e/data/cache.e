// Cache replacement over caller storage.
//
// `Lru` is a complete keyed cache: `u64` keys to `u64` values in a fixed number
// of slots, an open-addressing index inside the same storage, and eviction of
// the least recently used entry. The other policies are replacement orders over
// slot numbers `0..capacity`: the caller keeps its own key index (a `u64` to slot
// map) and asks the policy which slot to reuse (`evict`), tells it when a slot is
// filled (`insert`) and when it is hit (`touch`). `Fifo` reuses in arrival order,
// `Clock` gives each slot a second chance, `Lfu` reuses the least frequently hit
// slot (a linear scan; `Lru` is the constant-time choice), `Slru` promotes a slot
// hit twice into a protected segment, and `TwoQueue` keeps a ghost list of
// recently evicted keys so a key seen again is admitted straight to the main
// queue.

type Lru = struct { keys: []u64, values: []u64, prev: []u32, next: []u32, index: []u32, head: u32, tail: u32, len: usize, free: u32 }
type Fifo = struct { order: []u32, head: usize, len: usize }
type Clock = struct { referenced: []u8, filled: []u8, hand: usize }
type Lfu = struct { hits: []u64, filled: []u8 }
type Slru = struct { prev: []u32, next: []u32, protected: []u8, probation_head: u32, probation_tail: u32, protected_head: u32, protected_tail: u32, protected_len: usize, protected_cap: usize }
type TwoQueue = struct { prev: []u32, next: []u32, main: []u8, ghosts: []u64, ghost_at: usize, in_head: u32, in_tail: u32, in_len: usize, in_cap: usize, main_head: u32, main_tail: u32 }
error TooSmall
error Invalid

const NONE: u32 = 4294967295u32

// A keyed LRU with `capacity` slots: `keys`, `values`, `prev`, `next` need
// `capacity` entries and `index` twice that (a power of two is not required).
fn lru_init(keys: []u64, values: []u64, prev: []u32, next: []u32, index: []u32, capacity: usize) -> (Lru, err) {
    if capacity == 0usize || capacity >= 4294967295usize { ret (zero, Invalid) }
    if keys.len < capacity || values.len < capacity || prev.len < capacity || next.len < capacity || index.len < 2usize * capacity { ret (zero, TooSmall) }
    var c = Lru { keys: keys[..capacity], values: values[..capacity], prev: prev[..capacity], next: next[..capacity], index: index[..2usize * capacity], head: NONE, tail: NONE, len: 0usize, free: 0u32 }
    var i = 0usize
    while i < c.index.len {
        c.index[i] = NONE
        i += 1usize
    }
    // Free slots are chained through `next`.
    i = 0usize
    while i < capacity {
        c.next[i] = u32(i + 1usize)
        i += 1usize
    }
    c.next[capacity - 1usize] = NONE
    ret (c, ok)
}

fn lru_len(c: *const Lru) -> usize { ret c.len }

fn lru_hash(key: u64) -> u64 {
    var x = key *% 11400714819323198485u64
    x = x ^ (x >> 29u64)
    ret x
}

// The index cell holding `key`'s slot, or the cell where it would go.
fn lru_find(c: *const Lru, key: u64) -> (usize, bool) {
    var cell = usize(lru_hash(key) % u64(c.index.len))
    while true {
        let slot = c.index[cell]
        if slot == NONE { ret (cell, false) }
        if c.keys[usize(slot)] == key { ret (cell, true) }
        cell = (cell + 1usize) % c.index.len
    }
    ret (0usize, false)
}

fn lru_unlink(c: *Lru, slot: u32) {
    let p = c.prev[usize(slot)]
    let n = c.next[usize(slot)]
    if p == NONE { c.head = n } else { c.next[usize(p)] = n }
    if n == NONE { c.tail = p } else { c.prev[usize(n)] = p }
}

fn lru_push_front(c: *Lru, slot: u32) {
    c.prev[usize(slot)] = NONE
    c.next[usize(slot)] = c.head
    if c.head != NONE { c.prev[usize(c.head)] = slot }
    c.head = slot
    if c.tail == NONE { c.tail = slot }
}

// The value for `key`, marking it most recently used.
fn lru_get(c: *Lru, key: u64) -> (u64, bool) {
    let (cell, found) = lru_find(c, key)
    if !found { ret (0u64, false) }
    let slot = c.index[cell]
    lru_unlink(c, slot)
    lru_push_front(c, slot)
    ret (c.values[usize(slot)], true)
}

// Whether `key` is present, without touching its recency.
fn lru_contains(c: *const Lru, key: u64) -> bool {
    let (_, found) = lru_find(c, key)
    ret found
}

// Removes an index cell, re-inserting the run that follows it.
fn lru_index_remove(c: *Lru, cell: usize) {
    c.index[cell] = NONE
    var at = (cell + 1usize) % c.index.len
    while c.index[at] != NONE {
        let slot = c.index[at]
        c.index[at] = NONE
        let (again, _) = lru_find(c, c.keys[usize(slot)])
        c.index[again] = slot
        at = (at + 1usize) % c.index.len
    }
}

// Stores `value` under `key`, evicting the least recently used entry when full;
// answers the evicted key and whether one was evicted.
fn lru_put(c: *Lru, key: u64, value: u64) -> (u64, bool) {
    let (cell, found) = lru_find(c, key)
    if found {
        let slot = c.index[cell]
        c.values[usize(slot)] = value
        lru_unlink(c, slot)
        lru_push_front(c, slot)
        ret (0u64, false)
    }
    var evicted = 0u64
    var did_evict = false
    var slot = NONE
    if c.free != NONE {
        slot = c.free
        c.free = c.next[usize(slot)]
    } else {
        slot = c.tail
        evicted = c.keys[usize(slot)]
        did_evict = true
        lru_unlink(c, slot)
        let (old_cell, _) = lru_find(c, evicted)
        lru_index_remove(c, old_cell)
        c.len -= 1usize
    }
    c.keys[usize(slot)] = key
    c.values[usize(slot)] = value
    lru_push_front(c, slot)
    let (new_cell, _) = lru_find(c, key)
    c.index[new_cell] = slot
    c.len += 1usize
    ret (evicted, did_evict)
}

// Removes `key`; `false` when absent.
fn lru_remove(c: *Lru, key: u64) -> bool {
    let (cell, found) = lru_find(c, key)
    if !found { ret false }
    let slot = c.index[cell]
    lru_unlink(c, slot)
    lru_index_remove(c, cell)
    c.next[usize(slot)] = c.free
    c.free = slot
    c.len -= 1usize
    ret true
}

// The least recently used key, if any.
fn lru_oldest(c: *const Lru) -> (u64, bool) {
    if c.tail == NONE { ret (0u64, false) }
    ret (c.keys[usize(c.tail)], true)
}

// FIFO over `capacity` slots; `order.len >= capacity`.
fn fifo_init(order: []u32, capacity: usize) -> (Fifo, err) {
    if capacity == 0usize { ret (zero, Invalid) }
    if order.len < capacity { ret (zero, TooSmall) }
    ret (Fifo { order: order[..capacity], head: 0usize, len: 0usize }, ok)
}

// The slot to reuse: the oldest, or `false` while slots are free.
fn fifo_evict(f: *const Fifo) -> (u32, bool) {
    if f.len < f.order.len { ret (0u32, false) }
    ret (f.order[f.head], true)
}

// Records that `slot` was filled (after `fifo_evict` named it, or while free).
fn fifo_insert(f: *Fifo, slot: u32) {
    if f.len < f.order.len {
        f.order[(f.head + f.len) % f.order.len] = slot
        f.len += 1usize
    } else {
        f.order[f.head] = slot
        f.head = (f.head + 1usize) % f.order.len
    }
}

// Clock (second chance) over `capacity` slots; both slices need `capacity` bytes.
fn clock_init(referenced: []u8, filled: []u8, capacity: usize) -> (Clock, err) {
    if capacity == 0usize { ret (zero, Invalid) }
    if referenced.len < capacity || filled.len < capacity { ret (zero, TooSmall) }
    var i = 0usize
    while i < capacity {
        referenced[i] = 0u8
        filled[i] = 0u8
        i += 1usize
    }
    ret (Clock { referenced: referenced[..capacity], filled: filled[..capacity], hand: 0usize }, ok)
}

fn clock_touch(k: *Clock, slot: u32) { k.referenced[usize(slot)] = 1u8 }

fn clock_insert(k: *Clock, slot: u32) {
    k.filled[usize(slot)] = 1u8
    k.referenced[usize(slot)] = 0u8
}

// The slot to reuse: the first unreferenced one the hand reaches, clearing the
// reference bits it passes; a free slot when there is one.
fn clock_evict(k: *Clock) -> u32 {
    var i = 0usize
    while i < k.filled.len {
        if k.filled[i] == 0u8 { ret u32(i) }
        i += 1usize
    }
    while true {
        if k.referenced[k.hand] == 0u8 {
            let slot = k.hand
            k.hand = (k.hand + 1usize) % k.filled.len
            ret u32(slot)
        }
        k.referenced[k.hand] = 0u8
        k.hand = (k.hand + 1usize) % k.filled.len
    }
    ret 0u32
}

// LFU over `capacity` slots; `hits.len` and `filled.len` at least `capacity`.
fn lfu_init(hits: []u64, filled: []u8, capacity: usize) -> (Lfu, err) {
    if capacity == 0usize { ret (zero, Invalid) }
    if hits.len < capacity || filled.len < capacity { ret (zero, TooSmall) }
    var i = 0usize
    while i < capacity {
        hits[i] = 0u64
        filled[i] = 0u8
        i += 1usize
    }
    ret (Lfu { hits: hits[..capacity], filled: filled[..capacity] }, ok)
}

fn lfu_touch(l: *Lfu, slot: u32) { l.hits[usize(slot)] += 1u64 }

fn lfu_insert(l: *Lfu, slot: u32) {
    l.filled[usize(slot)] = 1u8
    l.hits[usize(slot)] = 1u64
}

// The slot to reuse: a free one, else the fewest hits (ties to the lowest slot).
fn lfu_evict(l: *const Lfu) -> u32 {
    var best = 0usize
    var i = 0usize
    while i < l.filled.len {
        if l.filled[i] == 0u8 { ret u32(i) }
        if l.hits[i] < l.hits[best] { best = i }
        i += 1usize
    }
    ret u32(best)
}

// Segmented LRU: a probation list and a protected list of at most
// `protected_cap` slots; `prev`, `next`, `protected` need `capacity` entries.
fn slru_init(prev: []u32, next: []u32, protected: []u8, capacity: usize, protected_cap: usize) -> (Slru, err) {
    if capacity == 0usize || protected_cap >= capacity { ret (zero, Invalid) }
    if prev.len < capacity || next.len < capacity || protected.len < capacity { ret (zero, TooSmall) }
    var i = 0usize
    while i < capacity {
        protected[i] = 2u8
        i += 1usize
    }
    ret (Slru { prev: prev[..capacity], next: next[..capacity], protected: protected[..capacity], probation_head: NONE, probation_tail: NONE, protected_head: NONE, protected_tail: NONE, protected_len: 0usize, protected_cap: protected_cap }, ok)
}

// `protected[slot]`: 0 probation, 1 protected, 2 free.
fn slru_unlink(s: *Slru, slot: u32) {
    let p = s.prev[usize(slot)]
    let n = s.next[usize(slot)]
    let in_protected = s.protected[usize(slot)] == 1u8
    if p == NONE {
        if in_protected { s.protected_head = n } else { s.probation_head = n }
    } else {
        s.next[usize(p)] = n
    }
    if n == NONE {
        if in_protected { s.protected_tail = p } else { s.probation_tail = p }
    } else {
        s.prev[usize(n)] = p
    }
}

fn slru_push_probation(s: *Slru, slot: u32) {
    s.protected[usize(slot)] = 0u8
    s.prev[usize(slot)] = NONE
    s.next[usize(slot)] = s.probation_head
    if s.probation_head != NONE { s.prev[usize(s.probation_head)] = slot }
    s.probation_head = slot
    if s.probation_tail == NONE { s.probation_tail = slot }
}

fn slru_push_protected(s: *Slru, slot: u32) {
    s.protected[usize(slot)] = 1u8
    s.prev[usize(slot)] = NONE
    s.next[usize(slot)] = s.protected_head
    if s.protected_head != NONE { s.prev[usize(s.protected_head)] = slot }
    s.protected_head = slot
    if s.protected_tail == NONE { s.protected_tail = slot }
    s.protected_len += 1usize
}

// A new slot enters probation at the front.
fn slru_insert(s: *Slru, slot: u32) { slru_push_probation(s, slot) }

// A hit promotes a probation slot to protected (demoting the protected tail
// when full) and refreshes a protected one.
fn slru_touch(s: *Slru, slot: u32) {
    if s.protected[usize(slot)] == 1u8 {
        slru_unlink(s, slot)
        s.protected_len -= 1usize
        slru_push_protected(s, slot)
        ret
    }
    if s.protected[usize(slot)] != 0u8 { ret }
    slru_unlink(s, slot)
    if s.protected_len >= s.protected_cap {
        let demoted = s.protected_tail
        slru_unlink(s, demoted)
        s.protected_len -= 1usize
        slru_push_probation(s, demoted)
    }
    slru_push_protected(s, slot)
}

// The slot to reuse: a free one, else the probation tail, else the protected tail.
fn slru_evict(s: *Slru) -> u32 {
    var i = 0usize
    while i < s.protected.len {
        if s.protected[i] == 2u8 { ret u32(i) }
        i += 1usize
    }
    var victim = s.probation_tail
    if victim == NONE {
        victim = s.protected_tail
        s.protected_len -= 1usize
    }
    slru_unlink(s, victim)
    s.protected[usize(victim)] = 2u8
    ret victim
}

// Whether `slot` currently sits in the protected segment.
fn slru_is_protected(s: *const Slru, slot: u32) -> bool { ret s.protected[usize(slot)] == 1u8 }

// 2Q: new slots enter a FIFO of `in_cap` slots; a key whose eviction is still
// remembered in `ghosts` is admitted to the main LRU. `prev`, `next`, `main`
// need `capacity` entries; `ghosts` any length (its length is the memory).
fn two_queue_init(prev: []u32, next: []u32, main: []u8, ghosts: []u64, capacity: usize, in_cap: usize) -> (TwoQueue, err) {
    if capacity == 0usize || in_cap == 0usize || in_cap > capacity { ret (zero, Invalid) }
    if prev.len < capacity || next.len < capacity || main.len < capacity { ret (zero, TooSmall) }
    var i = 0usize
    while i < capacity {
        main[i] = 2u8
        i += 1usize
    }
    i = 0usize
    while i < ghosts.len {
        ghosts[i] = 0u64
        i += 1usize
    }
    ret (TwoQueue { prev: prev[..capacity], next: next[..capacity], main: main[..capacity], ghosts: ghosts, ghost_at: 0usize, in_head: NONE, in_tail: NONE, in_len: 0usize, in_cap: in_cap, main_head: NONE, main_tail: NONE }, ok)
}

fn two_queue_remembers(q: *const TwoQueue, key: u64) -> bool {
    var i = 0usize
    while i < q.ghosts.len {
        if q.ghosts[i] == key { ret true }
        i += 1usize
    }
    ret false
}

fn two_queue_unlink(q: *TwoQueue, slot: u32) {
    let p = q.prev[usize(slot)]
    let n = q.next[usize(slot)]
    let in_main = q.main[usize(slot)] == 1u8
    if p == NONE {
        if in_main { q.main_head = n } else { q.in_head = n }
    } else {
        q.next[usize(p)] = n
    }
    if n == NONE {
        if in_main { q.main_tail = p } else { q.in_tail = p }
    } else {
        q.prev[usize(n)] = p
    }
    if !in_main { q.in_len -= 1usize }
}

fn two_queue_push(q: *TwoQueue, slot: u32, to_main: bool) {
    q.prev[usize(slot)] = NONE
    if to_main {
        q.main[usize(slot)] = 1u8
        q.next[usize(slot)] = q.main_head
        if q.main_head != NONE { q.prev[usize(q.main_head)] = slot }
        q.main_head = slot
        if q.main_tail == NONE { q.main_tail = slot }
    } else {
        q.main[usize(slot)] = 0u8
        q.next[usize(slot)] = q.in_head
        if q.in_head != NONE { q.prev[usize(q.in_head)] = slot }
        q.in_head = slot
        if q.in_tail == NONE { q.in_tail = slot }
        q.in_len += 1usize
    }
}

// Records `slot` filled with `key`: into the main queue when the key was
// recently evicted, otherwise into the FIFO.
fn two_queue_insert(q: *TwoQueue, slot: u32, key: u64) {
    two_queue_push(q, slot, two_queue_remembers(q, key))
}

// A hit refreshes a main-queue slot; FIFO slots are left in arrival order.
fn two_queue_touch(q: *TwoQueue, slot: u32) {
    if q.main[usize(slot)] != 1u8 { ret }
    two_queue_unlink(q, slot)
    two_queue_push(q, slot, true)
}

// The slot to reuse, given the key it holds is `key` (remembered as a ghost): a
// free slot, else the FIFO tail while the FIFO is full, else the main tail.
fn two_queue_evict(q: *TwoQueue, keys: []const u64) -> u32 {
    var i = 0usize
    while i < q.main.len {
        if q.main[i] == 2u8 { ret u32(i) }
        i += 1usize
    }
    var victim = NONE
    if q.in_len >= q.in_cap || q.main_tail == NONE { victim = q.in_tail } else { victim = q.main_tail }
    if victim == NONE { victim = q.main_tail }
    two_queue_unlink(q, victim)
    q.main[usize(victim)] = 2u8
    if q.ghosts.len > 0usize && usize(victim) < keys.len {
        q.ghosts[q.ghost_at] = keys[usize(victim)]
        q.ghost_at = (q.ghost_at + 1usize) % q.ghosts.len
    }
    ret victim
}

fn two_queue_in_main(q: *const TwoQueue, slot: u32) -> bool { ret q.main[usize(slot)] == 1u8 }
