// Section 4's vectors: the operation surface over `Vec[T, N]` and `Mask[T, N]`.
//
// Both types are builtins the compiler seeds into this module: a `Vec[T, N]` is one
// field `lanes: [N]T` and a `Mask[T, N]` is `lanes: [N]bool`, so a vector is exactly its
// width and is aligned to it (layout's one special case), and every function here is
// a loop over the lanes whose count folds to a constant. `T` and `N` are never written
// by a caller -- each is read off `V` by `e.meta`, which is what the surface's
// dependent names mean.
//
// On x64 the operations that are a few packed instructions lower to them (D5960): a call
// below becomes `VectorBinary` with an extended operation in `lower_simd_call`, on 16, 32
// and 64 byte vectors, and anything else is the loop here. A vector register class
// and SSE/AVX selection are the upgrade path; the source here does not change for it,
// only how many instructions come out (section 4: "every vector width compiles on
// every target").
//
// The lane-wise operators of section 4 (`+ - * /` on float lanes, `+% -% *% & | ^ ~`
// and a scalar shift on integer lanes, `& | ^ ~` on masks), the `Vec[T, N]{ ... }`
// literal and `v[i]` are the checker's and lowering's, over this same representation
// (D158, D159).
//
// Not here yet: the `align` check of the aligned forms, which read as the unaligned
// ones.

use e.meta
use e.math
use e.mem

fn splat[V: type](x: meta.element_type[V]()) -> V {
    var v: V = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        v.lanes[i] = x
        i += 1usize
    }
    ret v
}

fn load[V: type](s: []const meta.element_type[V](), off: usize) -> V {
    var v: V = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        v.lanes[i] = s[off + i]
        i += 1usize
    }
    ret v
}

fn store[V: type](s: []meta.element_type[V](), off: usize, v: V) {
    var i = 0usize
    while i < meta.array_len[V]() {
        s[off + i] = v.lanes[i]
        i += 1usize
    }
}

// An enabled masked lane is an ordinary slice access, but form its offset only after
// proving that the addition cannot wrap. On failure return a guaranteed-out-of-range
// index, leaving the slice operation to raise the required `bounds` trap in every mode.
fn masked_offset(len: usize, off: usize, lane: usize) -> usize {
    if off > len { ret off }
    if lane >= len - off { ret len }
    ret off + lane
}

fn load_aligned[V: type](s: []const meta.element_type[V](), off: usize) -> V {
    ret load[V](s, off)
}

fn store_aligned[V: type](s: []meta.element_type[V](), off: usize, v: V) {
    store[V](s, off, v)
}

fn load_masked[V: type](s: []const meta.element_type[V](), off: usize, m: Mask[meta.element_type[V](), meta.array_len[V]()]) -> V {
    var v: V = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        if m.lanes[i] {
            let at = masked_offset(s.len, off, i)
            v.lanes[i] = s[at]
        }
        i += 1usize
    }
    ret v
}

fn store_masked[V: type](s: []meta.element_type[V](), off: usize, m: Mask[meta.element_type[V](), meta.array_len[V]()], v: V) {
    var i = 0usize
    while i < meta.array_len[V]() {
        if m.lanes[i] {
            let at = masked_offset(s.len, off, i)
            s[at] = v.lanes[i]
        }
        i += 1usize
    }
}

fn gather[V: type](s: []const meta.element_type[V](), indices: Vec[u32, meta.array_len[V]()]) -> V {
    var v: V = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        v.lanes[i] = s[usize(indices.lanes[i])]
        i += 1usize
    }
    ret v
}

// Section 4: lane `i` of the result is lane `IDX[i]` of the 2N lanes of `a` then `b`.
// `IDX` is a comptime array (section 9), so the permutation is fixed at the call;
// here it is read lane by lane, and a register class would select it as one shuffle.
fn shuffle[V: type, IDX: [meta.array_len[V]()]u8](a: V, b: V) -> V {
    var v: V = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        let source = usize(IDX[i])
        if source < meta.array_len[V]() {
            v[i] = a[source]
        } else {
            v[i] = b[source - meta.array_len[V]()]
        }
        i += 1usize
    }
    ret v
}

// Section 4: on float lanes these are IEEE ordered comparisons, which is what the
// scalar operators are -- a NaN lane is `false` under every one but `cmp_ne`.
fn cmp_eq[V: type](a: V, b: V) -> Mask[meta.element_type[V](), meta.array_len[V]()] {
    var m: Mask[meta.element_type[V](), meta.array_len[V]()] = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        m.lanes[i] = a.lanes[i] == b.lanes[i]
        i += 1usize
    }
    ret m
}

