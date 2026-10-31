// The SPIR-V narrow-float path keeps f16 and bf16 as distinct raw u16 storage
// formats, widens arithmetic to f32, and rounds only at each narrow result.
// This is compile-time coverage: a Vulkan runtime fixture supplies numerical
// conformance separately.
use e.gpu
use e.math
use e.mem
use e.simd

@gpu(4)
fn narrow(n: u32, hs: []const f16, bs: []const bf16, fs: []const f32, ds: []const f64, ints: []const i32, ho: []f16, bo: []bf16, fo: []f32, flags: []u32) {
    let id = gpu.gid.x
    if id >= n { ret }
    let at = usize(id)
    let h = hs[at]
    let b = bs[at]
    let f = fs[at]
    let d = ds[at]
    let integer = ints[at]
    let h_offset = at * 13usize
    let b_offset = at * 13usize

    ho[h_offset] = h + 1.0f16
    ho[h_offset + 1usize] = h - h
    ho[h_offset + 2usize] = h * h
    ho[h_offset + 3usize] = h / h
    ho[h_offset + 4usize] = math.sqrt[f16](h)
    ho[h_offset + 5usize] = -h
    ho[h_offset + 6usize] = math.fma[f16](h, h, h)
    ho[h_offset + 7usize] = f16(f32(h))
    ho[h_offset + 9usize] = f16(integer)
    ho[h_offset + 10usize] = f16(d)
    ho[h_offset + 11usize] = mem.bitcast[f16](mem.bitcast[u16](h))
    ho[h_offset + 12usize] = f16(b)

    bo[b_offset] = b + 1.0bf16
    bo[b_offset + 1usize] = b - b
    bo[b_offset + 2usize] = b * b
    bo[b_offset + 3usize] = b / b
    bo[b_offset + 4usize] = math.sqrt[bf16](b)
    bo[b_offset + 5usize] = -b
    bo[b_offset + 6usize] = math.fma[bf16](b, b, b)
    bo[b_offset + 7usize] = bf16(f32(b))
    bo[b_offset + 9usize] = bf16(u32(integer & 2147483647i32))
    bo[b_offset + 10usize] = bf16(d)
    bo[b_offset + 11usize] = mem.bitcast[bf16](mem.bitcast[u16](b))
    bo[b_offset + 12usize] = bf16(h)

    var h_left: Vec[f16, 8] = zero
    var h_right: Vec[f16, 8] = zero
    var h_addend: Vec[f16, 8] = zero
    h_left.lanes[0] = h
    h_left.lanes[1] = h
    h_right.lanes[0] = h
    h_right.lanes[1] = h
    h_addend.lanes[0] = h
    h_addend.lanes[1] = h
    let h_vector = simd.fma[Vec[f16, 8]](h_left, h_right, h_addend)
    ho[h_offset + 8usize] = h_vector.lanes[0]

    var b_left: Vec[bf16, 8] = zero
    var b_right: Vec[bf16, 8] = zero
    var b_addend: Vec[bf16, 8] = zero
    b_left.lanes[0] = b
    b_left.lanes[1] = b
    b_right.lanes[0] = b
    b_right.lanes[1] = b
    b_addend.lanes[0] = b
    b_addend.lanes[1] = b
    let b_vector = simd.fma[Vec[bf16, 8]](b_left, b_right, b_addend)
    bo[b_offset + 8usize] = b_vector.lanes[0]

    var f_left: Vec[f32, 4] = zero
    var f_right: Vec[f32, 4] = zero
    var f_addend: Vec[f32, 4] = zero
    f_left.lanes[0] = f
    f_left.lanes[1] = f
    f_right.lanes[0] = f
    f_right.lanes[1] = f
    f_addend.lanes[0] = f
    f_addend.lanes[1] = f
    let f_vector = simd.fma[Vec[f32, 4]](f_left, f_right, f_addend)
    fo[at] = f_vector.lanes[0]

    var compared = 0u32
    if h < h { compared = compared | 1u32 }
    if h <= h { compared = compared | 2u32 }
    if h > h { compared = compared | 4u32 }
    if h >= h { compared = compared | 8u32 }
    if h == h { compared = compared | 16u32 }
    if h != h { compared = compared | 32u32 }
    if b < b { compared = compared | 64u32 }
    if b <= b { compared = compared | 128u32 }
    if b > b { compared = compared | 256u32 }
    if b >= b { compared = compared | 512u32 }
    if b == b { compared = compared | 1024u32 }
    if b != b { compared = compared | 2048u32 }
    flags[at] = compared
}

fn main() {}
