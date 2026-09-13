// An `i16` in a C variadic's `...` position: C would promote it to `int`, neper does
// not promote for you (spec section 5), so the call is refused at check time.
@import("libc", "printf")
extern fn raw_printf(format: *const u8, ...) -> i32

fn main() -> err {
    let small = 3i16
    let format = "%d\x00"
    let ignored = raw_printf(&format[0usize], small)
    ret ok
}
