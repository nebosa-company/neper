// Section 4's checked integer casts and section 11's `narrow` row: `wide` cuts 300 to a
// `u8`, `negative` puts -300 into a `u16`, `sign` puts 200 into an `i8`, `unsigned`
// puts a negative `i32` into a `usize` -- a widening whose sign cannot survive -- and
// `same` reinterprets a high `u32` as an `i32`; each traps with the value in its own
// signedness and the type it did not fit. Anything else runs casts that fit, the meant
// truncations `u8.trunc` and `i16.trunc` on values that do not, and a widening, and
// exits 0. The values come from the argument count so nothing folds.
use e.mem
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    let mode = args[args.len - 1usize]
    let n = args.len + 298usize
    if str.eq(mode, "wide") {
        let b = u8(n)
        if b == 3u8 { ret ok }
    }
    if str.eq(mode, "negative") {
        let m = 0i32 - i32(n)
        let b = u16(m)
        if b == 3u16 { ret ok }
    }
    if str.eq(mode, "sign") {
        let b = i8(u32(n) - 100u32)
        if b == 3i8 { ret ok }
    }
    if str.eq(mode, "unsigned") {
        let b = usize(2i32 - i32(n))
        if b == 3usize { ret ok }
    }
    if str.eq(mode, "same") {
        let b = i32(4294967000u32 + u32(n) - 300u32)
        if b == 3i32 { ret ok }
    }
    let fine = u8(n - 200usize) + u8(i32(n) - 250i32)
    if fine == 3u8 { ret ok }
    let low = i8(0i32 - i32(n) + 200i32)
    if low != -100i8 { ret ok }
    let kept = u8.trunc(n) + u8.trunc(0i32 - i32(n))
    if kept != 0u8 { ret ok }
    let signed_bits = i16.trunc(u32(n) + 65000u32)
    if signed_bits != -236i16 { ret ok }
    let widened = usize(i32(n))
    if widened != 300usize { ret ok }
    ret ok
}
