// Property-based testing over caller storage. Generators draw from an
// `e.algo.rand` PCG: `gen_int` an integer of an inclusive range, `gen_bytes`
// up to `max_len` random bytes, `gen_choice` one of the caller's values,
// `gen_list` up to `max_len` integers of a range, and `generate` dispatches
// on a `Gen` descriptor. Shrinkers take the caller's failing predicate (a
// context pointer and the candidate) and answer a smaller input that still
// fails: `shrink` moves an integer toward zero by binary search and then
// single steps, `shrink_bytes` is delta debugging (drop halves, quarters, ...
// single bytes, repeated until nothing drops) followed by each byte toward
// zero. Every predicate call is on a candidate the caller may keep.

use e.algo.rand
use e.mem

type Kind = enum u8 { Int, Bytes, Choice, List }
// `Int` and `List` use `lo..hi`; `Bytes` and `List` use `max_len`; `Choice` uses `choices`.
type Gen = struct { kind: Kind, lo: i64, hi: i64, max_len: usize, choices: []const i64 }
// `int` for `Int`/`Choice`; `len` counts the bytes or ints written for `Bytes`/`List`.
type Value = struct { int: i64, len: usize }
error TooSmall

fn int_gen(lo: i64, hi: i64) -> Gen { ret Gen { kind: .Int, lo: lo, hi: hi, max_len: 0usize, choices: zero } }
fn bytes_gen(max_len: usize) -> Gen { ret Gen { kind: .Bytes, lo: 0i64, hi: 0i64, max_len: max_len, choices: zero } }
fn choice_gen(choices: []const i64) -> Gen { ret Gen { kind: .Choice, lo: 0i64, hi: 0i64, max_len: 0usize, choices: choices } }
fn list_gen(max_len: usize, lo: i64, hi: i64) -> Gen { ret Gen { kind: .List, lo: lo, hi: hi, max_len: max_len, choices: zero } }

// An integer in `lo..hi` inclusive (`hi < lo` answers `lo`); the range must fit an i64.
fn gen_int(r: *rand.Pcg64, lo: i64, hi: i64) -> i64 {
    if hi <= lo { ret lo }
    let span = u64(hi - lo)
    if span == 18446744073709551615u64 { ret i64(rand.pcg64_next(r)) }
    ret lo + i64(rand.pcg64_bounded(r, span + 1u64))
}

// `0..max_len` random bytes into `out` (bounded by `out.len`); answers the count.
fn gen_bytes(r: *rand.Pcg64, out: []u8, max_len: usize) -> usize {
    var limit = max_len
    if limit > out.len { limit = out.len }
    let n = usize(rand.pcg64_bounded(r, u64(limit + 1usize)))
    var i = 0usize
    while i < n {
        out[i] = u8(rand.pcg64_next(r) & 255u64)
        i += 1usize
    }
    ret n
}

fn gen_choice(r: *rand.Pcg64, choices: []const i64) -> i64 {
    if choices.len == 0usize { ret 0i64 }
    ret choices[usize(rand.pcg64_bounded(r, u64(choices.len)))]
}

// `0..max_len` integers of `lo..hi` into `out`; answers the count.
fn gen_list(r: *rand.Pcg64, out: []i64, max_len: usize, lo: i64, hi: i64) -> usize {
    var limit = max_len
    if limit > out.len { limit = out.len }
    let n = usize(rand.pcg64_bounded(r, u64(limit + 1usize)))
    var i = 0usize
    while i < n {
        out[i] = gen_int(r, lo, hi)
        i += 1usize
    }
    ret n
}

// One value of `g`: bytes land in `bytes`, a list in `ints`.
fn generate(r: *rand.Pcg64, g: Gen, bytes: []u8, ints: []i64) -> Value {
    if g.kind == .Int { ret Value { int: gen_int(r, g.lo, g.hi), len: 0usize } }
    if g.kind == .Bytes { ret Value { int: 0i64, len: gen_bytes(r, bytes, g.max_len) } }
    if g.kind == .Choice { ret Value { int: gen_choice(r, g.choices), len: 0usize } }
    ret Value { int: 0i64, len: gen_list(r, ints, g.max_len, g.lo, g.hi) }
}

// The smallest-magnitude integer reachable from the failing `x` that still
// fails: binary search between the nearest known passing value and `x`,
// then single steps toward zero.
fn shrink[Ctx: type](ctx: *Ctx, fails: fn(*Ctx, i64) -> bool, x: i64) -> i64 {
    if x == 0i64 || fails(ctx, 0i64) { ret 0i64 }
    var passing = 0i64
    var current = x
    var gap = current - passing
    if gap < 0i64 { gap = 0i64 - gap }
    while gap > 1i64 {
        let mid = passing + (current - passing) / 2i64
        if fails(ctx, mid) { current = mid } else { passing = mid }
        gap = current - passing
        if gap < 0i64 { gap = 0i64 - gap }
    }
    var step = 1i64
    if current > 0i64 { step = -1i64 }
    while current != 0i64 && fails(ctx, current + step) { current += step }
    ret current
}

// Delta debugging over `data[..len]` with `scratch` (at least `len` bytes)
// for candidates; the result is left in `data`; answers its length.
fn shrink_bytes[Ctx: type](ctx: *Ctx, fails: fn(*Ctx, []const u8) -> bool, data: []u8, len: usize, scratch: []u8) -> (usize, err) {
    if scratch.len < len || data.len < len { ret (len, TooSmall) }
    var n = len
    var changed = true
    while changed && n > 0usize {
        changed = false
        var chunk = n / 2usize
        if chunk == 0usize { chunk = 1usize }
        while chunk >= 1usize {
            var start = 0usize
            while start < n {
                var take = chunk
                if start + take > n { take = n - start }
                mem.copy[u8](scratch[..start], data[..start])
                mem.copy[u8](scratch[start..n - take], data[start + take..n])
                if fails(ctx, scratch[..n - take]) {
                    mem.copy[u8](data[..n - take], scratch[..n - take])
                    n -= take
                    changed = true
                } else {
                    start += chunk
                }
            }
            chunk /= 2usize
        }
    }
    var i = 0usize
    while i < n {
        mem.copy[u8](scratch[..n], data[..n])
        var moving = true
        while moving && data[i] > 0u8 {
            moving = false
            scratch[i] = data[i] / 2u8
            if fails(ctx, scratch[..n]) {
                data[i] = scratch[i]
                moving = true
            } else {
                scratch[i] = data[i] - 1u8
                if fails(ctx, scratch[..n]) {
                    data[i] = scratch[i]
                    moving = true
                } else {
                    scratch[i] = data[i]
                }
            }
        }
        i += 1usize
    }
    ret (n, ok)
}
