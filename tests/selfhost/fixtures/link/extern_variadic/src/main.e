// A C variadic `extern fn` (spec section 5): `snprintf` called with an `i32`, an `i64`,
// an `f64`, a C string and one more `i32` past the fixed parameters -- eight arguments,
// so on both conventions some spill to the stack, and the `f64` is the case each
// convention makes special: Win64 wants it in the integer register of its position as
// well, and System V wants `al` to say how many xmm registers were used. Getting either
// wrong prints garbage rather than failing to link, so the text is compared exactly.
//
// Which library `snprintf` comes from is per-platform, so the declaration is in `plat`.
use plat

error Failed

fn main() -> err {
    var out: [64]u8 = zero
    let n = plat.format_into(out[0..], 42i32, -100000000000i64, 2.5f64, "ok\x00", 7i32)
    if n != 26i32 { ret Failed }
    let expected = "42 -100000000000 2.50 ok 7"
    var at = 0usize
    while at < expected.len {
        if out[at] != expected[at] { ret Failed }
        at += 1usize
    }
    if out[expected.len] != 0u8 { ret Failed }
    // No extra arguments at all is also a call to the same variadic.
    let m = plat.format_none(out[0..], "plain\x00")
    if m != 5i32 || out[0usize] != 112u8 || out[5usize] != 0u8 { ret Failed }
    ret ok
}
