// `--release` on wasm32-wasi (D5650): section 11's debug-only rows are left out as
// codegen_a64 leaves them out -- `+` and unary `-` wrap at every width (the 64-bit ones take
// a separate path), a narrowing cast truncates, a shift count is masked, a float outside its
// target saturates -- while the rows that trap in every mode stay. Built without the flag the
// first `+` traps (exit 134) on every target; built with it the program exits 0. With the
// argument `bounds` the always-on index check traps in both; `address` is the 32-bit address
// row (D5663). The values come from a variable the compiler cannot fold.
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    var n = 6usize
    if args.len > 100usize { n = 7usize }
    let wrapped = 250u8 + u8(n)
    if wrapped != 0u8 { os.exit(1i32) }
    let wide = 9223372036854775807i64 + i64(n)
    if wide != -9223372036854775803i64 { os.exit(2i32) }
    let product = 4611686018427387904u64 * u64(n)
    if product != 9223372036854775808u64 { os.exit(3i32) }
    let low = i8(n + 122usize)
    let flipped = -low
    if flipped != low { os.exit(4i32) }
    let cut = u8(n + 300usize)
    if cut != 50u8 { os.exit(5i32) }
    let shifted = 1u32 << u32(n + 30usize)
    if shifted != 16u32 { os.exit(6i32) }
    let big = i32(f64(n) * 1e18f64)
    if big != 2147483647i32 { os.exit(7i32) }
    let nan = f64(n) / 0.0f64 - f64(n) / 0.0f64
    if i64(nan) != 0i64 { os.exit(8i32) }
    let under = u32(0.0f64 - f64(n))
    if under != 0u32 { os.exit(9i32) }
    if args.len > 1usize && args[1usize].len == 6usize {
        var buffer: [8]u8 = zero
        buffer[n + 2usize] = 1u8
    }
    if args.len > 1usize && args[1usize].len == 7usize {
        var cell: [8]u8 = zero
        var window = mem.Arena { base: &cell[0usize], cap: 1099511627784usize, off: 0usize }
        let far = mem.view(&window, 1099511627776usize, 1usize)
        let forged = &far[0usize]
        *forged = 1u8
        if cell[0usize] != 1u8 { os.exit(10i32) }
    }
    ret ok
}
