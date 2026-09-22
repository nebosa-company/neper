// Two SMT theory procedures over caller storage. Equality with uninterpreted
// functions (EUF): terms form a DAG in parallel arrays -- `symbols[t]` names
// term `t`'s function symbol or constant, its arguments are
// `args[arg_starts[t]..arg_starts[t + 1]]` -- and `congruence_closure`
// merges the classes of asserted equalities with `e.algo.disjoint_set`, then
// merges every pair of same-symbol terms whose arguments became pairwise
// equal, to a fixpoint. Bit-vectors: a vector of width `w` is `w` CNF
// literals (LSB first) in an `e.algo.sat` formula; `bv_*` build constants,
// gates, ripple-carry arithmetic, shift-add multiplication and comparisons
// as Tseitin circuits, and `bit_blast` lowers a small expression tree into
// them so `sat.solve` decides the formula and `bv_value` reads the model.

use e.algo.disjoint_set as dsu
use e.algo.sat as sat

error TooSmall
error Invalid

// EUF ------------------------------------------------------------------

// The congruence closure of `eq_lhs[i] = eq_rhs[i]` over the term DAG;
// `parent`/`rank` hold one entry per term. Terms are the same afterwards
// exactly when the equalities entail it.
fn congruence_closure(symbols: []const u32, args: []const u32, arg_starts: []const usize, eq_lhs: []const u32, eq_rhs: []const u32, parent: []u32, rank: []u8) -> (dsu.DisjointSet, err) {
    let n = symbols.len
    if arg_starts.len < n + 1usize || eq_lhs.len != eq_rhs.len { ret (zero, Invalid) }
    if arg_starts[n] > args.len { ret (zero, Invalid) }
    let (s0, e) = dsu.init(parent, rank, n)
    if e != ok { ret (zero, TooSmall) }
    var s = s0
    var i = 0usize
    while i < eq_lhs.len {
        if usize(eq_lhs[i]) >= n || usize(eq_rhs[i]) >= n { ret (zero, Invalid) }
        let _ = dsu.join(&s, eq_lhs[i], eq_rhs[i])
        i += 1usize
    }
    // ponytail: O(n^2 · arity) sweep to a fixpoint; upgrade to use-lists
    // (Downey-Sethi-Tarjan) when term counts reach the thousands.
    var changed = true
    while changed {
        changed = false
        var a = 0usize
        while a < n {
            var b = a + 1usize
            while b < n {
                if symbols[a] == symbols[b] && !dsu.same(&s, u32(a), u32(b)) && congruent(&s, args, arg_starts, a, b) {
                    let _ = dsu.join(&s, u32(a), u32(b))
                    changed = true
                }
                b += 1usize
            }
            a += 1usize
        }
    }
    ret (s, ok)
}

// Same arity and pairwise-equal arguments under the current partition.
fn congruent(s: *dsu.DisjointSet, args: []const u32, arg_starts: []const usize, a: usize, b: usize) -> bool {
    let count = arg_starts[a + 1usize] - arg_starts[a]
    if arg_starts[b + 1usize] - arg_starts[b] != count { ret false }
    var k = 0usize
    while k < count {
        if !dsu.same(s, args[arg_starts[a] + k], args[arg_starts[b] + k]) { ret false }
        k += 1usize
    }
    ret true
}

// Do the equalities entail `a = b`?
fn euf_same(closure: *dsu.DisjointSet, a: u32, b: u32) -> bool { ret dsu.same(closure, a, b) }

// The representative of `a`'s class.
fn euf_class(closure: *dsu.DisjointSet, a: u32) -> u32 { ret dsu.find(closure, a) }

