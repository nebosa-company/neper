// e.algo.stat.arimax against TSA::arimax. tests/oracle/tsa_arimax.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tsa_arimax`; the layout of every case is at the top of scripts/r_oracle/groups/tsa_arimax.R.
// Several cases share one fit (the same arguments up to the last two numbers), so the fit is kept between them.

use e.algo.stat.arimax as ax
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn same(a: []const f64, b: []const f64) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i + 2usize < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn fit_of(a: *mem.Arena, z: []const f64) -> ax.ArxFit {
    let n = usize(z[0usize])
    let ncu = usize(z[8usize])
    let nt = usize(z[10usize])
    let (tp, e1) = mem.alloc[f64](a, nt + 1usize)
    let (tq, e2) = mem.alloc[f64](a, nt + 1usize)
    if e1 != ok || e2 != ok { os.exit(10) }
    var k = 0usize
    while k < nt {
        tp[k] = z[12usize + 2usize * k]
        tq[k] = z[13usize + 2usize * k]
        k += 1usize
    }
    let io0 = 12usize + 2usize * nt
    let y0 = io0 + ncu
    let x0 = y0 + n
    let t0 = x0 + n * ncu
    let f = ax.arimax_fit(a, z[y0..y0 + n], usize(z[1usize]), usize(z[2usize]), usize(z[3usize]), usize(z[4usize]), usize(z[5usize]), usize(z[6usize]), usize(z[7usize]),
        z[x0..x0 + n * ncu], z[io0..io0 + ncu], ncu, z[9usize] != 0.0f64, z[t0..t0 + n * nt], tp, tq, nt, usize(z[11usize]))
    ret f
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tsa_arimax.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let base = mem.mark(a)
    var failures = 0usize
    var at = 0usize
    var have = false
    var prev: []const f64 = golden.cases[0usize].args
    var fit: ax.ArxFit = zero
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let z = c.args
        if !have || !same(prev, z) {
            mem.reset(a, base)
            fit = fit_of(a, z)
            prev = z
            have = true
        }
        var got = 0.0f64 / 0.0f64
        if fit.good {
            let which = usize(z[z.len - 2usize])
            let ix = usize(z[z.len - 1usize])
            let m = fit.coef.len
            if which == 0usize { got = fit.coef[ix] }
            if which == 1usize { got = fit.sigma2 }
            if which == 2usize { got = fit.loglik }
            if which == 3usize { got = fit.aic }
            if which == 4usize { got = math.sqrt[f64](fit.vcov[ix * m + ix]) }
            if which == 5usize { got = fit.resid[ix] }
        }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 200usize {
                let (ib, be) = str.builder(a, 160usize)
                if be == ok {
                    var b = ib
                    let _ = str.push(&b, "case ")
                    let _ = str.push_f64(&b, f64(at))
                    let _ = str.push(&b, " n ")
                    let _ = str.push_f64(&b, z[0usize])
                    let _ = str.push(&b, " which ")
                    let _ = str.push_f64(&b, z[z.len - 2usize])
                    let _ = str.push(&b, " idx ")
                    let _ = str.push_f64(&b, z[z.len - 1usize])
                    let _ = str.push(&b, ": got ")
                    let _ = str.push_f64(&b, got)
                    let _ = str.push(&b, ", R says ")
                    let _ = str.push_f64(&b, c.want)
                    let _ = io.print(str.done(&b))
                    let _ = io.print("\n")
                }
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
