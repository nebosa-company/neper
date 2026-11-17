// e.algo.stat.biasedurn against BiasedUrn: Fisher's and Wallenius' noncentral hypergeometric distributions.
// tests/oracle/biasedurn.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R biasedurn`; the
// layout is at the top of scripts/r_oracle/groups/biasedurn.R.

use e.algo.stat.biasedurn as bu
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.eq(c.name, "mv") {
        // args (kind, what, idx, n, c, m[c], odds[c], xq[c])
        let cc = usize(z[4usize])
        ret bu.mv_value(a, usize(z[0usize]), z[5usize..5usize + cc], z[5usize + cc..5usize + 2usize * cc], z[3usize], z[5usize + 2usize * cc..5usize + 3usize * cc], usize(z[1usize]), usize(z[2usize]))
    }
    let kind = usize(z[0usize])
    let m1 = z[1usize]
    let m2 = z[2usize]
    let n = z[3usize]
    let w = z[4usize]
    let arg = z[5usize]
    let lo = bu.lo_of(m2, n)
    let (pmf, e) = mem.alloc[f64](a, usize(bu.hi_of(m1, n) - lo) + 2usize)
    if e != ok { ret 0.0f64 / 0.0f64 }
    if kind == 11usize {
        ret bu.odds_fisher(arg, m1, m2, n)
    }
    if kind == 5usize { ret bu.mode_fisher(m1, m2, n, w) }
    var cnt = 0usize
    if kind <= 5usize { cnt = bu.fisher_pmf(m1, m2, n, w, pmf) } else { cnt = bu.wallenius_pmf(m1, m2, n, w, pmf) }
    // kind within a family: 0 d, 1 p, 2 q, 3 mean, 4 var, 5 mode
    var k = kind
    if k >= 6usize { k -= 6usize }
    if kind == 12usize { k = 5usize }
    ret bu.summarise(pmf, cnt, lo, u8(k), arg)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/biasedurn.json")
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
