// `e.simd`'s codec operations against reference loops written here, on pseudo-random
// lanes biased toward the edges (0, all ones, the sign bit, the largest signed value),
// at sixteen, thirty-two and sixty-four bytes. On x64 most of these calls are one packed
// instruction and the rest the library's lane loop (which one depends on `--cpu`), so
// running the fixture at every level checks both against the same references. Every
// check has its own exit code.
use e.os
use e.mem
use e.meta
use e.simd

fn next(state: *u64) -> u64 {
    var x = *state
    x = x ^ (x << 13u32)
    x = x ^ (x >> 7u32)
    x = x ^ (x << 17u32)
    *state = x
    ret x
}

// A lane biased toward the values saturation, rounding and sign handling care about.
fn pick[T: type](state: *u64) -> T {
    let r = next(state)
    let m = r % 8u64
    if m == 0u64 { ret T.trunc(0u64) }
    if m == 1u64 { ret T.trunc(18446744073709551615u64) }
    if m == 2u64 { ret T.trunc(1u64 << u32(mem.size_of[T]() * 8usize - 1usize)) }
    if m == 3u64 { ret T.trunc((1u64 << u32(mem.size_of[T]() * 8usize - 1usize)) - 1u64) }
    ret T.trunc(r >> 8u32)
}

fn random[V: type](state: *u64) -> V {
    var v: V = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        v.lanes[i] = pick[meta.element_type[V]()](state)
        i += 1usize
    }
    ret v
}

fn lane_trunc[T: type](x: i64) -> T {
    ret T.trunc(x)
}

fn clamp(x: i64, lo: i64, hi: i64) -> i64 {
    if x < lo { ret lo }
    if x > hi { ret hi }
    ret x
}

fn moves() {
    var raw: [96]u8 = zero
    var i = 0usize
    while i < 96usize {
        raw[i] = u8.trunc(i * 7usize + 3usize)
        i += 1usize
    }
    let a = simd.load[Vec[u8, 16]](raw[0..], 5usize)
    var k = 0usize
    while k < 16usize {
        if a.lanes[k] != u8.trunc((k + 5usize) * 7usize + 3usize) { os.exit(10) }
        k += 1usize
    }
    let b = simd.load[Vec[u8, 64]](raw[0..], 32usize)
    k = 0usize
    while k < 64usize {
        if b.lanes[k] != u8.trunc((k + 32usize) * 7usize + 3usize) { os.exit(11) }
        k += 1usize
    }
    var out: [96]u8 = zero
    simd.store[Vec[u8, 32]](out[0..], 3usize, simd.load[Vec[u8, 32]](raw[0..], 40usize))
    k = 0usize
    while k < 96usize {
        var want = 0u8
        if k >= 3usize && k < 35usize { want = u8.trunc((k - 3usize + 40usize) * 7usize + 3usize) }
        if out[k] != want { os.exit(12) }
        k += 1usize
    }
    let s8 = simd.splat[Vec[u8, 16]](201u8)
    let s16 = simd.splat[Vec[u16, 8]](51234u16)
    let s32 = simd.splat[Vec[i32, 8]](-70000i32)
    let s64 = simd.splat[Vec[u64, 4]](0x1122334455667788u64)
    let sf = simd.splat[Vec[f32, 4]](1.5)
    let sd = simd.splat[Vec[f64, 2]](-2.25)
    k = 0usize
    while k < 16usize {
        if s8.lanes[k] != 201u8 { os.exit(13) }
        k += 1usize
    }
    k = 0usize
    while k < 8usize {
        if s16.lanes[k] != 51234u16 { os.exit(14) }
        if s32.lanes[k] != -70000i32 { os.exit(15) }
        k += 1usize
    }
    k = 0usize
    while k < 4usize {
        if s64.lanes[k] != 0x1122334455667788u64 { os.exit(16) }
        if sf.lanes[k] != 1.5 { os.exit(17) }
        k += 1usize
    }
    if sd.lanes[0] != -2.25 || sd.lanes[1] != -2.25 { os.exit(18) }
    // A float vector survives a round trip through memory bit for bit.
    var floats: [8]f32 = zero
    floats[2] = 3.25
    floats[5] = -0.5
    var copy: [8]f32 = zero
    simd.store[Vec[f32, 4]](copy[0..], 4usize, simd.load[Vec[f32, 4]](floats[0..], 1usize))
    if copy[5] != 3.25 || copy[8 - 1] != 0.0 || copy[4] != 0.0 { os.exit(19) }
}

