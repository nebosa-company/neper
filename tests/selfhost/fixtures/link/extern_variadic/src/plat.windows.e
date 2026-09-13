@import("msvcrt", "_snprintf")
extern fn raw_snprintf(out: *u8, size: usize, format: *const u8, ...) -> i32

fn format_into(out: []u8, a: i32, b: i64, c: f64, s: str, d: i32) -> i32 {
    let format = "%d %lld %.2f %s %d\x00"
    ret raw_snprintf(&out[0usize], out.len, &format[0usize], a, b, c, &s[0usize], d)
}

fn format_none(out: []u8, s: str) -> i32 {
    ret raw_snprintf(&out[0usize], out.len, &s[0usize])
}
