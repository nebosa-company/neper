// e.algo.stat.maxlikpkg against maxLik (NR, BHHH, BFGS, NM and stdEr). tests/oracle/maxlikpkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R maxlikpkg`; the case layout is at the top of scripts/r_oracle/groups/maxlikpkg.R.

use e.algo.stat.maxlikpkg as ml
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/maxlikpkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let model = usize(x[0usize])
        let method = usize(x[1usize])
        let what = usize(x[2usize])
        let idx = usize(x[3usize])
        let n = usize(x[4usize])
        let p = ml.npar(model)
        let (gm, e1) = mem.alloc[f64](a, n * p)
        let (th, e2) = mem.alloc[f64](a, p)
        let (g, e3) = mem.alloc[f64](a, p)
        let (h, e4) = mem.alloc[f64](a, p * p)
        let (se, e5) = mem.alloc[f64](a, p)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { os.exit(5) }
        var i = 0usize
        while i < p {
            th[i] = x[5usize + i]
            i += 1usize
        }
        var ctx = ml.MCtx{ model: model, n: n, p: p, x: x[5usize + p..5usize + p + n], y: x[5usize + p + n..5usize + p + 2usize * n], gm: gm, fcnt: 0usize, gcnt: 0usize }
        var maximum = 0.0f64
        var code = 0usize
        var cnt = 0usize
        if method == 0usize || method == 1usize {
            let (mx, cd, it) = ml.max_nr(a, &ctx, th, method == 1usize, g, h)
            maximum = mx
            code = cd
            cnt = it
        } else {
            let (mx, cd, it) = ml.max_optim(a, &ctx, th, method, g, h)
            maximum = mx
            code = cd
            cnt = it
        }
        var got = 0.0f64
        if what == 0usize { got = maximum }
        if what == 1usize { got = th[idx] }
        if what == 2usize {
            let _ = ml.std_err(a, h, p, se)
            got = se[idx]
        }
        if what == 3usize { got = f64(code) }
        if what == 4usize { got = f64(cnt) }
        if what == 5usize { got = g[idx] }
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