fn min_max[V: type](state: *u64, base: i32) {
    var round = 0usize
    while round < 200usize {
        let a = random[V](state)
        let b = random[V](state)
        let lo = simd.min[V](a, b)
        let hi = simd.max[V](a, b)
        var i = 0usize
        while i < meta.array_len[V]() {
            var want_lo = a.lanes[i]
            var want_hi = b.lanes[i]
            if b.lanes[i] < a.lanes[i] {
                want_lo = b.lanes[i]
                want_hi = a.lanes[i]
            }
            if lo.lanes[i] != want_lo { os.exit(base) }
            if hi.lanes[i] != want_hi { os.exit(base + 1) }
            i += 1usize
        }
        round += 1usize
    }
}

fn saturating[V: type](state: *u64, low: i64, high: i64, base: i32) {
    var round = 0usize
    while round < 200usize {
        let a = random[V](state)
        let b = random[V](state)
        let sum = simd.adds[V](a, b)
        let difference = simd.subs[V](a, b)
        var i = 0usize
        while i < meta.array_len[V]() {
            if i64(sum.lanes[i]) != clamp(i64(a.lanes[i]) + i64(b.lanes[i]), low, high) { os.exit(base) }
            if i64(difference.lanes[i]) != clamp(i64(a.lanes[i]) - i64(b.lanes[i]), low, high) { os.exit(base + 1) }
            i += 1usize
        }
        round += 1usize
    }
}

fn averages(state: *u64) {
    var round = 0usize
    while round < 200usize {
        let a8 = random[Vec[u8, 16]](state)
        let b8 = random[Vec[u8, 16]](state)
        let r8 = simd.avg_u8[Vec[u8, 16]](a8, b8)
        let a16 = random[Vec[u16, 16]](state)
        let b16 = random[Vec[u16, 16]](state)
        let r16 = simd.avg_u16[Vec[u16, 16]](a16, b16)
        var i = 0usize
        while i < 16usize {
            if i64(r8.lanes[i]) != (i64(a8.lanes[i]) + i64(b8.lanes[i]) + 1i64) / 2i64 { os.exit(60) }
            if i64(r16.lanes[i]) != (i64(a16.lanes[i]) + i64(b16.lanes[i]) + 1i64) / 2i64 { os.exit(61) }
            i += 1usize
        }
        round += 1usize
    }
}

fn absolute_difference[V: type](state: *u64, base: i32) {
    var round = 0usize
    while round < 200usize {
        let a = random[V](state)
        let b = random[V](state)
        let r = simd.abs_diff[V](a, b)
        var i = 0usize
        while i < meta.array_len[V]() {
            var want = i64(a.lanes[i]) - i64(b.lanes[i])
            if want < 0i64 { want = 0i64 - want }
            // A signed lane wraps: compare in the lane's own width.
            if meta.signed[meta.element_type[V]()]() {
                if i64(r.lanes[i]) != i64(lane_trunc[meta.element_type[V]()](want)) { os.exit(base) }
            } else {
                if i64(r.lanes[i]) != want { os.exit(base) }
            }
            i += 1usize
        }
        round += 1usize
    }
}

fn multiplies(state: *u64) {
    var round = 0usize
    while round < 300usize {
        let a = random[Vec[i16, 16]](state)
        let b = random[Vec[i16, 16]](state)
        let hi = simd.mulhi_i16[Vec[i16, 16]](a, b)
        let rounded = simd.mulhrs_i16[Vec[i16, 16]](a, b)
        let pairs = simd.madd_i16[Vec[i16, 16]](a, b)
        var i = 0usize
        while i < 16usize {
            let product = i64(a.lanes[i]) * i64(b.lanes[i])
            if i64(hi.lanes[i]) != product >> 16u32 { os.exit(70) }
            var q = (product >> 14u32) + 1i64
            q = q >> 1u32
            if q == 32768i64 { q = 0i64 - 32768i64 }
            if i64(rounded.lanes[i]) != q { os.exit(71) }
            i += 1usize
        }
        var j = 0usize
        while j < 8usize {
            let want = i64(a.lanes[2usize * j]) * i64(b.lanes[2usize * j]) + i64(a.lanes[2usize * j + 1usize]) * i64(b.lanes[2usize * j + 1usize])
            var wrapped = want
            if want == 2147483648i64 { wrapped = 0i64 - 2147483648i64 }
            if i64(pairs.lanes[j]) != wrapped { os.exit(72) }
            j += 1usize
        }
        round += 1usize
    }
}

