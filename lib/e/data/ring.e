// Fixed-capacity FIFO rings over caller-owned storage.

type Ring[T: type] = struct { items: []T, head: usize, len: usize }
type Iter[T: type] = struct { ring: *const Ring[T], index: usize }

fn init[T: type](storage: []T) -> Ring[T] {
    ret Ring[T] { items: storage, head: 0usize, len: 0usize }
}

fn len[T: type](r: *const Ring[T]) -> usize { ret r.len }

fn capacity[T: type](r: *const Ring[T]) -> usize { ret r.items.len }

fn push[T: type](r: *Ring[T], v: own T) -> bool {
    if r.len == r.items.len { ret false }
    let at = (r.head + r.len) % r.items.len
    r.items[at] = v
    r.len += 1usize
    ret true
}

fn push_overwrite[T: type](r: *Ring[T], v: own T) -> (T, bool) {
    if r.items.len == 0usize { ret (zero, false) }
    if r.len < r.items.len {
        let at = (r.head + r.len) % r.items.len
        r.items[at] = v
        r.len += 1usize
        ret (zero, false)
    }
    let replaced = r.items[r.head]
    r.items[r.head] = v
    r.head = (r.head + 1usize) % r.items.len
    ret (replaced, true)
}

fn pop[T: type](r: *Ring[T]) -> (T, bool) {
    if r.len == 0usize { ret (zero, false) }
    let value = r.items[r.head]
    r.head = (r.head + 1usize) % r.items.len
    r.len -= 1usize
    if r.len == 0usize { r.head = 0usize }
    ret (value, true)
}

fn peek[T: type](r: *const Ring[T]) -> (T, bool) {
    if r.len == 0usize { ret (zero, false) }
    ret (r.items[r.head], true)
}

fn clear[T: type](r: *Ring[T]) {
    r.head = 0usize
    r.len = 0usize
}

fn iter[T: type](r: *const Ring[T]) -> Iter[T] {
    ret Iter[T] { ring: r, index: 0usize }
}

fn iter_next[T: type](it: *Iter[T]) -> (T, bool) {
    if it.index >= it.ring.len { ret (zero, false) }
    let at = (it.ring.head + it.index) % it.ring.items.len
    let value = it.ring.items[at]
    it.index += 1usize
    ret (value, true)
}
