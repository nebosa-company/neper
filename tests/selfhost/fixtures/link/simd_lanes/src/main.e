// `e.simd` over `Vec[T, N]` and `Mask[T, N]`: the closed table's layout, every intrinsic
// but `shuffle` on integer and float lanes, the pairwise reduction order, the masked
// forms at a slice's tail, and the two bit intrinsics against their definitions.
// Every check has its own exit code.
use e.os
use e.mem
use e.meta
use e.simd

fn layout() {
    if mem.size_of[Vec[f32, 4]]() != 16usize { os.exit(10) }
    if mem.size_of[Vec[f32, 8]]() != 32usize { os.exit(11) }
    if mem.align_of[Vec[f32, 8]]() != 32usize { os.exit(12) }
    if mem.size_of[Vec[u8, 64]]() != 64usize { os.exit(13) }
    if mem.align_of[Vec[i16, 8]]() != 16usize { os.exit(14) }
    if meta.kind[Vec[i64, 2]]() != .Vec { os.exit(15) }
    if meta.kind[Mask[i64, 2]]() != .Vec { os.exit(16) }
    if meta.array_len[Vec[u64, 8]]() != 8usize { os.exit(17) }
    if mem.size_of[meta.element_type[Vec[u16, 8]]()]() != 2usize { os.exit(18) }
    // An array of vectors is laid out at the vector's alignment.
    var pair: [2]Vec[f64, 4] = zero
    pair[1].lanes[3] = 2.5
    if pair[0].lanes[3] != 0.0 || pair[1].lanes[3] != 2.5 { os.exit(19) }
}

fn moves() {
    var data: [12]f32 = zero
    var i = 0usize
    while i < 12usize {
        data[i] = f32(i) * 0.5
        i += 1usize
    }
    let a = simd.load[Vec[f32, 4]](data[0..], 2usize)
    if a.lanes[0] != 1.0 || a.lanes[3] != 2.5 { os.exit(20) }
    let b = simd.load_aligned[Vec[f32, 8]](data[0..], 4usize)
    if b.lanes[0] != 2.0 || b.lanes[7] != 5.5 { os.exit(21) }
    let s = simd.splat[Vec[f32, 4]](-1.0)
    simd.store[Vec[f32, 4]](data[0..], 8usize, s)
    if data[7] != 3.5 || data[8] != -1.0 || data[11] != -1.0 { os.exit(22) }
    simd.store_aligned[Vec[f32, 4]](data[0..], 0usize, a)
    if data[0] != 1.0 || data[3] != 2.5 || data[4] != 2.0 { os.exit(23) }
    // The masked forms only touch enabled lanes, so a tail shorter than a vector is
    // read and written without a scalar loop.
    var tail: [3]i32 = zero
    tail[0] = 7i32
    tail[1] = 8i32
    tail[2] = 9i32
    let low = simd.mask[Vec[i32, 4]](7u64)
    let t = simd.load_masked[Vec[i32, 4]](tail[0..], 0usize, low)
    if t.lanes[0] != 7i32 || t.lanes[2] != 9i32 || t.lanes[3] != 0i32 { os.exit(24) }
    let two = simd.mask[Vec[i32, 4]](5u64)
    simd.store_masked[Vec[i32, 4]](tail[0..], 0usize, two, simd.splat[Vec[i32, 4]](-5i32))
    if tail[0] != -5i32 || tail[1] != 8i32 || tail[2] != -5i32 { os.exit(25) }
    var table: [6]u16 = zero
    i = 0usize
    while i < 6usize {
        table[i] = u16(100usize + i)
        i += 1usize
    }
    var idx: Vec[u32, 8] = zero
    idx.lanes[0] = 5u32
    idx.lanes[1] = 0u32
    idx.lanes[7] = 3u32
    let g = simd.gather[Vec[u16, 8]](table[0..], idx)
    if g.lanes[0] != 105u16 || g.lanes[1] != 100u16 || g.lanes[2] != 100u16 || g.lanes[7] != 103u16 { os.exit(26) }
}

