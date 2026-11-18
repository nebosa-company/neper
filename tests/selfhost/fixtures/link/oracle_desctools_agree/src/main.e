// e.algo.stat.desctools's ccc and cronbach_alpha against DescTools. tests/oracle/desctools_agree.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R desctools_agree`; the layout is at the top of scripts/r_oracle/groups/desctools_agree.R.

use e.algo.stat.desctools as dt
use e.algo.rand.r as rg
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let (o, e) = mem.alloc[f64](a, 6usize)
    if e != ok { os.exit(4) }
    if z[0usize] == 8.0f64 {
        let n = usize(z[1usize])
        ret dt.cohen_d1(z[2usize..2usize + n])
    }
    if z[0usize] == 14.0f64 {
        let mn = usize(z[1usize])
        ret dt.mad_dt(a, z[5usize..5usize + mn], z[2usize], z[3usize] == 1.0f64, z[4usize] == 1.0f64)
    }
    if z[0usize] == 13.0f64 {
        ret dt.binom_ci2(z[2usize], z[3usize], z[4usize], usize(z[1usize]), usize(z[5usize]), 123i64)
    }
    if z[0usize] == 12.0f64 {
        let n = usize(z[1usize])
        var rng: rg.Rng = zero
        rg.seed(&rng, i64(z[2usize]))
        if dt.gini_bca(a, &rng, z[6usize..6usize + n], z[6usize + n..6usize + 2usize * n], z[5usize] == 1.0f64, z[4usize], usize(z[3usize]), usize(z[7usize + 2usize * n]), o) != ok { os.exit(9) }
        ret o[usize(z[6usize + 2usize * n])]
    }
    if z[0usize] == 10.0f64 {
        let n = usize(z[1usize])
        let xs = z[2usize..2usize + n]
        dt.cohen_d_ci(dt.cohen_d1(xs), 0usize, f64(n), 0.0f64, 0.0f64, 1.0f64 - z[2usize + n], o)
        ret o[usize(z[3usize + n])]
    }
    if z[0usize] == 11.0f64 {
        let nx = usize(z[1usize])
        let ny = usize(z[2usize])
        let xs = z[4usize..4usize + nx]
        let ys = z[4usize + nx..4usize + nx + ny]
        dt.cohen_d_ci(dt.cohen_d2(a, xs, ys, true, false), 1usize, 0.0f64, f64(nx), f64(ny), 1.0f64 - z[3usize], o)
        ret o[usize(z[4usize + nx + ny])]
    }
    if z[0usize] == 9.0f64 {
        let nx = usize(z[1usize])
        let ny = usize(z[2usize])
        let fl = usize(z[3usize])
        ret dt.cohen_d2(a, z[4usize..4usize + nx], z[4usize + nx..4usize + nx + ny], fl % 2usize == 1usize, fl >= 2usize)
    }
    if z[0usize] >= 2.0f64 {
        let kn = usize(z[0usize])
        let n = usize(z[1usize])
        let xs = z[2usize..2usize + n]
        let ex = z[2usize + n]
        let cf = z[3usize + n]
        let jj = usize(z[4usize + n])
        if kn == 2usize {
            dt.mean_ci(xs, ex, cf, o)
            ret o[jj]
        }
        if kn == 3usize || kn == 4usize {
            let ve = dt.var_ci(a, xs, cf, kn == 4usize, o)
            if ve != ok { os.exit(6) }
            ret o[jj]
        }
        if kn == 5usize { ret dt.mean_se(xs) }
        if kn == 7usize {
            let te = dt.mean_ci_trim(a, xs, ex, cf, o)
            if te != ok { os.exit(8) }
            ret o[jj]
        }
        let (cn, g1) = mem.alloc[f64](a, n)
        if g1 != ok { os.exit(7) }
        var q = 0usize
        while q < n {
            cn[q] = z[5usize + n + q]
            q += 1usize
        }
        ret dt.herfindahl(xs, cn, ex)
    }
    if z[0usize] == 0.0f64 {
        let n = usize(z[3usize])
        dt.ccc(z[4usize..4usize + n], z[4usize + n..4usize + 2usize * n], z[2usize], usize(z[1usize]), o)
        ret o[usize(z[4usize + 2usize * n])]
    }
    let n = usize(z[1usize])
    let nc = usize(z[2usize])
    let ce = dt.cronbach_alpha(a, z[4usize..4usize + n * nc], n, nc, z[3usize], o)
    if ce != ok { os.exit(5) }
    ret o[usize(z[4usize + n * nc])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/desctools_agree.json")
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
