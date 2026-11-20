// e.algo.stat.gamlssfit (RS, CG and mixed on design-matrix models) against gamlss. tests/oracle/gamlss_fit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gamlss_fit`; the header and data layout are at the top of scripts/r_oracle/groups/gamlss_fit.R.

use e.algo.stat.gamlssfit as gf
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gamlss_fit.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    var fam = 0usize
    var n = 0usize
    let (ncol, e1) = mem.alloc[usize](a, 3usize)
    let (link, e2) = mem.alloc[usize](a, 3usize)
    let (hs, e3) = mem.alloc[usize](a, 3usize)
    let (step, e4) = mem.alloc[f64](a, 3usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { os.exit(4) }
    let scen = mem.mark(a)
    var out: gf.Out = zero
    var ys: []const f64 = zero
    var ws: []const f64 = zero
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let x = c.args
        if usize(x[0usize]) != 99usize {
            mem.reset(a, scen)
            fam = usize(x[0usize])
            n = usize(x[2usize])
            var k = 0usize
            while k < 3usize {
                ncol[k] = usize(x[3usize + k])
                link[k] = usize(x[6usize + k])
                step[k] = x[17usize + k]
                hs[k] = 0usize
                k += 1usize
            }
            let y = x[20usize..20usize + n]
            let w = x[20usize + n..20usize + 2usize * n]
            let xs = x[20usize + 2usize * n..x.len]
            let (off, e5) = mem.alloc[f64](a, 4usize * n)
            let (st, e6) = mem.alloc[f64](a, 4usize * n)
            if e5 != ok || e6 != ok { os.exit(5) }
            var i = 0usize
            while i < 4usize * n {
                off[i] = 0.0f64
                st[i] = 0.0f64
                i += 1usize
            }
            let (o, fe) = gf.fit_model(a, fam, usize(x[1usize]), y, w, xs, ncol, link, off, st, hs, step, x[11usize], usize(x[12usize]), 0.001f64, 50usize, x[15usize] == 1.0f64, usize(x[13usize]), usize(x[14usize]))
            if fe != ok { os.exit(6) }
            out = o
            ys = y
            ws = w
        }
        let kind = usize(x[9usize])
        let idx = usize(x[10usize])
        var got = 0.0f64
        if kind == 0usize { got = out.coef[idx] }
        if kind == 1usize { got = out.gdev }
        if kind == 2usize { got = f64(out.iter) }
        if kind == 3usize && out.conv { got = 1.0f64 }
        if kind == 4usize { got = out.par[idx] }
        if kind == 5usize { got = out.df }
        if kind == 6usize { got = out.gdev + 2.0f64 * out.df }
        if kind == 7usize {
            var nobs = f64(n)
            var all_int = true
            var sw = 0.0f64
            var j = 0usize
            while j < n {
                if ws[j] != f64(i64(ws[j])) { all_int = false }
                sw += ws[j]
                j += 1usize
            }
            if all_int { nobs = sw }
            got = out.gdev + math.log[f64](nobs) * out.df
        }
        if kind == 8usize { got = out.wv[idx] }
        if kind == 9usize { got = out.wt[idx] }
        if kind == 10usize { got = out.eta[idx] }
        if kind == 11usize { got = gf.rqres(fam, ys[idx], out.par[idx], out.par[n + idx], out.par[2usize * n + idx]) }
        if kind == 12usize { got = gf.centile(fam, x[16usize], out.par[idx], out.par[n + idx], out.par[2usize * n + idx]) }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 8usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
