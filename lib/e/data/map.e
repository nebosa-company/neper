// A hash map with open addressing and linear probing, keyed by whatever has a `hash` and an
// `eq` -- which section 9 rule 4 gives every scalar, slice, array and enum, and a struct gets
// by declaring them. `Set[K]` is `Map[K, bool]` with the value left out of the surface.
//
// The table is three parallel arrays -- keys, values and one mark byte per slot -- so a probe
// touches the marks first and the keys only where a mark says one is there. Capacity is a
// power of two and the load stays under three quarters, counting the slots a removal left
// behind as well as the live ones: a table whose dead slots were never counted would probe
// longer and longer while its `len` stayed small.
//
// ponytail: growth allocates a fresh table from the arena and abandons the old one, since an
// arena gives nothing back. A map that grows many times in one arena leaves each earlier table
// behind it; `reserve` up front is what avoids that, and a reclaiming allocator is the upgrade.

use e.mem

type Map[K: type, V: type] = struct { state: *void }
type Set[K: type] = struct { map: Map[K, bool] }
type Iter[K: type, V: type] = struct { state: *const void, slot: usize }
type SetIter[K: type] = struct { inner: Iter[K, bool] }

// A slot's mark. A removal leaves `DEAD` rather than `EMPTY` because a probe that stopped at
// the hole would never reach whatever was placed beyond it while the hole was full.
const EMPTY: u8 = 0u8
const FULL: u8 = 1u8
const DEAD: u8 = 2u8

const DEFAULT_CAPACITY: usize = 16usize

type State[K: type, V: type] = struct {
    arena: *mem.Arena,
    keys: []K,
    values: []V,
    marks: []u8,
    count: usize,
    used: usize,
}

// The smallest power of two that holds `entries` under the load limit, and never less than
// the default: a table of two would grow at its second entry.
fn table_size(entries: usize) -> usize {
    var size = DEFAULT_CAPACITY
    while size * 3usize < entries * 4usize + 4usize { size = size * 2usize }
    ret size
}

fn allocate_state[K: type, V: type](a: *mem.Arena, size: usize) -> (*State[K, V], err) {
    let (state, state_error) = mem.alloc[State[K, V]](a, 1usize)
    if state_error != ok { ret (zero, state_error) }
    let (keys, keys_error) = mem.alloc[K](a, size)
    if keys_error != ok { ret (zero, keys_error) }
    let (values, values_error) = mem.alloc[V](a, size)
    if values_error != ok { ret (zero, values_error) }
    let (marks, marks_error) = mem.alloc[u8](a, size)
    if marks_error != ok { ret (zero, marks_error) }
    var at = 0usize
    while at < size {
        marks[at] = EMPTY
        at += 1usize
    }
    state[0usize].arena = a
    state[0usize].keys = keys
    state[0usize].values = values
    state[0usize].marks = marks
    state[0usize].count = 0usize
    state[0usize].used = 0usize
    ret (&state[0usize], ok)
}

// Where `key` is, or where it would go. The probe runs from the hash until an empty slot, and
// answers the first dead slot it passed when the key is absent -- so an insertion reuses the
// hole nearest the key's home rather than lengthening every later probe.
fn locate[K: type, V: type](s: *const State[K, V], key: K) -> (usize, bool, usize, bool) {
    let mask = s.marks.len - 1usize
    let digest: u64 = K.hash(key)
    var at = usize(digest) & mask
    var hole = 0usize
    var has_hole = false
    var walked = 0usize
    while walked < s.marks.len {
        let mark = s.marks[at]
        if mark == EMPTY { ret (at, false, hole, has_hole) }
        if mark == FULL {
            if K.eq(s.keys[at], key) { ret (at, true, hole, has_hole) }
        } else {
            if !has_hole {
                hole = at
                has_hole = true
            }
        }
        at = (at + 1usize) & mask
        walked += 1usize
    }
    // Every slot is full or dead, which the load limit does not allow; the hole, if any, is
    // still the right answer for an insertion.
    ret (at, false, hole, has_hole)
}

// A new table of `size` slots with every live entry moved across. Dead slots are not copied,
// which is how a table that has churned gets its probe lengths back.
fn rehash[K: type, V: type](s: *State[K, V], size: usize) -> err {
    let (fresh, fresh_error) = allocate_state[K, V](s.arena, size)
    if fresh_error != ok { ret fresh_error }
    let mask = size - 1usize
    var at = 0usize
    while at < s.marks.len {
        if s.marks[at] == FULL {
            let digest: u64 = K.hash(s.keys[at])
            var slot = usize(digest) & mask
            while fresh.marks[slot] != EMPTY { slot = (slot + 1usize) & mask }
            fresh.keys[slot] = s.keys[at]
            fresh.values[slot] = s.values[at]
            fresh.marks[slot] = FULL
        }
        at += 1usize
    }
    fresh.count = s.count
    fresh.used = s.count
    // The handle points at this state, so the state takes the new table rather than the handle
    // taking a new state.
    s.keys = fresh.keys
    s.values = fresh.values
    s.marks = fresh.marks
    s.count = fresh.count
    s.used = fresh.used
    ret ok
}

