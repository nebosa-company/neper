// e.algo.stat.seriationcrit against seriation: the permutation criteria. tests/oracle/seriation.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R seriation`; the layout is at the top of
// scripts/r_oracle/groups/seriation.R.

use e.algo.stat.hclust as hc
use e.algo.stat.seriationcrit as sc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "hc") {
        let hn = usize(z[0usize])
        let (tree, he) = hc.hclust(a, z[1usize..1usize + hn * hn], hn, usize(z[1usize + hn * hn]))
        if he != ok { ret nan }
        ret f64(tree.order[usize(z[2usize + hn * hn])])
    }
    if str.eq(c.name, "gw") {
        let gn = usize(z[0usize])
        let (go, ge) = mem.alloc[usize](a, gn)
        if ge != ok { ret nan }
        let gr = sc.gw_order(a, z[1usize..1usize + gn * gn], gn, go)
        if gr != ok { ret nan }
        ret f64(go[usize(z[1usize + gn * gn])] + 1usize)
    }
    if str.eq(c.name, "mc") {
        let nr = usize(z[0usize])
        let nc = usize(z[1usize])
        let x = z[2usize..2usize + nr * nc]
        let (ro, e1) = mem.alloc[usize](a, nr)
        let (co, e2) = mem.alloc[usize](a, nc)
        if e1 != ok || e2 != ok { ret nan }
        var i = 0usize
        while i < nr {
            ro[i] = usize(z[2usize + nr * nc + i]) - 1usize
            i += 1usize
        }
        i = 0usize
        while i < nc {
            co[i] = usize(z[2usize + nr * nc + nr + i]) - 1usize
            i += 1usize
        }
        let code = usize(z[2usize + nr * nc + nr + nc])
        if code == 0usize { ret sc.measure_of_effectiveness(x, nr, nc, ro, co) }
        ret sc.stress(x, nc, ro, co, code == 2usize)
    }
    let n = usize(z[0usize])
    let d = z[1usize..1usize + n * n]
    let (o, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret nan }
    var i = 0usize
    while i < n {
        o[i] = usize(z[1usize + n * n + i]) - 1usize
        i += 1usize
    }
    let code = usize(z[1usize + n * n + n])
    let param = usize(z[2usize + n * n + n])
    if code == 1usize { ret sc.path_length(d, n, o) }
    if code == 2usize { ret sc.lazy_path_length(d, n, o) }
    if code == 3usize { ret sc.least_squares(d, n, o) }
    if code == 4usize { ret sc.inertia(d, n, o) }
    if code == 5usize { ret sc.anti_robinson(d, n, o, 1usize) }
    if code == 6usize { ret sc.anti_robinson(d, n, o, 2usize) }
    if code == 7usize { ret sc.gradient(d, n, o, 1usize) }
    if code == 8usize { ret sc.gradient(d, n, o, 2usize) }
    if code == 12usize { ret sc.two_sum(d, n, o) }
    if code == 13usize { ret sc.rho(a, d, n, o) }
    if code == 9usize { ret sc.bar(d, n, o, param) }
    ret sc.rgar(d, n, o, param, code == 10usize)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/seriation.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
