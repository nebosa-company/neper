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
//
// Each policy also has a whole-policy access `lru(c, key)`, `fifo(f, keys, key)`,
// ... that finds the key, touches it on a hit or evicts and inserts it on a miss,
// answering `(hit, evicted key, whether one was evicted)`; the slot policies keep
// the key of every slot in a caller `keys` slice of `capacity` entries. `Arc` is
// the adaptive replacement cache: resident lists T1 (seen once) and T2 (seen
// again), ghost lists B1 and B2 of recently evicted keys, and a target `p` for
// T1's size that a B1 hit raises and a B2 hit lowers.

type Lru = struct { keys: []u64, values: []u64, prev: []u32, next: []u32, index: []u32, head: u32, tail: u32, len: usize, free: u32 }
type Fifo = struct { order: []u32, head: usize, len: usize }
type Clock = struct { referenced: []u8, filled: []u8, hand: usize }
type Lfu = struct { hits: []u64, filled: []u8 }
type Slru = struct { prev: []u32, next: []u32, protected: []u8, probation_head: u32, probation_tail: u32, protected_head: u32, protected_tail: u32, protected_len: usize, protected_cap: usize }
type TwoQueue = struct { prev: []u32, next: []u32, main: []u8, ghosts: []u64, ghost_at: usize, in_head: u32, in_tail: u32, in_len: usize, in_cap: usize, main_head: u32, main_tail: u32 }
type Arc = struct { keys: []u64, prev: []u32, next: []u32, list: []u8, t1: usize, t2: usize, b1: usize, b2: usize, p: usize, free: u32 }
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

// Touches `key` or inserts it (value 0) under LRU: `(hit, evicted key, evicted)`.
fn lru(c: *Lru, key: u64) -> (bool, u64, bool) {
    let (_, hit) = lru_get(c, key)
    if hit { ret (true, 0u64, false) }
    let (evicted, did_evict) = lru_put(c, key, 0u64)
    ret (false, evicted, did_evict)
}

// The slot among those not marked `free_mark` that holds `key`, or NONE.
// ponytail: a linear scan per access; index the keys (as `Lru` does) if it matters.
fn find_slot(keys: []const u64, marks: []const u8, free_mark: u8, key: u64) -> u32 {
    var i = 0usize
    while i < marks.len {
        if marks[i] != free_mark && keys[i] == key { ret u32(i) }
        i += 1usize
    }
    ret NONE
}

// FIFO access: a hit changes nothing; a miss fills the next free slot or the oldest.
fn fifo(f: *Fifo, keys: []u64, key: u64) -> (bool, u64, bool) {
    var j = 0usize
    while j < f.len {
        if keys[usize(f.order[(f.head + j) % f.order.len])] == key { ret (true, 0u64, false) }
        j += 1usize
    }
    let (victim, full) = fifo_evict(f)
    var slot = u32(f.len)
    var evicted = 0u64
    if full {
        slot = victim
        evicted = keys[usize(slot)]
    }
    keys[usize(slot)] = key
    fifo_insert(f, slot)
    ret (false, evicted, full)
}

// Clock access: a hit sets the reference bit; a miss takes the hand's victim.
fn clock(k: *Clock, keys: []u64, key: u64) -> (bool, u64, bool) {
    let slot = find_slot(keys, k.filled, 0u8, key)
    if slot != NONE {
        clock_touch(k, slot)
        ret (true, 0u64, false)
    }
    let victim = clock_evict(k)
    let was_filled = k.filled[usize(victim)] == 1u8
    let evicted = keys[usize(victim)]
    keys[usize(victim)] = key
    clock_insert(k, victim)
    ret (false, evicted, was_filled)
}

// LFU access: a hit counts; a miss replaces the least frequently hit slot.
fn lfu(l: *Lfu, keys: []u64, key: u64) -> (bool, u64, bool) {
    let slot = find_slot(keys, l.filled, 0u8, key)
    if slot != NONE {
        lfu_touch(l, slot)
        ret (true, 0u64, false)
    }
    let victim = lfu_evict(l)
    let was_filled = l.filled[usize(victim)] == 1u8
    let evicted = keys[usize(victim)]
    keys[usize(victim)] = key
    lfu_insert(l, victim)
    ret (false, evicted, was_filled)
}

