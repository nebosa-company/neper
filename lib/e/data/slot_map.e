// Stable handles over fixed, caller-funded storage. A `Key` is a slot and the
// generation the slot had when the value went in; removal bumps the generation, so a
// stale key answers nothing rather than someone else's value. A slot whose next
// generation would wrap is retired for good -- a generation never wraps -- which is
// what keeps every key that was ever issued distinct.

use e.mem

type Key = struct { slot: u32, generation: u32 }
type SlotMap[T: type] = struct { state: *void }
type Iter[T: type] = struct { state: *const void, slot: u32 }
error Full
error TooLarge

// `next_free` chains the free slots; `NO_SLOT` ends the chain, and a retired slot is
// on no chain at all.
type State[T: type] = struct { values: []T, generations: []u32, live: []bool, next_free: []u32, free_head: u32, len: usize }

const NO_SLOT: u32 = 4294967295u32
const LAST_GENERATION: u32 = 4294967295u32

fn init[T: type](a: *mem.Arena, initial_capacity: usize) -> (SlotMap[T], err) {
    var empty: SlotMap[T] = zero
    if initial_capacity >= usize(NO_SLOT) { ret (empty, TooLarge) }
    let (storage, storage_error) = mem.alloc[State[T]](a, 1usize)
    if storage_error != ok { ret (empty, storage_error) }
    let (values, values_error) = mem.alloc[T](a, initial_capacity)
    if values_error != ok { ret (empty, values_error) }
    let (generations, generations_error) = mem.alloc[u32](a, initial_capacity)
    if generations_error != ok { ret (empty, generations_error) }
    let (live, live_error) = mem.alloc[bool](a, initial_capacity)
    if live_error != ok { ret (empty, live_error) }
    let (next_free, next_free_error) = mem.alloc[u32](a, initial_capacity)
    if next_free_error != ok { ret (empty, next_free_error) }
    storage[0usize] = State[T] { values: values, generations: generations, live: live, next_free: next_free, free_head: NO_SLOT, len: 0usize }
    thread_free[T](&storage[0usize])
    ret (SlotMap[T] { state: mem.cast[*void](&storage[0usize]) }, ok)
}

// Every slot onto the free chain in order, generation 0, nothing live.
fn thread_free[T: type](s: *State[T]) {
    var at = s.values.len
    s.free_head = NO_SLOT
    while at > 0usize {
        at -= 1usize
        s.generations[at] = 0u32
        s.live[at] = false
        s.next_free[at] = s.free_head
        s.free_head = u32(at)
    }
    s.len = 0usize
}

fn len[T: type](m: *const SlotMap[T]) -> usize {
    let s = mem.cast[*const State[T]](m.state)
    ret s.len
}

fn capacity[T: type](m: *const SlotMap[T]) -> usize {
    let s = mem.cast[*const State[T]](m.state)
    ret s.values.len
}

fn insert[T: type](m: *SlotMap[T], value: T) -> (Key, err) {
    let s = mem.cast[*State[T]](m.state)
    if s.free_head == NO_SLOT { ret (zero, Full) }
    let slot = s.free_head
    s.free_head = s.next_free[usize(slot)]
    s.values[usize(slot)] = value
    s.live[usize(slot)] = true
    s.len += 1usize
    ret (Key { slot: slot, generation: s.generations[usize(slot)] }, ok)
}

fn holds[T: type](s: *const State[T], key: Key) -> bool {
    if usize(key.slot) >= s.values.len { ret false }
    ret s.live[usize(key.slot)] && s.generations[usize(key.slot)] == key.generation
}

fn get[T: type](m: *const SlotMap[T], key: Key) -> (*const T, bool) {
    let s = mem.cast[*const State[T]](m.state)
    if !holds[T](s, key) { ret (zero, false) }
    ret (&s.values[usize(key.slot)], true)
}

fn get_mut[T: type](m: *SlotMap[T], key: Key) -> (*T, bool) {
    let s = mem.cast[*State[T]](m.state)
    if !holds[T](s, key) { ret (zero, false) }
    ret (&s.values[usize(key.slot)], true)
}

// The slot goes back on the free chain with the next generation, unless that would
// wrap, in which case it is retired.
fn remove[T: type](m: *SlotMap[T], key: Key) -> (T, bool) {
    let s = mem.cast[*State[T]](m.state)
    if !holds[T](s, key) { ret (zero, false) }
    let at = usize(key.slot)
    let value = s.values[at]
    s.live[at] = false
    s.len -= 1usize
    if s.generations[at] != LAST_GENERATION {
        s.generations[at] += 1u32
        s.next_free[at] = s.free_head
        s.free_head = key.slot
    }
    ret (value, true)
}

// Every key issued so far is invalid afterwards: each live slot's generation moves on
// (or the slot retires), and the free chain is rebuilt over what is left.
fn clear[T: type](m: *SlotMap[T]) {
    let s = mem.cast[*State[T]](m.state)
    var at = 0usize
    while at < s.values.len {
        if s.live[at] {
            s.live[at] = false
            if s.generations[at] != LAST_GENERATION { s.generations[at] += 1u32 }
        }
        at += 1usize
    }
    s.free_head = NO_SLOT
    at = s.values.len
    while at > 0usize {
        at -= 1usize
        if s.generations[at] != LAST_GENERATION {
            s.next_free[at] = s.free_head
            s.free_head = u32(at)
        }
    }
    s.len = 0usize
}

fn iter[T: type](m: *const SlotMap[T]) -> Iter[T] {
    ret Iter[T] { state: mem.cast[*const void](m.state), slot: 0u32 }
}

fn iter_next[T: type](it: *Iter[T]) -> (Key, T, bool) {
    let s = mem.cast[*const State[T]](it.state)
    while usize(it.slot) < s.values.len {
        let at = usize(it.slot)
        it.slot += 1u32
        if s.live[at] { ret (Key { slot: u32(at), generation: s.generations[at] }, s.values[at], true) }
    }
    ret (zero, zero, false)
}
