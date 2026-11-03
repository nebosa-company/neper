// An 8-tap horizontal FIR over 10-bit rows (motion compensation) and a row sum, scalar and Vec (D5960).
// Run: edit MODE, `neper emit-executable benchmarks/cpu/simd_fir/src/main.e . x64 windows out.exe --release`;
// the exit code is the elapsed time in units of 5 ms (mode 4 checks Vec against scalar and exits 0).
// MODE 0/1: FIR scalar/Vec, 2/3: row sum scalar/Vec, 4: check Vec against scalar.
use e.os
use e.simd
use e.time

const MODE: usize = 0usize
const W: usize = 2048usize

fn fir_scalar(src: []i16, dst: []i16, taps: []i16, n: usize) {
    var x = 0usize
    while x < n {
        var sum = 0i32
        var k = 0usize
        while k < 8usize {
            sum += i32(taps[k]) * i32(src[x + k])
            k += 1usize
        }
        var r = (sum + 64i32) >> 7u32
        if r < 0i32 { r = 0i32 }
        if r > 1023i32 { r = 1023i32 }
        dst[x] = i16(r)
        x += 1usize
    }
}

fn fir_vec(src: []i16, dst: []i16, taps: []i16, n: usize) {
    let t01 = Vec[i16, 8]{ taps[0], taps[1], taps[0], taps[1], taps[0], taps[1], taps[0], taps[1] }
    let t23 = Vec[i16, 8]{ taps[2], taps[3], taps[2], taps[3], taps[2], taps[3], taps[2], taps[3] }
    let t45 = Vec[i16, 8]{ taps[4], taps[5], taps[4], taps[5], taps[4], taps[5], taps[4], taps[5] }
    let t67 = Vec[i16, 8]{ taps[6], taps[7], taps[6], taps[7], taps[6], taps[7], taps[6], taps[7] }
    let round = simd.splat[Vec[i32, 4]](64i32)
    let top = simd.splat[Vec[i16, 8]](1023i16)
    let floor = simd.splat[Vec[i16, 8]](0i16)
    var x = 0usize
    while x < n {
        let s0 = simd.load[Vec[i16, 8]](src, x)
        let s1 = simd.load[Vec[i16, 8]](src, x + 1usize)
        let s2 = simd.load[Vec[i16, 8]](src, x + 2usize)
        let s3 = simd.load[Vec[i16, 8]](src, x + 3usize)
        let s4 = simd.load[Vec[i16, 8]](src, x + 4usize)
        let s5 = simd.load[Vec[i16, 8]](src, x + 5usize)
        let s6 = simd.load[Vec[i16, 8]](src, x + 6usize)
        let s7 = simd.load[Vec[i16, 8]](src, x + 7usize)
        var lo = simd.madd_i16[Vec[i16, 8]](simd.unpack_lo[Vec[i16, 8]](s0, s1), t01)
        var hi = simd.madd_i16[Vec[i16, 8]](simd.unpack_hi[Vec[i16, 8]](s0, s1), t01)
        lo = lo +% simd.madd_i16[Vec[i16, 8]](simd.unpack_lo[Vec[i16, 8]](s2, s3), t23)
        hi = hi +% simd.madd_i16[Vec[i16, 8]](simd.unpack_hi[Vec[i16, 8]](s2, s3), t23)
        lo = lo +% simd.madd_i16[Vec[i16, 8]](simd.unpack_lo[Vec[i16, 8]](s4, s5), t45)
        hi = hi +% simd.madd_i16[Vec[i16, 8]](simd.unpack_hi[Vec[i16, 8]](s4, s5), t45)
        lo = lo +% simd.madd_i16[Vec[i16, 8]](simd.unpack_lo[Vec[i16, 8]](s6, s7), t67)
        hi = hi +% simd.madd_i16[Vec[i16, 8]](simd.unpack_hi[Vec[i16, 8]](s6, s7), t67)
        lo = (lo +% round) >> 7u32
        hi = (hi +% round) >> 7u32
        let packed = simd.pack_sat[Vec[i16, 8], Vec[i32, 4]](lo, hi)
        let clamped = simd.min[Vec[i16, 8]](simd.max[Vec[i16, 8]](packed, floor), top)
        simd.store[Vec[i16, 8]](dst, x, clamped)
        x += 8usize
    }
}

fn sum_scalar(src: []i16, n: usize) -> i64 {
    var total = 0i64
    var x = 0usize
    while x < n {
        total += i64(src[x])
        x += 1usize
    }
    ret total
}

fn sum_vec(src: []i16, n: usize) -> i64 {
    let ones = simd.splat[Vec[i16, 8]](1i16)
    var acc = simd.splat[Vec[i32, 4]](0i32)
    var x = 0usize
    while x < n {
        acc = acc +% simd.madd_i16[Vec[i16, 8]](simd.load[Vec[i16, 8]](src, x), ones)
        x += 8usize
    }
    ret i64(simd.reduce_add[Vec[i32, 4]](acc))
}

fn main() {
    var src: [2064]i16 = zero
    var dst: [2064]i16 = zero
    var ref: [2064]i16 = zero
    var taps: [8]i16 = zero
    taps[0] = -2i16
    taps[1] = 6i16
    taps[2] = -12i16
    taps[3] = 70i16
    taps[4] = 70i16
    taps[5] = -12i16
    taps[6] = 6i16
    taps[7] = -2i16
    var seed = 12345u32
    var i = 0usize
    while i < 2064usize {
        seed = seed *% 1664525u32 +% 1013904223u32
        src[i] = i16(seed >> 22u32)
        i += 1usize
    }
    if MODE == 4usize {
        fir_scalar(src[0..], ref[0..], taps[0..], W)
        fir_vec(src[0..], dst[0..], taps[0..], W)
        var k = 0usize
        while k < W {
            if ref[k] != dst[k] { os.exit(1) }
            k += 1usize
        }
        if sum_scalar(src[0..], W) != sum_vec(src[0..], W) { os.exit(2) }
        os.exit(0)
    }
    let (t0, e0) = time.monotonic()
    var rep = 0usize
    var sink = 0i64
    while rep < 20000usize {
        if MODE == 0usize { fir_scalar(src[0..], dst[0..], taps[0..], W) }
        if MODE == 1usize { fir_vec(src[0..], dst[0..], taps[0..], W) }
        if MODE == 2usize { sink += sum_scalar(src[0..], W) }
        if MODE == 3usize { sink += sum_vec(src[0..], W) }
        src[rep % 64usize] = src[(rep + 1usize) % 64usize]
        rep += 1usize
    }
    let (t1, e1) = time.monotonic()
    if sink == 7i64 { os.exit(250) }
    os.exit(i32((t1.nanos - t0.nanos) / 5000000i64))
}
