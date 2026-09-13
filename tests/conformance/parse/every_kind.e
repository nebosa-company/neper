// every keyword, punctuation and literal kind the lexer emits
/// a doc comment
use e.mem as memory
type T = struct { a: i32, b: [4]u8 }
const K: u64 = 0xFFu64 + 1_000 * 2 - 6 / 3 % 2
var g: f64 = 1.5e3
error Bad
type U = union { a: i32, b: f32 }
type E = enum { One, Two }
fn f[N: usize](p: *T, q: []const u8, r: fn(i32) -> bool, ...) -> (i32, err) {
    let s = "text\n"
    let c = 'x'
    let raw = r"raw \ string"
    var x = 1 +% 2 -% 3 *% 4 << 1 >> 1 & 2 | 3 ^ 4
    x += 1
    x -= 1
    x *= 2
    x /= 2
    x %= 3
    x +%= 1
    x -%= 1
    x *%= 1
    x <<= 1
    x >>= 1
    x &= 1
    x ^= 1
    x |= 1
    if x == 1 && x != 2 || x <= 3 && x >= 4 || x < 5 || x > 6 { ret (1, ok) }
    while !true || false { break }
    for i in 0..3 { continue }
    switch x {
    case 1:
        ret (2, ok)
    default:
        ret (3, Bad)
    }
    when target.os == .Windows { } else { }
    defer f[1](nil, q, r)
    try g2()
    var z: T = zero
    var u: T = undef
    @nocheck { z.a = ~x }
    let _ = 5
    shared var sh: i32 = 0i32
    unreachable("x")
    ret (i32(x), ok)
}
extern fn g2() -> err
