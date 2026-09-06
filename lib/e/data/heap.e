// Binary min-heap. `Heap` orders by `T.cmp`; `HeapBy` orders by a comparison
// carried with the heap, which is what an ordering over borrowed context needs.
//
// Every module-scope declaration is exported (spec section 5), so the sift loops are
// written out at each site rather than factored into helpers that would widen the
// module's public surface beyond its frozen API.

use e.data.list
use e.mem

type Heap[T: type] = struct { items: list.List[T] }
type HeapBy[T: type, Ctx: type] = struct { items: list.List[T], ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32 }
type Iter[T: type] = struct { items: []const T, index: usize }

fn init[T: type](a: *mem.Arena, capacity: usize) -> (Heap[T], err) {
    let (items, items_error) = list.init[T](a, capacity)
    if items_error != ok { ret (zero, items_error) }
    ret (Heap[T] { items: items }, ok)
}

fn from_slice[T: type](a: *mem.Arena, source: []const T) -> (Heap[T], err) {
    let (items, items_error) = list.from_slice[T](a, source)
    if items_error != ok { ret (zero, items_error) }
    var result = Heap[T] { items: items }
    heapify_in_place[T](list.slice[T](&result.items))
    ret (result, ok)
}

fn len[T: type](h: *const Heap[T]) -> usize { ret h.items.len }

fn push[T: type](h: *Heap[T], v: T) -> err {
    try list.push[T](&h.items, v)
    let items = list.slice[T](&h.items)
    var at = items.len - 1usize
    while at != 0usize {
        let above = at - 1usize
        let parent = above / 2usize
        if T.cmp(items[at], items[parent]) >= 0i32 { break }
        let carried = items[at]
        items[at] = items[parent]
        items[parent] = carried
        at = parent
    }
    ret ok
}

fn peek[T: type](h: *const Heap[T]) -> (T, bool) {
    if h.items.len == 0usize { ret (zero, false) }
    let items = list.slice_const[T](&h.items)
    ret (items[0usize], true)
}

fn pop[T: type](h: *Heap[T]) -> (T, bool) {
    if h.items.len == 0usize { ret (zero, false) }
    let full = list.slice[T](&h.items)
    let smallest = full[0usize]
    full[0usize] = full[full.len - 1usize]
    let (discarded, popped) = list.pop[T](&h.items)
    if !popped { ret (zero, false) }
    let items = list.slice[T](&h.items)
    var at = 0usize
    while true {
        let left = at * 2usize + 1usize
        if left >= items.len { break }
        var next = left
        let right = left + 1usize
        if right < items.len && T.cmp(items[right], items[left]) < 0i32 { next = right }
        if T.cmp(items[next], items[at]) >= 0i32 { break }
        let carried = items[at]
        items[at] = items[next]
        items[next] = carried
        at = next
    }
    ret (smallest, true)
}

fn clear[T: type](h: *Heap[T]) { list.clear[T](&h.items) }

fn init_by[T: type, Ctx: type](a: *mem.Arena, capacity: usize, ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32) -> (HeapBy[T, Ctx], err) {
    let (items, items_error) = list.init[T](a, capacity)
    if items_error != ok { ret (zero, items_error) }
    ret (HeapBy[T, Ctx] { items: items, ctx: ctx, cmp: cmp }, ok)
}

fn from_slice_by[T: type, Ctx: type](a: *mem.Arena, source: []const T, ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32) -> (HeapBy[T, Ctx], err) {
    let (items, items_error) = list.from_slice[T](a, source)
    if items_error != ok { ret (zero, items_error) }
    var result = HeapBy[T, Ctx] { items: items, ctx: ctx, cmp: cmp }
    heapify_in_place_by[T, Ctx](list.slice[T](&result.items), ctx, cmp)
    ret (result, ok)
}

fn len_by[T: type, Ctx: type](h: *const HeapBy[T, Ctx]) -> usize { ret h.items.len }

fn push_by[T: type, Ctx: type](h: *HeapBy[T, Ctx], value: T) -> err {
    try list.push[T](&h.items, value)
    let items = list.slice[T](&h.items)
    var at = items.len - 1usize
    while at != 0usize {
        let above = at - 1usize
        let parent = above / 2usize
        if h.cmp(h.ctx, items[at], items[parent]) >= 0i32 { break }
        let carried = items[at]
        items[at] = items[parent]
        items[parent] = carried
        at = parent
    }
    ret ok
}

fn peek_by[T: type, Ctx: type](h: *const HeapBy[T, Ctx]) -> (T, bool) {
    if h.items.len == 0usize { ret (zero, false) }
    let items = list.slice_const[T](&h.items)
    ret (items[0usize], true)
}

fn pop_by[T: type, Ctx: type](h: *HeapBy[T, Ctx]) -> (T, bool) {
    if h.items.len == 0usize { ret (zero, false) }
    let full = list.slice[T](&h.items)
    let smallest = full[0usize]
    full[0usize] = full[full.len - 1usize]
    let (discarded, popped) = list.pop[T](&h.items)
    if !popped { ret (zero, false) }
    let items = list.slice[T](&h.items)
    var at = 0usize
    while true {
        let left = at * 2usize + 1usize
        if left >= items.len { break }
        var next = left
        let right = left + 1usize
        if right < items.len && h.cmp(h.ctx, items[right], items[left]) < 0i32 { next = right }
        if h.cmp(h.ctx, items[next], items[at]) >= 0i32 { break }
        let carried = items[at]
        items[at] = items[next]
        items[next] = carried
        at = next
    }
    ret (smallest, true)
}

fn clear_by[T: type, Ctx: type](h: *HeapBy[T, Ctx]) { list.clear[T](&h.items) }

// Floyd's construction: every node above the leaves sifts down once, which is
// linear in the element count rather than n log n.
fn heapify_in_place[T: type](items: []T) {
    if items.len < 2usize { ret }
    var start = items.len / 2usize
    while start != 0usize {
        start -= 1usize
        var at = start
        while true {
            let left = at * 2usize + 1usize
            if left >= items.len { break }
            var smallest = left
            let right = left + 1usize
            if right < items.len && T.cmp(items[right], items[left]) < 0i32 { smallest = right }
            if T.cmp(items[smallest], items[at]) >= 0i32 { break }
            let carried = items[at]
            items[at] = items[smallest]
            items[smallest] = carried
            at = smallest
        }
    }
}

fn heapify_in_place_by[T: type, Ctx: type](items: []T, ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32) {
    if items.len < 2usize { ret }
    var start = items.len / 2usize
    while start != 0usize {
        start -= 1usize
        var at = start
        while true {
            let left = at * 2usize + 1usize
            if left >= items.len { break }
            var smallest = left
            let right = left + 1usize
            if right < items.len && cmp(ctx, items[right], items[left]) < 0i32 { smallest = right }
            if cmp(ctx, items[smallest], items[at]) >= 0i32 { break }
            let carried = items[at]
            items[at] = items[smallest]
            items[smallest] = carried
            at = smallest
        }
    }
}

// Iteration exposes internal heap order, not sorted order.
fn iter[T: type](h: *const Heap[T]) -> Iter[T] {
    ret Iter[T] { items: list.slice_const[T](&h.items), index: 0usize }
}

fn iter_by[T: type, Ctx: type](h: *const HeapBy[T, Ctx]) -> Iter[T] {
    ret Iter[T] { items: list.slice_const[T](&h.items), index: 0usize }
}

fn iter_next[T: type](it: *Iter[T]) -> (T, bool) {
    if it.index >= it.items.len { ret (zero, false) }
    let value = it.items[it.index]
    it.index += 1usize
    ret (value, true)
}
