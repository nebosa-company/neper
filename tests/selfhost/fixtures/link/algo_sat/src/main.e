// `e.algo.sat`: the solver finds models of satisfiable formulas and
// refuses the pigeonhole formula, the at-most and pseudo-boolean encodings
// agree with counting on every assignment, Tseitin gates make two circuits
// that `equivalent` tells apart, WalkSAT finds a model, and preprocessing
// applies units. Each check exits with its own code.

use e.algo.rand
use e.algo.sat as sat
use e.io
use e.mem
use e.os

// Solve with every original variable of `fixed[..n]` forced, then drop the units.
fn solve_fixed(f: *sat.Cnf, n: usize, fixed: []const i8, assignment: []i8, trail: []u32, level: []u32, flipped: []u8, learned: []i32, learned_starts: []usize) -> err {
    let before = f.clauses
    var i = 0usize
    while i < n {
        var lit = i32(i + 1usize)
        if fixed[i] < 0i8 { lit = 0i32 - lit }
        if sat.clause1(f, lit) != ok { ret sat.TooSmall }
        i += 1usize
    }
    let verdict = sat.solve(f, assignment, trail, level, flipped, learned, learned_starts, 100000usize)
    f.clauses = before
    ret verdict
}

fn main(a: *mem.Arena, args: []str) -> err {
    var literals: [2048]i32 = zero
    var starts: [512]usize = zero
    var assignment: [128]i8 = zero
    var trail: [128]u32 = zero
    var level: [128]u32 = zero
    var flipped: [129]u8 = zero
    var learned: [2048]i32 = zero
    var learned_starts: [256]usize = zero
    var fixed: [8]i8 = zero

    // 1: a satisfiable and an unsatisfiable formula.
    let (f0, make_error) = sat.cnf(literals[..], starts[..], 3usize)
    if make_error != ok { os.exit(1i32) }
    var f = f0
    // (x1 or x2) and (not x1 or x3) and (not x2 or not x3) and (x1 or x3).
    if sat.clause2(&f, 1i32, 2i32) != ok || sat.clause2(&f, 0i32 - 1i32, 3i32) != ok || sat.clause2(&f, 0i32 - 2i32, 0i32 - 3i32) != ok || sat.clause2(&f, 1i32, 3i32) != ok { os.exit(1i32) }
    if sat.solve(&f, assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..], 1000usize) != ok || !sat.satisfied(&f, assignment[..]) { os.exit(1i32) }
    // x1 must be true and x3 true, x2 false.
    if assignment[0usize] != 1i8 || assignment[2usize] != 1i8 || assignment[1usize] != 0i8 - 1i8 { os.exit(1i32) }
    // Pigeonhole: 3 pigeons, 2 holes (p_ij = variable 2i + j + 1).
    let (g0, g_error) = sat.cnf(literals[..], starts[..], 6usize)
    if g_error != ok { os.exit(1i32) }
    var g = g0
    var p = 0usize
    while p < 3usize {
        if sat.clause2(&g, i32(2usize * p + 1usize), i32(2usize * p + 2usize)) != ok { os.exit(1i32) }
        p += 1usize
    }
    var h = 0usize
    while h < 2usize {
        var lits: [3]i32 = zero
        lits[0usize] = i32(h + 1usize)
        lits[1usize] = i32(h + 3usize)
        lits[2usize] = i32(h + 5usize)
        if sat.at_most(&g, lits[..], 1usize) != ok { os.exit(1i32) }
        h += 1usize
    }
    if sat.solve(&g, assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..], 100000usize) != sat.Unsatisfiable { os.exit(1i32) }
    if sat.clause1(&f, 0i32) != sat.Invalid || sat.clause1(&f, 9i32) != sat.Invalid { os.exit(1i32) }

    // 2: encodings against counting over every assignment of four variables.
    let (e0, e_error) = sat.cnf(literals[..], starts[..], 4usize)
    if e_error != ok { os.exit(2i32) }
    var e = e0
    var four: [4]i32 = zero
    four[0usize] = 1i32
    four[1usize] = 2i32
    four[2usize] = 3i32
    four[3usize] = 4i32
    if sat.at_most(&e, four[..], 2usize) != ok { os.exit(2i32) }
    var mask = 0usize
    while mask < 16usize {
        var ones = 0usize
        var i = 0usize
        while i < 4usize {
            fixed[i] = 0i8 - 1i8
            if (mask >> u32(i)) & 1usize == 1usize {
                fixed[i] = 1i8
                ones += 1usize
            }
            i += 1usize
        }
        let verdict = solve_fixed(&e, 4usize, fixed[..], assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..])
        if (ones <= 2usize && verdict != ok) || (ones > 2usize && verdict != sat.Unsatisfiable) { os.exit(2i32) }
        mask += 1usize
    }
    // 3 x1 + 2 x2 + 2 x3 + 1 x4 <= 4.
    let (q0, q_error) = sat.cnf(literals[..], starts[..], 4usize)
    if q_error != ok { os.exit(2i32) }
    var q = q0
    var coefficients: [4]u32 = zero
    coefficients[0usize] = 3u32
    coefficients[1usize] = 2u32
    coefficients[2usize] = 2u32
    coefficients[3usize] = 1u32
    var memo: [40]i32 = zero
    if sat.pseudo_boolean(&q, four[..], coefficients[..], 4u32, memo[..]) != ok { os.exit(2i32) }
    mask = 0usize
    while mask < 16usize {
        var total = 0u32
        var i = 0usize
        while i < 4usize {
            fixed[i] = 0i8 - 1i8
            if (mask >> u32(i)) & 1usize == 1usize {
                fixed[i] = 1i8
                total += coefficients[i]
            }
            i += 1usize
        }
        let verdict = solve_fixed(&q, 4usize, fixed[..], assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..])
        if (total <= 4u32 && verdict != ok) || (total > 4u32 && verdict != sat.Unsatisfiable) { os.exit(2i32) }
        mask += 1usize
    }
    let (z0, z_error) = sat.cnf(literals[..], starts[..], 2usize)
    if z_error != ok { os.exit(2i32) }
    var z = z0
    if sat.pseudo_boolean(&z, four[..2usize], coefficients[..2usize], 1u32, memo[..]) != ok { os.exit(2i32) }
    // Both must be false: the formula forces it.
    if sat.solve(&z, assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..], 1000usize) != ok || assignment[0usize] != 0i8 - 1i8 || assignment[1usize] != 0i8 - 1i8 { os.exit(2i32) }

    // 3: circuits and equivalence.
    let (c0, c_error) = sat.cnf(literals[..], starts[..], 2usize)
    if c_error != ok { os.exit(3i32) }
    var c = c0
    let (left, l_error) = sat.tseitin_and(&c, 1i32, 2i32)
    let (not_a_or_not_b, o_error) = sat.tseitin_or(&c, sat.tseitin_not(1i32), sat.tseitin_not(2i32))
    if l_error != ok || o_error != ok { os.exit(3i32) }
    let right = sat.tseitin_not(not_a_or_not_b)
    let (same, same_error) = sat.equivalent(&c, left, right, assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..])
    if same_error != ok || !same { os.exit(3i32) }
    let (d0, d_error) = sat.cnf(literals[..], starts[..], 2usize)
    if d_error != ok { os.exit(3i32) }
    var d = d0
    let (x, x_error) = sat.tseitin_xor(&d, 1i32, 2i32)
    let (o, or_error) = sat.tseitin_or(&d, 1i32, 2i32)
    if x_error != ok || or_error != ok { os.exit(3i32) }
    let (differ, differ_error) = sat.equivalent(&d, x, o, assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..])
    if differ_error != ok || differ { os.exit(3i32) }
    // The witness has both inputs true.
    if assignment[0usize] != 1i8 || assignment[1usize] != 1i8 { os.exit(3i32) }

    // 4: WalkSAT and preprocessing (the formulas share the literal pool, so rebuild the first).
    let (f1, rebuild_error) = sat.cnf(literals[..], starts[..], 3usize)
    if rebuild_error != ok { os.exit(4i32) }
    f = f1
    if sat.clause2(&f, 1i32, 2i32) != ok || sat.clause2(&f, 0i32 - 1i32, 3i32) != ok || sat.clause2(&f, 0i32 - 2i32, 0i32 - 3i32) != ok || sat.clause2(&f, 1i32, 3i32) != ok { os.exit(4i32) }
    var r = rand.pcg64(6u64, 1u64)
    let (walk, walk_error) = sat.walksat(&f, assignment[..], 0.3f64, 1000usize, &r)
    if walk_error != ok || !walk || !sat.satisfied(&f, assignment[..]) { os.exit(4i32) }
    // Preprocess: units propagate through the first formula plus x2 forced... x1 unit.
    if sat.clause1(&f, 1i32) != ok { os.exit(4i32) }
    let before = f.clauses
    if sat.preprocess(&f, fixed[..]) != ok || fixed[0usize] != 1i8 || fixed[2usize] != 1i8 || fixed[1usize] != 0i8 - 1i8 || f.clauses >= before { os.exit(4i32) }
    // Contradictory units.
    if sat.clause1(&f, 2i32) != ok || sat.clause1(&f, 0i32 - 2i32) != ok || sat.preprocess(&f, fixed[..]) != sat.Unsatisfiable { os.exit(4i32) }

    // 5: #226.1: a coefficient past the remaining bound must take the false branch,
    // never wrap the partial sum (the old code trapped here).
    let (w0, w_error) = sat.cnf(literals[..], starts[..], 2usize)
    if w_error != ok { os.exit(5i32) }
    var w = w0
    var big_coeff: [2]u32 = zero
    big_coeff[0usize] = 1u32
    big_coeff[1usize] = 4294967295u32
    var big_lits: [2]i32 = zero
    big_lits[0usize] = 1i32
    big_lits[1usize] = 2i32
    var big_memo: [6]i32 = zero
    if sat.pseudo_boolean(&w, big_lits[..], big_coeff[..], 1u32, big_memo[..]) != ok { os.exit(5i32) }
    if sat.solve(&w, assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..], 1000usize) != ok { os.exit(5i32) }
    if assignment[1usize] != 0i8 - 1i8 { os.exit(5i32) }

    // 6: #226.2: an empty clause makes WalkSAT answer Unsatisfiable instead of
    // picking a literal from nothing.
    let (v0, v_error) = sat.cnf(literals[..], starts[..], 1usize)
    if v_error != ok { os.exit(6i32) }
    var v = v0
    var empty_clause: [0]i32 = zero
    if sat.add_clause(&v, empty_clause[..]) != ok { os.exit(6i32) }
    var vr = rand.pcg64(9u64, 2u64)
    let (walk2, walk2_error) = sat.walksat(&v, assignment[..], 0.3f64, 10usize, &vr)
    if walk2 || walk2_error != sat.Unsatisfiable { os.exit(6i32) }

    // 7: #226.3: a bad gate or counter input answers Invalid, not TooSmall, and is
    // refused before a fresh variable or clause is added.
    let (u0, u_error) = sat.cnf(literals[..], starts[..], 2usize)
    if u_error != ok { os.exit(7i32) }
    var u = u0
    let (_, bad_gate) = sat.tseitin_and(&u, 0i32, 1i32)
    let (_, out_gate) = sat.tseitin_or(&u, 1i32, 5i32)
    if bad_gate != sat.Invalid || out_gate != sat.Invalid { os.exit(7i32) }
    let (at0, at_error) = sat.cnf(literals[..], starts[..], 2usize)
    if at_error != ok { os.exit(7i32) }
    var at = at0
    var bad_pair: [2]i32 = zero
    bad_pair[0usize] = 1i32
    bad_pair[1usize] = 0i32
    if sat.at_most(&at, bad_pair[..], 0usize) != sat.Invalid { os.exit(7i32) }

    // 8: #226.4: a cyclic or out-of-order circuit answers Invalid instead of
    // recursing forever, and a Var literal is checked.
    let (t0, t_error) = sat.cnf(literals[..], starts[..], 1usize)
    if t_error != ok { os.exit(8i32) }
    var tt = t0
    var cycle_kind: [2]sat.Gate = zero
    cycle_kind[0usize] = .Not
    cycle_kind[1usize] = .Not
    var cycle_left: [2]i32 = zero
    cycle_left[0usize] = 1i32
    cycle_left[1usize] = 0i32
    var cycle_right: [2]i32 = zero
    let (_, cycle_error) = sat.tseitin(&tt, cycle_kind[..], cycle_left[..], cycle_right[..], 1usize)
    if cycle_error != sat.Invalid { os.exit(8i32) }
    var var_kind: [1]sat.Gate = zero
    var_kind[0usize] = .Var
    var var_left: [1]i32 = zero
    var var_right: [1]i32 = zero
    let (_, var_error) = sat.tseitin(&tt, var_kind[..], var_left[..], var_right[..], 0usize)
    if var_error != sat.Invalid { os.exit(8i32) }

    try io.print("algo sat ok\n")
    ret ok
}
