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

// ---- build, then freeze (D1559, H02) ----------------------------------------
//
// A list that is built and then only read: `builder` makes a `Builder`, a resource
// owed to `freeze` or `builder_drop`, `build_push` grows it, and `freeze` consumes
// it and hands back the elements as a read-only slice. After the freeze the builder
// is moved, so growing it again is E-SAFETY-0001, and a builder neither frozen nor
// dropped is E-SAFETY-0002 at the exit that forgets it. The slice lives in the
// builder's arena, not in the builder, so it outlives the freeze.
type Builder[T: type] = resource(builder_drop) struct { list: List[T] }

fn builder[T: type](a: *mem.Arena, capacity: usize) -> (Builder[T], err) {
    let (made, made_error) = init[T](a, capacity)
    ret (Builder[T] { list: made }, made_error)
}

fn build_push[T: type](b: *Builder[T], v: own T) -> err {
    ret push[T](&b.list, v)
}

// The elements so far, read-only; the builder is its caller's to freeze or drop.
fn built[T: type](b: *const Builder[T]) -> []const T {
    ret b.list.items[..b.list.len]
}

// The audited hand-over: the builder ends and its elements stay in the arena.
@unsafe
fn freeze[T: type](b: own Builder[T]) -> []const T {
    ret b.list.items[..b.list.len]
}

// A builder given up without a freeze; its storage stays with the arena.
@unsafe
fn builder_drop[T: type](b: own Builder[T]) {
}
