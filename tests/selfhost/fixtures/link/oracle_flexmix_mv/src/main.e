// e.algo.stat.flexmixmv against flexmix (FLXMCmvnorm full and diagonal, FLXMCmvbinary). tests/oracle/flexmix_mv.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R flexmix_mv`; the layout is at the top of scripts/r_oracle/groups/flexmix_mv.R.

use e.algo.rand.r as rg
use e.algo.stat.flexmixmv as mv
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn wsum(v: []const f64) -> f64 {
    var s = 0.0f64
    var q = 0usize
    while q < v.len {
        s += f64(q + 1usize) * v[q]
        q += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let d = usize(z[1usize])
    let k = usize(z[2usize])
    let model = usize(z[3usize])
    let what = usize(z[4usize])
    let idx = usize(z[5usize])
    let seed = i64(z[6usize])
    let y = z[7usize..7usize + n * d]
    let ini = z[7usize + n * d..7usize + n * d + n]
    var f: mv.Mv = zero
    var e = ok
    if seed > 0i64 {
        var rng: rg.Rng = zero
        rg.seed(&rng, seed)
        let (f1, e1) = mv.random(a, &rng, y, n, d, k, model, 0.05f64, 0.000001f64, 200usize)
        f = f1
        e = e1
    } else {
        let (f2, e2) = mv.em(a, y, n, d, ini, model, 0.05f64, 0.000001f64, 200usize)
        f = f2
        e = e2
    }
    if e != ok { os.exit(5) }
    if what == 0usize { ret f.llh }
    if what == 1usize { ret f64(f.iter) }
    if what == 2usize { ret f64(f.k) }
    if what == 3usize { ret wsum(f.prior[0usize..f.k]) }
    if what == 4usize { ret wsum(f.center[0usize..f.k * d]) }
    if what == 5usize { ret wsum(f.cov[0usize..f.k * d * d]) }
    if what == 6usize {
        var cs = 0.0f64
        var q = 0usize
        while q < n {
            cs += f64(q + 1usize) * f64(f.cluster[q] + 1usize)
            q += 1usize
        }
        ret cs
    }
    if what == 7usize { ret mv.aic(&f) }
    if what == 8usize { ret mv.bic(&f, n) }
    if what == 9usize { ret mv.icl(&f, n) }
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/flexmix_mv.json")
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
