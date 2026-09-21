// `e.math.gf`: the AES worked example 0x57 * 0x83 = 0xc1, the inverse of
// 0x53, generator orders (3 is primitive under the AES polynomial, 2 under
// the Reed-Solomon one, and 2 has order 51 under AES), the tables agree
// with `mul` everywhere, and carry-less products and reductions match a
// Python polynomial reference. Each check exits with its own code.

use e.io
use e.math.gf
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: products, powers and inverses.
    if gf.mul(0x57u8, 0x83u8, 0x1bu8) != 0xc1u8 || gf.add(0x57u8, 0x83u8) != 0xd4u8 { os.exit(1i32) }
    let (inverse, inverse_error) = gf.inverse(0x53u8, 0x1bu8)
    if inverse_error != ok || inverse != 0xcau8 || gf.mul(0x53u8, inverse, 0x1bu8) != 1u8 { os.exit(1i32) }
    let (_, zero_error) = gf.inverse(0u8, 0x1bu8)
    if zero_error != gf.Invalid { os.exit(1i32) }
    if gf.pow(3u8, 10u32, 0x1bu8) != 0x72u8 || gf.pow(2u8, 200u32, 0x1du8) != 0x1cu8 || gf.pow(9u8, 0u32, 0x1bu8) != 1u8 { os.exit(1i32) }

    // 2: tables over primitive generators, and a short-order one refused.
    var exp: [510]u8 = zero
    var log: [256]u8 = zero
    if gf.tables(3u8, 0x1bu8, exp[..], log[..]) != ok { os.exit(2i32) }
    var x = 0usize
    while x < 256usize {
        var y = 0usize
        while y < 256usize {
            if gf.mul_table(u8(x), u8(y), exp[..], log[..]) != gf.mul(u8(x), u8(y), 0x1bu8) { os.exit(2i32) }
            y += 1usize
        }
        x += 1usize
    }
    if exp[255usize] != 1u8 || exp[10usize] != 0x72u8 || log[0x72usize] != 10u8 { os.exit(2i32) }
    if gf.tables(2u8, 0x1du8, exp[..], log[..]) != ok || exp[200usize] != 0x1cu8 { os.exit(2i32) }
    if gf.tables(2u8, 0x1bu8, exp[..], log[..]) != gf.Invalid { os.exit(2i32) }
    if gf.tables(3u8, 0x1bu8, exp[..500usize], log[..]) != gf.TooSmall { os.exit(2i32) }

    // 3: carry-less multiplication and reduction.
    let (high, low) = gf.clmul(0x123456789abcdef0u64, 0xfedcba9876543210u64)
    if high != 0x0e038d8688850b04u64 || low != 0x0a0789828c810f00u64 { os.exit(3i32) }
    let (h2, l2) = gf.clmul(0xfedcba9876543210u64, 0x123456789abcdef0u64)
    if h2 != high || l2 != low { os.exit(3i32) }
    let (h1, l1) = gf.clmul(0xffffffffffffffffu64, 2u64)
    if h1 != 1u64 || l1 != 0xfffffffffffffffeu64 { os.exit(3i32) }
    if gf.reduce(high, low, 0x1bu64) != 0x8827ab55d976fa6cu64 { os.exit(3i32) }
    if gf.reduce(0x8000000000000000u64, 0u64, 0x1bu64) != 0x80000000000000afu64 { os.exit(3i32) }
    if gf.reduce(0u64, 12345u64, 0x1bu64) != 12345u64 { os.exit(3i32) }

    try io.print("math gf ok\n")
    ret ok
}
