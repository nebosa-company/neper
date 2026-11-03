use e.mem
use e.os
use e.simd

type F32x4 = Vec[f32, 4]
type I32x4 = Vec[i32, 4]

// `round_i32` (one `cvtps2dq` where the target has it): ties to even, and NaN or out-of-range lanes are the integer's least value.
fn check_round() -> bool {
    var d: [8]f32 = zero
    d[0usize] = 0.5
    d[1usize] = 1.5
    d[2usize] = 2.5
    d[3usize] = 0.0 - 1.5
    d[4usize] = 2147483520.0
    d[5usize] = 2147483648.0
    d[6usize] = 0.0 - 3000000000.0
    d[7usize] = mem.bitcast[f32](2143289344u32)
    let a = simd.round_i32[F32x4, I32x4](simd.load[F32x4](d[0usize..8usize], 0usize))
    let b = simd.round_i32[F32x4, I32x4](simd.load[F32x4](d[0usize..8usize], 4usize))
    let least = 0i32 - 2147483647i32 - 1i32
    ret a.lanes[0usize] == 0i32 && a.lanes[1usize] == 2i32 && a.lanes[2usize] == 2i32 && a.lanes[3usize] == 0i32 - 2i32 && b.lanes[0usize] == 2147483520i32 && b.lanes[1usize] == least && b.lanes[2usize] == least && b.lanes[3usize] == least
}

// A chain of float arithmetic whose intermediates only feed the next operation: whatever NaN goes in (an infinity times zero, a
// signalling NaN, one with a payload), the answer's NaN lanes are the canonical 0x7fc00000.
fn chain(x: F32x4, y: F32x4, z: F32x4) -> F32x4 {
    ret x * y + z * x - y / z
}

fn canonical(v: F32x4, lane: usize) -> bool {
    ret mem.bitcast[u32](v.lanes[lane]) == 2143289344u32
}

fn main(a: *mem.Arena, args: []str) -> err {
    if !check_round() { os.exit(1i32) }
    var d: [12]u32 = zero
    d[0usize] = 2139095040u32
    d[1usize] = 2141192193u32
    d[2usize] = 1065353216u32
    d[3usize] = 4290772997u32
    d[4usize] = 0u32
    d[5usize] = 1065353216u32
    d[6usize] = 1073741824u32
    d[7usize] = 1065353216u32
    d[8usize] = 1077936128u32
    d[9usize] = 1073741824u32
    d[10usize] = 1065353216u32
    d[11usize] = 2143289443u32
    var f: [12]f32 = zero
    var k = 0usize
    while k < 12usize {
        f[k] = mem.bitcast[f32](d[k])
        k += 1usize
    }
    let x = simd.load[F32x4](f[0usize..12usize], 0usize)
    let y = simd.load[F32x4](f[0usize..12usize], 4usize)
    let z = simd.load[F32x4](f[0usize..12usize], 8usize)
    let r = chain(x, y, z)
    if !canonical(r, 0usize) || !canonical(r, 1usize) || !canonical(r, 3usize) { os.exit(2i32) }
    if mem.bitcast[u32](r.lanes[2usize]) != 1065353216u32 { os.exit(3i32) }
    let s = chain(y, z, x)
    if !canonical(s, 0usize) || !canonical(s, 1usize) || !canonical(s, 3usize) { os.exit(4i32) }
    ret ok
}