// SLRU access: a hit promotes or refreshes; a miss enters probation.
fn slru(s: *Slru, keys: []u64, key: u64) -> (bool, u64, bool) {
    let slot = find_slot(keys, s.protected, 2u8, key)
    if slot != NONE {
        slru_touch(s, slot)
        ret (true, 0u64, false)
    }
    var was_filled = true
    var i = 0usize
    while i < s.protected.len {
        if s.protected[i] == 2u8 { was_filled = false }
        i += 1usize
    }
    let victim = slru_evict(s)
    let evicted = keys[usize(victim)]
    keys[usize(victim)] = key
    slru_insert(s, victim)
    ret (false, evicted, was_filled)
}

// 2Q access: a hit refreshes a main-queue slot; a miss evicts (remembering the
// victim's key) and admits `key` to the main queue when it is remembered.
fn two_queue(q: *TwoQueue, keys: []u64, key: u64) -> (bool, u64, bool) {
    let slot = find_slot(keys, q.main, 2u8, key)
    if slot != NONE {
        two_queue_touch(q, slot)
        ret (true, 0u64, false)
    }
    var was_filled = true
    var i = 0usize
    while i < q.main.len {
        if q.main[i] == 2u8 { was_filled = false }
        i += 1usize
    }
    let victim = two_queue_evict(q, keys)
    let evicted = keys[usize(victim)]
    keys[usize(victim)] = key
    two_queue_insert(q, victim, key)
    ret (false, evicted, was_filled)
}

// ARC over `capacity` resident entries: `keys` and `list` need `2 * capacity`
// entries (residents plus ghosts), `prev` and `next` four more (list sentinels).
fn arc_init(keys: []u64, prev: []u32, next: []u32, list: []u8, capacity: usize) -> (Arc, err) {
    if capacity == 0usize || capacity >= 1073741823usize { ret (zero, Invalid) }
    let n = 2usize * capacity
    if keys.len < n || list.len < n || prev.len < n + 4usize || next.len < n + 4usize { ret (zero, TooSmall) }
    var c = Arc { keys: keys[..n], prev: prev[..n + 4usize], next: next[..n + 4usize], list: list[..n], t1: 0usize, t2: 0usize, b1: 0usize, b2: 0usize, p: 0usize, free: 0u32 }
    var i = 0usize
    while i < n {
        c.list[i] = 0u8
        c.next[i] = u32(i + 1usize)
        i += 1usize
    }
    c.next[n - 1usize] = NONE
    while i < n + 4usize {
        c.next[i] = u32(i)
        c.prev[i] = u32(i)
        i += 1usize
    }
    ret (c, ok)
}

// `list[node]`: 0 free, 1 T1, 2 T2, 3 B1, 4 B2; each list is circular through
// its sentinel node `2 * capacity + list - 1`, MRU first.
fn arc_sentinel(c: *const Arc, l: u8) -> u32 { ret u32(c.keys.len + usize(l) - 1usize) }

fn arc_count(c: *const Arc, l: u8) -> usize {
    if l == 1u8 { ret c.t1 }
    if l == 2u8 { ret c.t2 }
    if l == 3u8 { ret c.b1 }
    ret c.b2
}

fn arc_set_count(c: *Arc, l: u8, n: usize) {
    if l == 1u8 { c.t1 = n } else if l == 2u8 { c.t2 = n } else if l == 3u8 { c.b1 = n } else { c.b2 = n }
}

fn arc_unlink(c: *Arc, node: u32) {
    let p = c.prev[usize(node)]
    let n = c.next[usize(node)]
    c.next[usize(p)] = n
    c.prev[usize(n)] = p
    let l = c.list[usize(node)]
    arc_set_count(c, l, arc_count(c, l) - 1usize)
}

fn arc_push(c: *Arc, node: u32, l: u8) {
    let s = arc_sentinel(c, l)
    let n = c.next[usize(s)]
    c.prev[usize(node)] = s
    c.next[usize(node)] = n
    c.next[usize(s)] = node
    c.prev[usize(n)] = node
    c.list[usize(node)] = l
    arc_set_count(c, l, arc_count(c, l) + 1usize)
}

