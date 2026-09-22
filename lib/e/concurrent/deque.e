// A work-stealing deque: the Chase-Lev deque over a fixed circular buffer the caller
// supplies. One owner pushes and pops at the bottom; any number of thieves steal from
// the top. `top` and `bottom` are `i64` as in the paper, because `pop` moves `bottom`
// below `top` for a moment and the comparison has to see that as negative rather than
// as a wrap. The capacity is fixed and a power of two: a push that would overrun the
// buffer answers `Full` instead of growing, since the storage is the caller's.
//
// The read of a slot in `steal` may race with the owner refilling it, but only after
// `top` has moved past the thief's index, and then the thief's compare-and-swap loses
// and the value is dropped -- the same benign race the original relies on.
use e.atomic

type Deque[T: type] = struct { items: []T, top: Atomic[i64], bottom: Atomic[i64], mask: usize }
type Outcome = enum u8 { Stolen, Empty, Retry }
error Invalid
error Full

// The buffer's length is the capacity and must be a power of two above zero.
fn deque[T: type](items: []T) -> (Deque[T], err) {
    let n = items.len
    if n == 0usize || n & (n - 1usize) != 0usize { ret (zero, Invalid) }
    ret (Deque[T] { items: items, top: atomic.init(0i64), bottom: atomic.init(0i64), mask: n - 1usize }, ok)
}

// Owner only.
fn push[T: type](d: *Deque[T], v: T) -> err {
    let b = atomic.load(&d.bottom, .Relaxed)
    let t = atomic.load(&d.top, .Acquire)
    if usize(b - t) > d.mask { ret Full }
    d.items[usize(b) & d.mask] = v
    atomic.store(&d.bottom, b + 1i64, .Release)
    ret ok
}

// Owner only: the newest item, or `false` when empty. With one item left the owner
// and a thief both want it, and the compare-and-swap on `top` decides.
fn pop[T: type](d: *Deque[T]) -> (T, bool) {
    let b = atomic.load(&d.bottom, .Relaxed) - 1i64
    atomic.store(&d.bottom, b, .Relaxed)
    atomic.fence(.SeqCst)
    let t = atomic.load(&d.top, .Relaxed)
    if t > b {
        atomic.store(&d.bottom, b + 1i64, .Relaxed)
        ret (zero, false)
    }
    let v = d.items[usize(b) & d.mask]
    if t < b { ret (v, true) }
    let (won, seen) = atomic.cas(&d.top, t, t + 1i64, .SeqCst, .Relaxed)
    atomic.store(&d.bottom, b + 1i64, .Relaxed)
    if won { ret (v, true) }
    ret (zero, false)
}

// Any thread: the oldest item. `Retry` means another taker won the race for it and
// the caller should simply call again.
fn steal[T: type](d: *Deque[T]) -> (T, Outcome) {
    let t = atomic.load(&d.top, .Acquire)
    atomic.fence(.SeqCst)
    let b = atomic.load(&d.bottom, .Acquire)
    if t >= b { ret (zero, .Empty) }
    let v = d.items[usize(t) & d.mask]
    let (won, seen) = atomic.cas(&d.top, t, t + 1i64, .SeqCst, .Relaxed)
    if !won { ret (zero, .Retry) }
    ret (v, .Stolen)
}

// A snapshot; exact only when read by the owner with no thief active.
fn len[T: type](d: *Deque[T]) -> usize {
    let b = atomic.load(&d.bottom, .Relaxed)
    let t = atomic.load(&d.top, .Relaxed)
    if b <= t { ret 0usize }
    ret usize(b - t)
}

fn capacity[T: type](d: *const Deque[T]) -> usize {
    ret d.mask + 1usize
}