fn cmp_ne[V: type](a: V, b: V) -> Mask[meta.element_type[V](), meta.array_len[V]()] {
    var m: Mask[meta.element_type[V](), meta.array_len[V]()] = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        m.lanes[i] = a.lanes[i] != b.lanes[i]
        i += 1usize
    }
    ret m
}

fn cmp_lt[V: type](a: V, b: V) -> Mask[meta.element_type[V](), meta.array_len[V]()] {
    var m: Mask[meta.element_type[V](), meta.array_len[V]()] = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        m.lanes[i] = a.lanes[i] < b.lanes[i]
        i += 1usize
    }
    ret m
}

fn cmp_le[V: type](a: V, b: V) -> Mask[meta.element_type[V](), meta.array_len[V]()] {
    var m: Mask[meta.element_type[V](), meta.array_len[V]()] = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        m.lanes[i] = a.lanes[i] <= b.lanes[i]
        i += 1usize
    }
    ret m
}

fn cmp_gt[V: type](a: V, b: V) -> Mask[meta.element_type[V](), meta.array_len[V]()] {
    var m: Mask[meta.element_type[V](), meta.array_len[V]()] = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        m.lanes[i] = a.lanes[i] > b.lanes[i]
        i += 1usize
    }
    ret m
}

fn cmp_ge[V: type](a: V, b: V) -> Mask[meta.element_type[V](), meta.array_len[V]()] {
    var m: Mask[meta.element_type[V](), meta.array_len[V]()] = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        m.lanes[i] = a.lanes[i] >= b.lanes[i]
        i += 1usize
    }
    ret m
}

fn select[V: type](m: Mask[meta.element_type[V](), meta.array_len[V]()], yes: V, no: V) -> V {
    var v = no
    var i = 0usize
    while i < meta.array_len[V]() {
        if m.lanes[i] { v.lanes[i] = yes.lanes[i] }
        i += 1usize
    }
    ret v
}

fn any[V: type](m: Mask[meta.element_type[V](), meta.array_len[V]()]) -> bool {
    var i = 0usize
    while i < meta.array_len[V]() {
        if m.lanes[i] { ret true }
        i += 1usize
    }
    ret false
}

fn all[V: type](m: Mask[meta.element_type[V](), meta.array_len[V]()]) -> bool {
    var i = 0usize
    while i < meta.array_len[V]() {
        if !m.lanes[i] { ret false }
        i += 1usize
    }
    ret true
}

fn bits[V: type](m: Mask[meta.element_type[V](), meta.array_len[V]()]) -> u64 {
    var packed = 0u64
    var i = 0usize
    while i < meta.array_len[V]() {
        if m.lanes[i] { packed = packed | (1u64 << u32(i)) }
        i += 1usize
    }
    ret packed
}

fn mask[V: type](packed: u64) -> Mask[meta.element_type[V](), meta.array_len[V]()] {
    var m: Mask[meta.element_type[V](), meta.array_len[V]()] = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        m.lanes[i] = ((packed >> u32(i)) & 1u64) != 0u64
        i += 1usize
    }
    ret m
}

// Section 4: a fixed pairwise tree in lane order -- `(0+1)+(2+3)` and so on -- so a
// float sum is the same bits on every target. Each level folds lane `2i` and `2i+1`
// into lane `i`, and an odd trailing lane is carried forward to `width / 2`, so every
// width works, not only powers of two (#470).
fn reduce_add[V: type](v: V) -> meta.element_type[V]() {
    var acc = v
    var width = meta.array_len[V]()
    while width > 1usize {
        var i = 0usize
        while i < width / 2usize {
            acc.lanes[i] = lane_add[meta.element_type[V]()](acc.lanes[2usize * i], acc.lanes[2usize * i + 1usize])
            i += 1usize
        }
        if width % 2usize == 1usize { acc.lanes[width / 2usize] = acc.lanes[width - 1usize] }
        width = (width + 1usize) / 2usize
    }
    ret acc.lanes[0]
}

// Section 4: an integer vector has only the wrapping forms, and a float lane one IEEE
// addition.
fn lane_add[T: type](a: T, b: T) -> T {
    if meta.kind[T]() == .Float {
        ret a + b
    } else {
        ret a +% b
    }
}

// `min`/`max` are IEEE `minimum`/`maximum` on float lanes (NaN wins, `-0 < +0`), which
// `e.math` already is; an integer lane has only one order.
fn lane_min[T: type](a: T, b: T) -> T {
    if meta.kind[T]() == .Float { ret math.min[T](a, b) }
    if b < a { ret b }
    ret a
}

