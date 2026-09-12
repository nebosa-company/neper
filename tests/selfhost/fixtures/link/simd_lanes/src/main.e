// `e.simd` over `Vec[T, N]` and `Mask[T, N]`: the closed table's layout, every intrinsic
// on integer and float lanes, the pairwise reduction order, the masked
// forms at a slice's tail, the two bit intrinsics against their definitions, and section
// 4's lane-wise operators on float, integer and mask lanes, in a generic too, and the
// `Vec[T, N]{ ... }` literal with `v[i]` on both sides of an assignment.
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

fn axpy[V: type](a: V, x: V, y: V) -> V {
    ret a * x + y
}

fn spread[V: type](v: V) -> V {
    let shifted = v << 1u32
    ret shifted | v
}

fn operators() {
    let a = simd.splat[Vec[f32, 4]](1.5)
    let b = simd.splat[Vec[f32, 4]](2.0)
    let c = a * b + a
    if c.lanes[0] != 4.5 || c.lanes[3] != 4.5 { os.exit(80) }
    let d = (c - b) / b
    if d.lanes[2] != 1.25 { os.exit(81) }
    var x: Vec[i32, 4] = zero
    x.lanes[0] = 2147483647i32
    x.lanes[1] = 6i32
    let y = simd.splat[Vec[i32, 4]](1i32)
    // The wrapping forms are the only arithmetic an integer vector has.
    let w = x +% y
    if w.lanes[0] != -2147483648i32 || w.lanes[1] != 7i32 || w.lanes[2] != 1i32 { os.exit(82) }
    let m = (x *% y) -% y
    if m.lanes[1] != 5i32 { os.exit(83) }
    let bits = (x & y) | (y ^ y)
    if bits.lanes[0] != 1i32 || bits.lanes[1] != 0i32 { os.exit(84) }
    let sh = y << 3u32
    if sh.lanes[3] != 8i32 { os.exit(85) }
    let back = sh >> 2u32
    if back.lanes[3] != 2i32 { os.exit(86) }
    let inv = ~y
    if inv.lanes[0] != -2i32 { os.exit(87) }
    let p = simd.mask[Vec[i32, 4]](3u64)
    let q = simd.mask[Vec[i32, 4]](6u64)
    if simd.bits[Vec[i32, 4]](p & q) != 2u64 { os.exit(88) }
    if simd.bits[Vec[i32, 4]](p | q) != 7u64 { os.exit(89) }
    if simd.bits[Vec[i32, 4]](p ^ q) != 5u64 { os.exit(90) }
    if simd.bits[Vec[i32, 4]](~p) != 12u64 { os.exit(91) }
    // Through a generic, where the vector is still `V` when the operator is checked.
    let r = axpy[Vec[f64, 2]](simd.splat[Vec[f64, 2]](2.0), simd.splat[Vec[f64, 2]](3.0), simd.splat[Vec[f64, 2]](1.0))
    if r.lanes[1] != 7.0 { os.exit(92) }
    let t = spread[Vec[u8, 16]](simd.splat[Vec[u8, 16]](5u8))
    if t.lanes[15] != 15u8 { os.exit(93) }
    // A NaN lane stays a NaN lane; the others are untouched by it.
    var n = simd.splat[Vec[f64, 2]](1.0)
    n.lanes[0] = mem.bitcast[f64](9221120237041090560u64)
    let s = n + n
    if s.lanes[0] == s.lanes[0] || s.lanes[1] != 2.0 { os.exit(94) }
}

fn first_two[V: type](v: V) -> f64 {
    ret f64(v[0]) + f64(v[1])
}

fn spellings() {
    let c = Vec[i32, 4]{ 1, 2, 3, 4 }
    if c[0] != 1i32 || c[3] != 4i32 { os.exit(100) }
    var v = Vec[f32, 4]{ 0.5, 1.5, 2.5, 3.5 }
    v[2] = 9.0
    if v[2] != 9.0 || v.lanes[1] != 1.5 { os.exit(101) }
    let i = 3usize
    if v[i] != 3.5 { os.exit(102) }
    let d = (c +% c)[1]
    if d != 4i32 { os.exit(103) }
    if first_two[Vec[f64, 2]](Vec[f64, 2]{ 1.25, 2.0 }) != 3.25 { os.exit(104) }
    let m = Mask[i32, 4]{ true, false, true, false }
    if simd.bits[Vec[i32, 4]](m) != 5u64 { os.exit(105) }
    let wide = Vec[u8, 16]{ 0u8, 1u8, 2u8, 3u8, 4u8, 5u8, 6u8, 7u8, 8u8, 9u8, 10u8, 11u8, 12u8, 13u8, 14u8, 15u8 }
    if simd.reduce_add[Vec[u8, 16]](wide) != 120u8 || wide[15] != 15u8 { os.exit(106) }
}

fn twice_shuffled[V: type, IDX: [meta.array_len[V]()]u8](v: V) -> V {
    let once = simd.shuffle[V, IDX](v, v)
    ret simd.shuffle[V, IDX](once, once)
}

fn shuffles() {
    let a = Vec[i32, 4]{ 10, 11, 12, 13 }
    let b = Vec[i32, 4]{ 20, 21, 22, 23 }
    // Lanes from both operands, `a` first.
    let r = simd.shuffle[Vec[i32, 4], [4]u8{ 3, 0, 5, 7 }](a, b)
    if r[0] != 13i32 || r[1] != 10i32 || r[2] != 21i32 || r[3] != 23i32 { os.exit(110) }
    let rev = simd.shuffle[Vec[i32, 4], [_]u8{ 3u8, 2u8, 1u8, 0u8 }](a, a)
    if rev[0] != 13i32 || rev[3] != 10i32 { os.exit(111) }
    let f = simd.shuffle[Vec[f64, 2], [2]u8{ 1, 2 }](Vec[f64, 2]{ 1.5, 2.5 }, Vec[f64, 2]{ 3.5, 4.5 })
    if f[0] != 2.5 || f[1] != 3.5 { os.exit(112) }
    // The comptime array forwarded by name through another generic.
    let t = twice_shuffled[Vec[i32, 4], [4]u8{ 1, 2, 3, 0 }](a)
    if t[0] != 12i32 || t[3] != 11i32 { os.exit(113) }
}

fn main() {
    layout()
    moves()
    masks()
    reductions()
    conversions()
    bit_intrinsics()
    operators()
    spellings()
    shuffles()
    os.exit(0)
}
