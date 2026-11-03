use e.mem
use e.os
use e.simd

type U8x16 = Vec[u8, 16]
type I16x8 = Vec[i16, 8]
type U16x8 = Vec[u16, 8]
type I32x4 = Vec[i32, 4]
type U32x4 = Vec[u32, 4]
type F32x4 = Vec[f32, 4]

// Every packed `e.simd` operation on awkward lanes (extremes, ties, the top bit set), each answer compared with the plain integer
// arithmetic the operation is defined by. The program is the same on every target; a target that lowers the operations to its vector
// instructions is held to the same answers as the loops they replace. Each check exits with its own code.

fn u8_at(i: usize, salt: usize) -> u8 {
    let table = [8]u8{ 0u8, 1u8, 127u8, 128u8, 129u8, 254u8, 255u8, 77u8 }
    ret table[(i * 3usize + salt) % 8usize]
}

fn i16_at(i: usize, salt: usize) -> i16 {
    let table = [8]i16{ 0i16, 1i16, -1i16, 32767i16, -32768i16, 12345i16, -23456i16, 100i16 }
    ret table[(i * 5usize + salt) % 8usize]
}

fn u16_at(i: usize, salt: usize) -> u16 {
    let table = [8]u16{ 0u16, 1u16, 32767u16, 32768u16, 65535u16, 40000u16, 255u16, 256u16 }
    ret table[(i * 3usize + salt) % 8usize]
}

fn i32_at(i: usize, salt: usize) -> i32 {
    let table = [8]i32{ 0i32, 1i32, -1i32, 2147483647i32, -2147483647i32 - 1i32, 123456i32, -654321i32, 65536i32 }
    ret table[(i * 3usize + salt) % 8usize]
}

fn u32_at(i: usize, salt: usize) -> u32 {
    let table = [8]u32{ 0u32, 1u32, 2147483647u32, 2147483648u32, 4294967295u32, 123456u32, 65536u32, 7u32 }
    ret table[(i * 5usize + salt) % 8usize]
}

fn smaller(x: i64, y: i64) -> i64 {
    if x < y { ret x }
    ret y
}

fn larger(x: i64, y: i64) -> i64 {
    if x > y { ret x }
    ret y
}

fn distance(x: i64, y: i64) -> i64 {
    if x > y { ret x - y }
    ret y - x
}

fn clamp(x: i64, low: i64, high: i64) -> i64 {
    if x < low { ret low }
    if x > high { ret high }
    ret x
}

