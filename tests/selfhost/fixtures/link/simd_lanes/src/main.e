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
    // The aligned forms check the address against the vector's width (D210), so the
    // sixteen lanes start at the first 64-byte boundary inside a larger array.
    var raw: [32]f32 = zero
    let base = mem.address_of(&raw[0])
    let skew = (64usize - base % 64usize) % 64usize / 4usize
    var data = raw[skew..skew + 16usize]
    var i = 0usize
    while i < 16usize {
        data[i] = f32(i) * 0.5
        i += 1usize
    }
    let a = simd.load[Vec[f32, 4]](data[0..], 2usize)
    if a.lanes[0] != 1.0 || a.lanes[3] != 2.5 { os.exit(20) }
    let b = simd.load_aligned[Vec[f32, 8]](data[0..], 8usize)
    if b.lanes[0] != 4.0 || b.lanes[7] != 7.5 { os.exit(21) }
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
    // `~` over a whole sixteen-byte vector: every lane distinct, so a packed form that
    // covered only part of the vector would be caught at one end or the other.
    let flipped = ~Vec[u8, 16]{ 0u8, 1u8, 2u8, 3u8, 4u8, 5u8, 6u8, 7u8, 8u8, 9u8, 10u8, 11u8, 12u8, 13u8, 14u8, 15u8 }
    if flipped[0] != 255u8 || flipped[7] != 248u8 || flipped[15] != 240u8 { os.exit(99) }
    // Thirty-two and sixty-four byte vectors are two and four whole registers' worth,
    // and a packed operation reads no lane it is not given, so each is the same
    // instruction once per sixteen-byte chunk over the chunk's own addresses. Every
    // check writes a lane in each chunk, so a form that answered only the first chunk,
    // or read the chunks in the wrong order, is caught.
    var fa = simd.splat[Vec[f32, 8]](1.5)
    fa[0] = 0.5
    fa[4] = 2.5
    fa[7] = 4.0
    let fb = simd.splat[Vec[f32, 8]](2.0)
    let fc = fa * fb + fa
    if fc[0] != 1.5 || fc[3] != 4.5 || fc[4] != 7.5 || fc[7] != 12.0 { os.exit(138) }
    let fd = (fc - fa) / fb
    if fd[0] != 0.5 || fd[4] != 2.5 || fd[7] != 4.0 { os.exit(139) }
    // Section 11's canonical NaN is made lane by lane inside each chunk, so a NaN in
    // the second one is canonical too and the other chunk is untouched by it.
    var fe = simd.splat[Vec[f32, 8]](1.0)
    fe[5] = mem.bitcast[f32](4290772993u32)
    let ff = fe - fe
    if mem.bitcast[u32](ff[5]) != 2143289344u32 { os.exit(140) }
    if ff[0] != 0.0 || ff[7] != 0.0 { os.exit(141) }
    var ia = simd.splat[Vec[i32, 8]](6i32)
    ia[0] = 2147483647i32
    ia[4] = -1i32
    let ib = simd.splat[Vec[i32, 8]](1i32)
    let ic = ia +% ib
    if ic[0] != -2147483648i32 || ic[3] != 7i32 || ic[4] != 0i32 || ic[7] != 7i32 { os.exit(142) }
    let ig = (ia & ib) | (ib ^ ib)
    if ig[0] != 1i32 || ig[3] != 0i32 || ig[4] != 1i32 { os.exit(143) }
    let ih = ~ia
    if ih[0] != -2147483648i32 || ih[3] != -7i32 || ih[4] != 0i32 { os.exit(144) }
    // Sixteen-bit lanes are the one packed multiply the baseline has, at this width too.
    var ja = simd.splat[Vec[i16, 16]](3i16)
    ja[0] = 300i16
    ja[8] = -4i16
    let jb = ja *% simd.splat[Vec[i16, 16]](7i16)
    if jb[0] != 2100i16 || jb[7] != 21i16 || jb[8] != -28i16 || jb[15] != 21i16 { os.exit(145) }
    // Sixty-four bytes are four chunks, with a lane of its own in each.
    var ka = simd.splat[Vec[u8, 64]](9u8)
    ka[0] = 1u8
    ka[16] = 2u8
    ka[32] = 3u8
    ka[63] = 4u8
    let kb = simd.splat[Vec[u8, 64]](250u8)
    let kc = ka +% kb
    if kc[0] != 251u8 || kc[16] != 252u8 || kc[32] != 253u8 || kc[63] != 254u8 { os.exit(146) }
    if kc[1] != 3u8 || kc[47] != 3u8 { os.exit(147) }
    let kd = ~(ka ^ kb)
    if kd[0] != 4u8 || kd[16] != 7u8 || kd[32] != 6u8 || kd[63] != 1u8 { os.exit(148) }
    if kd[1] != 12u8 { os.exit(149) }
    let p = simd.mask[Vec[i32, 4]](3u64)
    let q = simd.mask[Vec[i32, 4]](6u64)
    if simd.bits[Vec[i32, 4]](p & q) != 2u64 { os.exit(88) }
    if simd.bits[Vec[i32, 4]](p | q) != 7u64 { os.exit(89) }
    if simd.bits[Vec[i32, 4]](p ^ q) != 5u64 { os.exit(90) }
    if simd.bits[Vec[i32, 4]](~p) != 12u64 { os.exit(91) }
    // Sixteen mask lanes are sixteen bytes, so `& | ^` take the byte lanes' packed form
    // and `~` a packed form of its own -- a mask lane is `0` or `1`, not eight bits, so
    // its `~` is a compare and a subtract rather than the byte vector's `pxor`. The two
    // patterns differ in every nibble, so a packed form that covered only part of the
    // mask would be caught at one end.
    let ma = simd.mask[Vec[u8, 16]](43981u64)
    let mb = simd.mask[Vec[u8, 16]](61680u64)
    if simd.bits[Vec[u8, 16]](ma & mb) != 41152u64 { os.exit(107) }
    if simd.bits[Vec[u8, 16]](ma | mb) != 64509u64 { os.exit(108) }
    if simd.bits[Vec[u8, 16]](ma ^ mb) != 23357u64 { os.exit(109) }
    if simd.bits[Vec[u8, 16]](~ma) != 21554u64 { os.exit(114) }
    if simd.bits[Vec[u8, 16]](~mb) != 3855u64 { os.exit(115) }
    // A flipped lane is still a mask lane, so it selects and reduces like one.
    if simd.all[Vec[u8, 16]](~ma) || !simd.any[Vec[u8, 16]](~ma) { os.exit(116) }
    if !simd.all[Vec[u8, 16]](~simd.mask[Vec[u8, 16]](0u64)) { os.exit(117) }
    // Eight mask lanes are eight bytes, the register's low half, and take the same four
    // instructions over a quadword move. The mask's width is the lane count and not the
    // vector's, so the mask of a thirty-two-byte vector is packed here while the vector
    // itself is not. The two patterns alternate, so a packed form that reached past the
    // eight bytes, or short of them, would be caught at one end.
    let na = simd.mask[Vec[i16, 8]](180u64)
    let nb = simd.mask[Vec[i16, 8]](90u64)
    if simd.bits[Vec[i16, 8]](na & nb) != 16u64 { os.exit(118) }
    if simd.bits[Vec[i16, 8]](na | nb) != 254u64 { os.exit(119) }
    if simd.bits[Vec[i16, 8]](na ^ nb) != 238u64 { os.exit(120) }
    if simd.bits[Vec[i16, 8]](~na) != 75u64 { os.exit(121) }
    if simd.bits[Vec[i16, 8]](~nb) != 165u64 { os.exit(122) }
    if simd.all[Vec[i16, 8]](~na) || !simd.any[Vec[i16, 8]](~na) { os.exit(123) }
    let wa = simd.mask[Vec[f32, 8]](180u64)
    let wb = simd.mask[Vec[f32, 8]](90u64)
    if simd.bits[Vec[f32, 8]](wa ^ wb) != 238u64 { os.exit(124) }
    if simd.bits[Vec[f32, 8]](~(wa & wb)) != 239u64 { os.exit(125) }
    // Four mask lanes are four bytes, the register's low quarter, and take the same
    // instructions over a doubleword move. The two patterns overlap in two lanes and
    // differ in the other two, so a packed form reaching past the four bytes, or short
    // of them, is caught at one end and a swapped lane in the middle.
    let qa = simd.mask[Vec[f64, 4]](11u64)
    let qb = simd.mask[Vec[f64, 4]](13u64)
    if simd.bits[Vec[f64, 4]](qa & qb) != 9u64 { os.exit(42) }
    if simd.bits[Vec[f64, 4]](qa | qb) != 15u64 { os.exit(43) }
    if simd.bits[Vec[f64, 4]](qa ^ qb) != 6u64 { os.exit(44) }
    if simd.bits[Vec[f64, 4]](~qa) != 4u64 { os.exit(45) }
    if simd.bits[Vec[f64, 4]](~qb) != 2u64 { os.exit(46) }
    if simd.all[Vec[f64, 4]](~qa) || !simd.any[Vec[f64, 4]](~qa) { os.exit(47) }
    // The mask of a sixteen-byte vector is four bytes too, and reduces the same.
    let qc = simd.mask[Vec[i32, 4]](11u64)
    let qd = simd.mask[Vec[i32, 4]](13u64)
    if simd.bits[Vec[i32, 4]](~(qc & qd)) != 6u64 { os.exit(48) }
    if !simd.all[Vec[i32, 4]](qc | ~qc) { os.exit(49) }
    // Two mask lanes are two bytes, the register's low eighth, which no packed move
    // carries in both directions: the pair goes through a general register instead. The
    // two patterns agree in the high lane and differ in the low one, so a move that
    // reads or writes the wrong width is caught either way.
    let ha = simd.mask[Vec[f64, 2]](2u64)
    let hb = simd.mask[Vec[f64, 2]](3u64)
    if simd.bits[Vec[f64, 2]](ha & hb) != 2u64 { os.exit(64) }
    if simd.bits[Vec[f64, 2]](ha | hb) != 3u64 { os.exit(65) }
    if simd.bits[Vec[f64, 2]](ha ^ hb) != 1u64 { os.exit(66) }
    if simd.bits[Vec[f64, 2]](~ha) != 1u64 { os.exit(67) }
    if simd.bits[Vec[f64, 2]](~hb) != 0u64 { os.exit(68) }
    if simd.all[Vec[f64, 2]](~ha) || !simd.any[Vec[f64, 2]](~ha) { os.exit(69) }
    // Thirty-two and sixty-four mask lanes are more bytes than a register holds, so they
    // are two and four whole registers' worth and take the same four instructions once
    // per chunk. The two patterns differ in every chunk, so a form that answered only
    // the first chunk, or read the chunks in the wrong order, is caught.
    let da = simd.mask[Vec[u8, 32]](2779115760u64)
    let db = simd.mask[Vec[u8, 32]](1010604441u64)
    if simd.bits[Vec[u8, 32]](da & db) != 606376080u64 { os.exit(126) }
    if simd.bits[Vec[u8, 32]](da | db) != 3183344121u64 { os.exit(127) }
    if simd.bits[Vec[u8, 32]](da ^ db) != 2576968041u64 { os.exit(128) }
    if simd.bits[Vec[u8, 32]](~da) != 1515851535u64 { os.exit(129) }
    if simd.bits[Vec[u8, 32]](~db) != 3284362854u64 { os.exit(130) }
    if simd.all[Vec[u8, 32]](~da) || !simd.any[Vec[u8, 32]](~da) { os.exit(131) }
    // The mask's width is its lane count and not its vector's, so the thirty-two lanes of
    // a sixty-four-byte vector are the same thirty-two bytes.
    let dc = simd.mask[Vec[i16, 32]](2779115760u64)
    if simd.bits[Vec[i16, 32]](~(dc & dc)) != 1515851535u64 { os.exit(132) }
    if !simd.all[Vec[i16, 32]](dc | ~dc) { os.exit(133) }
    let ea = simd.mask[Vec[u8, 64]](11936211302008789401u64)
    let eb = simd.mask[Vec[u8, 64]](1085185381097498214u64)
    if simd.bits[Vec[u8, 64]](ea & eb) != 361783649600798720u64 { os.exit(134) }
    if simd.bits[Vec[u8, 64]](ea | eb) != 12659613033505488895u64 { os.exit(135) }
    if simd.bits[Vec[u8, 64]](ea ^ eb) != 12297829383904690175u64 { os.exit(136) }
    if simd.bits[Vec[u8, 64]](~ea) != 6510532771700762214u64 { os.exit(137) }
    // A flipped lane is still a mask lane, so it selects and reduces like one.
    if !simd.all[Vec[u8, 64]](~simd.mask[Vec[u8, 64]](0u64)) { os.exit(27) }
    if simd.all[Vec[u8, 64]](~ea) || !simd.any[Vec[u8, 64]](~ea) { os.exit(28) }
    // An integer vector of two lanes has the same two-byte mask, and it reduces the same.
    let hc = simd.mask[Vec[i64, 2]](1u64)
    if simd.bits[Vec[i64, 2]](~hc) != 2u64 { os.exit(58) }
    if !simd.all[Vec[i64, 2]](hc | ~hc) { os.exit(59) }
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
    // Section 11's canonical NaN lane by lane, bit for bit: a NaN that comes out of a
    // vector operation carries no sign and no payload, whichever width the lanes are.
    var g = simd.splat[Vec[f64, 2]](1.0)
    g.lanes[0] = mem.bitcast[f64](18444492273895866369u64)
    let h = g * g
    if mem.bitcast[u64](h.lanes[0]) != 9221120237041090560u64 { os.exit(95) }
    if h.lanes[1] != 1.0 { os.exit(96) }
    var e = simd.splat[Vec[f32, 4]](1.0)
    e.lanes[2] = mem.bitcast[f32](4290772993u32)
    let f = e - e
    if mem.bitcast[u32](f.lanes[2]) != 2143289344u32 { os.exit(97) }
    if f.lanes[0] != 0.0 { os.exit(98) }
}