fn masks() {
    var a: Vec[f64, 4] = zero
    var b: Vec[f64, 4] = zero
    a.lanes[0] = 1.0
    b.lanes[0] = 2.0
    a.lanes[1] = 3.0
    b.lanes[1] = 3.0
    a.lanes[2] = 5.0
    b.lanes[2] = 4.0
    let nan = mem.bitcast[f64](9221120237041090560u64)
    a.lanes[3] = nan
    b.lanes[3] = 0.0
    if simd.bits[Vec[f64, 4]](simd.cmp_eq[Vec[f64, 4]](a, b)) != 2u64 { os.exit(30) }
    if simd.bits[Vec[f64, 4]](simd.cmp_ne[Vec[f64, 4]](a, b)) != 13u64 { os.exit(31) }
    if simd.bits[Vec[f64, 4]](simd.cmp_lt[Vec[f64, 4]](a, b)) != 1u64 { os.exit(32) }
    if simd.bits[Vec[f64, 4]](simd.cmp_le[Vec[f64, 4]](a, b)) != 3u64 { os.exit(33) }
    if simd.bits[Vec[f64, 4]](simd.cmp_gt[Vec[f64, 4]](a, b)) != 4u64 { os.exit(34) }
    if simd.bits[Vec[f64, 4]](simd.cmp_ge[Vec[f64, 4]](a, b)) != 6u64 { os.exit(35) }
    let m = simd.cmp_gt[Vec[f64, 4]](a, b)
    let picked = simd.select[Vec[f64, 4]](m, a, b)
    if picked.lanes[0] != 2.0 || picked.lanes[1] != 3.0 || picked.lanes[2] != 5.0 || picked.lanes[3] != 0.0 { os.exit(36) }
    if !simd.any[Vec[f64, 4]](m) || simd.all[Vec[f64, 4]](m) { os.exit(37) }
    var none: Mask[f64, 4] = zero
    if simd.any[Vec[f64, 4]](none) || simd.bits[Vec[f64, 4]](none) != 0u64 { os.exit(38) }
    let every = simd.mask[Vec[f64, 4]](255u64)
    if !simd.all[Vec[f64, 4]](every) || simd.bits[Vec[f64, 4]](every) != 15u64 { os.exit(39) }
    // Integer lanes, the widest table row: 64 lanes of u8 and a 64-bit mask.
    let ones = simd.splat[Vec[u8, 64]](1u8)
    var mixed = ones
    mixed.lanes[63] = 0u8
    let wide = simd.cmp_eq[Vec[u8, 64]](ones, mixed)
    if simd.bits[Vec[u8, 64]](wide) != 9223372036854775807u64 { os.exit(40) }
    let back = simd.mask[Vec[u8, 64]](9223372036854775808u64)
    if !back.lanes[63] || back.lanes[62] || back.lanes[0] { os.exit(41) }
}

fn reductions() {
    var v: Vec[f32, 8] = zero
    // 2^24 + 1 + 1 + ...: a left-to-right sum loses every 1; the tree loses only the first
    // (2^24 + 1 ties to even) and keeps the other six as three pairs of 2.
    v.lanes[0] = 16777216.0
    v.lanes[1] = 1.0
    v.lanes[2] = 1.0
    v.lanes[3] = 1.0
    v.lanes[4] = 1.0
    v.lanes[5] = 1.0
    v.lanes[6] = 1.0
    v.lanes[7] = 1.0
    if simd.reduce_add[Vec[f32, 8]](v) != 16777222.0 { os.exit(50) }
    var w: Vec[i32, 4] = zero
    w.lanes[0] = 2147483647i32
    w.lanes[1] = 1i32
    w.lanes[2] = -7i32
    w.lanes[3] = 3i32
    // (2^31-1 + 1) + (-7 + 3): the first pair wraps, the tree order is what the spec fixes.
    if simd.reduce_add[Vec[i32, 4]](w) != 2147483644i32 { os.exit(51) }
    if simd.reduce_min[Vec[i32, 4]](w) != -7i32 { os.exit(52) }
    if simd.reduce_max[Vec[i32, 4]](w) != 2147483647i32 { os.exit(53) }
    var f: Vec[f64, 2] = zero
    f.lanes[0] = 0.0
    f.lanes[1] = -0.0
    if !math_is_negative(simd.reduce_min[Vec[f64, 2]](f)) { os.exit(54) }
    if math_is_negative(simd.reduce_max[Vec[f64, 2]](f)) { os.exit(55) }
    var u: Vec[u64, 2] = zero
    u.lanes[0] = 18446744073709551615u64
    u.lanes[1] = 2u64
    if simd.reduce_add[Vec[u64, 2]](u) != 1u64 { os.exit(56) }
    if simd.reduce_max[Vec[u64, 2]](u) != 18446744073709551615u64 { os.exit(57) }
}

