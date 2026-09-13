// Section 11's `overflow` row: `+ - *` and unary `-` on every width, signed and
// unsigned, trap when the result does not fit -- `add32`, `sub8`, `mulu16`, `add64`,
// `subusize`, `mulusize` (the one that needs `mul`'s high half), `muli64` and `neg`
// each name their type and operator. Anything else runs the same operators in range,
// the wrapping `+%` past the edge, and exits 0. The values come from the argument
// count so nothing folds.
use e.mem
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    let mode = args[args.len - 1usize]
    let n = args.len + 5usize
    if str.eq(mode, "add32") {
        let x = 2147483641i32 + i32(n)
        if x == 3i32 { ret ok }
    }
    if str.eq(mode, "sub8") {
        let x = i8(0i32 - 125i32) - i8(n)
        if x == 3i8 { ret ok }
    }
    if str.eq(mode, "mulu16") {
        let x = 10000u16 * u16(n)
        if x == 3u16 { ret ok }
    }
    if str.eq(mode, "add64") {
        let x = 9223372036854775801i64 + i64(n)
        if x == 3i64 { ret ok }
    }
    if str.eq(mode, "subusize") {
        let x = 3usize - n
        if x == 3usize { ret ok }
    }
    if str.eq(mode, "mulusize") {
        let x = 3000000000000000000usize * n
        if x == 3usize { ret ok }
    }
    if str.eq(mode, "muli64") {
        let x = 3000000000000000000i64 * i64(n)
        if x == 3i64 { ret ok }
    }
    if str.eq(mode, "neg") {
        let m = i16(0i32 - 32761i32 - i32(n))
        let x = -m
        if x == 3i16 { ret ok }
    }
    let fine = 2147483640i32 - i32(n) * 3i32 + i32(n)
    if fine == 3i32 { ret ok }
    let big = 9223372036854775800usize + n
    if big == 3usize { ret ok }
    let product = 3000000000usize * n + 4000000000000000000usize * 4usize / 2usize
    if product == 3usize { ret ok }
    let wrapped = 2147483647i32 +% i32(n)
    if wrapped != -2147483642i32 { ret ok }
    let negated = -i16(n)
    if negated != -7i16 { ret ok }
    ret ok
}