// Is the conjunction of the equalities and the disequalities
// `neq_lhs[i] != neq_rhs[i]` satisfiable? (Yes exactly when no disequality
// joins two terms the closure made equal.)
fn euf_satisfiable(symbols: []const u32, args: []const u32, arg_starts: []const usize, eq_lhs: []const u32, eq_rhs: []const u32, neq_lhs: []const u32, neq_rhs: []const u32, parent: []u32, rank: []u8) -> (bool, err) {
    if neq_lhs.len != neq_rhs.len { ret (false, Invalid) }
    let (s0, e) = congruence_closure(symbols, args, arg_starts, eq_lhs, eq_rhs, parent, rank)
    if e != ok { ret (false, e) }
    var s = s0
    var i = 0usize
    while i < neq_lhs.len {
        if usize(neq_lhs[i]) >= symbols.len || usize(neq_rhs[i]) >= symbols.len { ret (false, Invalid) }
        if dsu.same(&s, neq_lhs[i], neq_rhs[i]) { ret (false, ok) }
        i += 1usize
    }
    ret (true, ok)
}

// Bit-vectors ----------------------------------------------------------

// A literal forced true (one fresh variable and a unit clause).
fn bv_true(f: *sat.Cnf) -> (i32, err) {
    let t = sat.fresh(f)
    let e = sat.clause1(f, t)
    if e != ok { ret (0i32, e) }
    ret (t, ok)
}

// `out` (its width is the vector's) receives the bits of `value`.
fn bv_const(f: *sat.Cnf, value: u64, out: []i32) -> err {
    let (t, e) = bv_true(f)
    if e != ok { ret e }
    var i = 0usize
    while i < out.len {
        out[i] = 0i32 - t
        if i < 64usize && ((value >> u32(i)) & 1u64) == 1u64 { out[i] = t }
        i += 1usize
    }
    ret ok
}

// A vector of fresh, unconstrained variables.
fn bv_fresh(f: *sat.Cnf, out: []i32) -> err {
    var i = 0usize
    while i < out.len {
        out[i] = sat.fresh(f)
        i += 1usize
    }
    ret ok
}

fn widths_match(a: []const i32, b: []const i32, out: []const i32) -> bool { ret a.len == b.len && a.len == out.len }

fn bv_and(f: *sat.Cnf, a: []const i32, b: []const i32, out: []i32) -> err {
    if !widths_match(a, b, out) { ret Invalid }
    var i = 0usize
    while i < out.len {
        let (o, e) = sat.tseitin_and(f, a[i], b[i])
        if e != ok { ret e }
        out[i] = o
        i += 1usize
    }
    ret ok
}

fn bv_or(f: *sat.Cnf, a: []const i32, b: []const i32, out: []i32) -> err {
    if !widths_match(a, b, out) { ret Invalid }
    var i = 0usize
    while i < out.len {
        let (o, e) = sat.tseitin_or(f, a[i], b[i])
        if e != ok { ret e }
        out[i] = o
        i += 1usize
    }
    ret ok
}

fn bv_xor(f: *sat.Cnf, a: []const i32, b: []const i32, out: []i32) -> err {
    if !widths_match(a, b, out) { ret Invalid }
    var i = 0usize
    while i < out.len {
        let (o, e) = sat.tseitin_xor(f, a[i], b[i])
        if e != ok { ret e }
        out[i] = o
        i += 1usize
    }
    ret ok
}

// Bitwise complement needs no gates.
fn bv_not(a: []const i32, out: []i32) -> err {
    if a.len != out.len { ret Invalid }
    var i = 0usize
    while i < out.len {
        out[i] = 0i32 - a[i]
        i += 1usize
    }
    ret ok
}

// `out = a + b` modulo 2^w by a ripple-carry adder; `out` may alias `a` or `b`.
fn bv_add(f: *sat.Cnf, a: []const i32, b: []const i32, out: []i32) -> err {
    if !widths_match(a, b, out) { ret Invalid }
    ret ripple(f, a, b, out, false, 0i32)
}

// `out = a - b` modulo 2^w (`a + ~b + 1`).
fn bv_sub(f: *sat.Cnf, a: []const i32, b: []const i32, out: []i32) -> err {
    if !widths_match(a, b, out) { ret Invalid }
    let (t, e) = bv_true(f)
    if e != ok { ret e }
    ret ripple(f, a, b, out, true, t)
}

