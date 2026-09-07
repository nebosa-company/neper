// Section 8's thirteen operations, run rather than only checked: each returns the
// value that was there before, `add` and `sub` wrap, and the ordering rules the
// checker enforces have to still produce working code.
//
// The widths matter more than the operations do. `and`, `or`, `xor`, `min` and `max`
// have no instruction that gives back the previous value, so each is a compare-and-swap
// loop that has to widen what it reads before comparing; `min` and `max` pick their
// condition from the sign; and a narrow compare-and-swap must compare only its own
// width. Every one of those is a way to be wrong that a `u64`-only test would miss.

use e.atomic

error Failed

type Counter = struct { hits: Atomic[u64], guard: Atomic[u32] }

type Widths = struct {
    a: Atomic[i8],
    b: Atomic[u8],
    c: Atomic[i16],
    d: Atomic[i32],
    e: Atomic[u32],
    f: Atomic[isize],
    g: Atomic[usize],
}

type Node = struct { tag: u64 }
type Link = struct { next: Atomic[*Node] }

fn scalar_operations() -> err {
    var c: Counter = zero

    if atomic.add(&c.hits, 5u64, .Relaxed) != 0u64 { ret Failed }
    if atomic.add(&c.hits, 7u64, .Relaxed) != 5u64 { ret Failed }
    if atomic.load(&c.hits, .Acquire) != 12u64 { ret Failed }
    if atomic.sub(&c.hits, 2u64, .Relaxed) != 12u64 { ret Failed }
    if atomic.load(&c.hits, .Relaxed) != 10u64 { ret Failed }

    // The plain store and the sequentially consistent one, which is an exchange.
    atomic.store(&c.hits, 100u64, .Release)
    if atomic.load(&c.hits, .Relaxed) != 100u64 { ret Failed }
    atomic.store(&c.hits, 200u64, .SeqCst)
    if atomic.load(&c.hits, .SeqCst) != 200u64 { ret Failed }

    if atomic.xchg(&c.hits, 9u64, .AcqRel) != 200u64 { ret Failed }
    if atomic.load(&c.hits, .Relaxed) != 9u64 { ret Failed }

    // The five that are compare-and-swap loops.
    atomic.store(&c.hits, 12u64, .Relaxed)
    if atomic.or(&c.hits, 3u64, .Relaxed) != 12u64 { ret Failed }
    if atomic.load(&c.hits, .Relaxed) != 15u64 { ret Failed }
    if atomic.and(&c.hits, 6u64, .Relaxed) != 15u64 { ret Failed }
    if atomic.load(&c.hits, .Relaxed) != 6u64 { ret Failed }
    if atomic.xor(&c.hits, 5u64, .Relaxed) != 6u64 { ret Failed }
    if atomic.load(&c.hits, .Relaxed) != 3u64 { ret Failed }
    if atomic.min(&c.hits, 9u64, .Relaxed) != 3u64 { ret Failed }
    if atomic.load(&c.hits, .Relaxed) != 3u64 { ret Failed }
    if atomic.max(&c.hits, 9u64, .Relaxed) != 3u64 { ret Failed }
    if atomic.load(&c.hits, .Relaxed) != 9u64 { ret Failed }

    // A strong compare-and-swap: it reports what it found either way.
    let (won, seen) = atomic.cas(&c.hits, 9u64, 42u64, .AcqRel, .Acquire)
    if !won || seen != 9u64 { ret Failed }
    if atomic.load(&c.hits, .Relaxed) != 42u64 { ret Failed }
    let (lost, found) = atomic.cas(&c.hits, 9u64, 7u64, .AcqRel, .Acquire)
    if lost || found != 42u64 { ret Failed }
    if atomic.load(&c.hits, .Relaxed) != 42u64 { ret Failed }

    // A narrower field beside a wider one, each left alone by the other.
    if atomic.add(&c.guard, 3u32, .Relaxed) != 0u32 { ret Failed }
    if atomic.load(&c.guard, .Relaxed) != 3u32 { ret Failed }
    if atomic.load(&c.hits, .Relaxed) != 42u64 { ret Failed }

    atomic.fence(.SeqCst)
    ret ok
}

