// e.algo.stat.smspline against R smooth.spline with a given spar. tests/oracle/smspline.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R smspline`; the layout is at the top of scripts/r_oracle/groups/smspline.R.

use e.algo.stat.smspline as sm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    var f: sm.SmSpline = zero
    let (w, e) = mem.alloc[f64](a, n)
    if e != ok { ret nan }
    var i = 0usize
    while i < n {
        w[i] = 1.0f64
        i += 1usize
    }
    if str.eq(c.name, "ssdf") {
        let mm = usize(z[2usize])
        let sp = sm.fit_df(a, z[3usize..3usize + n], z[3usize + n..3usize + 2usize * n], w, z[1usize], &f)
        let ix = usize(z[3usize + 2usize * n + mm])
        if ix < mm { ret sm.predict(a, &f, z[3usize + 2usize * n + ix]) }
        if ix == mm { ret sp }
        if ix == mm + 1usize { ret f.lambda }
        ret f.df
    }
    if str.eq(c.name, "dfat") {
        if sm.fit(a, z[2usize..2usize + n], z[2usize + n..2usize + 2usize * n], w, z[1usize], &f) != ok { ret nan }
        ret f.df
    }
    if str.eq(c.name, "lam") {
        if sm.fit(a, z[2usize..2usize + n], z[2usize + n..2usize + 2usize * n], w, z[1usize], &f) != ok { ret nan }
        ret f.lambda
    }
    let m = usize(z[2usize])
    if sm.fit(a, z[3usize..3usize + n], z[3usize + n..3usize + 2usize * n], w, z[1usize], &f) != ok { ret nan }
    ret sm.predict(a, &f, z[3usize + 2usize * n + usize(z[3usize + 2usize * n + m])])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/smspline.json")
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
