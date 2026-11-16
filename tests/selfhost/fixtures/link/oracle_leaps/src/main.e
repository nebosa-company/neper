// e.algo.stat.leaps against leaps::regsubsets (nbest = 1): exhaustive, forward and backward. tests/oracle/leaps.json
// comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R leaps`; the layout is at the top of
// scripts/r_oracle/groups/leaps.R.

use e.algo.stat.leaps as lp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let method = u8(z[0usize])
    let n = usize(z[1usize])
    let p = usize(z[2usize])
    let nvmax = usize(z[3usize])
    let x = z[4usize..4usize + n * p]
    let y = z[4usize + n * p..4usize + n * p + n]
    let k = usize(z[4usize + n * p + n])
    let q = usize(z[5usize + n * p + n])
    let (masks, e1) = mem.alloc[u32](a, p + 1usize)
    let (rss, e2) = mem.alloc[f64](a, p + 1usize)
    if e1 != ok || e2 != ok { ret nan }
    lp.regsubsets(a, x, y, n, p, nvmax, method, masks, rss)
    if q == 0usize { ret f64(masks[k - 1usize]) }
    if q == 1usize { ret rss[k - 1usize] }
    // centred total sum of squares and the all-variable residual sum of squares
    var m = 0.0f64
    var i = 0usize
    while i < n {
        m += y[i]
        i += 1usize
    }
    m = m / f64(n)
    var nullrss = 0.0f64
    i = 0usize
    while i < n {
        nullrss += (y[i] - m) * (y[i] - m)
        i += 1usize
    }
    let full = lp.subset_rss(a, x, y, n, p, u32((1usize << p) - 1usize))
    let (rsq, adj, cp, bic) = lp.summarise(n, p, k, rss[k - 1usize], nullrss, full)
    if q == 2usize { ret rsq }
    if q == 3usize { ret adj }
    if q == 4usize { ret cp }
    ret bic
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/leaps.json")
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
