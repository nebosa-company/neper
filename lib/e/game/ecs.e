// The entity store (D249): slots with generations, and components in parallel columns.
//
// An `Entity` is a slot and the generation that slot held when it was handed out, so a
// handle kept across a despawn is detectably stale rather than quietly pointing at
// whoever moved in. A generation is odd while its slot is live and even once it is free,
// which makes `alive` one comparison and needs no separate table.
//
// Every buffer is the caller's. The store allocates nothing, so its capacity is whatever
// was handed to `init` and a full store is an error rather than a surprise.

use e.mem

type Entity = struct {
    slot: u32,
    generation: u32,
}

// One component type: `stride` bytes per slot in `bytes`, and a bit per slot in
// `present` saying whether this slot has one.
type Column = struct {
    id: u16,
    stride: usize,
    bytes: []u8,
    present: []u64,
}

type Store = struct {
    columns: []Column,
    generations: []u32,
    free: []u32,
    count: usize,
    free_count: usize,
}

type Query = struct {
    store: *Store,
    ids: []const u16,
    at: usize,
}

error Full
error Unknown
error Stale
error Size

fn init(s: *Store, columns: []Column, generations: []u32, free: []u32) -> err {
    var at = 0usize
    while at < generations.len {
        generations[at] = 0u32
        at += 1usize
    }
    at = 0usize
    while at < columns.len {
        if columns[at].stride == 0usize { ret Size }
        if columns[at].bytes.len < columns[at].stride * generations.len { ret Size }
        if columns[at].present.len < (generations.len + 63usize) / 64usize { ret Size }
        var word = 0usize
        while word < columns[at].present.len {
            columns[at].present[word] = 0u64
            word += 1usize
        }
        at += 1usize
    }
    s.columns = columns
    s.generations = generations
    s.free = free
    s.count = 0usize
    s.free_count = 0usize
    ret ok
}

fn bit_set(words: []u64, index: usize) {
    words[index / 64usize] = words[index / 64usize] | (1u64 << u32(index % 64usize))
}

fn bit_clear(words: []u64, index: usize) {
    words[index / 64usize] = words[index / 64usize] & ~(1u64 << u32(index % 64usize))
}

fn bit_test(words: []const u64, index: usize) -> bool {
    ret (words[index / 64usize] & (1u64 << u32(index % 64usize))) != 0u64
}

fn column_of(s: Store, id: u16) -> (usize, bool) {
    var at = 0usize
    while at < s.columns.len {
        if s.columns[at].id == id { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// A freed slot is reused before a fresh one is taken, so a long run of spawns and
// despawns stays inside the slots it has rather than walking off the end.
fn spawn(s: *Store) -> (Entity, err) {
    var slot = 0usize
    if s.free_count > 0usize {
        s.free_count = s.free_count - 1usize
        slot = usize(s.free[s.free_count])
    } else {
        if s.count == s.generations.len { ret (Entity { slot: 0u32, generation: 0u32 }, Full) }
        slot = s.count
        s.count = s.count + 1usize
    }
    s.generations[slot] = s.generations[slot] + 1u32
    ret (Entity { slot: u32(slot), generation: s.generations[slot] }, ok)
}

fn alive(s: Store, e: Entity) -> bool {
    if usize(e.slot) >= s.count { ret false }
    if s.generations[usize(e.slot)] != e.generation { ret false }
    ret e.generation % 2u32 == 1u32
}

fn despawn(s: *Store, e: Entity) -> err {
    if !alive(*s, e) { ret Stale }
    let slot = usize(e.slot)
    var at = 0usize
    while at < s.columns.len {
        bit_clear(s.columns[at].present, slot)
        at += 1usize
    }
    s.generations[slot] = s.generations[slot] + 1u32
    if s.free_count < s.free.len {
        s.free[s.free_count] = e.slot
        s.free_count = s.free_count + 1usize
    }
    ret ok
}

fn attach(s: *Store, e: Entity, id: u16, value: []const u8) -> err {
    if !alive(*s, e) { ret Stale }
    let (index, found) = column_of(*s, id)
    if !found { ret Unknown }
    let stride = s.columns[index].stride
    if value.len != stride { ret Size }
    let base = usize(e.slot) * stride
    var at = 0usize
    while at < stride {
        s.columns[index].bytes[base + at] = value[at]
        at += 1usize
    }
    bit_set(s.columns[index].present, usize(e.slot))
    ret ok
}

fn detach(s: *Store, e: Entity, id: u16) -> err {
    if !alive(*s, e) { ret Stale }
    let (index, found) = column_of(*s, id)
    if !found { ret Unknown }
    bit_clear(s.columns[index].present, usize(e.slot))
    ret ok
}

fn has(s: Store, e: Entity, id: u16) -> bool {
    if !alive(s, e) { ret false }
    let (index, found) = column_of(s, id)
    if !found { ret false }
    ret bit_test(s.columns[index].present, usize(e.slot))
}

// The component's own bytes, written in place: there is no copy out and back.
fn get(s: Store, e: Entity, id: u16) -> ([]u8, err) {
    var empty: []u8 = zero
    if !alive(s, e) { ret (empty, Stale) }
    let (index, found) = column_of(s, id)
    if !found { ret (empty, Unknown) }
    if !bit_test(s.columns[index].present, usize(e.slot)) { ret (empty, Unknown) }
    let stride = s.columns[index].stride
    let base = usize(e.slot) * stride
    ret (s.columns[index].bytes[base..base + stride], ok)
}

fn query(s: *Store, ids: []const u16) -> Query {
    ret Query { store: s, ids: ids, at: 0usize }
}

// Walks slots in order, so a query answers the same sequence on every machine.
fn next(q: *Query) -> (Entity, bool) {
    while q.at < q.store.count {
        let slot = q.at
        q.at = q.at + 1usize
        let generation = q.store.generations[slot]
        if generation % 2u32 == 1u32 {
            let candidate = Entity { slot: u32(slot), generation: generation }
            var matched = true
            var at = 0usize
            while at < q.ids.len {
                let (index, found) = column_of(*q.store, q.ids[at])
                if !found || !bit_test(q.store.columns[index].present, slot) { matched = false }
                at += 1usize
            }
            if matched { ret (candidate, true) }
        }
    }
    ret (Entity { slot: 0u32, generation: 0u32 }, false)
}

fn live_count(s: Store) -> usize {
    var total = 0usize
    var slot = 0usize
    while slot < s.count {
        if s.generations[slot] % 2u32 == 1u32 { total += 1usize }
        slot += 1usize
    }
    ret total
}
