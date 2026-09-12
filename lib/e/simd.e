// Section 4's vectors: the operation surface over `Vec[T, N]` and `Mask[T, N]`.
//
// Both types are builtins the compiler seeds into this module: a `Vec[T, N]` is one
// field `lanes: [N]T` and a `Mask[T, N]` is `lanes: [N]bool`, so a vector is exactly its
// width and is aligned to it (layout's one special case), and every function here is
// a loop over the lanes whose count folds to a constant. `T` and `N` are never written
// by a caller -- each is read off `V` by `e.meta`, which is what the surface's
// dependent names mean.
//
// ponytail: every operation lowers to N scalar instructions. A vector register class
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
        if m.lanes[i] { v.lanes[i] = s[off + i] }
        i += 1usize
    }
    ret v
}

fn store_masked[V: type](s: []meta.element_type[V](), off: usize, m: Mask[meta.element_type[V](), meta.array_len[V]()], v: V) {
    var i = 0usize
    while i < meta.array_len[V]() {
        if m.lanes[i] { s[off + i] = v.lanes[i] }
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
// into lane `i`, which is why it can be done in place: `2i >= i`.
fn reduce_add[V: type](v: V) -> meta.element_type[V]() {
    var acc = v
    var width = meta.array_len[V]()
    while width > 1usize {
        var i = 0usize
        while i < width / 2usize {
            acc.lanes[i] = lane_add[meta.element_type[V]()](acc.lanes[2usize * i], acc.lanes[2usize * i + 1usize])
            i += 1usize
        }
        width = width / 2usize
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
        width = width / 2usize
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
        width = width / 2usize
    }
    ret acc.lanes[0]
}

// Lane-wise `T(x)` to `W`'s lane type, with section 4's Casts table: whatever the
// scalar conversion does on a lane, this does on every lane.
fn convert[V: type, W: type](v: V) -> W {
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
