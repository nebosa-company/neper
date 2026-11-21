// e.algo.stat.tgp_design against R's tgp::dopt.gp and tgp.design (on a fit without a tree) under set.seed.
// tests/oracle/tgpdesign.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tgpdesign`.
// A case is (data seed, seed, nn, n, m, ncand, iter, k): the k-th chosen candidate index (1-based). The inputs are
// rebuilt from the data seed with R's generator.

use e.algo.rand.r as rr
use e.algo.stat.tgp_design as design
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn same_key(a: []const f64, b: []const f64) -> bool {
    var i = 0usize
    while i < 7usize {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tgpdesign.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    let group = mem.mark(a)
    var prev: []f64 = zero
    var have = false
    var fi: []i64 = zero
    var oe: err = ok
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let x = c.args
        if !have || !same_key(x, prev) {
            mem.reset(a, group)
            let nn = usize(x[2usize])
            let n = usize(x[3usize])
            let m = usize(x[4usize])
            let ncand = usize(x[5usize])
            var r: rr.Rng = zero
            rr.seed(&r, i64(x[0usize]))
            let (xm, e1) = mem.alloc[f64](a, n * m + 1usize)
            let (xc, e2) = mem.alloc[f64](a, ncand * m)
            if e1 != ok || e2 != ok { os.exit(5) }
            var i = 0usize
            var j = 0usize
            while j < m {
                i = 0usize
                while i < n {
                    xm[i * m + j] = rr.runif(&r, 0.0f64, 1.0f64)
                    i += 1usize
                }
                j += 1usize
            }
            j = 0usize
            while j < m {
                i = 0usize
                while i < ncand {
                    xc[i * m + j] = rr.runif(&r, 0.0f64, 1.0f64)
                    i += 1usize
                }
                j += 1usize
            }
            rr.seed(&r, i64(x[1usize]))
            let (res, re) = design.dopt_gp(a, &r, nn, xm, n, m, xc, ncand, usize(x[6usize]))
            fi = res
            oe = re
            prev = x
            have = true
        }
        var got = 0.0f64 / 0.0f64
        if oe == ok { got = f64(fi[usize(x[7usize])]) }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 15usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
