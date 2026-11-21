// e.algo.stat.gbmpkg against R's gbm: gradient boosting with no subsampling for the gaussian,
// bernoulli, poisson, adaboost and laplace losses on 40 rows of 3 variables built by a formula
// over the row index, so no generator has to match. Three tree settings per loss; for each, the
// fit at all 40 rows, the relative influence of each variable, and predict at five new rows with
// all the trees and with half of them.
// tests/oracle/gbmpkg.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gbmpkg`.
// A case is (loss, ntrees, shrinkage, depth, minobs, k, row): k 0 is the fit at training row
// `row`, 1 to 3 the influence of variable k, 10 + t predict at new row `row` with t trees.

use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle
use e.algo.stat.gbmpkg as gbm

const N: usize = 40usize
const P: usize = 3usize

fn col(i: i64, j: i64) -> f64 {
    let m = (i * 37i64 + j * 101i64 + i * j * 13i64) % 997i64
    ret f64(m) / 997.0f64 + f64(i) * 0.000001f64
}

// n rows by 3 variables, column-major, row index starting at shift + 1.
fn make_x(a: *mem.Arena, n: usize, shift: i64) -> []f64 {
    let (x, e) = mem.alloc[f64](a, n * P)
    if e != ok { os.exit(5) }
    var j = 0usize
    while j < P {
        var r = 0usize
        while r < n {
            x[j * n + r] = col(i64(r) + 1i64 + shift, i64(j) + 1i64)
            r += 1usize
        }
        j += 1usize
    }
    ret x
}

fn make_y(a: *mem.Arena, loss: usize, x: []const f64) -> []f64 {
    let (y, e) = mem.alloc[f64](a, N)
    if e != ok { os.exit(5) }
    var r = 0usize
    while r < N {
        let i = i64(r) + 1i64
        let ee = f64((i * 53i64) % 101i64) / 101.0f64
        let x1 = x[r]
        let x2 = x[N + r]
        let x3 = x[2usize * N + r]
        var v = 0.0f64
        if loss == 0usize {
            var b = 0.0f64
            if x2 > 0.5f64 { b = 1.0f64 }
            v = 3.0f64 * x1 + b * 2.0f64 + ee
        } else if loss == 1usize {
            if x1 + 0.4f64 * ee > 0.55f64 { v = 1.0f64 }
        } else if loss == 2usize {
            v = math.floor(5.0f64 * x1 + 2.0f64 * ee)
        } else if loss == 3usize {
            if x2 + 0.4f64 * ee > 0.55f64 { v = 1.0f64 }
        } else {
            var b = 0.0f64
            if x3 > 0.4f64 { b = 1.0f64 }
            v = 3.0f64 * x1 - b * 2.0f64 + ee
        }
        y[r] = v
        r += 1usize
    }
    ret y
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gbmpkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let x = make_x(a, N, 0i64)
    let xnew = make_x(a, 5usize, 1000i64)
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let g = c.args
        let loss = usize(g[0usize])
        let ntrees = usize(g[1usize])
        let shrink = g[2usize]
        let depth = usize(g[3usize])
        let minobs = usize(g[4usize])
        let k = usize(g[5usize])
        let row = usize(g[6usize])
        let y = make_y(a, loss, x)
        let (fitted, fe) = mem.alloc[f64](a, N)
        let (rec, re) = mem.alloc[f64](a, ntrees * (4usize * depth + 2usize) + 1usize)
        let (inf, ie) = mem.alloc[f64](a, P)
        if fe != ok || re != ok || ie != ok { os.exit(4) }
        var got = 0.0f64 / 0.0f64
        if k >= 1usize && k <= 3usize {
            let e = gbm.influence(a, loss, x, y, N, P, ntrees, shrink, depth, minobs, fitted, inf)
            if e == ok { got = inf[k - 1usize] }
        } else {
            let e = gbm.model(a, loss, x, y, N, P, ntrees, shrink, depth, minobs, fitted, rec)
            if e == ok {
                if k == 0usize {
                    got = fitted[row - 1usize]
                } else {
                    var out: [5]f64 = zero
                    gbm.predict_model(rec, ntrees, depth, k - 10usize, xnew, 5usize, out[0..])
                    got = out[row - 1usize]
                }
            }
        }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 15usize {
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