// Section 4's shifts, which are packed when the count is one the compiler knows: the
// baseline shifts sixteen-, thirty-two- and sixty-four-bit lanes by an immediate, all
// three ways but the arithmetic right shift of a sixty-four-bit lane, and a byte lane
// not at all. Every check has distinct lanes, so a form that shifted the wrong lane
// width, or read past the vector, is caught at one end or the other.
fn shifts() {
    let wa = Vec[i16, 8]{ 1i16, -2i16, 3i16, -4i16, 5i16, -6i16, 7i16, -32768i16 }
    let wl = wa << 2u32
    if wl[0] != 4i16 || wl[1] != -8i16 || wl[7] != 0i16 { os.exit(150) }
    // A signed lane shifts its sign in, which is a different instruction from the one
    // an unsigned lane of the same width takes.
    let wr = wa >> 1u32
    if wr[1] != -1i16 || wr[3] != -2i16 || wr[6] != 3i16 { os.exit(151) }
    let ua = Vec[u16, 8]{ 65535u16, 1u16, 2u16, 3u16, 4u16, 5u16, 6u16, 32768u16 }
    let ur = ua >> 3u32
    if ur[0] != 8191u16 || ur[1] != 0u16 || ur[7] != 4096u16 { os.exit(152) }
    // Sixty-four-bit lanes shift left and right unsigned; the arithmetic right shift is
    // the one shape of the three the baseline has no instruction for, so it keeps the
    // lane loop and has to answer the same.
    let qa = Vec[u64, 2]{ 18446744073709551615u64, 1u64 }
    if (qa >> 60u32)[0] != 15u64 || (qa << 63u32)[1] != 9223372036854775808u64 { os.exit(153) }
    let sa = Vec[i64, 2]{ -16i64, 48i64 }
    if (sa >> 2u32)[0] != -4i64 || (sa >> 2u32)[1] != 12i64 { os.exit(154) }
    // A count of zero is still a shift, and the width less one is the largest count a
    // lane admits.
    let za = Vec[i32, 4]{ -1i32, 2i32, 3i32, 4i32 }
    if (za << 0u32)[0] != -1i32 || (za >> 31u32)[0] != -1i32 || (za >> 31u32)[3] != 0i32 { os.exit(155) }
    // A count the compiler does not know is packed too: it rides in the low quadword of
    // a second register, with the check that traps on a count the width does not admit
    // ahead of it, and every lane answers what a written-out count answers.
    let n = u32(za[1])
    if (za << n)[1] != 8i32 || (za >> n)[0] != -1i32 || (za >> n)[3] != 1i32 { os.exit(156) }
    if (wa << n)[0] != 4i16 || (wa >> n)[1] != -1i16 || (ua >> n)[0] != 16383u16 { os.exit(160) }
    // Sixty-four-bit lanes shift left and right unsigned by a register count as well; the
    // signed right shift is the shape with no instruction, so it stays the lane loop.
    if (qa << n)[1] != 4u64 || (qa >> n)[0] != 4611686018427387903u64 { os.exit(161) }
    if (sa << n)[0] != -64i64 || (sa >> n)[0] != -4i64 { os.exit(162) }
    // Byte lanes have no packed shift at all, so they keep the lane loop too.
    let ba = Vec[u8, 16]{ 1u8, 2u8, 4u8, 8u8, 16u8, 32u8, 64u8, 128u8, 255u8, 3u8, 5u8, 9u8, 17u8, 33u8, 65u8, 129u8 }
    if (ba >> 1u32)[8] != 127u8 || (ba << 1u32)[7] != 0u8 { os.exit(157) }
    // Thirty-two bytes are two chunks with the one count in each, so a lane written in
    // the second chunk is shifted like one in the first.
    var wd = simd.splat[Vec[i32, 8]](3i32)
    wd[0] = -8i32
    wd[4] = 64i32
    wd[7] = -1i32
    let ws = wd >> 1u32
    if ws[0] != -4i32 || ws[3] != 1i32 || ws[4] != 32i32 || ws[7] != -1i32 { os.exit(158) }
    let wsl = wd << 4u32
    if wsl[0] != -128i32 || wsl[3] != 48i32 || wsl[4] != 1024i32 || wsl[7] != -16i32 { os.exit(159) }
    // The register count is loaded once per chunk, so the second chunk shifts by it too.
    let wsn = wd << n
    if wsn[0] != -32i32 || wsn[3] != 12i32 || wsn[4] != 256i32 || wsn[7] != -4i32 { os.exit(163) }
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
    shifts()
    spellings()
    shuffles()
    os.exit(0)
}