fn widths() -> err {
    var w: Widths = zero

    // Signed min and max across zero.
    atomic.store(&w.a, -5i8, .Relaxed)
    if atomic.load(&w.a, .Relaxed) != -5i8 { ret Failed }
    if atomic.min(&w.a, 3i8, .Relaxed) != -5i8 { ret Failed }
    if atomic.load(&w.a, .Relaxed) != -5i8 { ret Failed }
    if atomic.max(&w.a, 3i8, .Relaxed) != -5i8 { ret Failed }
    if atomic.load(&w.a, .Relaxed) != 3i8 { ret Failed }

    atomic.store(&w.c, -300i16, .Relaxed)
    if atomic.max(&w.c, -400i16, .Relaxed) != -300i16 { ret Failed }
    if atomic.load(&w.c, .Relaxed) != -300i16 { ret Failed }
    if atomic.min(&w.c, -400i16, .Relaxed) != -300i16 { ret Failed }
    if atomic.load(&w.c, .Relaxed) != -400i16 { ret Failed }

    atomic.store(&w.d, -7i32, .Relaxed)
    if atomic.add(&w.d, 10i32, .Relaxed) != -7i32 { ret Failed }
    if atomic.load(&w.d, .Relaxed) != 3i32 { ret Failed }
    if atomic.min(&w.d, -1i32, .Relaxed) != 3i32 { ret Failed }
    if atomic.load(&w.d, .Relaxed) != -1i32 { ret Failed }

    // Unsigned min and max must not read the top bit as a sign.
    atomic.store(&w.b, 200u8, .Relaxed)
    if atomic.min(&w.b, 100u8, .Relaxed) != 200u8 { ret Failed }
    if atomic.load(&w.b, .Relaxed) != 100u8 { ret Failed }
    atomic.store(&w.e, 4000000000u32, .Relaxed)
    if atomic.max(&w.e, 5u32, .Relaxed) != 4000000000u32 { ret Failed }
    if atomic.load(&w.e, .Relaxed) != 4000000000u32 { ret Failed }
    if atomic.min(&w.e, 5u32, .Relaxed) != 4000000000u32 { ret Failed }
    if atomic.load(&w.e, .Relaxed) != 5u32 { ret Failed }

    // `add` and `sub` wrap, as section 8 says.
    atomic.store(&w.b, 250u8, .Relaxed)
    if atomic.add(&w.b, 10u8, .Relaxed) != 250u8 { ret Failed }
    if atomic.load(&w.b, .Relaxed) != 4u8 { ret Failed }

    if atomic.add(&w.g, 9usize, .Relaxed) != 0usize { ret Failed }
    if atomic.load(&w.g, .Relaxed) != 9usize { ret Failed }
    atomic.store(&w.f, -2isize, .Relaxed)
    if atomic.xor(&w.f, 1isize, .Relaxed) != -2isize { ret Failed }
    if atomic.load(&w.f, .Relaxed) != -1isize { ret Failed }

    // A narrow compare-and-swap compares only its own width.
    atomic.store(&w.d, 5i32, .Relaxed)
    let (won, seen) = atomic.cas(&w.d, 5i32, -9i32, .SeqCst, .Relaxed)
    if !won || seen != 5i32 { ret Failed }
    if atomic.load(&w.d, .Relaxed) != -9i32 { ret Failed }
    let (lost, found) = atomic.cas(&w.d, 5i32, 1i32, .SeqCst, .Relaxed)
    if lost || found != -9i32 { ret Failed }

    // Every field kept to itself.
    if atomic.load(&w.a, .Relaxed) != 3i8 { ret Failed }
    if atomic.load(&w.b, .Relaxed) != 4u8 { ret Failed }
    if atomic.load(&w.c, .Relaxed) != -400i16 { ret Failed }
    if atomic.load(&w.e, .Relaxed) != 5u32 { ret Failed }
    if atomic.load(&w.g, .Relaxed) != 9usize { ret Failed }
    ret ok
}

fn pointers() -> err {
    var one: Node = zero
    one.tag = 77u64
    var link: Link = zero
    atomic.store(&link.next, &one, .Release)
    let p = atomic.load(&link.next, .Acquire)
    if p.tag != 77u64 { ret Failed }
    if atomic.xchg(&link.next, &one, .AcqRel).tag != 77u64 { ret Failed }
    ret ok
}

// `init(v)` is the one operation that touches no shared location: it builds the value
// the caller is about to store, so it is legal wherever a value is.
fn constructed() -> err {
    var c = Counter { hits: atomic.init(3u64), guard: atomic.init(4u32) }
    if atomic.load(&c.hits, .Relaxed) != 3u64 { ret Failed }
    if atomic.load(&c.guard, .Relaxed) != 4u32 { ret Failed }
    var d: Atomic[u32] = atomic.init(9u32)
    if atomic.load(&d, .Relaxed) != 9u32 { ret Failed }
    ret ok
}

fn main() -> err {
    try scalar_operations()
    try widths()
    try pointers()
    try constructed()
    ret ok
}
