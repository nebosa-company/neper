// `os.clock` and `os.random` on every host. The wall clock is checked against two dates rather than
// against zero, which would pass while still carrying the wrong epoch or the wrong scale; the
// monotonic clock only has to never go back; random bytes have to be there and not repeat.

use e.mem
use e.os
use e.atomic

// 2020-01-01 and 2100-01-01 in Unix nanoseconds.
const YEAR_2020_NS: i64 = 1577836800000000000i64
const YEAR_2100_NS: i64 = 4102444800000000000i64

fn main(a: *mem.Arena) -> err {
    let (wall, wall_error) = os.clock(.Wall)
    if wall_error != ok { os.exit(10i32) }
    if wall < YEAR_2020_NS || wall > YEAR_2100_NS { os.exit(11i32) }

    let (first, first_error) = os.clock(.Monotonic)
    if first_error != ok { os.exit(20i32) }
    var last = first
    var step = 0usize
    while step < 1000usize {
        let (now, now_error) = os.clock(.Monotonic)
        if now_error != ok { os.exit(21i32) }
        if now < last { os.exit(22i32) }
        last = now
        step += 1usize
    }

    // A futex wait with a timeout returns, by waking or by timing out or, on a host with one
    // thread, at once; whichever it was, the clock has not gone back across it.
    var cell: Atomic[u32] = zero
    let waited = os.wait_u32(&cell, 0u32, 1000000i64)
    if waited != ok && waited != os.Timeout && waited != os.Interrupted { os.exit(30i32) }
    let (after, after_error) = os.clock(.Monotonic)
    if after_error != ok { os.exit(31i32) }
    if after < last { os.exit(32i32) }

    var first_draw: [32]u8 = zero
    if os.random(first_draw[..]) != ok { os.exit(40i32) }
    var second_draw: [32]u8 = zero
    if os.random(second_draw[..]) != ok { os.exit(41i32) }
    var any = false
    var same_bytes = true
    var at = 0usize
    while at < 32usize {
        if first_draw[at] != 0u8 { any = true }
        if first_draw[at] != second_draw[at] { same_bytes = false }
        at += 1usize
    }
    if !any { os.exit(42i32) }
    if same_bytes { os.exit(43i32) }

    // Nothing asked for is not a failure, and more than one call's worth is filled throughout.
    var nothing: []u8 = zero
    if os.random(nothing) != ok { os.exit(44i32) }
    let (big, big_error) = mem.alloc[u8](a, 200000usize)
    if big_error != ok { os.exit(45i32) }
    if os.random(big) != ok { os.exit(46i32) }
    var tail_any = false
    var tail = 199000usize
    while tail < 200000usize {
        if big[tail] != 0u8 { tail_any = true }
        tail += 1usize
    }
    if !tail_any { os.exit(47i32) }
    ret ok
}