fn lane_max[T: type](a: T, b: T) -> T {
    if meta.kind[T]() == .Float { ret math.max[T](a, b) }
    if b > a { ret b }
    ret a
}

fn reduce_min[V: type](v: V) -> meta.element_type[V]() {
    var acc = v
    var width = meta.array_len[V]()
    while width > 1usize {
        var i = 0usize
        while i < width / 2usize {
            acc.lanes[i] = lane_min[meta.element_type[V]()](acc.lanes[2usize * i], acc.lanes[2usize * i + 1usize])
            i += 1usize
        }
        if width % 2usize == 1usize { acc.lanes[width / 2usize] = acc.lanes[width - 1usize] }
        width = (width + 1usize) / 2usize
    }
    ret acc.lanes[0]
}

fn reduce_max[V: type](v: V) -> meta.element_type[V]() {
    var acc = v
    var width = meta.array_len[V]()
    while width > 1usize {
        var i = 0usize
        while i < width / 2usize {
            acc.lanes[i] = lane_max[meta.element_type[V]()](acc.lanes[2usize * i], acc.lanes[2usize * i + 1usize])
            i += 1usize
        }
        if width % 2usize == 1usize { acc.lanes[width / 2usize] = acc.lanes[width - 1usize] }
        width = (width + 1usize) / 2usize
    }
    ret acc.lanes[0]
}

// Lane-wise float to signed integer, rounded to nearest with ties to even (`cvtps2dq` on x64); a lane that is NaN or outside the
// integer range is the integer's least value. Unlike `convert` it never saturates, and is one instruction where the target has it.
fn round_i32[V: type, W: type](v: V) -> W {
    var w: W = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        let x = f64(v.lanes[i])
        if x >= -2147483648.0f64 && x < 2147483648.0f64 {
            w.lanes[i] = meta.element_type[W]()(math.round[f64](x))
        } else {
            w.lanes[i] = meta.element_type[W]()(0i64 - 2147483647i64 - 1i64)
        }
        i += 1usize
    }
    ret w
}

// Lane-wise `T(x)` to `W`'s lane type, with section 4's Casts table: whatever the
// scalar conversion does on a lane, this does on every lane. The vectors must have
// the same lane count; otherwise no lane-wise correspondence exists.
fn convert[V: type, W: type](v: V) -> W {
    if meta.array_len[V]() != meta.array_len[W]() {
        unreachable("simd.convert requires equal lane counts")
    }
    var w: W = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        w.lanes[i] = meta.element_type[W]()(v.lanes[i])
        i += 1usize
    }
    ret w
}

fn fma[V: type](a: V, b: V, c: V) -> V {
    var v: V = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        v.lanes[i] = math.fma[meta.element_type[V]()](a.lanes[i], b.lanes[i], c.lanes[i])
        i += 1usize
    }
    ret v
}

// Section 13's two bit intrinsics as the bit loop every target without the
// instruction gets: `pdep` scatters the low bits of `x` to the set bits of
// `bit_mask`, `pext` gathers the bits of `x` under the set bits of `bit_mask` down
// to the low end.
fn pdep(x: u64, bit_mask: u64) -> u64 {
    var result = 0u64
    var source = 0u32
    var bit = 0u32
    while bit < 64u32 {
        if ((bit_mask >> bit) & 1u64) != 0u64 {
            if ((x >> source) & 1u64) != 0u64 { result = result | (1u64 << bit) }
            source += 1u32
        }
        bit += 1u32
    }
    ret result
}

fn pext(x: u64, bit_mask: u64) -> u64 {
    var result = 0u64
    var target_bit = 0u32
    var bit = 0u32
    while bit < 64u32 {
        if ((bit_mask >> bit) & 1u64) != 0u64 {
            if ((x >> bit) & 1u64) != 0u64 { result = result | (1u64 << target_bit) }
            target_bit += 1u32
        }
        bit += 1u32
    }
    ret result
}

// ---- Codec operations (D5960)
//
// The operations a video codec's inner loops are made of. Each is a loop over the lanes
// here, and on x64 a call into this module is one packed instruction instead when the
// vector is sixteen, thirty-two or sixty-four bytes and the instruction level has it
// (`--cpu x64-v2` for `shuffle_bytes`, `mulhrs_i16` and the min and max of the lanes SSE2
// has no form for); the answer is the same bits either way. The operations that move
// lanes between positions (`unpack_lo`, `unpack_hi`, `pack_sat`, `shuffle_bytes`) work
// on each sixteen-byte block of the vector on its own, which is what both SSE and AVX2
// do and so what a wider vector can be built from. Lane types the description does not
// name are not defined and trap.

