// `e.math.opt.milp`: branch and cut against scipy.optimize.milp (HiGHS,
// mip_rel_gap 0, see ../vectors.py): the classic instance whose relaxation
// (41.25) is fractional, a 0/1 knapsack, general integers with negative
// bounds, mixed integer and continuous variables, equality rows, a 4 x 4
// assignment and a set cover, each solved with Gomory cuts on and off to the
// same objective with a feasible integral x; an integer-infeasible and an
// unbounded instance; twenty LCG-generated mixed instances within 1e-6 of
// HiGHS; Gomory's example, where the root cuts close the gap and the search
// needs fewer nodes than without; and the node limit. Objectives are
// compared, not solutions. Each check exits with its own code.

use e.io
use e.math
use e.math.opt.milp
use e.mem
use e.os

type Work = struct { scratch: []f64, slots: []usize, x: []f64 }

fn near(v: f64, want: f64) -> bool {
    var d = v - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= 0.000001f64 * (1.0f64 + want * want)
}

fn run(p: *const milp.Problem, cut_rounds: u32, node_limit: u32, w: *Work) -> (milp.Result, err) {
    var o = milp.defaults()
    o.cut_rounds = cut_rounds
    o.node_limit = node_limit
    let (r, failure) = milp.solve(p, o, w.x, w.scratch, w.slots)
    ret (r, failure)
}

// x within its bounds, integral where asked, every row satisfied, and c·x the reported objective.
fn feasible(p: *const milp.Problem, x: []const f64, objective: f64) -> bool {
    var value = 0.0f64
    var j = 0usize
    while j < p.n {
        let v = x[j]
        if v < p.lower[j] - 0.000001f64 || v > p.upper[j] + 0.000001f64 { ret false }
        if p.integer[j] {
            var f = v - math.floor[f64](v)
            if f > 0.5f64 { f = 1.0f64 - f }
            if f > 0.000001f64 { ret false }
        }
        value += p.c[j] * v
        j += 1usize
    }
    var i = 0usize
    while i < p.m {
        var s = 0.0f64
        j = 0usize
        while j < p.n {
            s += p.a[i * p.n + j] * x[j]
            j += 1usize
        }
        if s < p.row_lower[i] - 0.000001f64 || s > p.row_upper[i] + 0.000001f64 { ret false }
        i += 1usize
    }
    ret near(value, objective)
}

// Optimal at `want` with a feasible x, cuts on and off; answers the failing
// half (1 on, 2 off) or 0.
fn both(p: *const milp.Problem, want: f64, w: *Work) -> i32 {
    var rounds = 3u32
    var half = 1i32
    while half <= 2i32 {
        let (r, failure) = run(p, rounds, 100000u32, w)
        if failure != ok || r.status != .Optimal || !near(r.objective, want) || !feasible(p, w.x, want) { ret half }
        if r.bound > r.objective + 0.000001f64 || r.nodes == 0u32 { ret half }
        if half == 2i32 && r.cuts != 0u32 { ret half }
        rounds = 0u32
        half += 1i32
    }
    ret 0i32
}

fn check_classic(w: *Work) -> bool {
    var c = [2]f64{ 0.0f64 - 5.0f64, 0.0f64 - 8.0f64 }
    var a = [4]f64{ 1.0f64, 1.0f64, 5.0f64, 9.0f64 }
    var rl = [2]f64{ 0.0f64 - 1.0e30f64, 0.0f64 - 1.0e30f64 }
    var ru = [2]f64{ 6.0f64, 45.0f64 }
    var lo = [2]f64{ 0.0f64, 0.0f64 }
    var hi = [2]f64{ 1.0e30f64, 1.0e30f64 }
    var integer = [2]bool{ true, true }
    let p = milp.Problem { n: 2usize, m: 2usize, c: c[..], a: a[..], row_lower: rl[..], row_upper: ru[..], lower: lo[..], upper: hi[..], integer: integer[..] }
    if both(&p, 0.0f64 - 40.0f64, w) != 0i32 { ret false }
    // One node: the relaxation's 41.25 is the bound and no integer point is known.
    let (r, failure) = run(&p, 0u32, 1u32, w)
    if failure != ok || r.status != .NodeLimit || r.nodes != 1u32 || !near(r.bound, 0.0f64 - 41.25f64) { ret false }
    ret true
}

