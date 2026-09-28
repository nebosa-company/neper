// The platform's own libraries, built by nobody here. Win64 passes eight bytes as their
// bits and sixteen as a copy's address, and returns sixteen through a hidden pointer.
type Key = struct { k: i64 }
type LongDiv = struct { quot: i64, rem: i64 }
type Complex = struct { x: f64, y: f64 }

// The call that found the bug: the key's address arrived where its bits belong.
@import("msvcrt", "_abs64")
extern fn key_abs(k: Key) -> i64

@import("ucrtbase", "lldiv")
extern fn long_div(a: i64, b: i64) -> LongDiv

@import("msvcrt", "_cabs")
extern fn modulus(z: Complex) -> f64