fn sums_of_differences[V: type](state: *u64, base: i32) {
    var round = 0usize
    while round < 200usize {
        let a = random[V](state)
        let b = random[V](state)
        let r = simd.sad_u8[V](a, b)
        var j = 0usize
        while j < meta.array_len[V]() / 8usize {
            var want = 0i64
            var k = 0usize
            while k < 8usize {
                var d = i64(a.lanes[8usize * j + k]) - i64(b.lanes[8usize * j + k])
                if d < 0i64 { d = 0i64 - d }
                want += d
                k += 1usize
            }
            if i64(r.lanes[j]) != want { os.exit(base) }
            j += 1usize
        }
        round += 1usize
    }
}

fn interleaves[V: type](state: *u64, base: i32) {
    var round = 0usize
    while round < 100usize {
        let a = random[V](state)
        let b = random[V](state)
        let lo = simd.unpack_lo[V](a, b)
        let hi = simd.unpack_hi[V](a, b)
        let per_block = 16usize / mem.size_of[meta.element_type[V]()]()
        var i = 0usize
        while i < meta.array_len[V]() {
            let block = i / per_block
            let within = i % per_block
            let source = block * per_block + within / 2usize
            var from_a = a.lanes[source]
            var from_b = b.lanes[source]
            if within % 2usize == 0usize {
                if lo.lanes[i] != from_a { os.exit(base) }
            } else {
                if lo.lanes[i] != from_b { os.exit(base) }
            }
            let high_source = source + per_block / 2usize
            from_a = a.lanes[high_source]
            from_b = b.lanes[high_source]
            if within % 2usize == 0usize {
                if hi.lanes[i] != from_a { os.exit(base + 1) }
            } else {
                if hi.lanes[i] != from_b { os.exit(base + 1) }
            }
            i += 1usize
        }
        round += 1usize
    }
}

fn packs[V: type, W: type](state: *u64, low: i64, high: i64, base: i32) {
    var round = 0usize
    while round < 200usize {
        let a = random[W](state)
        let b = random[W](state)
        let r = simd.pack_sat[V, W](a, b)
        let per_block = 16usize / mem.size_of[meta.element_type[W]()]()
        var i = 0usize
        while i < meta.array_len[W]() {
            let block = i / per_block
            let within = i % per_block
            if i64(r.lanes[block * per_block * 2usize + within]) != clamp(i64(a.lanes[i]), low, high) { os.exit(base) }
            if i64(r.lanes[block * per_block * 2usize + per_block + within]) != clamp(i64(b.lanes[i]), low, high) { os.exit(base + 1) }
            i += 1usize
        }
        round += 1usize
    }
}

fn shuffles[V: type](state: *u64, base: i32) {
    var round = 0usize
    while round < 200usize {
        let a = random[V](state)
        var index = random[V](state)
        if round % 3usize == 0usize {
            var i = 0usize
            while i < meta.array_len[V]() {
                index.lanes[i] = index.lanes[i] & 15u8
                i += 1usize
            }
        }
        let r = simd.shuffle_bytes[V](a, index)
        var i = 0usize
        while i < meta.array_len[V]() {
            let block = i / 16usize * 16usize
            var want = 0u8
            if index.lanes[i] < 128u8 { want = a.lanes[block + usize(index.lanes[i] & 15u8)] }
            if want == want {
                if r.lanes[i] != want { os.exit(base) }
            } else {
                if r.lanes[i] == r.lanes[i] { os.exit(base) }
            }
            i += 1usize
        }
        round += 1usize
    }
}

fn masks[V: type](state: *u64, base: i32) {
    var round = 0usize
    while round < 200usize {
        let a = random[V](state)
        let bits = simd.movemask[V](a)
        var want = 0u64
        var i = 0usize
        while i < meta.array_len[V]() {
            if a.lanes[i] >= 128u8 { want = want + (1u64 << u32(i)) }
            i += 1usize
        }
        if bits != want { os.exit(base) }
        round += 1usize
    }
}