fn check_knapsack(w: *Work) -> bool {
    var c = [10]f64{ 0.0f64 - 15.0f64, 0.0f64 - 10.0f64, 0.0f64 - 9.0f64, 0.0f64 - 5.0f64, 0.0f64 - 12.0f64, 0.0f64 - 7.0f64, 0.0f64 - 11.0f64, 0.0f64 - 8.0f64, 0.0f64 - 6.0f64, 0.0f64 - 13.0f64 }
    var a = [10]f64{ 7.0f64, 5.0f64, 4.0f64, 3.0f64, 6.0f64, 4.0f64, 6.0f64, 5.0f64, 3.0f64, 7.0f64 }
    var rl = [1]f64{ 0.0f64 - 1.0e30f64 }
    var ru = [1]f64{ 26.0f64 }
    var lo = [10]f64{ 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64 }
    var hi = [10]f64{ 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64 }
    var integer = [10]bool{ true, true, true, true, true, true, true, true, true, true }
    let p = milp.Problem { n: 10usize, m: 1usize, c: c[..], a: a[..], row_lower: rl[..], row_upper: ru[..], lower: lo[..], upper: hi[..], integer: integer[..] }
    ret both(&p, 0.0f64 - 53.0f64, w) == 0i32
}

fn check_general(w: *Work) -> bool {
    var c = [4]f64{ 0.0f64 - 3.0f64, 0.0f64 - 2.0f64, 4.0f64, 0.0f64 - 1.0f64 }
    var a = [12]f64{ 2.0f64, 3.0f64, 1.0f64, 1.0f64, 1.0f64, 0.0f64 - 1.0f64, 2.0f64, 0.0f64, 0.0f64, 2.0f64, 0.0f64 - 1.0f64, 3.0f64 }
    var rl = [3]f64{ 0.0f64 - 1.0e30f64, 0.0f64 - 4.0f64, 1.0f64 }
    var ru = [3]f64{ 17.0f64, 9.0f64, 1.0e30f64 }
    var lo = [4]f64{ 0.0f64 - 3.0f64, 0.0f64 - 5.0f64, 0.0f64, 0.0f64 - 2.0f64 }
    var hi = [4]f64{ 7.0f64, 6.0f64, 4.0f64, 8.0f64 }
    var integer = [4]bool{ true, true, true, true }
    let p = milp.Problem { n: 4usize, m: 3usize, c: c[..], a: a[..], row_lower: rl[..], row_upper: ru[..], lower: lo[..], upper: hi[..], integer: integer[..] }
    ret both(&p, 0.0f64 - 25.0f64, w) == 0i32
}

fn check_mixed(w: *Work) -> bool {
    var c = [4]f64{ 0.0f64 - 4.0f64, 0.0f64 - 5.0f64, 0.0f64 - 3.0f64, 0.0f64 - 1.0f64 }
    var a = [12]f64{ 3.0f64, 2.0f64, 1.5f64, 1.0f64, 1.0f64, 4.0f64, 2.0f64, 0.5f64, 2.0f64, 1.0f64, 1.0f64, 3.0f64 }
    var rl = [3]f64{ 0.0f64 - 1.0e30f64, 0.0f64 - 1.0e30f64, 2.0f64 }
    var ru = [3]f64{ 20.5f64, 17.25f64, 15.0f64 }
    var lo = [4]f64{ 0.0f64, 0.0f64, 0.0f64, 0.0f64 }
    var hi = [4]f64{ 1.0e30f64, 1.0e30f64, 3.5f64, 1.0e30f64 }
    var integer = [4]bool{ true, true, false, false }
    let p = milp.Problem { n: 4usize, m: 3usize, c: c[..], a: a[..], row_lower: rl[..], row_upper: ru[..], lower: lo[..], upper: hi[..], integer: integer[..] }
    ret both(&p, 0.0f64 - 34.09090909090909f64, w) == 0i32
}

