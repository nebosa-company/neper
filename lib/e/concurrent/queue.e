// A bounded multi-producer, multi-consumer FIFO: a ring of `T` in the arena under one
// mutex, with a condition for the consumers and one for the producers. `push` waits
// for room and `pop` for an item; the timed forms answer `false` on the timeout and
// the `try` forms at once. `close` wakes every waiter; what is buffered is still
// popped, and only then is the queue `Closed`. A capacity of zero is `Invalid`.
// Everything is allocated in `init`, as the fence says.
use e.mem
use e.sync
use e.time

type Queue[T: type] = struct { state: *void }
error Closed
error Invalid

type State[T: type] = struct { lock: sync.Mutex, not_empty: sync.Condition, not_full: sync.Condition, items: []T, head: usize, count: usize, closed: bool }

fn init[T: type](a: *mem.Arena, initial_capacity: usize) -> (Queue[T], err) {
    if initial_capacity == 0usize { ret (zero, Invalid) }
    let (storage, storage_error) = mem.alloc[State[T]](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    let (items, items_error) = mem.alloc[T](a, initial_capacity)
    if items_error != ok { ret (zero, items_error) }
    storage[0].lock = sync.mutex()
    storage[0].not_empty = sync.condition()
    storage[0].not_full = sync.condition()
    storage[0].items = items
    storage[0].head = 0usize
    storage[0].count = 0usize
    storage[0].closed = false
    var q: Queue[T] = zero
    q.state = mem.cast[*void](&storage[0])
    ret (q, ok)
}

fn state_of[T: type](q: *Queue[T]) -> *State[T] {
    ret mem.cast[*State[T]](q.state)
}

// Appends under the lock; the caller holds it and has checked for room.
fn place[T: type](s: *State[T], value: T) {
    var slot = s.head + s.count
    if slot >= s.items.len { slot -= s.items.len }
    s.items[slot] = value
    s.count += 1usize
    sync.condition_signal(&s.not_empty)
}

fn take[T: type](s: *State[T]) -> T {
    let value = s.items[s.head]
    s.head += 1usize
    if s.head == s.items.len { s.head = 0usize }
    s.count -= 1usize
    sync.condition_signal(&s.not_full)
    ret value
}

fn try_push[T: type](q: *Queue[T], value: T) -> (bool, err) {
    let s = state_of[T](q)
    sync.mutex_lock(&s.lock)
    if s.closed {
        sync.mutex_unlock(&s.lock)
        ret (false, Closed)
    }
    if s.count == s.items.len {
        sync.mutex_unlock(&s.lock)
        ret (false, ok)
    }
    place[T](s, value)
    sync.mutex_unlock(&s.lock)
    ret (true, ok)
}

fn push[T: type](q: *Queue[T], value: own T) -> err {
    let s = state_of[T](q)
    sync.mutex_lock(&s.lock)
    while !s.closed && s.count == s.items.len { sync.condition_wait(&s.not_full, &s.lock) }
    if s.closed {
        sync.mutex_unlock(&s.lock)
        ret Closed
    }
    place[T](s, value)
    sync.mutex_unlock(&s.lock)
    ret ok
}

fn push_for[T: type](q: *Queue[T], value: T, timeout: time.Duration) -> (bool, err) {
    let s = state_of[T](q)
    let deadline = sync.deadline_for(timeout)
    sync.mutex_lock(&s.lock)
    while !s.closed && s.count == s.items.len {
        let left = sync.remaining_for(deadline)
        if left <= 0i64 {
            sync.mutex_unlock(&s.lock)
            ret (false, ok)
        }
        let woken = sync.condition_wait_for(&s.not_full, &s.lock, time.Duration { nanos: left })
    }
    if s.closed {
        sync.mutex_unlock(&s.lock)
        ret (false, Closed)
    }
    place[T](s, value)
    sync.mutex_unlock(&s.lock)
    ret (true, ok)
}

fn try_pop[T: type](q: *Queue[T]) -> (T, bool, err) {
    let s = state_of[T](q)
    sync.mutex_lock(&s.lock)
    if s.count == 0usize {
        let closed = s.closed
        sync.mutex_unlock(&s.lock)
        if closed { ret (zero, false, Closed) }
        ret (zero, false, ok)
    }
    let value = take[T](s)
    sync.mutex_unlock(&s.lock)
    ret (value, true, ok)
}

fn pop[T: type](q: *Queue[T]) -> (T, err) {
    let s = state_of[T](q)
    sync.mutex_lock(&s.lock)
    while !s.closed && s.count == 0usize { sync.condition_wait(&s.not_empty, &s.lock) }
    if s.count == 0usize {
        sync.mutex_unlock(&s.lock)
        ret (zero, Closed)
    }
    let value = take[T](s)
    sync.mutex_unlock(&s.lock)
    ret (value, ok)
}

fn pop_for[T: type](q: *Queue[T], timeout: time.Duration) -> (T, bool, err) {
    let s = state_of[T](q)
    let deadline = sync.deadline_for(timeout)
    sync.mutex_lock(&s.lock)
    while !s.closed && s.count == 0usize {
        let left = sync.remaining_for(deadline)
        if left <= 0i64 {
            sync.mutex_unlock(&s.lock)
            ret (zero, false, ok)
        }
        let woken = sync.condition_wait_for(&s.not_empty, &s.lock, time.Duration { nanos: left })
    }
    if s.count == 0usize {
        sync.mutex_unlock(&s.lock)
        ret (zero, false, Closed)
    }
    let value = take[T](s)
    sync.mutex_unlock(&s.lock)
    ret (value, true, ok)
}

fn close[T: type](q: *Queue[T]) -> err {
    let s = state_of[T](q)
    sync.mutex_lock(&s.lock)
    if s.closed {
        sync.mutex_unlock(&s.lock)
        ret Closed
    }
    s.closed = true
    sync.condition_broadcast(&s.not_empty)
    sync.condition_broadcast(&s.not_full)
    sync.mutex_unlock(&s.lock)
    ret ok
}

fn len[T: type](q: *const Queue[T]) -> usize {
    let s = mem.cast[*State[T]](q.state)
    sync.mutex_lock(&s.lock)
    let count = s.count
    sync.mutex_unlock(&s.lock)
    ret count
}

fn capacity[T: type](q: *const Queue[T]) -> usize {
    let s = mem.cast[*State[T]](q.state)
    ret s.items.len
}
