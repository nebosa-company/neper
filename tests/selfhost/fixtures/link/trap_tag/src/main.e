// Section 11's `tag` row and the `narrow` row for a float source. `tag` reads the payload
// of a member the tag does not name, `write` writes one; `nan`, `big`, `negative` and
// `wide` cast a float outside the target -- NaN, past 2^31, below zero into a `u16`,
// past 2^63 -- each trapping with its record. Anything else reads the live payload,
// casts floats that fit at both edges of their ranges, and exits 0. The values come
// from the argument count so nothing folds.
use e.mem
use e.str

type Node = union enum u8 { Nil, Lit: i32, Pair: [2]i32 }

fn main(a: *mem.Arena, args: []str) -> err {
    let mode = args[args.len - 1usize]
    let n = i32(args.len) + 5i32
    var node = Node{ Lit: n }
    if str.eq(mode, "tag") {
        let p = node.Pair
        if p[0usize] == 3i32 { ret ok }
    }
    if str.eq(mode, "write") {
        var other: Node = .Nil
        other.Lit = 4i32
    }
    if str.eq(mode, "nan") {
        let f = f64(n) / 0.0f64 - f64(n) / 0.0f64
        let i = i32(f)
        if i == 3i32 { ret ok }
    }
    if str.eq(mode, "big") {
        let f = f64(n) * 1000000000.0f64
        let i = i32(f)
        if i == 3i32 { ret ok }
    }
    if str.eq(mode, "negative") {
        let f = 0.0f32 - f32(n)
        let u = u16(f)
        if u == 3u16 { ret ok }
    }
    if str.eq(mode, "wide") {
        let f = 0.0f64 - f64(n) * 1e18f64 * 10.0f64
        let i = i64(f)
        if i == 3i64 { ret ok }
    }
    let v = node.Lit
    if v != 7i32 { ret ok }
    let fits = i8(f64(n) * -18.0f64) +% i8.trunc(u8(f32(n) * 36.0f32))
    if fits != 3i8 { ret ok }
    let edge = i64(-9.2e18f64) + i64(u32(4.29e9f64)) + i64(i16(-32768.9f64))
    if edge == 3i64 { ret ok }
    if node.tag != .Lit { ret ok }
    ret ok
}