fn check_equality(w: *Work) -> bool {
    var c = [4]f64{ 2.0f64, 3.0f64, 1.0f64, 4.0f64 }
    var a = [8]f64{ 3.0f64, 5.0f64, 7.0f64, 2.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64 }
    var rl = [2]f64{ 47.0f64, 11.0f64 }
    var ru = [2]f64{ 47.0f64, 11.0f64 }
    var lo = [4]f64{ 0.0f64, 0.0f64, 0.0f64, 0.0f64 }
    var hi = [4]f64{ 1.0e30f64, 1.0e30f64, 1.0e30f64, 1.0e30f64 }
    var integer = [4]bool{ true, true, true, true }
    let p = milp.Problem { n: 4usize, m: 2usize, c: c[..], a: a[..], row_lower: rl[..], row_upper: ru[..], lower: lo[..], upper: hi[..], integer: integer[..] }
    ret both(&p, 20.0f64, w) == 0i32
}

// 4 x 4 assignment: x[r*4 + k] is worker r on job k.
fn check_assignment(w: *Work) -> bool {
    var c = [16]f64{ 9.0f64, 2.0f64, 7.0f64, 8.0f64, 6.0f64, 4.0f64, 3.0f64, 7.0f64, 5.0f64, 8.0f64, 1.0f64, 8.0f64, 7.0f64, 6.0f64, 9.0f64, 4.0f64 }
    var a: [128]f64 = zero
    var rl: [8]f64 = zero
    var ru: [8]f64 = zero
    var lo: [16]f64 = zero
    var hi: [16]f64 = zero
    var integer: [16]bool = zero
    var k = 0usize
    while k < 16usize {
        a[(k / 4usize) * 16usize + k] = 1.0f64
        a[(4usize + k % 4usize) * 16usize + k] = 1.0f64
        hi[k] = 1.0f64
        integer[k] = true
        k += 1usize
    }
    k = 0usize
    while k < 8usize {
        rl[k] = 1.0f64
        ru[k] = 1.0f64
        k += 1usize
    }
    let p = milp.Problem { n: 16usize, m: 8usize, c: c[..], a: a[..], row_lower: rl[..], row_upper: ru[..], lower: lo[..], upper: hi[..], integer: integer[..] }
    ret both(&p, 13.0f64, w) == 0i32
}

fn check_cover(w: *Work) -> bool {
    var c = [6]f64{ 3.0f64, 2.0f64, 4.0f64, 3.0f64, 2.0f64, 5.0f64 }
    var a = [42]f64{ 1.0f64, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 1.0f64, 1.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 1.0f64, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 1.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 1.0f64, 0.0f64, 1.0f64, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 1.0f64, 1.0f64, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 1.0f64 }
    var rl = [7]f64{ 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64 }
    var ru = [7]f64{ 1.0e30f64, 1.0e30f64, 1.0e30f64, 1.0e30f64, 1.0e30f64, 1.0e30f64, 1.0e30f64 }
    var lo = [6]f64{ 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64 }
    var hi = [6]f64{ 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64 }
    var integer = [6]bool{ true, true, true, true, true, true }
    let p = milp.Problem { n: 6usize, m: 7usize, c: c[..], a: a[..], row_lower: rl[..], row_upper: ru[..], lower: lo[..], upper: hi[..], integer: integer[..] }
    ret both(&p, 8.0f64, w) == 0i32
}