fn lane_bits[T: type]() -> u32 {
    ret u32(mem.size_of[T]()) * 8u32
}

fn lane_low[T: type]() -> i64 {
    if meta.signed[T]() { ret 0i64 - (1i64 << (lane_bits[T]() - 1u32)) }
    ret 0i64
}

fn lane_high[T: type]() -> i64 {
    if meta.signed[T]() { ret (1i64 << (lane_bits[T]() - 1u32)) - 1i64 }
    ret (1i64 << lane_bits[T]()) - 1i64
}

fn trunc_lane[T: type](x: i32) -> T {
    ret T.trunc(x)
}

fn saturate[T: type](x: i64) -> T {
    if x < lane_low[T]() { ret T(lane_low[T]()) }
    if x > lane_high[T]() { ret T(lane_high[T]()) }
    ret T(x)
}

// Lane-wise minimum and maximum; an integer lane has one order, a float lane the IEEE
// `minimum`/`maximum` of `reduce_min`.
fn min[V: type](a: V, b: V) -> V {
    var v: V = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        v.lanes[i] = lane_min[meta.element_type[V]()](a.lanes[i], b.lanes[i])
        i += 1usize
    }
    ret v
}

fn max[V: type](a: V, b: V) -> V {
    var v: V = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        v.lanes[i] = lane_max[meta.element_type[V]()](a.lanes[i], b.lanes[i])
        i += 1usize
    }
    ret v
}

// Saturating add and subtract on 8-, 16- and 32-bit integer lanes: the sum is clamped to
// the lane's range instead of wrapping.
fn adds[V: type](a: V, b: V) -> V {
    var v: V = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        v.lanes[i] = saturate[meta.element_type[V]()](i64(a.lanes[i]) + i64(b.lanes[i]))
        i += 1usize
    }
    ret v
}

fn subs[V: type](a: V, b: V) -> V {
    var v: V = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        v.lanes[i] = saturate[meta.element_type[V]()](i64(a.lanes[i]) - i64(b.lanes[i]))
        i += 1usize
    }
    ret v
}

// The rounding average `(a + b + 1) >> 1` of unsigned 8-bit (`avg_u8`) or 16-bit
// (`avg_u16`) lanes, without the intermediate sum overflowing.
fn avg_u8[V: type](a: V, b: V) -> V {
    var v: V = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        v.lanes[i] = meta.element_type[V]()((i64(a.lanes[i]) + i64(b.lanes[i]) + 1i64) >> 1u32)
        i += 1usize
    }
    ret v
}

fn avg_u16[V: type](a: V, b: V) -> V {
    ret avg_u8[V](a, b)
}

// `|a - b|` of an unsigned lane; on a signed lane the difference wraps like `-%`.
fn abs_diff[V: type](a: V, b: V) -> V {
    var v: V = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        if a.lanes[i] > b.lanes[i] {
            v.lanes[i] = a.lanes[i] -% b.lanes[i]
        } else {
            v.lanes[i] = b.lanes[i] -% a.lanes[i]
        }
        i += 1usize
    }
    ret v
}

// `i16` lanes: the high half of the 32-bit product (`mulhi_i16`, `pmulhw`), and the
// rounded Q15 product `((a * b >> 14) + 1) >> 1` (`mulhrs_i16`, `pmulhrsw`), which
// wraps in the one case, -32768 * -32768, where the result does not fit.
fn mulhi_i16[V: type](a: V, b: V) -> V {
    var v: V = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        v.lanes[i] = trunc_lane[meta.element_type[V]()]((i32(a.lanes[i]) * i32(b.lanes[i])) >> 16u32)
        i += 1usize
    }
    ret v
}

fn mulhrs_i16[V: type](a: V, b: V) -> V {
    var v: V = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        let product = (i32(a.lanes[i]) * i32(b.lanes[i])) >> 14u32
        v.lanes[i] = trunc_lane[meta.element_type[V]()]((product + 1i32) >> 1u32)
        i += 1usize
    }
    ret v
}

