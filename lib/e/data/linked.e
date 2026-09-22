// A doubly linked list whose nodes live in one arena-grown `list.List`, addressed by
// index rather than pointer: growth moves the storage but not the identities, and a
// removed slot is never reused, so a `NodeId` stays valid exactly as long as its node
// is live and answers `InvalidNode` forever after.

use e.mem
use e.data.list as list

type NodeId = u32
const NONE: NodeId = 4294967295
type Node[T: type] = struct { value: T, previous: NodeId, next: NodeId, live: bool }
type List[T: type] = struct { nodes: list.List[Node[T]], first: NodeId, last: NodeId, len: usize }
type Iter[T: type] = struct { list: *const List[T], next: NodeId }
error InvalidNode
error TooLarge

fn init[T: type](a: *mem.Arena, capacity: usize) -> (List[T], err) {
    let (nodes, init_error) = list.init[Node[T]](a, capacity)
    if init_error != ok { ret (zero, init_error) }
    var result: List[T] = zero
    result.nodes = nodes
    result.first = NONE
    result.last = NONE
    ret (result, ok)
}

fn len[T: type](l: *const List[T]) -> usize { ret l.len }

fn first[T: type](l: *const List[T]) -> (NodeId, bool) { ret (l.first, l.first != NONE) }

fn last[T: type](l: *const List[T]) -> (NodeId, bool) { ret (l.last, l.last != NONE) }

fn node[T: type](l: *const List[T], id: NodeId) -> (*const Node[T], err) {
    if usize(id) >= l.nodes.len || !l.nodes.items[usize(id)].live { ret (zero, InvalidNode) }
    ret (&l.nodes.items[usize(id)], ok)
}

// A fresh node at the end of the storage, linked to nothing yet.
fn allocate[T: type](l: *List[T], value: T) -> (NodeId, err) {
    if l.nodes.len >= usize(NONE) { ret (NONE, TooLarge) }
    var fresh: Node[T] = zero
    fresh.value = value
    fresh.previous = NONE
    fresh.next = NONE
    fresh.live = true
    var push_error: err = ok
    push_error = list.push[Node[T]](&l.nodes, fresh)
    if push_error != ok { ret (NONE, push_error) }
    ret (u32(l.nodes.len - 1usize), ok)
}

fn push_front[T: type](l: *List[T], value: own T) -> (NodeId, err) {
    if l.first == NONE {
        let (id, allocate_error) = allocate[T](l, value)
        if allocate_error != ok { ret (NONE, allocate_error) }
        l.first = id
        l.last = id
        l.len = 1usize
        ret (id, ok)
    }
    let (id, insert_error) = insert_before[T](l, l.first, value)
    ret (id, insert_error)
}

fn push_back[T: type](l: *List[T], value: own T) -> (NodeId, err) {
    if l.last == NONE {
        let (id, push_error) = push_front[T](l, value)
        ret (id, push_error)
    }
    let (id, insert_error) = insert_after[T](l, l.last, value)
    ret (id, insert_error)
}

fn insert_before[T: type](l: *List[T], at: NodeId, value: own T) -> (NodeId, err) {
    if usize(at) >= l.nodes.len || !l.nodes.items[usize(at)].live { ret (NONE, InvalidNode) }
    let (id, allocate_error) = allocate[T](l, value)
    if allocate_error != ok { ret (NONE, allocate_error) }
    let before = l.nodes.items[usize(at)].previous
    l.nodes.items[usize(id)].previous = before
    l.nodes.items[usize(id)].next = at
    l.nodes.items[usize(at)].previous = id
    if before == NONE {
        l.first = id
    } else {
        l.nodes.items[usize(before)].next = id
    }
    l.len += 1usize
    ret (id, ok)
}

fn insert_after[T: type](l: *List[T], at: NodeId, value: own T) -> (NodeId, err) {
    if usize(at) >= l.nodes.len || !l.nodes.items[usize(at)].live { ret (NONE, InvalidNode) }
    let (id, allocate_error) = allocate[T](l, value)
    if allocate_error != ok { ret (NONE, allocate_error) }
    let after = l.nodes.items[usize(at)].next
    l.nodes.items[usize(id)].previous = at
    l.nodes.items[usize(id)].next = after
    l.nodes.items[usize(at)].next = id
    if after == NONE {
        l.last = id
    } else {
        l.nodes.items[usize(after)].previous = id
    }
    l.len += 1usize
    ret (id, ok)
}

fn remove[T: type](l: *List[T], id: NodeId) -> (T, err) {
    if usize(id) >= l.nodes.len || !l.nodes.items[usize(id)].live { ret (zero, InvalidNode) }
    let removed = l.nodes.items[usize(id)]
    if removed.previous == NONE {
        l.first = removed.next
    } else {
        l.nodes.items[usize(removed.previous)].next = removed.next
    }
    if removed.next == NONE {
        l.last = removed.previous
    } else {
        l.nodes.items[usize(removed.next)].previous = removed.previous
    }
    l.nodes.items[usize(id)].live = false
    l.len -= 1usize
    ret (removed.value, ok)
}

