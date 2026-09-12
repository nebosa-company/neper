// A fixed-capacity hash map sharded by the key's hash, each shard an open-addressed
// table of its own under its own mutex, so operations on different shards never
// wait on each other and one on the same shard is linearizable by the lock. A key's
// shard is the top bits of `K.hash`; its slot is the low bits, probed linearly.
// Capacity is split evenly across the shards and a new key into a full shard is
// `Full` -- the map is fixed, and "full" is the shard's fullness, which is what a
// caller sizing `capacity` should expect. `len` sums the shards one after another.
// After `close` every operation is `Closed`. Zero capacity or shards is `Invalid`.
use e.mem
use e.sync

type Map[K: type, V: type] = struct { state: *void }
error Closed
error Full
error Invalid

const EMPTY: u8 = 0u8
const FULL_MARK: u8 = 1u8
const DEAD: u8 = 2u8

type Shard[K: type, V: type] = struct { lock: sync.Mutex, keys: []K, values: []V, marks: []u8, count: usize, used: usize }
type State[K: type, V: type] = struct { shards: []Shard[K, V], closed: bool, slots_per_shard: usize }

fn init[K: type, V: type](a: *mem.Arena, capacity: usize, shards: u16) -> (Map[K, V], err) {
    if capacity == 0usize || shards == 0u16 { ret (zero, Invalid) }
    let (storage, storage_error) = mem.alloc[State[K, V]](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    let (table, table_error) = mem.alloc[Shard[K, V]](a, usize(shards))
    if table_error != ok { ret (zero, table_error) }
    // Each shard holds its share of the capacity at a load under three quarters.
    var per_shard = (capacity + usize(shards) - 1usize) / usize(shards)
    var slots = 4usize
    while slots * 3usize < per_shard * 4usize { slots = slots * 2usize }
    var i = 0usize
    while i < usize(shards) {
        let (keys, keys_error) = mem.alloc[K](a, slots)
        if keys_error != ok { ret (zero, keys_error) }
        let (values, values_error) = mem.alloc[V](a, slots)
        if values_error != ok { ret (zero, values_error) }
        let (marks, marks_error) = mem.alloc[u8](a, slots)
        if marks_error != ok { ret (zero, marks_error) }
        var j = 0usize
        while j < slots {
            marks[j] = EMPTY
            j += 1usize
        }
        table[i].lock = sync.mutex()
        table[i].keys = keys
        table[i].values = values
        table[i].marks = marks
        table[i].count = 0usize
        table[i].used = 0usize
        i += 1usize
    }
    storage[0].shards = table
    storage[0].closed = false
    storage[0].slots_per_shard = per_shard
    var m: Map[K, V] = zero
    m.state = mem.cast[*void](&storage[0])
    ret (m, ok)
}

// The shard and the probe start for a key.
fn locate[K: type, V: type](s: *State[K, V], key: K) -> (usize, usize) {
    let digest: u64 = K.hash(key)
    let shard = usize(digest >> 32u32) % s.shards.len
    let slot = usize(digest & 4294967295u64) & (s.shards[shard].marks.len - 1usize)
    ret (shard, slot)
}

// The slot holding `key`, or where it would go: (slot, found).
fn probe[K: type, V: type](shard: *Shard[K, V], start: usize, key: K) -> (usize, bool) {
    let mask = shard.marks.len - 1usize
    var at = start
    var hole = 0usize
    var has_hole = false
    var walked = 0usize
    while walked < shard.marks.len {
        let mark = shard.marks[at]
        if mark == EMPTY {
            if has_hole { ret (hole, false) }
            ret (at, false)
        }
        if mark == FULL_MARK {
            if K.eq(shard.keys[at], key) { ret (at, true) }
        } else {
            if !has_hole {
                hole = at
                has_hole = true
            }
        }
        at = (at + 1usize) & mask
        walked += 1usize
    }
    ret (hole, false)
}

fn get[K: type, V: type](m: *const Map[K, V], key: K) -> (V, bool, err) {
    let s = mem.cast[*State[K, V]](m.state)
    if s.closed { ret (zero, false, Closed) }
    let (index, start) = locate[K, V](s, key)
    let shard = &s.shards[index]
    sync.mutex_lock(&shard.lock)
    let (slot, found) = probe[K, V](shard, start, key)
    var value: V = zero
    if found { value = shard.values[slot] }
    sync.mutex_unlock(&shard.lock)
    ret (value, found, ok)
}

// True when the key was new; a present key takes the value and answers false.
fn put[K: type, V: type](m: *Map[K, V], key: K, value: V) -> (bool, err) {
    let s = mem.cast[*State[K, V]](m.state)
    if s.closed { ret (false, Closed) }
    let (index, start) = locate[K, V](s, key)
    let shard = &s.shards[index]
    sync.mutex_lock(&shard.lock)
    let (slot, found) = probe[K, V](shard, start, key)
    if found {
        shard.values[slot] = value
        sync.mutex_unlock(&shard.lock)
        ret (false, ok)
    }
    if shard.count >= s.slots_per_shard || shard.used + 1usize > shard.marks.len * 3usize / 4usize {
        sync.mutex_unlock(&shard.lock)
        ret (false, Full)
    }
    if shard.marks[slot] == EMPTY { shard.used += 1usize }
    shard.keys[slot] = key
    shard.values[slot] = value
    shard.marks[slot] = FULL_MARK
    shard.count += 1usize
    sync.mutex_unlock(&shard.lock)
    ret (true, ok)
}

fn remove[K: type, V: type](m: *Map[K, V], key: K) -> (V, bool, err) {
    let s = mem.cast[*State[K, V]](m.state)
    if s.closed { ret (zero, false, Closed) }
    let (index, start) = locate[K, V](s, key)
    let shard = &s.shards[index]
    sync.mutex_lock(&shard.lock)
    let (slot, found) = probe[K, V](shard, start, key)
    var value: V = zero
    if found {
        value = shard.values[slot]
        shard.marks[slot] = DEAD
        shard.count -= 1usize
    }
    sync.mutex_unlock(&shard.lock)
    ret (value, found, ok)
}

fn len[K: type, V: type](m: *const Map[K, V]) -> (usize, err) {
    let s = mem.cast[*State[K, V]](m.state)
    if s.closed { ret (0usize, Closed) }
    var total = 0usize
    var i = 0usize
    while i < s.shards.len {
        let shard = &s.shards[i]
        sync.mutex_lock(&shard.lock)
        total += shard.count
        sync.mutex_unlock(&shard.lock)
        i += 1usize
    }
    ret (total, ok)
}

fn close[K: type, V: type](m: *Map[K, V]) -> err {
    let s = mem.cast[*State[K, V]](m.state)
    if s.closed { ret Closed }
    s.closed = true
    ret ok
}
