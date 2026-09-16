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
