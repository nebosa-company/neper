// Arena-grown contiguous lists.

use e.mem

type List[T: type] = struct { items: []T, len: usize, arena: *mem.Arena }
type Iter[T: type] = struct { items: []const T, index: usize }

fn init[T: type](a: *mem.Arena, capacity: usize) -> (List[T], err) {
    var items: []T = zero
    if capacity != 0usize {
        let (allocated, allocation_error) = mem.alloc[T](a, capacity)
        if allocation_error != ok { ret (zero, allocation_error) }
        items = allocated
    }
    ret (List[T] { items: items, len: 0usize, arena: a }, ok)
}

fn from_slice[T: type](a: *mem.Arena, src: []const T) -> (List[T], err) {
    let (initial, init_error) = init[T](a, src.len)
    if init_error != ok { ret (zero, init_error) }
    var result = initial
    var at = 0usize
    while at < src.len {
        result.items[at] = src[at]
        at += 1usize
    }
    result.len = src.len
    ret (result, ok)
}

fn slice[T: type](l: *List[T]) -> []T { ret l.items[..l.len] }

fn slice_const[T: type](l: *const List[T]) -> []const T { ret l.items[..l.len] }

fn reserve[T: type](l: *List[T], capacity: usize) -> err {
    if capacity <= l.items.len { ret ok }
    let (items, allocation_error) = mem.alloc[T](l.arena, capacity)
    if allocation_error != ok { ret allocation_error }
    var at = 0usize
    while at < l.len {
        items[at] = l.items[at]
        at += 1usize
    }
    l.items = items
    ret ok
}

fn push[T: type](l: *List[T], v: own T) -> err {
    if l.len == l.items.len {
        var next_capacity = 1usize
        if l.items.len != 0usize { next_capacity = l.items.len * 2usize }
        try reserve[T](l, next_capacity)
    }
    l.items[l.len] = v
    l.len += 1usize
    ret ok
}

fn pop[T: type](l: *List[T]) -> (T, bool) {
    if l.len == 0usize { ret (zero, false) }
    l.len -= 1usize
    ret (l.items[l.len], true)
}

fn insert[T: type](l: *List[T], index: usize, v: own T) -> err {
    if index > l.len {
        l.items[l.items.len] = v
        ret ok
    }
    if l.len == l.items.len {
        var next_capacity = 1usize
        if l.items.len != 0usize { next_capacity = l.items.len * 2usize }
        try reserve[T](l, next_capacity)
    }
    var at = l.len
    while at > index {
        l.items[at] = l.items[at - 1usize]
        at -= 1usize
    }
    l.items[index] = v
    l.len += 1usize
    ret ok
}

fn remove[T: type](l: *List[T], index: usize) -> T {
    if index >= l.len { ret l.items[l.items.len] }
    let value = l.items[index]
    var at = index
    while at + 1usize < l.len {
        l.items[at] = l.items[at + 1usize]
        at += 1usize
    }
    l.len -= 1usize
    ret value
}

fn clear[T: type](l: *List[T]) { l.len = 0usize }

fn iter[T: type](l: *const List[T]) -> Iter[T] {
    ret Iter[T] { items: l.items[..l.len], index: 0usize }
}

fn iter_next[T: type](it: *Iter[T]) -> (T, bool) {
    if it.index >= it.items.len { ret (zero, false) }
    let value = it.items[it.index]
    it.index += 1usize
    ret (value, true)
}