// Every identifier issued so far is invalid afterwards; the storage is kept.
fn clear[T: type](l: *List[T]) {
    list.clear[Node[T]](&l.nodes)
    l.first = NONE
    l.last = NONE
    l.len = 0usize
}

fn iter[T: type](l: *const List[T]) -> Iter[T] {
    ret Iter[T] { list: l, next: l.first }
}

fn iter_next[T: type](it: *Iter[T]) -> (T, bool) {
    if it.next == NONE { ret (zero, false) }
    let current = it.list.nodes.items[usize(it.next)]
    it.next = current.next
    ret (current.value, true)
}

// Whether `to` follows `from` in the chain (`from == to` counts), and whether
// `stop` lies on the way -- the splice source range, and the check that its target
// is not inside it.
fn spans[T: type](l: *const List[T], from: NodeId, to: NodeId, stop: NodeId) -> (bool, bool) {
    var cursor = from
    var hits_stop = false
    while cursor != NONE {
        if cursor == stop { hits_stop = true }
        if cursor == to { ret (true, hits_stop) }
        cursor = l.nodes.items[usize(cursor)].next
    }
    ret (false, hits_stop)
}

// Moves the nodes `from..=to` of `src` into `dst` before `before` (`NONE`
// appends). When `dst` is `src` the nodes keep their identifiers and only four
// links change; across lists the values move and `src`'s identifiers die.
fn splice[T: type](dst: *List[T], before: NodeId, src: *List[T], from: NodeId, to: NodeId) -> err {
    if usize(from) >= src.nodes.len || !src.nodes.items[usize(from)].live { ret InvalidNode }
    if usize(to) >= src.nodes.len || !src.nodes.items[usize(to)].live { ret InvalidNode }
    if before != NONE && (usize(before) >= dst.nodes.len || !dst.nodes.items[usize(before)].live) { ret InvalidNode }
    let (reaches, hits_before) = spans[T](src, from, to, before)
    if !reaches { ret InvalidNode }
    if dst != src {
        var cursor = from
        var moving = true
        while moving {
            let step = src.nodes.items[usize(cursor)].next
            let (value, remove_error) = remove[T](src, cursor)
            if remove_error != ok { ret remove_error }
            var insert_error: err = ok
            if before == NONE {
                let (_, e) = push_back[T](dst, value)
                insert_error = e
            } else {
                let (_, e) = insert_before[T](dst, before, value)
                insert_error = e
            }
            if insert_error != ok { ret insert_error }
            moving = cursor != to
            cursor = step
        }
        ret ok
    }
    if hits_before { ret InvalidNode }
    // Unlink the range from where it is ...
    let before_range = src.nodes.items[usize(from)].previous
    let after_range = src.nodes.items[usize(to)].next
    if before_range == NONE { src.first = after_range } else { src.nodes.items[usize(before_range)].next = after_range }
    if after_range == NONE { src.last = before_range } else { src.nodes.items[usize(after_range)].previous = before_range }
    // ... and link it in ahead of `before` (or at the end).
    var previous = dst.last
    if before != NONE { previous = dst.nodes.items[usize(before)].previous }
    dst.nodes.items[usize(from)].previous = previous
    dst.nodes.items[usize(to)].next = before
    if previous == NONE { dst.first = from } else { dst.nodes.items[usize(previous)].next = from }
    if before == NONE { dst.last = to } else { dst.nodes.items[usize(before)].previous = to }
    ret ok
}

// Whether `sub`'s values occur as one contiguous run of `l`'s (an empty `sub` does).
// ponytail: O(n * m) scan; a KMP over values if sublists get long.
fn contains_sublist[T: type](l: *const List[T], sub: *const List[T]) -> bool {
    if sub.first == NONE { ret true }
    var start = l.first
    while start != NONE {
        var cursor = start
        var want = sub.first
        while cursor != NONE && want != NONE && T.eq(l.nodes.items[usize(cursor)].value, sub.nodes.items[usize(want)].value) {
            cursor = l.nodes.items[usize(cursor)].next
            want = sub.nodes.items[usize(want)].next
        }
        if want == NONE { ret true }
        start = l.nodes.items[usize(start)].next
    }
    ret false
}

// The self-organising list: the first node equal to `value` moves to the front;
// answers the position it was found at (0 when already first) and whether it was.
fn move_to_front[T: type](l: *List[T], value: T) -> (usize, bool) {
    var position = 0usize
    var cursor = l.first
    while cursor != NONE && !T.eq(l.nodes.items[usize(cursor)].value, value) {
        cursor = l.nodes.items[usize(cursor)].next
        position += 1usize
    }
    if cursor == NONE { ret (0usize, false) }
    if position > 0usize {
        let e = splice[T](l, l.first, l, cursor, cursor)
        if e != ok { ret (position, false) }
    }
    ret (position, true)
}
