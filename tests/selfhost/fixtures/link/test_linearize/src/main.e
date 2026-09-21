// `e.test.linearize`: 30 LCG-generated histories of up to 8 reads, writes
// and compare-and-swaps answer, under the register, counter and set models,
// the verdict bitmasks a Python brute force over every permutation found; the
// classic stale read after a completed write is refused and its fresh twin
// and a read concurrent with the write are accepted. Each check exits with
// its own code.

use e.io
use e.mem
use e.os
use e.test.linearize as lin

type Lcg = struct { state: u64 }

fn draw(l: *Lcg) -> u64 {
    l.state = l.state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret l.state >> 33u32
}

fn op_of(k: u64) -> lin.Op {
    if k == 0u64 { ret .Read }
    if k == 1u64 { ret .Write }
    ret .Cas
}

fn event(call_time: u64, return_time: u64, op: lin.Op, arg: i64, result: i64) -> lin.Event {
    ret lin.Event { call_time: call_time, return_time: return_time, op: op, arg: arg, arg2: 0i64, result: result }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var l = Lcg { state: 9u64 }
    var history: [8]lin.Event = zero
    var placed: [8]u8 = zero

    // 1: 30 random histories under three models.
    var register_mask = 0u64
    var counter_mask = 0u64
    var set_mask = 0u64
    var k = 0usize
    while k < 30usize {
        let n = 1usize + usize(draw(&l) % 8u64)
        var i = 0usize
        while i < n {
            let call_time = draw(&l) % 20u64
            let duration = draw(&l) % 5u64
            let op = op_of(draw(&l) % 3u64)
            let arg = i64(draw(&l) % 3u64)
            let arg2 = i64(draw(&l) % 3u64)
            var result = 0i64
            if op == .Read { result = i64(draw(&l) % 3u64) }
            if op == .Cas { result = i64(draw(&l) % 2u64) }
            history[i] = lin.Event { call_time: call_time, return_time: call_time + duration, op: op, arg: arg, arg2: arg2, result: result }
            i += 1usize
        }
        let (r, re) = lin.check(history[..n], .Register, 0i64, placed[..])
        let (c, ce) = lin.check(history[..n], .Counter, 0i64, placed[..])
        let (s, se) = lin.check(history[..n], .Set, 0i64, placed[..])
        if re != ok || ce != ok || se != ok { os.exit(1i32) }
        if r { register_mask = register_mask | (1u64 << u32(k)) }
        if c { counter_mask = counter_mask | (1u64 << u32(k)) }
        if s { set_mask = set_mask | (1u64 << u32(k)) }
        k += 1usize
    }
    if register_mask != 604058048u64 { os.exit(1i32) }
    if counter_mask != 604188736u64 { os.exit(1i32) }
    if set_mask != 607330560u64 { os.exit(1i32) }

    // 2: the classic stale read, its fresh twin, and a concurrent read.
    history[0usize] = event(0u64, 1u64, .Write, 1i64, 0i64)
    history[1usize] = event(2u64, 3u64, .Read, 0i64, 0i64)
    let (stale, stale_error) = lin.check(history[..2usize], .Register, 0i64, placed[..])
    if stale_error != ok || stale { os.exit(2i32) }
    history[1usize] = event(2u64, 3u64, .Read, 0i64, 1i64)
    let (fresh, fresh_error) = lin.check(history[..2usize], .Register, 0i64, placed[..])
    if fresh_error != ok || !fresh { os.exit(2i32) }
    history[0usize] = event(0u64, 5u64, .Write, 1i64, 0i64)
    history[1usize] = event(2u64, 3u64, .Read, 0i64, 0i64)
    history[2usize] = event(4u64, 6u64, .Read, 0i64, 1i64)
    let (overlap, overlap_error) = lin.check(history[..3usize], .Register, 0i64, placed[..])
    if overlap_error != ok || !overlap { os.exit(2i32) }
    let (empty, empty_error) = lin.check(history[..0usize], .Register, 0i64, placed[..])
    if empty_error != ok || !empty { os.exit(2i32) }
    let (_, room) = lin.check(history[..3usize], .Register, 0i64, placed[..2usize])
    if room != lin.TooSmall { os.exit(2i32) }
    history[2usize] = event(7u64, 6u64, .Read, 0i64, 1i64)
    let (_, backwards) = lin.check(history[..3usize], .Register, 0i64, placed[..])
    if backwards != lin.Invalid { os.exit(2i32) }

    try io.print("test linearize ok\n")
    ret ok
}
