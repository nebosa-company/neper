// A bounded channel: a ring buffer of `T` under one mutex, with a condition on each
// side. Section 8's `e.sync` supplies both, so nothing here touches an atomic
// directly and the whole module is the buffer arithmetic plus who to wake.
//
// The handle is a `*void` because a channel is shared by threads that each hold their
// own copy of it, so the state cannot live in the handle. It comes from the caller's
// arena and is freed with it; `close` only marks it closed.
//
// Every wait is a `while` over the condition it waits on, never an `if`: a condition
// wake is not a promise that the state changed, and a closing broadcast wakes waiters
// that must then find the channel closed rather than an empty slot.

use e.mem
use e.sync

type Channel[T: type] = struct { state: *void }

error Closed

type ChannelState[T: type] = struct {
    lock: sync.Mutex,
    not_full: sync.Condition,
    not_empty: sync.Condition,
    buffer: []T,
    head: usize,
    count: usize,
    closed: bool,
}

// A capacity of zero is invalid: there would be nowhere to put a value and no
// rendezvous in this surface to hand it over directly. The refusal is `sync.Invalid`
// because this module's fence declares one error and it is `Closed`, which this is
// not; `e.concurrent.queue` declares an `Invalid` of its own for the same case, and
// e.channel would want one too if its surface were being written today.
fn init[T: type](a: *mem.Arena, cap: usize) -> (Channel[T], err) {
    var empty: Channel[T] = zero
    if cap == 0usize { ret (empty, sync.Invalid) }
    let (storage, storage_error) = mem.alloc[ChannelState[T]](a, 1usize)
    if storage_error != ok { ret (empty, storage_error) }
    let (buffer, buffer_error) = mem.alloc[T](a, cap)
    if buffer_error != ok { ret (empty, buffer_error) }
    storage[0usize] = ChannelState[T] { lock: sync.mutex(), not_full: sync.condition(), not_empty: sync.condition(), buffer: buffer, head: 0usize, count: 0usize, closed: false }
    ret (Channel[T] { state: mem.cast[*void](&storage[0usize]) }, ok)
}

fn send[T: type](c: *Channel[T], value: T) -> err {
    let s = mem.cast[*ChannelState[T]](c.state)
    sync.mutex_lock(&s.lock)
    while s.count == s.buffer.len && !s.closed {
        sync.condition_wait(&s.not_full, &s.lock)
    }
    if s.closed {
        sync.mutex_unlock(&s.lock)
        ret Closed
    }
    let at = slot_of[T](s, s.count)
    s.buffer[at] = value
    s.count += 1usize
    sync.condition_signal(&s.not_empty)
    sync.mutex_unlock(&s.lock)
    ret ok
}

fn try_send[T: type](c: *Channel[T], value: T) -> (bool, err) {
    let s = mem.cast[*ChannelState[T]](c.state)
    sync.mutex_lock(&s.lock)
    if s.closed {
        sync.mutex_unlock(&s.lock)
        ret (false, Closed)
    }
    if s.count == s.buffer.len {
        sync.mutex_unlock(&s.lock)
        ret (false, ok)
    }
    let at = slot_of[T](s, s.count)
    s.buffer[at] = value
    s.count += 1usize
    sync.condition_signal(&s.not_empty)
    sync.mutex_unlock(&s.lock)
    ret (true, ok)
}

// A closed channel still hands back what it holds: `Closed` is returned only once the
// buffer is drained.
fn receive[T: type](c: *Channel[T]) -> (T, err) {
    var empty: T = zero
    let s = mem.cast[*ChannelState[T]](c.state)
    sync.mutex_lock(&s.lock)
    while s.count == 0usize && !s.closed {
        sync.condition_wait(&s.not_empty, &s.lock)
    }
    if s.count == 0usize {
        sync.mutex_unlock(&s.lock)
        ret (empty, Closed)
    }
    let value = s.buffer[s.head]
    s.head = wrap_of[T](s, s.head + 1usize)
    s.count -= 1usize
    sync.condition_signal(&s.not_full)
    sync.mutex_unlock(&s.lock)
    ret (value, ok)
}

fn try_receive[T: type](c: *Channel[T]) -> (T, bool, err) {
    var empty: T = zero
    let s = mem.cast[*ChannelState[T]](c.state)
    sync.mutex_lock(&s.lock)
    if s.count == 0usize {
        var drained_error = ok
        if s.closed { drained_error = Closed }
        sync.mutex_unlock(&s.lock)
        ret (empty, false, drained_error)
    }
    let value = s.buffer[s.head]
    s.head = wrap_of[T](s, s.head + 1usize)
    s.count -= 1usize
    sync.condition_signal(&s.not_full)
    sync.mutex_unlock(&s.lock)
    ret (value, true, ok)
}

// Closing wakes everyone: a blocked sender has to give up and a blocked receiver has
// to drain what is left and then stop.
fn close[T: type](c: *Channel[T]) -> err {
    let s = mem.cast[*ChannelState[T]](c.state)
    sync.mutex_lock(&s.lock)
    if s.closed {
        sync.mutex_unlock(&s.lock)
        ret Closed
    }
    s.closed = true
    sync.condition_broadcast(&s.not_full)
    sync.condition_broadcast(&s.not_empty)
    sync.mutex_unlock(&s.lock)
    ret ok
}

fn len[T: type](c: *const Channel[T]) -> usize {
    let s = mem.cast[*ChannelState[T]](c.state)
    sync.mutex_lock(&s.lock)
    let held = s.count
    sync.mutex_unlock(&s.lock)
    ret held
}

fn capacity[T: type](c: *const Channel[T]) -> usize {
    let s = mem.cast[*ChannelState[T]](c.state)
    ret s.buffer.len
}

// The buffer is a ring, so both ends wrap. Written as a subtraction rather than a
// remainder because the operands are already below twice the capacity.
fn wrap_of[T: type](s: *ChannelState[T], at: usize) -> usize {
    if at >= s.buffer.len { ret at - s.buffer.len }
    ret at
}

fn slot_of[T: type](s: *ChannelState[T], offset: usize) -> usize {
    ret wrap_of[T](s, s.head + offset)
}