fn init[K: type, V: type](a: *mem.Arena, capacity: usize) -> (Map[K, V], err) {
    let (state, state_error) = allocate_state[K, V](a, table_size(capacity))
    if state_error != ok { ret (zero, state_error) }
    ret (Map[K, V] { state: mem.cast[*void](state) }, ok)
}

fn len[K: type, V: type](m: *const Map[K, V]) -> usize {
    let s = mem.cast[*const State[K, V]](m.state)
    ret s.count
}

// Room for `capacity` entries in all without growing, counting what is already there.
fn reserve[K: type, V: type](m: *Map[K, V], capacity: usize) -> err {
    let s = mem.cast[*State[K, V]](m.state)
    var wanted = capacity
    if s.used > wanted { wanted = s.used }
    let size = table_size(wanted)
    if size <= s.marks.len { ret ok }
    ret rehash[K, V](s, size)
}

// `true` when the key was not there before. A key that was keeps its slot and takes the new
// value, so a map's iteration order does not change under updates.
fn put[K: type, V: type](m: *Map[K, V], key: K, value: V) -> (bool, err) {
    let s = mem.cast[*State[K, V]](m.state)
    let (found_at, found, hole, has_hole) = locate[K, V](s, key)
    if found {
        s.values[found_at] = value
        ret (false, ok)
    }
    var at = found_at
    if has_hole {
        at = hole
    } else {
        // A fresh slot is taken, so the load is checked before it is: past three quarters the
        // table doubles and the key is placed in the new one.
        if (s.used + 1usize) * 4usize > s.marks.len * 3usize {
            let grow_error = rehash[K, V](s, s.marks.len * 2usize)
            if grow_error != ok { ret (false, grow_error) }
            let (again_at, again_found, again_hole, again_has_hole) = locate[K, V](s, key)
            at = again_at
        }
        s.used += 1usize
    }
    s.keys[at] = key
    s.values[at] = value
    s.marks[at] = FULL
    s.count += 1usize
    ret (true, ok)
}

fn get[K: type, V: type](m: *const Map[K, V], key: K) -> (V, bool) {
    let s = mem.cast[*const State[K, V]](m.state)
    let (at, found, hole, has_hole) = locate[K, V](s, key)
    if !found { ret (zero, false) }
    ret (s.values[at], true)
}

// A pointer into the table, good until the next `put` that grows it or `remove` of this key.
fn get_ptr[K: type, V: type](m: *Map[K, V], key: K) -> (*V, bool) {
    let s = mem.cast[*State[K, V]](m.state)
    let (at, found, hole, has_hole) = locate[K, V](s, key)
    if !found { ret (zero, false) }
    ret (&s.values[at], true)
}

fn remove[K: type, V: type](m: *Map[K, V], key: K) -> (V, bool) {
    let s = mem.cast[*State[K, V]](m.state)
    let (at, found, hole, has_hole) = locate[K, V](s, key)
    if !found { ret (zero, false) }
    let taken = s.values[at]
    s.marks[at] = DEAD
    s.count -= 1usize
    ret (taken, true)
}

// Every slot empty again, the table kept: a map that is cleared is usually about to be filled
// to the same size.
fn clear[K: type, V: type](m: *Map[K, V]) {
    let s = mem.cast[*State[K, V]](m.state)
    var at = 0usize
    while at < s.marks.len {
        s.marks[at] = EMPTY
        at += 1usize
    }
    s.count = 0usize
    s.used = 0usize
}

fn set_init[K: type](a: *mem.Arena, capacity: usize) -> (Set[K], err) {
    let (inner, inner_error) = init[K, bool](a, capacity)
    if inner_error != ok { ret (zero, inner_error) }
    ret (Set[K] { map: inner }, ok)
}

fn set_add[K: type](s: *Set[K], key: K) -> (bool, err) {
    let (added, add_error) = put[K, bool](&s.map, key, true)
    ret (added, add_error)
}

fn set_has[K: type](s: *const Set[K], key: K) -> bool {
    let (held, present) = get[K, bool](&s.map, key)
    ret present
}

fn set_remove[K: type](s: *Set[K], key: K) -> bool {
    let (held, present) = remove[K, bool](&s.map, key)
    ret present
}

// Iteration is in slot order, which is no order a caller should read anything into; what it
// promises is every live entry once, and the same sequence twice over an unchanged map.
fn iter[K: type, V: type](m: *const Map[K, V]) -> Iter[K, V] {
    ret Iter[K, V] { state: mem.cast[*const void](m.state), slot: 0usize }
}

fn iter_next[K: type, V: type](it: *Iter[K, V]) -> (K, V, bool) {
    let s = mem.cast[*const State[K, V]](it.state)
    while it.slot < s.marks.len {
        let at = it.slot
        it.slot += 1usize
        if s.marks[at] == FULL { ret (s.keys[at], s.values[at], true) }
    }
    ret (zero, zero, false)
}

fn set_iter[K: type](s: *const Set[K]) -> SetIter[K] {
    ret SetIter[K] { inner: iter[K, bool](&s.map) }
}

fn set_iter_next[K: type](it: *SetIter[K]) -> (K, bool) {
    let (key, held, more) = iter_next[K, bool](&it.inner)
    ret (key, more)
}