// Ripple-carry `a + (invert_b ? ~b : b) + carry` (`carry` 0 means none);
// reads bit `i` of both inputs before writing `out[i]`, so aliasing is safe.
fn ripple(f: *sat.Cnf, a: []const i32, b: []const i32, out: []i32, invert_b: bool, carry: i32) -> err {
    var c = carry
    var i = 0usize
    while i < out.len {
        let x = a[i]
        var y = b[i]
        if invert_b { y = 0i32 - y }
        let (half, half_error) = sat.tseitin_xor(f, x, y)
        if half_error != ok { ret half_error }
        let (both, both_error) = sat.tseitin_and(f, x, y)
        if both_error != ok { ret both_error }
        if c == 0i32 {
            out[i] = half
            c = both
        } else {
            let (sum, sum_error) = sat.tseitin_xor(f, half, c)
            if sum_error != ok { ret sum_error }
            let (pass, pass_error) = sat.tseitin_and(f, half, c)
            if pass_error != ok { ret pass_error }
            let (next_carry, carry_error) = sat.tseitin_or(f, both, pass)
            if carry_error != ok { ret carry_error }
            out[i] = sum
            c = next_carry
        }
        i += 1usize
    }
    ret ok
}

// `out = a * b` modulo 2^w by shift-and-add; `scratch.len >= w`, and `out`
// must not alias `a` or `b`.
fn bv_mul(f: *sat.Cnf, a: []const i32, b: []const i32, out: []i32, scratch: []i32) -> err {
    if !widths_match(a, b, out) { ret Invalid }
    let w = out.len
    if scratch.len < w { ret TooSmall }
    var j = 0usize
    while j < w {
        let (o, e) = sat.tseitin_and(f, a[j], b[0usize])
        if e != ok { ret e }
        out[j] = o
        j += 1usize
    }
    // Row i is (a << i) & b[i]; only its bits i..w survive the modulus.
    var i = 1usize
    while i < w {
        j = 0usize
        while j + i < w {
            let (o, e) = sat.tseitin_and(f, a[j], b[i])
            if e != ok { ret e }
            scratch[j] = o
            j += 1usize
        }
        let e = ripple(f, out[i..w], scratch[..w - i], out[i..w], false, 0i32)
        if e != ok { ret e }
        i += 1usize
    }
    ret ok
}

// A literal true exactly when `a == b`.
fn bv_eq(f: *sat.Cnf, a: []const i32, b: []const i32) -> (i32, err) {
    if a.len != b.len || a.len == 0usize { ret (0i32, Invalid) }
    var differ = 0i32
    var i = 0usize
    while i < a.len {
        let (x, x_error) = sat.tseitin_xor(f, a[i], b[i])
        if x_error != ok { ret (0i32, x_error) }
        if i == 0usize {
            differ = x
        } else {
            let (o, o_error) = sat.tseitin_or(f, differ, x)
            if o_error != ok { ret (0i32, o_error) }
            differ = o
        }
        i += 1usize
    }
    ret (0i32 - differ, ok)
}

// A literal true exactly when `a < b` as unsigned integers.
fn bv_ult(f: *sat.Cnf, a: []const i32, b: []const i32) -> (i32, err) {
    if a.len != b.len || a.len == 0usize { ret (0i32, Invalid) }
    var less = 0i32
    var i = 0usize
    while i < a.len {
        // Bit i decides unless equal, in which case the lower bits decide.
        let (here, here_error) = sat.tseitin_and(f, 0i32 - a[i], b[i])
        if here_error != ok { ret (0i32, here_error) }
        if i == 0usize {
            less = here
        } else {
            let (x, x_error) = sat.tseitin_xor(f, a[i], b[i])
            if x_error != ok { ret (0i32, x_error) }
            let (below, below_error) = sat.tseitin_and(f, 0i32 - x, less)
            if below_error != ok { ret (0i32, below_error) }
            let (o, o_error) = sat.tseitin_or(f, here, below)
            if o_error != ok { ret (0i32, o_error) }
            less = o
        }
        i += 1usize
    }
    ret (less, ok)
}

