// e.algo.stat.glmnet (gaussian) against glmnet at a user lambda sequence. tests/oracle/glmnet.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R glmnet`; the layout is at the top of
// scripts/r_oracle/groups/glmnet.R.

use e.algo.stat.glmnet as gl
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if c.name[0usize] == 108u8 {
        // lpath: (n, p, alpha, std, k, vf[p], y[n], X[n p])
        let ln = usize(x[0usize])
        let lp = usize(x[1usize])
        let (lo, le) = mem.alloc[f64](a, 100usize)
        if le != ok { ret 0.0f64 / 0.0f64 }
        if gl.lambda_path(a, x[5usize + lp + ln..5usize + lp + ln + ln * lp], x[5usize + lp..5usize + lp + ln], ln, lp, x[2usize], x[3usize] != 0.0f64, x[5usize..5usize + lp], 100usize, lo) != ok { ret 0.0f64 / 0.0f64 }
        ret lo[usize(x[4usize])]
    }
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let nl = usize(x[4usize])
    let lam = x[5usize..5usize + nl]
    let vf = x[5usize + nl..5usize + nl + p]
    let y = x[5usize + nl + p..5usize + nl + p + n]
    let xm = x[5usize + nl + p + n..5usize + nl + p + n + n * p]
    let at = 5usize + nl + p + n + n * p
    let wl = n * usize(x[at + 2usize])
    let bl = p * usize(x[at + 3usize])
    let (coef, ce) = mem.alloc[f64](a, nl * (p + 1usize))
    if ce != ok { ret 0.0f64 / 0.0f64 }
    var ge = ok
    if c.name[0usize] == 98u8 {
        ge = gl.binomial(a, xm, y, n, p, x[2usize], x[3usize] != 0.0f64, vf, lam, coef)
    } else {
        ge = gl.gaussian(a, xm, y, x[at + 4usize..at + 4usize + wl], x[at + 4usize + wl..at + 4usize + wl + bl], x[at + 4usize + wl + bl..at + 4usize + wl + 2usize * bl], n, p, x[2usize], x[3usize] != 0.0f64, vf, lam, coef)
    }
    if ge != ok { ret 0.0f64 / 0.0f64 }
    ret coef[usize(x[at]) * (p + 1usize) + usize(x[at + 1usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/glmnet.json")
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