// The least recently used node of list `l` (its sentinel when empty).
fn arc_lru(c: *const Arc, l: u8) -> u32 { ret c.prev[usize(arc_sentinel(c, l))] }

fn arc_release(c: *Arc, node: u32) {
    arc_unlink(c, node)
    c.list[usize(node)] = 0u8
    c.next[usize(node)] = c.free
    c.free = node
}

// ponytail: a linear scan over 2 * capacity nodes per access.
fn arc_find(c: *const Arc, key: u64) -> u32 {
    var i = 0usize
    while i < c.keys.len {
        if c.list[i] != 0u8 && c.keys[i] == key { ret u32(i) }
        i += 1usize
    }
    ret NONE
}

// REPLACE: moves the LRU of T1 to B1 when T1 is over its target `p` (or at it
// on a B2 hit), else the LRU of T2 to B2; answers the key that left.
fn arc_replace(c: *Arc, in_b2: bool) -> (u64, bool) {
    var from = 2u8
    if c.t1 > 0usize && (c.t1 > c.p || (in_b2 && c.t1 == c.p)) { from = 1u8 }
    if from == 2u8 && c.t2 == 0usize { from = 1u8 }
    if arc_count(c, from) == 0usize { ret (0u64, false) }
    let victim = arc_lru(c, from)
    arc_unlink(c, victim)
    arc_push(c, victim, from + 2u8)
    ret (c.keys[usize(victim)], true)
}

// ARC access: `(hit, evicted key, evicted)`. A resident key moves to the front
// of T2; a ghost hit adapts `p` toward the list that was hit and re-admits the
// key to T2; a new key enters T1, making room per the paper's cases.
fn arc(c: *Arc, key: u64) -> (bool, u64, bool) {
    let cap = c.keys.len / 2usize
    let node = arc_find(c, key)
    if node != NONE {
        let l = c.list[usize(node)]
        if l == 1u8 || l == 2u8 {
            arc_unlink(c, node)
            arc_push(c, node, 2u8)
            ret (true, 0u64, false)
        }
        if l == 3u8 {
            var delta = c.b2 / c.b1
            if delta < 1usize { delta = 1usize }
            c.p += delta
            if c.p > cap { c.p = cap }
        } else {
            var delta = c.b1 / c.b2
            if delta < 1usize { delta = 1usize }
            if c.p > delta { c.p -= delta } else { c.p = 0usize }
        }
        let (ghost_evicted, ghost_did) = arc_replace(c, l == 4u8)
        arc_unlink(c, node)
        arc_push(c, node, 2u8)
        ret (false, ghost_evicted, ghost_did)
    }
    var evicted = 0u64
    var did_evict = false
    let l1 = c.t1 + c.b1
    let l2 = c.t2 + c.b2
    if l1 == cap {
        if c.t1 < cap {
            arc_release(c, arc_lru(c, 3u8))
            let (e1, d1) = arc_replace(c, false)
            evicted = e1
            did_evict = d1
        } else {
            let victim = arc_lru(c, 1u8)
            evicted = c.keys[usize(victim)]
            did_evict = true
            arc_release(c, victim)
        }
    } else if l1 + l2 >= cap {
        if l1 + l2 == 2usize * cap { arc_release(c, arc_lru(c, 4u8)) }
        let (e2, d2) = arc_replace(c, false)
        evicted = e2
        did_evict = d2
    }
    let fresh = c.free
    c.free = c.next[usize(fresh)]
    c.keys[usize(fresh)] = key
    arc_push(c, fresh, 1u8)
    ret (false, evicted, did_evict)
}

// Resident entries (T1 plus T2).
fn arc_len(c: *const Arc) -> usize { ret c.t1 + c.t2 }

// The adaptive target for T1's size, in `0..=capacity`.
fn arc_p(c: *const Arc) -> usize { ret c.p }

// Whether `key` is resident (ghosts do not count).
fn arc_contains(c: *const Arc, key: u64) -> bool {
    let node = arc_find(c, key)
    ret node != NONE && c.list[usize(node)] <= 2u8
}

// Hits over accesses; 0 when nothing was accessed.
fn hit_rate(hits: u64, accesses: u64) -> f64 {
    if accesses == 0u64 { ret 0.0f64 }
    ret f64(hits) / f64(accesses)
}
