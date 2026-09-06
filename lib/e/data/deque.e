// Arena-grown double-ended queues.

use e.mem

type Deque[T: type] = struct { items: []T, head: usize, len: usize, arena: *mem.Arena }
type Iter[T: type] = struct { deque: *const Deque[T], index: usize }

fn init[T: type](a: *mem.Arena, capacity: usize) -> (Deque[T], err) {
    var items: []T = zero
    if capacity != 0usize {
        let (allocated, allocation_error) = mem.alloc[T](a, capacity)
        if allocation_error != ok { ret (zero, allocation_error) }
        items = allocated
    }
    ret (Deque[T] { items: items, head: 0usize, len: 0usize, arena: a }, ok)
}

fn len[T: type](d: *const Deque[T]) -> usize { ret d.len }

fn reserve[T: type](d: *Deque[T], capacity: usize) -> err {
    if capacity <= d.items.len { ret ok }
    let (items, allocation_error) = mem.alloc[T](d.arena, capacity)
    if allocation_error != ok { ret allocation_error }
    var at = 0usize
    while at < d.len {
        items[at] = d.items[(d.head + at) % d.items.len]
        at += 1usize
    }
    d.items = items
    d.head = 0usize
    ret ok
}

fn push_front[T: type](d: *Deque[T], v: T) -> err {
    if d.len == d.items.len {
        var next_capacity = 1usize
        if d.items.len != 0usize { next_capacity = d.items.len * 2usize }
        try reserve[T](d, next_capacity)
    }
    if d.head == 0usize { d.head = d.items.len }
    d.head -= 1usize
    d.items[d.head] = v
    d.len += 1usize
    ret ok
}

fn push_back[T: type](d: *Deque[T], v: T) -> err {
    if d.len == d.items.len {
        var next_capacity = 1usize
        if d.items.len != 0usize { next_capacity = d.items.len * 2usize }
        try reserve[T](d, next_capacity)
    }
    let at = (d.head + d.len) % d.items.len
    d.items[at] = v
    d.len += 1usize
    ret ok
}

fn pop_front[T: type](d: *Deque[T]) -> (T, bool) {
    if d.len == 0usize { ret (zero, false) }
    let value = d.items[d.head]
    d.head = (d.head + 1usize) % d.items.len
    d.len -= 1usize
    if d.len == 0usize { d.head = 0usize }
    ret (value, true)
}

fn pop_back[T: type](d: *Deque[T]) -> (T, bool) {
    if d.len == 0usize { ret (zero, false) }
    let at = (d.head + d.len - 1usize) % d.items.len
    let value = d.items[at]
    d.len -= 1usize
    if d.len == 0usize { d.head = 0usize }
    ret (value, true)
}

fn get[T: type](d: *const Deque[T], index: usize) -> T {
    if index >= d.len { ret d.items[d.items.len] }
    ret d.items[(d.head + index) % d.items.len]
}

fn clear[T: type](d: *Deque[T]) {
    d.head = 0usize
    d.len = 0usize
}

fn iter[T: type](d: *const Deque[T]) -> Iter[T] {
    ret Iter[T] { deque: d, index: 0usize }
}

fn iter_next[T: type](it: *Iter[T]) -> (T, bool) {
    if it.index >= it.deque.len { ret (zero, false) }
    let value = it.deque.items[(it.deque.head + it.index) % it.deque.items.len]
    it.index += 1usize
    ret (value, true)
}
