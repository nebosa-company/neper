// The packed forms of three loops of `e.gfx.scene` (an opaque image's row blend, its bytes for the frame, and the copy of those
// bytes to the frame). Where the compiler lowers `e.simd` to vector instructions (x64, AArch64) they are a few instructions a pixel;
// elsewhere the same code is the loops `e.simd` is defined by.

use e.mem
use e.simd

type F32x4 = Vec[f32, 4]
type I32x4 = Vec[i32, 4]
type I16x8 = Vec[i16, 8]
type U8x16 = Vec[u8, 16]

// The byte of a channel value in 0..1 with no float to integer conversion, which saturates and checks: v * 255 is exact in f64, adding
// 2^52 rounds it to an integer, ties to even, and the integer is the sum's low bits. That is the renderer's `channel_byte` except where
// the f32 steps of `v * 255.0 + 0.5` round across a half (about 130 values of v in 0..1, one level apart).
fn vid_byte(v: f32) -> u32 {
    ret u32(mem.bitcast[u64](f64(v) * 255.0f64 + 4503599627370496.0f64) & 255u64)
}

// Pixels from..end of `src` to `dst`, four at a time; the index reached (the rest is the caller's).
fn copy_pixels(dst: []u32, src: []const u32, from: usize, end: usize, bgra: bool) -> usize {
    var i = from
    var swap: U8x16 = zero
    var j = 0usize
    while j < 4usize {
        swap.lanes[j * 4usize] = u8(j * 4usize + 2usize)
        swap.lanes[j * 4usize + 1usize] = u8(j * 4usize + 1usize)
        swap.lanes[j * 4usize + 2usize] = u8(j * 4usize)
        swap.lanes[j * 4usize + 3usize] = u8(j * 4usize + 3usize)
        j += 1usize
    }
    @nocheck {
        while i + 4usize <= end {
            var four = *mem.cast[*const U8x16](&src[i])
            if bgra { four = simd.shuffle_bytes[U8x16](four, swap) }
            *mem.cast[*U8x16](&dst[i]) = four
            i += 4usize
        }
    }
    ret i
}

// canvas at `at` (four floats a pixel) takes rows[h0 + 4i ..] * iv + rows[h1 + 4i ..] * fv for each of the n pixels whose colv is set.
fn blend_row(canvas: []f32, start: usize, rows: []const f32, h0: usize, h1: usize, colv: []const bool, n: usize, iv: f32, fv: f32) {
    let ivv = simd.splat[F32x4](iv)
    let fvv = simd.splat[F32x4](fv)
    var at = start
    var i = 0usize
    @nocheck {
        while i < n {
            if colv[i] {
                let o = i * 4usize
                *mem.cast[*F32x4](&canvas[at]) = *mem.cast[*const F32x4](&rows[h0 + o]) * ivv + *mem.cast[*const F32x4](&rows[h1 + o]) * fvv
            }
            at += 4usize
            i += 1usize
        }
    }
}

// The bytes of `count` canvas pixels from `from` to vid[to ..], red first, four pixels at a time.
fn row_bytes(canvas: []const f32, start: usize, vid: []u32, first: usize, count: usize) {
    var from = start
    var to = first
    var i = 0usize
    let scale = simd.splat[F32x4](255.0)
    @nocheck {
        while i + 4usize <= count {
            let q0 = simd.round_i32[F32x4, I32x4](*mem.cast[*const F32x4](&canvas[from]) * scale)
            let q1 = simd.round_i32[F32x4, I32x4](*mem.cast[*const F32x4](&canvas[from + 4usize]) * scale)
            let q2 = simd.round_i32[F32x4, I32x4](*mem.cast[*const F32x4](&canvas[from + 8usize]) * scale)
            let q3 = simd.round_i32[F32x4, I32x4](*mem.cast[*const F32x4](&canvas[from + 12usize]) * scale)
            *mem.cast[*U8x16](&vid[to]) = simd.pack_sat[U8x16, I16x8](simd.pack_sat[I16x8, I32x4](q0, q1), simd.pack_sat[I16x8, I32x4](q2, q3))
            from += 16usize
            to += 4usize
            i += 4usize
        }
        while i < count {
            vid[to] = vid_byte(canvas[from]) | (vid_byte(canvas[from + 1usize]) << 8u32) | (vid_byte(canvas[from + 2usize]) << 16u32) | (vid_byte(canvas[from + 3usize]) << 24u32)
            from += 4usize
            to += 1usize
            i += 1usize
        }
    }
}
