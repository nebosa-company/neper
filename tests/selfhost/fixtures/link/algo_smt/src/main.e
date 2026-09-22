// `e.algo.smt`: congruence closure proves the textbook f^3(a) = a, f^5(a) = a
// entails f(a) = a, refutes f(a, b) = a with f(f(a, b), b) != a, and partitions
// an LCG-generated DAG as the Python replica does; bit-blasting factors 145
// in 8 bits, adds constants, refutes x < y < x, and lowers an expression
// tree whose model satisfies it. Each check exits with its own code.

use e.algo.sat as sat
use e.algo.smt as smt
use e.io
use e.mem
use e.os

fn next_lcg(state: *u64) -> u64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret *state >> 33u32
}

fn solve(f: *sat.Cnf, assignment: []i8, trail: []u32, level: []u32, flipped: []u8, learned: []i32, learned_starts: []usize) -> err {
    ret sat.solve(f, assignment, trail, level, flipped, learned, learned_starts, 200000usize)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var parent: [64]u32 = zero
    var rank: [64]u8 = zero

    // 1: f(f(f(a))) = a, f^5(a) = a |- f(a) = a. Terms t = f^t(a); a = symbol 0, f = symbol 1.
    var symbols: [6]u32 = zero
    var targs: [5]u32 = zero
    var starts: [7]usize = zero
    var t = 0usize
    while t < 6usize {
        if t > 0usize {
            symbols[t] = 1u32
            targs[t - 1usize] = u32(t - 1usize)
        }
        starts[t + 1usize] = t
        t += 1usize
    }
    var eq_lhs: [2]u32 = zero
    var eq_rhs: [2]u32 = zero
    eq_lhs[0usize] = 3u32
    eq_lhs[1usize] = 5u32
    let (c1, e1) = smt.congruence_closure(symbols[..], targs[..], starts[..], eq_lhs[..], eq_rhs[..], parent[..], rank[..])
    if e1 != ok { os.exit(1i32) }
    var closure1 = c1
    if !smt.euf_same(&closure1, 1u32, 0u32) || !smt.euf_same(&closure1, 2u32, 4u32) { os.exit(1i32) }
    // Without the second equality f(a) = a does not follow.
    let (c1b, e1b) = smt.congruence_closure(symbols[..], targs[..], starts[..], eq_lhs[..1usize], eq_rhs[..1usize], parent[..], rank[..])
    if e1b != ok { os.exit(1i32) }
    var closure1b = c1b
    if smt.euf_same(&closure1b, 1u32, 0u32) || !smt.euf_same(&closure1b, 4u32, 1u32) { os.exit(1i32) }

    // 2: f(a, b) = a, f(f(a, b), b) != a is unsatisfiable. Terms 0 = a, 1 = b, 2 = f(a, b), 3 = f(2, b).
    var symbols2: [4]u32 = zero
    symbols2[1usize] = 1u32
    symbols2[2usize] = 2u32
    symbols2[3usize] = 2u32
    var args2: [4]u32 = zero
    args2[1usize] = 1u32
    args2[2usize] = 2u32
    args2[3usize] = 1u32
    var starts2: [5]usize = zero
    starts2[3usize] = 2usize
    starts2[4usize] = 4usize
    eq_lhs[0usize] = 2u32
    var neq_lhs: [1]u32 = zero
    var neq_rhs: [1]u32 = zero
    neq_lhs[0usize] = 3u32
    let (sat2, e2) = smt.euf_satisfiable(symbols2[..], args2[..], starts2[..], eq_lhs[..1usize], eq_rhs[..1usize], neq_lhs[..], neq_rhs[..], parent[..], rank[..])
    if e2 != ok || sat2 { os.exit(2i32) }
    // f(a, b) != b alone is fine.
    neq_lhs[0usize] = 2u32
    neq_rhs[0usize] = 1u32
    let (sat2b, e2b) = smt.euf_satisfiable(symbols2[..], args2[..], starts2[..], eq_lhs[..1usize], eq_rhs[..1usize], neq_lhs[..], neq_rhs[..], parent[..], rank[..])
    if e2b != ok || !sat2b { os.exit(2i32) }
    let (_, bad) = smt.congruence_closure(symbols2[..], args2[..], starts2[..], eq_lhs[..1usize], eq_rhs[..2usize], parent[..], rank[..])
    if bad != smt.Invalid { os.exit(2i32) }

    // 3: an LCG-generated 40-term DAG; the canonical partition matches the replica.
    var state = 12345u64
    var symbols3: [40]u32 = zero
    var args3: [80]u32 = zero
    var starts3: [41]usize = zero
    var used = 0usize
    t = 0usize
    while t < 40usize {
        if t < 6usize {
            symbols3[t] = u32(next_lcg(&state) % 4u64)
        } else {
            symbols3[t] = 4u32 + u32(next_lcg(&state) % 3u64)
            let arity = 1usize + usize(next_lcg(&state) % 2u64)
            var k = 0usize
            while k < arity {
                args3[used] = u32(next_lcg(&state) % u64(t))
                used += 1usize
                k += 1usize
            }
        }
        starts3[t + 1usize] = used
        t += 1usize
    }
    var eq3_lhs: [10]u32 = zero
    var eq3_rhs: [10]u32 = zero
    var i = 0usize
    while i < 10usize {
        eq3_lhs[i] = u32(next_lcg(&state) % 40u64)
        eq3_rhs[i] = u32(next_lcg(&state) % 40u64)
        i += 1usize
    }
    let (c3, e3) = smt.congruence_closure(symbols3[..], args3[..used], starts3[..], eq3_lhs[..], eq3_rhs[..], parent[..], rank[..])
    if e3 != ok { os.exit(3i32) }
    var closure3 = c3
    var checksum = 0usize
    var distinct = 0usize
    t = 0usize
    while t < 40usize {
        var canonical = 0usize
        while !smt.euf_same(&closure3, u32(canonical), u32(t)) { canonical += 1usize }
        if canonical == t { distinct += 1usize }
        if smt.euf_class(&closure3, u32(canonical)) != smt.euf_class(&closure3, u32(t)) { os.exit(3i32) }
        checksum += canonical * (t + 1usize)
        t += 1usize
    }
    if checksum != 16257usize || distinct != 26usize { os.exit(3i32) }

    // Shared SAT storage for the bit-vector checks.
    var literals: [24000]i32 = zero
    var cstarts: [8000]usize = zero
    var assignment: [1200]i8 = zero
    var trail: [1200]u32 = zero
    var level: [1200]u32 = zero
    var flipped: [1201]u8 = zero
    var learned: [4000]i32 = zero
    var learned_starts: [400]usize = zero
    var x: [8]i32 = zero
    var y: [8]i32 = zero
    var z: [8]i32 = zero
    var k: [8]i32 = zero
    var scratch: [8]i32 = zero

    // 4: x * y == 0x91 with x, y >= 2 in 8 bits factors 145.
    let (f4, make4) = sat.cnf(literals[..], cstarts[..], 0usize)
    if make4 != ok { os.exit(4i32) }
    var f = f4
    if smt.bv_fresh(&f, x[..]) != ok || smt.bv_fresh(&f, y[..]) != ok { os.exit(4i32) }
    if smt.bv_mul(&f, x[..], y[..], z[..], scratch[..]) != ok { os.exit(4i32) }
    if smt.bv_const(&f, 145u64, k[..]) != ok { os.exit(4i32) }
    let (is_product, eq4) = smt.bv_eq(&f, z[..], k[..])
    if eq4 != ok || sat.clause1(&f, is_product) != ok { os.exit(4i32) }
    var two: [8]i32 = zero
    if smt.bv_const(&f, 2u64, two[..]) != ok { os.exit(4i32) }
    let (x_small, lt4x) = smt.bv_ult(&f, x[..], two[..])
    let (y_small, lt4y) = smt.bv_ult(&f, y[..], two[..])
    if lt4x != ok || lt4y != ok { os.exit(4i32) }
    if sat.clause1(&f, 0i32 - x_small) != ok || sat.clause1(&f, 0i32 - y_small) != ok { os.exit(4i32) }
    if solve(&f, assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..]) != ok { os.exit(4i32) }
    let xv = smt.bv_value(assignment[..], x[..])
    let yv = smt.bv_value(assignment[..], y[..])
    if xv < 2u64 || yv < 2u64 || ((xv * yv) & 255u64) != 145u64 { os.exit(4i32) }
    if smt.bv_value(assignment[..], z[..]) != 145u64 { os.exit(4i32) }

    // 5: a + b == c for three LCG pairs, and a - b back again.
    state = 777u64
    var pair = 0usize
    while pair < 3usize {
        let av = next_lcg(&state) & 255u64
        let bv = next_lcg(&state) & 255u64
        let (f5, make5) = sat.cnf(literals[..], cstarts[..], 0usize)
        if make5 != ok { os.exit(5i32) }
        var g = f5
        if smt.bv_const(&g, av, x[..]) != ok || smt.bv_const(&g, bv, y[..]) != ok { os.exit(5i32) }
        if smt.bv_add(&g, x[..], y[..], z[..]) != ok || smt.bv_sub(&g, z[..], y[..], k[..]) != ok { os.exit(5i32) }
        if solve(&g, assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..]) != ok { os.exit(5i32) }
        if smt.bv_value(assignment[..], z[..]) != ((av + bv) & 255u64) { os.exit(5i32) }
        if smt.bv_value(assignment[..], k[..]) != av { os.exit(5i32) }
        pair += 1usize
    }
    // Shifts and gates on the last pair (a = 69, b = 205 from the replica).
    let (f5s, make5s) = sat.cnf(literals[..], cstarts[..], 0usize)
    if make5s != ok { os.exit(5i32) }
    var h = f5s
    if smt.bv_const(&h, 69u64, x[..]) != ok || smt.bv_const(&h, 205u64, y[..]) != ok { os.exit(5i32) }
    if smt.bv_shl_const(&h, x[..], 3usize, z[..]) != ok || smt.bv_lshr_const(&h, y[..], 2usize, k[..]) != ok { os.exit(5i32) }
    if smt.bv_xor(&h, z[..], k[..], scratch[..]) != ok || smt.bv_not(scratch[..], two[..]) != ok { os.exit(5i32) }
    if solve(&h, assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..]) != ok { os.exit(5i32) }
    if smt.bv_value(assignment[..], z[..]) != ((69u64 << 3u32) & 255u64) || smt.bv_value(assignment[..], k[..]) != (205u64 >> 2u32) { os.exit(5i32) }
    if smt.bv_value(assignment[..], two[..]) != ((((69u64 << 3u32) & 255u64) ^ (205u64 >> 2u32)) ^ 255u64) { os.exit(5i32) }

    // 6: x < y and y < x is unsatisfiable; x < y alone is not.
    let (f6, make6) = sat.cnf(literals[..], cstarts[..], 0usize)
    if make6 != ok { os.exit(6i32) }
    var q = f6
    if smt.bv_fresh(&q, x[..]) != ok || smt.bv_fresh(&q, y[..]) != ok { os.exit(6i32) }
    let (xy, lt6a) = smt.bv_ult(&q, x[..], y[..])
    if lt6a != ok || sat.clause1(&q, xy) != ok { os.exit(6i32) }
    if solve(&q, assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..]) != ok { os.exit(6i32) }
    if smt.bv_value(assignment[..], x[..]) >= smt.bv_value(assignment[..], y[..]) { os.exit(6i32) }
    let (yx, lt6b) = smt.bv_ult(&q, y[..], x[..])
    if lt6b != ok || sat.clause1(&q, yx) != ok { os.exit(6i32) }
    if solve(&q, assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..]) != sat.Unsatisfiable { os.exit(6i32) }

    // 7: bit_blast over (x xor (y + 3)) == 0x5a; the model satisfies it.
    var ops: [7]u8 = zero
    var lhs: [7]u32 = zero
    var rhs: [7]u32 = zero
    var consts: [7]u64 = zero
    ops[0usize] = smt.OP_VAR
    ops[1usize] = smt.OP_VAR
    ops[2usize] = smt.OP_CONST
    consts[2usize] = 3u64
    ops[3usize] = smt.OP_ADD
    lhs[3usize] = 1u32
    rhs[3usize] = 2u32
    ops[4usize] = smt.OP_XOR
    lhs[4usize] = 0u32
    rhs[4usize] = 3u32
    ops[5usize] = smt.OP_CONST
    consts[5usize] = 90u64
    ops[6usize] = smt.OP_EQ
    lhs[6usize] = 4u32
    rhs[6usize] = 5u32
    var bits: [56]i32 = zero
    let (f7, make7) = sat.cnf(literals[..], cstarts[..], 0usize)
    if make7 != ok { os.exit(7i32) }
    var r = f7
    if smt.bit_blast(&r, ops[..], lhs[..], rhs[..], consts[..], 8usize, bits[..], scratch[..]) != ok { os.exit(7i32) }
    if sat.clause1(&r, bits[48usize]) != ok { os.exit(7i32) }
    if solve(&r, assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..]) != ok { os.exit(7i32) }
    let x7 = smt.bv_value(assignment[..], bits[..8usize])
    let y7 = smt.bv_value(assignment[..], bits[8usize..16usize])
    if (x7 ^ ((y7 + 3u64) & 255u64)) != 90u64 { os.exit(7i32) }
    // A child index at or past its parent is refused.
    lhs[6usize] = 6u32
    if smt.bit_blast(&r, ops[..], lhs[..], rhs[..], consts[..], 8usize, bits[..], scratch[..]) != smt.Invalid { os.exit(7i32) }

    try io.print("algo smt ok\n")
    ret ok
}