// `out = a << k`, the vacated low bits false.
fn bv_shl_const(f: *sat.Cnf, a: []const i32, k: usize, out: []i32) -> err {
    if a.len != out.len { ret Invalid }
    let (t, e) = bv_true(f)
    if e != ok { ret e }
    var i = out.len
    while i > 0usize {
        i -= 1usize
        out[i] = 0i32 - t
        if i >= k { out[i] = a[i - k] }
    }
    ret ok
}

// `out = a >> k` (logical), the vacated high bits false.
fn bv_lshr_const(f: *sat.Cnf, a: []const i32, k: usize, out: []i32) -> err {
    if a.len != out.len { ret Invalid }
    let (t, e) = bv_true(f)
    if e != ok { ret e }
    var i = 0usize
    while i < out.len {
        out[i] = 0i32 - t
        if i + k < a.len { out[i] = a[i + k] }
        i += 1usize
    }
    ret ok
}

// The model's value of a vector (`assignment` from `sat.solve`).
fn bv_value(assignment: []const i8, bits: []const i32) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < bits.len && i < 64usize {
        if sat.value_of(assignment, bits[i]) > 0i8 { v |= 1u64 << u32(i) }
        i += 1usize
    }
    ret v
}

// Expression-tree opcodes for `bit_blast`.
const OP_CONST: u8 = 0u8
const OP_VAR: u8 = 1u8
const OP_AND: u8 = 2u8
const OP_OR: u8 = 3u8
const OP_XOR: u8 = 4u8
const OP_NOT: u8 = 5u8
const OP_ADD: u8 = 6u8
const OP_SUB: u8 = 7u8
const OP_MUL: u8 = 8u8
const OP_EQ: u8 = 9u8
const OP_ULT: u8 = 10u8

// Lowers the tree `ops[t]` with children `lhs[t]`, `rhs[t]` (indices below
// `t`; `consts[t]` for `OP_CONST`) into `f`. Node `t`'s bits land in
// `bits[t * width .. (t + 1) * width]`; a comparison's single output literal
// is `bits[t * width]`. `scratch.len >= width`.
fn bit_blast(f: *sat.Cnf, ops: []const u8, lhs: []const u32, rhs: []const u32, consts: []const u64, width: usize, bits: []i32, scratch: []i32) -> err {
    let n = ops.len
    if width == 0usize || lhs.len < n || rhs.len < n || consts.len < n { ret Invalid }
    if bits.len < n * width || scratch.len < width { ret TooSmall }
    var t = 0usize
    while t < n {
        let out = bits[t * width..(t + 1usize) * width]
        let op = ops[t]
        if op == OP_CONST {
            let e = bv_const(f, consts[t], out)
            if e != ok { ret e }
        } else if op == OP_VAR {
            let e = bv_fresh(f, out)
            if e != ok { ret e }
        } else {
            if usize(lhs[t]) >= t { ret Invalid }
            let a = bits[usize(lhs[t]) * width..(usize(lhs[t]) + 1usize) * width]
            if op == OP_NOT {
                let e = bv_not(a, out)
                if e != ok { ret e }
            } else {
                if usize(rhs[t]) >= t { ret Invalid }
                let b = bits[usize(rhs[t]) * width..(usize(rhs[t]) + 1usize) * width]
                var e = ok
                if op == OP_AND {
                    e = bv_and(f, a, b, out)
                } else if op == OP_OR {
                    e = bv_or(f, a, b, out)
                } else if op == OP_XOR {
                    e = bv_xor(f, a, b, out)
                } else if op == OP_ADD {
                    e = bv_add(f, a, b, out)
                } else if op == OP_SUB {
                    e = bv_sub(f, a, b, out)
                } else if op == OP_MUL {
                    e = bv_mul(f, a, b, out, scratch)
                } else if op == OP_EQ {
                    let (lit, cmp_error) = bv_eq(f, a, b)
                    e = cmp_error
                    out[0usize] = lit
                } else if op == OP_ULT {
                    let (lit, cmp_error) = bv_ult(f, a, b)
                    e = cmp_error
                    out[0usize] = lit
                } else {
                    ret Invalid
                }
                if e != ok { ret e }
            }
        }
        t += 1usize
    }
    ret ok
}