fn randomf[V: type](state: *u64) -> V {
    var v: V = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        let r = next(state) % 6u64
        var x = 0.0f64
        if r == 1u64 { x = 1.5f64 }
        if r == 2u64 { x = -1.5f64 }
        if r == 3u64 { x = 2.0f64 }
        if r == 4u64 { x = -0.0f64 }
        v.lanes[i] = meta.element_type[V]()(x)
        if r == 5u64 {
            if mem.size_of[meta.element_type[V]()]() == 4usize {
                v.lanes[i] = mem.bitcast[meta.element_type[V]()](2143289344u32)
            } else {
                v.lanes[i] = mem.bitcast[meta.element_type[V]()](9221120237041090560u64)
            }
        }
        i += 1usize
    }
    ret v
}

fn compare_lanes[V: type](a: V, b: V, base: i32) {
    let eq = simd.cmp_eq[V](a, b)
    let ne = simd.cmp_ne[V](a, b)
    let lt = simd.cmp_lt[V](a, b)
    let le = simd.cmp_le[V](a, b)
    let gt = simd.cmp_gt[V](a, b)
    let ge = simd.cmp_ge[V](a, b)
    var i = 0usize
    while i < meta.array_len[V]() {
        if eq.lanes[i] != (a.lanes[i] == b.lanes[i]) { os.exit(base) }
        if ne.lanes[i] != (a.lanes[i] != b.lanes[i]) { os.exit(base + 1) }
        if lt.lanes[i] != (a.lanes[i] < b.lanes[i]) { os.exit(base + 2) }
        if le.lanes[i] != (a.lanes[i] <= b.lanes[i]) { os.exit(base + 3) }
        if gt.lanes[i] != (a.lanes[i] > b.lanes[i]) { os.exit(base + 4) }
        if ge.lanes[i] != (a.lanes[i] >= b.lanes[i]) { os.exit(base + 5) }
        i += 1usize
    }
}

fn compares[V: type](state: *u64, base: i32) {
    var round = 0usize
    while round < 200usize {
        let a = random[V](state)
        var b = random[V](state)
        if round % 4usize == 0usize { b = a }
        compare_lanes[V](a, b, base)
        round += 1usize
    }
}

fn compares_float[V: type](state: *u64, base: i32) {
    var round = 0usize
    while round < 200usize {
        compare_lanes[V](randomf[V](state), randomf[V](state), base)
        round += 1usize
    }
}

fn selects_1(state: *u64, base: i32) {
    var round = 0usize
    while round < 200usize {
        let a = random[Vec[u8, 16]](state)
        let b = random[Vec[u8, 16]](state)
        var m: Mask[u8, 16] = zero
        var i = 0usize
        while i < 16usize {
            m.lanes[i] = (next(state) & 1u64) != 0u64
            i += 1usize
        }
        let r = simd.select[Vec[u8, 16]](m, a, b)
        i = 0usize
        while i < 16usize {
            var want = b.lanes[i]
            if m.lanes[i] { want = a.lanes[i] }
            if want == want {
                if r.lanes[i] != want { os.exit(base) }
            } else {
                if r.lanes[i] == r.lanes[i] { os.exit(base) }
            }
            i += 1usize
        }
        round += 1usize
    }
}

fn selects_2(state: *u64, base: i32) {
    var round = 0usize
    while round < 200usize {
        let a = random[Vec[i16, 8]](state)
        let b = random[Vec[i16, 8]](state)
        var m: Mask[i16, 8] = zero
        var i = 0usize
        while i < 8usize {
            m.lanes[i] = (next(state) & 1u64) != 0u64
            i += 1usize
        }
        let r = simd.select[Vec[i16, 8]](m, a, b)
        i = 0usize
        while i < 8usize {
            var want = b.lanes[i]
            if m.lanes[i] { want = a.lanes[i] }
            if want == want {
                if r.lanes[i] != want { os.exit(base) }
            } else {
                if r.lanes[i] == r.lanes[i] { os.exit(base) }
            }
            i += 1usize
        }
        round += 1usize
    }
}

fn selects_3(state: *u64, base: i32) {
    var round = 0usize
    while round < 200usize {
        let a = random[Vec[u32, 4]](state)
        let b = random[Vec[u32, 4]](state)
        var m: Mask[u32, 4] = zero
        var i = 0usize
        while i < 4usize {
            m.lanes[i] = (next(state) & 1u64) != 0u64
            i += 1usize
        }
        let r = simd.select[Vec[u32, 4]](m, a, b)
        i = 0usize
        while i < 4usize {
            var want = b.lanes[i]
            if m.lanes[i] { want = a.lanes[i] }
            if want == want {
                if r.lanes[i] != want { os.exit(base) }
            } else {
                if r.lanes[i] == r.lanes[i] { os.exit(base) }
            }
            i += 1usize
        }
        round += 1usize
    }
}

