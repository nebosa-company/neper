// e.algo.stat.rcompanion against rcompanion. tests/oracle/rcompanion.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R rcompanion`; the layout is at the top of scripts/r_oracle/groups/rcompanion.R.

use e.algo.stat.rcompanion as rc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nm = c.name
    if str.eq(nm, "nsp") {
        let n = usize(x[0usize])
        let m = n * (n - 1usize) / 2usize
        let (pp, e1) = mem.alloc[f64](a, m)
        let (aj, e2) = mem.alloc[f64](a, m)
        if e1 != ok || e2 != ok { os.exit(5) }
        if rc.nominal_symmetry_pairs(a, x[2usize..2usize + n * n], n, pp, aj) != ok { ret 0.0f64 / 0.0f64 }
        if x[1usize] < 0.0f64 { ret pp[usize(0.0f64 - x[1usize] - 1.0f64)] }
        ret aj[usize(x[1usize])]
    }
    if str.eq(nm, "nsym") {
        let n = usize(x[0usize])
        ret rc.nominal_symmetry_p(x[1usize..1usize + n * n], n)
    }
    if str.eq(nm, "srh") {
        let n = usize(x[0usize])
        let l1 = usize(x[1usize])
        let l2 = usize(x[2usize])
        let (g1, e1) = mem.alloc[usize](a, n)
        let (g2, e2) = mem.alloc[usize](a, n)
        let (o, e3) = mem.alloc[f64](a, 6usize)
        if e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
        var i = 0usize
        while i < n {
            g1[i] = usize(x[3usize + i])
            g2[i] = usize(x[3usize + n + i])
            i += 1usize
        }
        if rc.scheirer_ray_hare(a, x[3usize + 2usize * n..3usize + 3usize * n], g1, l1, g2, l2, o) != ok { ret 0.0f64 / 0.0f64 }
        ret o[usize(x[3usize + 3usize * n])]
    }
    if str.eq(nm, "epsilon") || str.eq(nm, "freeman") {
        let n = usize(x[0usize])
        let k = usize(x[1usize])
        let (g, ge) = mem.alloc[usize](a, n)
        if ge != ok { os.exit(5) }
        var i = 0usize
        while i < n {
            g[i] = usize(x[2usize + n + i])
            i += 1usize
        }
        if str.eq(nm, "epsilon") { ret rc.epsilon_squared(a, x[2usize..2usize + n], g, k) }
        ret rc.freeman_theta(x[2usize..2usize + n], g, k)
    }
    if str.eq(nm, "cliff") || str.eq(nm, "vda") {
        let n1 = usize(x[0usize])
        let n2 = usize(x[1usize])
        if str.eq(nm, "cliff") { ret rc.cliff_delta(x[2usize..2usize + n1], x[2usize + n1..2usize + n1 + n2]) }
        ret rc.vda(x[2usize..2usize + n1], x[2usize + n1..2usize + n1 + n2])
    }
    let r = usize(x[0usize])
    let cc = usize(x[1usize])
    if str.eq(nm, "cramer") { ret rc.cramer_v(x[3usize..3usize + r * cc], r, cc, x[2usize] == 1.0f64) }
    ret rc.cohen_w(x[2usize..2usize + r * cc], r, cc)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/rcompanion.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