// 2x + 2y = 3 has a feasible relaxation and no integer point; x - y <= 1
// with -x - y minimised is unbounded.
fn check_infeasible_unbounded(w: *Work) -> i32 {
    var c = [2]f64{ 1.0f64, 1.0f64 }
    var a = [2]f64{ 2.0f64, 2.0f64 }
    var rl = [1]f64{ 3.0f64 }
    var ru = [1]f64{ 3.0f64 }
    var lo = [2]f64{ 0.0f64, 0.0f64 }
    var hi = [2]f64{ 10.0f64, 10.0f64 }
    var integer = [2]bool{ true, true }
    let p = milp.Problem { n: 2usize, m: 1usize, c: c[..], a: a[..], row_lower: rl[..], row_upper: ru[..], lower: lo[..], upper: hi[..], integer: integer[..] }
    let (r1, e1) = run(&p, 3u32, 100000u32, w)
    if e1 != ok || r1.status != .Infeasible { ret 1i32 }
    let (r2, e2) = run(&p, 0u32, 100000u32, w)
    if e2 != ok || r2.status != .Infeasible { ret 2i32 }
    c[0usize] = 0.0f64 - 1.0f64
    c[1usize] = 0.0f64 - 1.0f64
    a[1usize] = 0.0f64 - 1.0f64
    rl[0usize] = 0.0f64 - 1.0e30f64
    ru[0usize] = 1.0f64
    hi[0usize] = 1.0e30f64
    hi[1usize] = milp.infinity()
    let q = milp.Problem { n: 2usize, m: 1usize, c: c[..], a: a[..], row_lower: rl[..], row_upper: ru[..], lower: lo[..], upper: hi[..], integer: integer[..] }
    let (r3, e3) = run(&q, 3u32, 100000u32, w)
    if e3 != ok || r3.status != .Unbounded { ret 3i32 }
    ret 0i32
}

// Gomory's example, max y with 3x + 2y <= 6 and -3x + 2y <= 0: the
// relaxation sits at (1, 1.5); cuts reach an integral root.
fn check_gomory(w: *Work) -> i32 {
    var c = [2]f64{ 0.0f64, 0.0f64 - 1.0f64 }
    var a = [4]f64{ 3.0f64, 2.0f64, 0.0f64 - 3.0f64, 2.0f64 }
    var rl = [2]f64{ 0.0f64 - 1.0e30f64, 0.0f64 - 1.0e30f64 }
    var ru = [2]f64{ 6.0f64, 0.0f64 }
    var lo = [2]f64{ 0.0f64, 0.0f64 }
    var hi = [2]f64{ 1.0e30f64, 1.0e30f64 }
    var integer = [2]bool{ true, true }
    let p = milp.Problem { n: 2usize, m: 2usize, c: c[..], a: a[..], row_lower: rl[..], row_upper: ru[..], lower: lo[..], upper: hi[..], integer: integer[..] }
    let (on, e1) = run(&p, 3u32, 100000u32, w)
    if e1 != ok || on.status != .Optimal || !near(on.objective, 0.0f64 - 1.0f64) || on.cuts == 0u32 { ret 1i32 }
    let (off, e2) = run(&p, 0u32, 100000u32, w)
    if e2 != ok || off.status != .Optimal || !near(off.objective, 0.0f64 - 1.0f64) || off.cuts != 0u32 { ret 2i32 }
    if on.nodes >= off.nodes { ret 3i32 }
    ret 0i32
}

type Lcg = struct { s: u64 }

fn draw(g: *Lcg, k: u64) -> u64 {
    g.s = g.s *% 6364136223846793005u64 +% 1442695040888963407u64
    ret (g.s >> 33u32) % k
}

