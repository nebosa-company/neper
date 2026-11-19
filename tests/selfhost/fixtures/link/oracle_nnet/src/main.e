// e.algo.stat.nnetpkg against nnet multinom. tests/oracle/nnet.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R nnet`; the layout is at the top of scripts/r_oracle/groups/nnet.R.

use e.algo.stat.nnetpkg as nn
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "netv") || str.eq(c.name, "nets") || str.eq(c.name, "netw") {
        let nn_ = usize(z[0usize])
        let pp = usize(z[1usize])
        let hh = usize(z[2usize])
        let nw = hh * (pp + 1usize) + hh + 1usize
        let (wv, ew) = mem.alloc[f64](a, nw)
        let (fit, ef) = mem.alloc[f64](a, nn_)
        if ew != ok || ef != ok { ret nan }
        var q = 0usize
        while q < nw {
            wv[q] = z[5usize + q]
            q += 1usize
        }
        let xo = 5usize + nw
        let yo = xo + nn_ * pp
        let wo = yo + nn_
        let val = nn.nnet_fit(a, z[xo..yo], z[yo..wo], z[wo..wo + nn_], nn_, pp, hh, z[3usize], usize(z[4usize]), 1.0e-8f64, 1.0e-4f64, wv, fit)
        if str.eq(c.name, "netv") { ret val }
        var sm = 0.0f64
        q = 0usize
        if str.eq(c.name, "nets") {
            while q < nn_ {
                sm += fit[q]
                q += 1usize
            }
            ret sm
        }
        while q < nw {
            sm += wv[q] * f64(q + 1usize)
            q += 1usize
        }
        ret sm
    }
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let nk = usize(z[2usize])
    let (coef, e1) = mem.alloc[f64](a, (nk - 1usize) * p)
    if e1 != ok { ret nan }
    let dev = nn.multinom(a, z[4usize + n..4usize + n + n * p], z[4usize..4usize + n], n, p, nk, z[3usize], z[4usize + n + n * p..4usize + 2usize * n + n * p], coef)
    if str.eq(c.name, "dev") { ret dev }
    var s = 0.0f64
    var i = 0usize
    while i < coef.len {
        s += coef[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/nnet.json")
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