fn math_is_negative(x: f64) -> bool {
    let sign = mem.bitcast[u64](x) >> 63u32
    ret sign != 0u64
}

fn conversions() {
    var v: Vec[i32, 4] = zero
    v.lanes[0] = -3i32
    v.lanes[1] = 7i32
    v.lanes[3] = 2147483647i32
    let f = simd.convert[Vec[i32, 4], Vec[f64, 4]](v)
    if f.lanes[0] != -3.0 || f.lanes[1] != 7.0 || f.lanes[2] != 0.0 || f.lanes[3] != 2147483647.0 { os.exit(60) }
    let narrow = simd.convert[Vec[i32, 4], Vec[i64, 4]](v)
    if narrow.lanes[0] != -3i64 || narrow.lanes[3] != 2147483647i64 { os.exit(61) }
    var x: Vec[f32, 4] = zero
    x.lanes[0] = 2.0
    x.lanes[1] = 3.0
    x.lanes[2] = 0.5
    x.lanes[3] = -1.0
    let y = simd.splat[Vec[f32, 4]](4.0)
    var z: Vec[f32, 4] = zero
    z.lanes[0] = 1.0
    z.lanes[3] = 0.25
    let r = simd.fma[Vec[f32, 4]](x, y, z)
    if r.lanes[0] != 9.0 || r.lanes[1] != 12.0 || r.lanes[2] != 2.0 || r.lanes[3] != -3.75 { os.exit(62) }
    // fma is fused: (1 + 2^-23)^2 - (1 + 2^-22) is 2^-46, which a rounded product loses.
    let near = simd.splat[Vec[f32, 4]](mem.bitcast[f32](1065353217u32))
    let neg = simd.splat[Vec[f32, 4]](mem.bitcast[f32](3212836866u32))
    let exact = simd.fma[Vec[f32, 4]](near, near, neg)
    if exact.lanes[2] != mem.bitcast[f32](679477248u32) { os.exit(63) }
}

fn bit_intrinsics() {
    if simd.pdep(0u64, 0u64) != 0u64 { os.exit(70) }
    if simd.pdep(65535u64, 4278255360u64) != 4278255360u64 { os.exit(71) }
    if simd.pdep(5u64, 4278255360u64) != 1280u64 { os.exit(72) }
    if simd.pdep(18446744073709551615u64, 18446744073709551615u64) != 18446744073709551615u64 { os.exit(73) }
    if simd.pdep(1u64, 9223372036854775808u64) != 9223372036854775808u64 { os.exit(74) }
    if simd.pext(0u64, 4278255360u64) != 0u64 { os.exit(75) }
    if simd.pext(4278255360u64, 4278255360u64) != 65535u64 { os.exit(76) }
    if simd.pext(1281u64, 4278255360u64) != 5u64 { os.exit(77) }
    if simd.pext(9223372036854775808u64, 9223372036854775808u64) != 1u64 { os.exit(78) }
    if simd.pext(simd.pdep(2989u64, 1234605616436508552u64), 1234605616436508552u64) != 2989u64 { os.exit(79) }
}

fn main() {
    layout()
    moves()
    masks()
    reductions()
    conversions()
    bit_intrinsics()
    os.exit(0)
}