// Mirrors `random_instance` in vectors.py: boxes, a hidden integral point
// x0, and rows <=, >= or ranged around its activity. Answers (n, m).
fn random_instance(seed: u64, c: []f64, a: []f64, rl: []f64, ru: []f64, lo: []f64, hi: []f64, integer: []bool) -> (usize, usize) {
    var s = Lcg { s: seed }
    let n = 6usize + usize(draw(&s, 7u64))
    let m = 3usize + usize(draw(&s, 5u64))
    var x0: [16]f64 = zero
    var j = 0usize
    while j < n {
        let l = 0.0f64 - f64(draw(&s, 3u64))
        let width = 1u64 + draw(&s, 8u64)
        lo[j] = l
        hi[j] = l + f64(width)
        integer[j] = draw(&s, 4u64) != 0u64
        x0[j] = l + f64(draw(&s, width + 1u64))
        j += 1usize
    }
    j = 0usize
    while j < n {
        c[j] = f64(draw(&s, 21u64)) - 10.0f64
        j += 1usize
    }
    var i = 0usize
    while i < m {
        var act = 0.0f64
        j = 0usize
        while j < n {
            let v = f64(draw(&s, 13u64)) - 4.0f64
            a[i * n + j] = v
            act += v * x0[j]
            j += 1usize
        }
        let kind = draw(&s, 3u64)
        let slack = f64(draw(&s, 5u64))
        rl[i] = act - slack
        ru[i] = act + slack
        if kind == 0u64 { rl[i] = 0.0f64 - 1.0e30f64 }
        if kind == 1u64 { ru[i] = 1.0e30f64 }
        i += 1usize
    }
    ret (n, m)
}

// Twenty random instances against HiGHS, cuts on and off; answers the first
// failing instance + 1 or 0.
fn check_random(w: *Work) -> i32 {
    let expected = [20]f64{ 0.0f64 - 70.0f64, 0.0f64 - 94.0f64, 0.0f64 - 28.000000000000046f64, 0.0f64 - 67.28571428571429f64, 0.0f64 - 124.00000000000001f64, 0.0f64 - 139.64864864864865f64, 0.0f64 - 46.0f64, 0.0f64 - 197.5f64, 0.0f64 - 29.000000000000064f64, 0.0f64 - 91.28571428571428f64, 0.0f64 - 7.0f64, 0.0f64 - 64.0f64, 40.14285714285713f64, 0.0f64 - 29.857142857142858f64, 2.7857142857142856f64, 0.0f64 - 83.5f64, 0.0f64 - 8.89041095890412f64, 0.0f64 - 12.0f64, 0.0f64 - 75.77777777777781f64, 0.0f64 - 56.75f64 }
    var c: [16]f64 = zero
    var a: [128]f64 = zero
    var rl: [8]f64 = zero
    var ru: [8]f64 = zero
    var lo: [16]f64 = zero
    var hi: [16]f64 = zero
    var integer: [16]bool = zero
    var k = 0usize
    while k < 20usize {
        let (n, m) = random_instance(1000u64 + u64(k), c[..], a[..], rl[..], ru[..], lo[..], hi[..], integer[..])
        let p = milp.Problem { n: n, m: m, c: c[..n], a: a[..m * n], row_lower: rl[..m], row_upper: ru[..m], lower: lo[..n], upper: hi[..n], integer: integer[..n] }
        if both(&p, expected[k], w) != 0i32 { ret i32(k) + 1i32 }
        k += 1usize
    }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let nodes = 4096usize
    let (scratch, e1) = mem.alloc[f64](a, milp.scratch_len(16usize, 8usize, 64usize, nodes))
    if e1 != ok { os.exit(99i32) }
    let (slots, e2) = mem.alloc[usize](a, milp.slot_len(16usize, 8usize, 64usize))
    if e2 != ok { os.exit(99i32) }
    let (x, e3) = mem.alloc[f64](a, 16usize)
    if e3 != ok { os.exit(99i32) }
    var w = Work { scratch: scratch, slots: slots, x: x }

    if !check_classic(&w) { os.exit(1i32) }
    if !check_knapsack(&w) { os.exit(2i32) }
    if !check_general(&w) { os.exit(3i32) }
    if !check_mixed(&w) { os.exit(4i32) }
    if !check_equality(&w) { os.exit(5i32) }
    if !check_assignment(&w) { os.exit(6i32) }
    if !check_cover(&w) { os.exit(7i32) }
    let bad = check_infeasible_unbounded(&w)
    if bad != 0i32 { os.exit(10i32 + bad) }
    let gomory = check_gomory(&w)
    if gomory != 0i32 { os.exit(20i32 + gomory) }
    let failing = check_random(&w)
    if failing != 0i32 { os.exit(30i32 + failing) }
    try io.print("math opt milp ok\n")
    ret ok
}