fn main(a: *mem.Arena, args: []str) -> err {
    var ua: U8x16 = zero
    var ub: U8x16 = zero
    var ia: I16x8 = zero
    var ib: I16x8 = zero
    var wa: U16x8 = zero
    var wb: U16x8 = zero
    var la: I32x4 = zero
    var lb: I32x4 = zero
    var ka: U32x4 = zero
    var kb: U32x4 = zero
    var i = 0usize
    while i < 16usize {
        ua.lanes[i] = u8_at(i, 1usize)
        ub.lanes[i] = u8_at(i, 4usize)
        i += 1usize
    }
    i = 0usize
    while i < 8usize {
        ia.lanes[i] = i16_at(i, 2usize)
        ib.lanes[i] = i16_at(i, 5usize)
        wa.lanes[i] = u16_at(i, 1usize)
        wb.lanes[i] = u16_at(i, 6usize)
        i += 1usize
    }
    i = 0usize
    while i < 4usize {
        la.lanes[i] = i32_at(i, 1usize)
        lb.lanes[i] = i32_at(i, 4usize)
        ka.lanes[i] = u32_at(i, 2usize)
        kb.lanes[i] = u32_at(i, 3usize)
        i += 1usize
    }
    // minimum, maximum, saturating add and subtract, average, absolute difference on bytes
    let mn = simd.min[U8x16](ua, ub)
    let mx = simd.max[U8x16](ua, ub)
    let ad = simd.adds[U8x16](ua, ub)
    let sb = simd.subs[U8x16](ua, ub)
    let av = simd.avg_u8[U8x16](ua, ub)
    let df = simd.abs_diff[U8x16](ua, ub)
    i = 0usize
    while i < 16usize {
        let x = i64(ua.lanes[i])
        let y = i64(ub.lanes[i])
        if i64(mn.lanes[i]) != smaller(x, y) { os.exit(1i32) }
        if i64(mx.lanes[i]) != larger(x, y) { os.exit(2i32) }
        if i64(ad.lanes[i]) != clamp(x + y, 0i64, 255i64) { os.exit(3i32) }
        if i64(sb.lanes[i]) != clamp(x - y, 0i64, 255i64) { os.exit(4i32) }
        if i64(av.lanes[i]) != (x + y + 1i64) / 2i64 { os.exit(5i32) }
        if i64(df.lanes[i]) != distance(x, y) { os.exit(6i32) }
        i += 1usize
    }
    // signed words
    let imn = simd.min[I16x8](ia, ib)
    let imx = simd.max[I16x8](ia, ib)
    let iad = simd.adds[I16x8](ia, ib)
    let isb = simd.subs[I16x8](ia, ib)
    let hi = simd.mulhi_i16[I16x8](ia, ib)
    let hr = simd.mulhrs_i16[I16x8](ia, ib)
    i = 0usize
    while i < 8usize {
        let x = i64(ia.lanes[i])
        let y = i64(ib.lanes[i])
        if i64(imn.lanes[i]) != smaller(x, y) { os.exit(7i32) }
        if i64(imx.lanes[i]) != larger(x, y) { os.exit(8i32) }
        if i64(iad.lanes[i]) != clamp(x + y, -32768i64, 32767i64) { os.exit(9i32) }
        if i64(isb.lanes[i]) != clamp(x - y, -32768i64, 32767i64) { os.exit(10i32) }
        if i64(hi.lanes[i]) != (x * y) >> 16u32 { os.exit(11i32) }
        var want = (((x * y) >> 14u32) + 1i64) >> 1u32
        if want == 32768i64 { want = -32768i64 }
        if i64(hr.lanes[i]) != want { os.exit(12i32) }
        i += 1usize
    }
    // unsigned words and words of 32 bits
    let wavg = simd.avg_u16[U16x8](wa, wb)
    let wdiff = simd.abs_diff[U16x8](wa, wb)
    let wmin = simd.min[U16x8](wa, wb)
    let kmax = simd.max[U32x4](ka, kb)
    let lmin = simd.min[I32x4](la, lb)
    i = 0usize
    while i < 8usize {
        let x = i64(wa.lanes[i])
        let y = i64(wb.lanes[i])
        if i64(wavg.lanes[i]) != (x + y + 1i64) / 2i64 { os.exit(13i32) }
        if i64(wdiff.lanes[i]) != distance(x, y) { os.exit(14i32) }
        if i64(wmin.lanes[i]) != smaller(x, y) { os.exit(15i32) }
        i += 1usize
    }
    i = 0usize
    while i < 4usize {
        let x = i64(ka.lanes[i])
        let y = i64(kb.lanes[i])
        if i64(kmax.lanes[i]) != larger(x, y) { os.exit(16i32) }
        let p = i64(la.lanes[i])
        let q = i64(lb.lanes[i])
        if i64(lmin.lanes[i]) != smaller(p, q) { os.exit(17i32) }
        i += 1usize
    }
    // multiply-add of words, sum of absolute differences
    let md = simd.madd_i16[I16x8](ia, ib)
    i = 0usize
    while i < 4usize {
        let want = i32(ia.lanes[2usize * i]) * i32(ib.lanes[2usize * i]) +% i32(ia.lanes[2usize * i + 1usize]) * i32(ib.lanes[2usize * i + 1usize])
        if md.lanes[i] != want { os.exit(18i32) }
        i += 1usize
    }
    let sd = simd.sad_u8[U8x16](ua, ub)
    var half = 0usize
    while half < 2usize {
        var total = 0i64
        var k = 0usize
        while k < 8usize {
            let x = i64(ua.lanes[half * 8usize + k])
            let y = i64(ub.lanes[half * 8usize + k])
            total += distance(x, y)
            k += 1usize
        }
        if i64(sd.lanes[half]) != total { os.exit(19i32) }
        half += 1usize
    }
    // interleave and pack
    let lo = simd.unpack_lo[U8x16](ua, ub)
    let up = simd.unpack_hi[U8x16](ua, ub)
    i = 0usize
    while i < 8usize {
        if lo.lanes[2usize * i] != ua.lanes[i] || lo.lanes[2usize * i + 1usize] != ub.lanes[i] { os.exit(20i32) }
        if up.lanes[2usize * i] != ua.lanes[8usize + i] || up.lanes[2usize * i + 1usize] != ub.lanes[8usize + i] { os.exit(21i32) }
        i += 1usize
    }
    let pus = simd.pack_sat[U8x16, I16x8](ia, ib)
    let pss = simd.pack_sat[Vec[i8, 16], I16x8](ia, ib)
    let p32 = simd.pack_sat[I16x8, I32x4](la, lb)
    let pu32 = simd.pack_sat[U16x8, I32x4](la, lb)
    i = 0usize
    while i < 8usize {
        if i64(pus.lanes[i]) != clamp(i64(ia.lanes[i]), 0i64, 255i64) || i64(pus.lanes[8usize + i]) != clamp(i64(ib.lanes[i]), 0i64, 255i64) { os.exit(22i32) }
        if i64(pss.lanes[i]) != clamp(i64(ia.lanes[i]), -128i64, 127i64) || i64(pss.lanes[8usize + i]) != clamp(i64(ib.lanes[i]), -128i64, 127i64) { os.exit(23i32) }
        i += 1usize
    }
    i = 0usize
    while i < 4usize {
        if i64(p32.lanes[i]) != clamp(i64(la.lanes[i]), -32768i64, 32767i64) || i64(p32.lanes[4usize + i]) != clamp(i64(lb.lanes[i]), -32768i64, 32767i64) { os.exit(24i32) }
        if i64(pu32.lanes[i]) != clamp(i64(la.lanes[i]), 0i64, 65535i64) || i64(pu32.lanes[4usize + i]) != clamp(i64(lb.lanes[i]), 0i64, 65535i64) { os.exit(25i32) }
        i += 1usize
    }
    // byte shuffle: an index with the top bit set, or past fifteen, is zero
    var index: U8x16 = zero
    i = 0usize
    while i < 16usize {
        index.lanes[i] = u8((i * 7usize + 3usize) % 16usize)
        i += 1usize
    }
    index.lanes[2usize] = 128u8
    index.lanes[5usize] = 255u8
    index.lanes[9usize] = 17u8
    let sh = simd.shuffle_bytes[U8x16](ua, index)
    i = 0usize
    while i < 16usize {
        var want = 0u8
        if (index.lanes[i] & 128u8) == 0u8 { want = ua.lanes[usize(index.lanes[i] & 15u8)] }
        if sh.lanes[i] != want { os.exit(26i32) }
        i += 1usize
    }
    // one bit per byte, the top one
    let mm = simd.movemask[U8x16](ua)
    var mask_want = 0u64
    i = 0usize
    while i < 16usize {
        if (ua.lanes[i] & 128u8) != 0u8 { mask_want = mask_want | (1u64 << u64(i)) }
        i += 1usize
    }
    if mm != mask_want { os.exit(27i32) }
    // comparisons and select, integer and float
    let eq = simd.cmp_eq[U8x16](ua, ub)
    let gt = simd.cmp_gt[U8x16](ua, ub)
    let le = simd.cmp_le[U8x16](ua, ub)
    let ne = simd.cmp_ne[U8x16](ua, ub)
    i = 0usize
    while i < 16usize {
        if eq.lanes[i] != (ua.lanes[i] == ub.lanes[i]) { os.exit(28i32) }
        if gt.lanes[i] != (ua.lanes[i] > ub.lanes[i]) { os.exit(29i32) }
        if le.lanes[i] != (ua.lanes[i] <= ub.lanes[i]) { os.exit(30i32) }
        if ne.lanes[i] != (ua.lanes[i] != ub.lanes[i]) { os.exit(31i32) }
        i += 1usize
    }
    let sgt = simd.cmp_gt[I16x8](ia, ib)
    let sle = simd.cmp_le[I16x8](ia, ib)
    let ugt = simd.cmp_gt[U32x4](ka, kb)
    let seq = simd.cmp_eq[I32x4](la, lb)
    i = 0usize
    while i < 8usize {
        if sgt.lanes[i] != (ia.lanes[i] > ib.lanes[i]) { os.exit(32i32) }
        if sle.lanes[i] != (ia.lanes[i] <= ib.lanes[i]) { os.exit(33i32) }
        i += 1usize
    }
    i = 0usize
    while i < 4usize {
        if ugt.lanes[i] != (ka.lanes[i] > kb.lanes[i]) { os.exit(34i32) }
        if seq.lanes[i] != (la.lanes[i] == lb.lanes[i]) { os.exit(35i32) }
        i += 1usize
    }
    let chosen = simd.select[I16x8](sgt, ia, ib)
    i = 0usize
    while i < 8usize {
        var want = ib.lanes[i]
        if ia.lanes[i] > ib.lanes[i] { want = ia.lanes[i] }
        if chosen.lanes[i] != want { os.exit(36i32) }
        i += 1usize
    }
    var fa: F32x4 = zero
    var fb: F32x4 = zero
    fa.lanes[0usize] = 1.5
    fb.lanes[0usize] = 1.5
    fa.lanes[1usize] = 2.0
    fb.lanes[1usize] = 3.0
    fa.lanes[2usize] = mem.bitcast[f32](2143289344u32)
    fb.lanes[2usize] = 1.0
    fa.lanes[3usize] = 5.0
    fb.lanes[3usize] = -5.0
    let feq = simd.cmp_eq[F32x4](fa, fb)
    let flt = simd.cmp_lt[F32x4](fa, fb)
    let fle = simd.cmp_le[F32x4](fa, fb)
    let fne = simd.cmp_ne[F32x4](fa, fb)
    let fge = simd.cmp_ge[F32x4](fa, fb)
    if !feq.lanes[0usize] || feq.lanes[1usize] || feq.lanes[2usize] || feq.lanes[3usize] { os.exit(37i32) }
    if flt.lanes[0usize] || !flt.lanes[1usize] || flt.lanes[2usize] || flt.lanes[3usize] { os.exit(38i32) }
    if !fle.lanes[0usize] || !fle.lanes[1usize] || fle.lanes[2usize] || fle.lanes[3usize] { os.exit(39i32) }
    if fne.lanes[0usize] || !fne.lanes[1usize] || !fne.lanes[2usize] || !fne.lanes[3usize] { os.exit(40i32) }
    if !fge.lanes[0usize] || fge.lanes[1usize] || fge.lanes[2usize] || !fge.lanes[3usize] { os.exit(41i32) }
    // splat, and the rounding conversion
    let spl = simd.splat[I32x4](-7i32)
    i = 0usize
    while i < 4usize {
        if spl.lanes[i] != -7i32 { os.exit(42i32) }
        i += 1usize
    }
    var rr: F32x4 = zero
    rr.lanes[0usize] = 2.5
    rr.lanes[1usize] = -1.5
    rr.lanes[2usize] = 3000000000.0
    rr.lanes[3usize] = mem.bitcast[f32](2143289344u32)
    let rn = simd.round_i32[F32x4, I32x4](rr)
    if rn.lanes[0usize] != 2i32 || rn.lanes[1usize] != -2i32 { os.exit(43i32) }
    if rn.lanes[2usize] != 0i32 - 2147483647i32 - 1i32 || rn.lanes[3usize] != 0i32 - 2147483647i32 - 1i32 { os.exit(44i32) }
    ret ok
}
