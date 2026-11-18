// e.algo.stat.flexmixpkg against flexmix (the Gaussian regression mixture from a given initial clustering). tests/oracle/flexmix_gauss.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R flexmix_gauss`; the layout is at the top of scripts/r_oracle/groups/flexmix_gauss.R.

use e.algo.stat.flexmixpkg as fx
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let k = usize(z[2usize])
    let what = usize(z[3usize])
    let idx = usize(z[4usize])
    let x = z[5usize..5usize + n * p]
    let y = z[5usize + n * p..5usize + n * p + n]
    let (init1, e0) = mem.alloc[f64](a, n)
    if e0 != ok { os.exit(4) }
    var i = 0usize
    while i < n {
        init1[i] = z[5usize + n * p + n + i] - 1.0f64
        i += 1usize
    }
    // x is stored column pairs (1, x1) per row
    let (f, e) = fx.gaussian(a, x, y, n, p, k, init1, 200usize, 0.05f64, 0.000001f64)
    if e != ok { os.exit(5) }
    if what == 0usize { ret f.llh }
    if what == 1usize { ret f64(f.iter) }
    if what == 2usize { ret f64(f.k) }
    if what == 3usize { ret f.prior[idx] }
    if what == 4usize { ret f.coef[idx] }
    if what == 5usize { ret f.sigma[idx] }
    ret f64(f.cluster[idx] + 1usize)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/flexmix_gauss.json")
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
