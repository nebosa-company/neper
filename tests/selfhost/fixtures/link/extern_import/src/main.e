// `extern fn` bound by `@import(LIBRARY, SYMBOL)`, reached through the image's import
// table. Two libraries, so the import directory carries more than one descriptor; a
// repeated symbol, which is one slot both calls read; and effects that are observable,
// so a call that reached the wrong slot is a wrong answer rather than a link error.
//
// The neper-side name is deliberately not the foreign one -- D11 keeps them
// independent, and `@import` is the whole of what ties them together.
error Failed

@import("kernel32", "GetTickCount64")
extern fn tick_count() -> u64

@import("kernel32", "Sleep")
extern fn sleep_ms(ms: u32)

@import("kernel32", "GetCurrentProcessId")
extern fn process_id() -> u32

// A second library, to prove the import directory carries more than one descriptor.
@import("msvcrt", "abs")
extern fn c_abs(v: i32) -> i32

@import("msvcrt", "_abs64")
extern fn c_labs(v: i64) -> i64

fn main() -> err {
    // The neper-side name is not the foreign one: D11 keeps them independent, and
    // `@import` is what ties this declaration to `GetTickCount64`.
    let before = tick_count()
    sleep_ms(30u32)
    let after = tick_count()
    if after < before { ret Failed }
    if after - before < 10u64 { ret Failed }

    if process_id() == 0u32 { ret Failed }

    // Two symbols from a second library, one of them called twice: a repeated symbol
    // is one slot and both calls read it.
    if c_abs(-7i32) != 7i32 { ret Failed }
    if c_abs(7i32) != 7i32 { ret Failed }
    if c_labs(-100000000000i64) != 100000000000i64 { ret Failed }
    ret ok
}
