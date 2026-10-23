@import("libc.so.6", "memset")
extern fn raw_zero(dst: *u8, value: i32, count: usize) -> *u8

fn fill_zero(dst: *u8, count: usize) {
    let ignored = raw_zero(dst, 0i32, count)
}
