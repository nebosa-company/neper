// `extern fn` bound by `@import(LIBRARY, SYMBOL)`, reached through whatever the image
// format calls its import table: a descriptor and an address table on PE, and
// `DT_NEEDED` with a `GLOB_DAT` relocation into a slot on ELF. Either way the call is
// an indirect one through a slot the loader fills before this runs.
//
// The neper-side name is deliberately not the foreign one -- D11 keeps them
// independent, and `@import` is the whole of what ties them together. Which library
// each symbol comes from is per-platform, so the declarations live in `plat`.
//
// Every effect checked here is observable, so a call that reached the wrong slot is a
// wrong answer rather than a link error.

use plat

error Failed

fn main() -> err {
    if plat.identity() == 0u32 { ret Failed }

    // A symbol named twice is one slot, and both calls read it.
    if plat.absolute(-7i32) != 7i32 { ret Failed }
    if plat.absolute(7i32) != 7i32 { ret Failed }
    if plat.absolute(-2147483647i32) != 2147483647i32 { ret Failed }

    // A wider one, from the same library on one platform and a second on the other.
    if plat.absolute_wide(-100000000000i64) != 100000000000i64 { ret Failed }

    // A negative `int` from a foreign call. Equality alone would not catch this: the bug
    // it guards is a result read as 0xFFFFFFFF, which compares equal to nothing and is
    // greater than zero, so both the value and its sign are checked.
    if plat.parse_signed("-5") != -5i32 { ret Failed }
    if plat.parse_signed("-5") > 0i32 { ret Failed }
    if plat.parse_signed("-2147483647") != -2147483647i32 { ret Failed }
    if plat.parse_signed("7") != 7i32 { ret Failed }

    // A call with no result, and a clock that has to move across it.
    let before = plat.ticks()
    plat.pause(30u32)
    let after = plat.ticks()
    if after < before { ret Failed }
    ret ok
}