// `i16` lanes in, `i32` lanes out, half as many: lane `j` is `a[2j] * b[2j] + a[2j+1] *
// b[2j+1]` (`pmaddwd`), wrapping when both products are 2^30.
fn madd_i16[V: type](a: V, b: V) -> Vec[i32, meta.array_len[V]() / 2usize] {
    var v: Vec[i32, meta.array_len[V]() / 2usize] = zero
    var j = 0usize
    while j < meta.array_len[V]() / 2usize {
        let low = i32(a.lanes[2usize * j]) * i32(b.lanes[2usize * j])
        let high = i32(a.lanes[2usize * j + 1usize]) * i32(b.lanes[2usize * j + 1usize])
        v.lanes[j] = low +% high
        j += 1usize
    }
    ret v
}

// `u8` lanes in, `u64` lanes out, an eighth as many: lane `j` is the sum of
// `|a[i] - b[i]|` over its eight bytes (`psadbw`).
fn sad_u8[V: type](a: V, b: V) -> Vec[u64, meta.array_len[V]() / 8usize] {
    var v: Vec[u64, meta.array_len[V]() / 8usize] = zero
    var i = 0usize
    while i < meta.array_len[V]() {
        var difference = u64(a.lanes[i])
        if a.lanes[i] > b.lanes[i] {
            difference = u64(a.lanes[i]) - u64(b.lanes[i])
        } else {
            difference = u64(b.lanes[i]) - u64(a.lanes[i])
        }
        v.lanes[i / 8usize] = v.lanes[i / 8usize] + difference
        i += 1usize
    }
    ret v
}

// Interleave the low halves (`unpack_lo`) or the high halves (`unpack_hi`) of each
// sixteen-byte block of `a` and `b`: `a0 b0 a1 b1 ...`. With `b` zero this widens an
// unsigned lane to twice its width, viewed as the next wider vector.
fn unpack_lo[V: type](a: V, b: V) -> V {
    var v: V = zero
    let block = 16usize / mem.size_of[meta.element_type[V]()]()
    var at = 0usize
    while at < meta.array_len[V]() {
        var j = 0usize
        while j < block / 2usize {
            v.lanes[at + 2usize * j] = a.lanes[at + j]
            v.lanes[at + 2usize * j + 1usize] = b.lanes[at + j]
            j += 1usize
        }
        at += block
    }
    ret v
}

fn unpack_hi[V: type](a: V, b: V) -> V {
    var v: V = zero
    let block = 16usize / mem.size_of[meta.element_type[V]()]()
    var at = 0usize
    while at < meta.array_len[V]() {
        var j = 0usize
        while j < block / 2usize {
            v.lanes[at + 2usize * j] = a.lanes[at + block / 2usize + j]
            v.lanes[at + 2usize * j + 1usize] = b.lanes[at + block / 2usize + j]
            j += 1usize
        }
        at += block
    }
    ret v
}

// Narrow each lane of `a` and then of `b` to half the width, clamping to the range of
// the result lane (`packuswb`, `packsswb`, `packssdw`, `packusdw`): in each sixteen-byte
// block, the first half of the result is `a`'s block and the second `b`'s. `W` is the
// wider vector type and `V` the narrower; the source lanes are signed.
fn pack_sat[V: type, W: type](a: W, b: W) -> V {
    var v: V = zero
    let block = 16usize / mem.size_of[meta.element_type[W]()]()
    var at = 0usize
    while at < meta.array_len[W]() {
        var j = 0usize
        while j < block {
            v.lanes[at + j] = saturate[meta.element_type[V]()](i64(a.lanes[at + j]))
            v.lanes[at + block + j] = saturate[meta.element_type[V]()](i64(b.lanes[at + j]))
            j += 1usize
        }
        at += block
    }
    ret v
}

// Within each sixteen-byte block, byte `i` of the result is byte `index[i] & 15` of `a`'s
// block, or zero where `index[i]` has its top bit set (`pshufb`).
fn shuffle_bytes[V: type](a: V, index: V) -> V {
    var v: V = zero
    var at = 0usize
    while at < meta.array_len[V]() {
        var j = 0usize
        while j < 16usize {
            let selector = index.lanes[at + j]
            if (selector & 128u8) == 0u8 {
                v.lanes[at + j] = a.lanes[at + usize(selector & 15u8)]
            }
            j += 1usize
        }
        at += 16usize
    }
    ret v
}

// Bit `i` of the result is the top bit of byte lane `i` (`pmovmskb`).
fn movemask[V: type](v: V) -> u64 {
    var packed = 0u64
    var i = 0usize
    while i < meta.array_len[V]() {
        if (v.lanes[i] & 128u8) != 0u8 { packed = packed | (1u64 << u32(i)) }
        i += 1usize
    }
    ret packed
}