fn selects_4(state: *u64, base: i32) {
    var round = 0usize
    while round < 200usize {
        let a = randomf[Vec[f64, 2]](state)
        let b = randomf[Vec[f64, 2]](state)
        var m: Mask[f64, 2] = zero
        var i = 0usize
        while i < 2usize {
            m.lanes[i] = (next(state) & 1u64) != 0u64
            i += 1usize
        }
        let r = simd.select[Vec[f64, 2]](m, a, b)
        i = 0usize
        while i < 2usize {
            var want = b.lanes[i]
            if m.lanes[i] { want = a.lanes[i] }
            if want == want {
                if r.lanes[i] != want { os.exit(base) }
            } else {
                if r.lanes[i] == r.lanes[i] { os.exit(base) }
            }
            i += 1usize
        }
        round += 1usize
    }
}

fn selects_5(state: *u64, base: i32) {
    var round = 0usize
    while round < 200usize {
        let a = random[Vec[i64, 2]](state)
        let b = random[Vec[i64, 2]](state)
        var m: Mask[i64, 2] = zero
        var i = 0usize
        while i < 2usize {
            m.lanes[i] = (next(state) & 1u64) != 0u64
            i += 1usize
        }
        let r = simd.select[Vec[i64, 2]](m, a, b)
        i = 0usize
        while i < 2usize {
            var want = b.lanes[i]
            if m.lanes[i] { want = a.lanes[i] }
            if want == want {
                if r.lanes[i] != want { os.exit(base) }
            } else {
                if r.lanes[i] == r.lanes[i] { os.exit(base) }
            }
            i += 1usize
        }
        round += 1usize
    }
}

fn selects_6(state: *u64, base: i32) {
    var round = 0usize
    while round < 200usize {
        let a = random[Vec[u8, 64]](state)
        let b = random[Vec[u8, 64]](state)
        var m: Mask[u8, 64] = zero
        var i = 0usize
        while i < 64usize {
            m.lanes[i] = (next(state) & 1u64) != 0u64
            i += 1usize
        }
        let r = simd.select[Vec[u8, 64]](m, a, b)
        i = 0usize
        while i < 64usize {
            var want = b.lanes[i]
            if m.lanes[i] { want = a.lanes[i] }
            if want == want {
                if r.lanes[i] != want { os.exit(base) }
            } else {
                if r.lanes[i] == r.lanes[i] { os.exit(base) }
            }
            i += 1usize
        }
        round += 1usize
    }
}

fn selects_7(state: *u64, base: i32) {
    var round = 0usize
    while round < 200usize {
        let a = randomf[Vec[f32, 8]](state)
        let b = randomf[Vec[f32, 8]](state)
        var m: Mask[f32, 8] = zero
        var i = 0usize
        while i < 8usize {
            m.lanes[i] = (next(state) & 1u64) != 0u64
            i += 1usize
        }
        let r = simd.select[Vec[f32, 8]](m, a, b)
        i = 0usize
        while i < 8usize {
            var want = b.lanes[i]
            if m.lanes[i] { want = a.lanes[i] }
            if want == want {
                if r.lanes[i] != want { os.exit(base) }
            } else {
                if r.lanes[i] == r.lanes[i] { os.exit(base) }
            }
            i += 1usize
        }
        round += 1usize
    }
}

// A packed store writes memory the scalar code around it also reads: nothing may be
// carried across it from before.
fn aliasing() {
    var buf: [32]u8 = zero
    buf[3] = 9u8
    let before = buf[3]
    simd.store[Vec[u8, 16]](buf[0..], 0usize, simd.splat[Vec[u8, 16]](7u8))
    if before != 9u8 || buf[3] != 7u8 { os.exit(240) }
    buf[5] = 1u8
    let again = simd.load[Vec[u8, 16]](buf[0..], 0usize)
    if again.lanes[5] != 1u8 || again.lanes[4] != 7u8 { os.exit(241) }
    simd.store[Vec[u8, 16]](buf[0..], 4usize, simd.splat[Vec[u8, 16]](2u8))
    var total = 0u32
    var i = 0usize
    while i < 32usize {
        total += u32(buf[i])
        i += 1usize
    }
    if total != 4u32 * 7u32 + 16u32 * 2u32 + 12u32 * 0u32 + 0u32 + 0u32 { os.exit(242) }
}

