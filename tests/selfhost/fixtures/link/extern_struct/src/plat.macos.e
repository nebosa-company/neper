// The platform's own libraries, built by nobody here. System V passes eight bytes of
// integer in one register, returns sixteen in rax and rdx, and takes a `double complex`
// -- two doubles -- in xmm0 and xmm1.
type Key = struct { k: i64 }
type LongDiv = struct { quot: i64, rem: i64 }
type Complex = struct { x: f64, y: f64 }

// The call that found the bug: the key's address arrived where its bits belong.
@import("libc.so.6", "labs")
extern fn key_abs(k: Key) -> i64

@import("libc.so.6", "lldiv")
extern fn long_div(a: i64, b: i64) -> LongDiv

@import("libm.so.6", "cabs")
extern fn modulus(z: Complex) -> f64
