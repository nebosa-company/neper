// Section 11's release build, `emit-executable ... --release`: the debug-only rows are
// left out and their release results stand in their place -- `+` wraps, a narrowing
// cast truncates, a shift count is masked, and a float outside its target saturates,
// NaN to 0, on every target -- while the rows that trap in every mode are untouched.
// The runner builds this once in each mode: in debug the first `+` traps; in release
// every check below passes and the program exits 0. The values come from the
// argument count so nothing folds.
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    let n = args.len + 5usize
    // overflow wraps
    let wrapped = 250u8 + u8(n)
    if wrapped != 0u8 { os.exit(1i32) }
    // narrow truncates
    let cut = u8(n + 300usize)
    if cut != 50u8 { os.exit(2i32) }
    // shift masks
    let shifted = 1u32 << u32(n + 30usize)
    if shifted != 16u32 { os.exit(3i32) }
    // float saturates
    let big = i32(f64(n) * 1e18f64)
    if big != 2147483647i32 { os.exit(4i32) }
    let low = i16(0.0f32 - f32(n) * 1e9f32)
    if low != -32768i16 { os.exit(5i32) }
    let nan = f64(n) / 0.0f64 - f64(n) / 0.0f64
    if i64(nan) != 0i64 { os.exit(6i32) }
    let under = u32(0.0f64 - f64(n))
    if under != 0u32 { os.exit(7i32) }
    let fits = u8(f64(n) * 30.0f64)
    if fits != 180u8 { os.exit(8i32) }
    let top = u64(2e19f64)
    if top != 18446744073709551615u64 { os.exit(9i32) }
    let exact = i64(0.0f64 - f64(n) * 1.5e18f64)
    if exact != -9000000000000000000i64 { os.exit(10i32) }
    // the release rows still trap
    if args.len > 100usize {
        let q = 7usize / (n - 6usize)
        if q == 1usize { ret ok }
    }
    ret ok
}