fn main() {
    var state = 0x9e3779b97f4a7c15u64
    moves()
    aliasing()
    min_max[Vec[u8, 16]](&state, 20)
    min_max[Vec[i16, 8]](&state, 22)
    min_max[Vec[u16, 8]](&state, 24)
    min_max[Vec[i8, 16]](&state, 26)
    min_max[Vec[i32, 4]](&state, 28)
    min_max[Vec[u32, 4]](&state, 30)
    min_max[Vec[u8, 64]](&state, 32)
    min_max[Vec[i64, 2]](&state, 34)
    saturating[Vec[u8, 16]](&state, 0i64, 255i64, 40)
    saturating[Vec[i8, 16]](&state, 0i64 - 128i64, 127i64, 42)
    saturating[Vec[u16, 8]](&state, 0i64, 65535i64, 44)
    saturating[Vec[i16, 8]](&state, 0i64 - 32768i64, 32767i64, 46)
    saturating[Vec[u8, 32]](&state, 0i64, 255i64, 48)
    saturating[Vec[i16, 32]](&state, 0i64 - 32768i64, 32767i64, 50)
    saturating[Vec[i32, 4]](&state, 0i64 - 2147483648i64, 2147483647i64, 52)
    averages(&state)
    absolute_difference[Vec[u8, 16]](&state, 62)
    absolute_difference[Vec[u16, 8]](&state, 63)
    absolute_difference[Vec[i16, 8]](&state, 64)
    absolute_difference[Vec[u8, 64]](&state, 65)
    absolute_difference[Vec[i32, 4]](&state, 66)
    multiplies(&state)
    sums_of_differences[Vec[u8, 16]](&state, 80)
    sums_of_differences[Vec[u8, 64]](&state, 81)
    interleaves[Vec[u8, 16]](&state, 90)
    interleaves[Vec[u16, 8]](&state, 92)
    interleaves[Vec[u32, 4]](&state, 94)
    interleaves[Vec[u64, 2]](&state, 96)
    interleaves[Vec[u8, 32]](&state, 98)
    interleaves[Vec[i16, 32]](&state, 100)
    packs[Vec[u8, 16], Vec[i16, 8]](&state, 0i64, 255i64, 110)
    packs[Vec[i8, 16], Vec[i16, 8]](&state, 0i64 - 128i64, 127i64, 112)
    packs[Vec[i16, 8], Vec[i32, 4]](&state, 0i64 - 32768i64, 32767i64, 114)
    packs[Vec[u16, 8], Vec[i32, 4]](&state, 0i64, 65535i64, 116)
    packs[Vec[u8, 32], Vec[i16, 16]](&state, 0i64, 255i64, 118)
    packs[Vec[i16, 32], Vec[i32, 16]](&state, 0i64 - 32768i64, 32767i64, 120)
    shuffles[Vec[u8, 16]](&state, 130)
    shuffles[Vec[u8, 32]](&state, 131)
    shuffles[Vec[u8, 64]](&state, 132)
    masks[Vec[u8, 16]](&state, 140)
    masks[Vec[u8, 32]](&state, 141)
    masks[Vec[u8, 64]](&state, 142)
    compares[Vec[u8, 16]](&state, 150)
    compares[Vec[i8, 16]](&state, 156)
    compares[Vec[u16, 8]](&state, 162)
    compares[Vec[i16, 8]](&state, 168)
    compares[Vec[u32, 4]](&state, 174)
    compares[Vec[i32, 4]](&state, 180)
    compares[Vec[u8, 64]](&state, 186)
    compares[Vec[i16, 32]](&state, 192)
    compares[Vec[u32, 16]](&state, 198)
    compares[Vec[i64, 2]](&state, 204)
    compares_float[Vec[f32, 4]](&state, 210)
    compares_float[Vec[f64, 2]](&state, 216)
    compares_float[Vec[f32, 16]](&state, 222)
    selects_1(&state, 230)
    selects_2(&state, 231)
    selects_3(&state, 232)
    selects_4(&state, 233)
    selects_5(&state, 234)
    selects_6(&state, 235)
    selects_7(&state, 236)
    os.exit(0)
}
