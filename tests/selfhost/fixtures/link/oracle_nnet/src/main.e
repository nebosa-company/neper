// e.algo.stat.nnetpkg against nnet multinom. tests/oracle/nnet.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R nnet`; the layout is at the top of scripts/r_oracle/groups/nnet.R.

use e.algo.rand.r as rr
use e.algo.stat.nnetpkg as nn
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "ci") {
        let nc = usize(z[0usize])
        let kc = usize(z[1usize])
        let (cl, ec) = mem.alloc[usize](a, nc)
        let (mt, em) = mem.alloc[f64](a, nc * kc)
        if ec != ok || em != ok { ret nan }
        var qi = 0usize
        while qi < nc {
            cl[qi] = usize(z[2usize + qi])
            qi += 1usize
        }
        nn.class_ind(cl, kc, mt)
        var s2 = 0.0f64
        qi = 0usize
        while qi < nc * kc {
            s2 += mt[qi] * f64(qi + 1usize)
            qi += 1usize
        }
        ret s2
    }
    if str.eq(c.name, "pd") {
        let nn_ = usize(z[0usize])
        let pp = usize(z[1usize])
        let hh = usize(z[2usize])
        let kk = usize(z[3usize])
        let md = usize(z[4usize])
        let skp = z[7usize] > 0.5f64
        var nw = hh * (pp + 1usize) + kk * (1usize + hh)
        if skp { nw += kk * pp }
        let (wv, ew) = mem.alloc[f64](a, nw)
        let (fit, ef) = mem.alloc[f64](a, nn_ * kk)
        if ew != ok || ef != ok { ret nan }
        var g: rr.Rng = zero
        rr.seed(&g, i64(z[8usize]))
        var q = 0usize
        while q < nw {
            wv[q] = rr.runif(&g, 0.0f64 - z[9usize], z[9usize])
            q += 1usize
        }
        let xo = 10usize
        let yo = xo + nn_ * pp
        let wo = yo + nn_ * kk
        let mo = wo + nn_
        let mm = usize(z[mo])
        let _ = nn.nnet_fit(a, z[xo..yo], z[yo..wo], z[wo..wo + nn_], nn_, pp, hh, kk, md, skp, z[5usize], usize(z[6usize]), 1.0e-8f64, 1.0e-4f64, wv, fit)
        let (pr, ep) = mem.alloc[f64](a, mm * kk)
        if ep != ok { ret nan }
        nn.nnet_predict(z[mo + 1usize..mo + 1usize + mm * pp], mm, pp, hh, kk, md, skp, wv, pr)
        var s3 = 0.0f64
        q = 0usize
        while q < mm * kk {
            s3 += pr[q] * f64(q + 1usize)
            q += 1usize
        }
        ret s3
    }
    if str.eq(c.name, "sdv") || str.eq(c.name, "sds") || str.eq(c.name, "sdw") {
        let nn_ = usize(z[0usize])
        let pp = usize(z[1usize])
        let hh = usize(z[2usize])
        let kk = usize(z[3usize])
        let md = usize(z[4usize])
        let skp = z[7usize] > 0.5f64
        var nw = hh * (pp + 1usize) + kk * (1usize + hh)
        if skp { nw += kk * pp }
        let (wv, ew) = mem.alloc[f64](a, nw)
        let (fit, ef) = mem.alloc[f64](a, nn_ * kk)
        if ew != ok || ef != ok { ret nan }
        var g: rr.Rng = zero
        rr.seed(&g, i64(z[8usize]))
        var q = 0usize
        while q < nw {
            wv[q] = rr.runif(&g, 0.0f64 - z[9usize], z[9usize])
            q += 1usize
        }
        let xo = 10usize
        let yo = xo + nn_ * pp
        let wo = yo + nn_ * kk
        let val = nn.nnet_fit(a, z[xo..yo], z[yo..wo], z[wo..wo + nn_], nn_, pp, hh, kk, md, skp, z[5usize], usize(z[6usize]), 1.0e-8f64, 1.0e-4f64, wv, fit)
        if str.eq(c.name, "sdv") { ret val }
        var sm = 0.0f64
        q = 0usize
        if str.eq(c.name, "sds") {
            while q < nn_ * kk {
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
    if str.eq(c.name, "netv") || str.eq(c.name, "nets") || str.eq(c.name, "netw") {
        let nn_ = usize(z[0usize])
        let pp = usize(z[1usize])
        let hh = usize(z[2usize])
        let kk = usize(z[3usize])
        let md = usize(z[4usize])
        let skp = z[7usize] > 0.5f64
        var nw = hh * (pp + 1usize) + kk * (1usize + hh)
        if skp { nw += kk * pp }
        let (wv, ew) = mem.alloc[f64](a, nw)
        let (fit, ef) = mem.alloc[f64](a, nn_ * kk)
        if ew != ok || ef != ok { ret nan }
        var q = 0usize
        while q < nw {
            wv[q] = z[8usize + q]
            q += 1usize
        }
        let xo = 8usize + nw
        let yo = xo + nn_ * pp
        let wo = yo + nn_ * kk
        let val = nn.nnet_fit(a, z[xo..yo], z[yo..wo], z[wo..wo + nn_], nn_, pp, hh, kk, md, skp, z[5usize], usize(z[6usize]), 1.0e-8f64, 1.0e-4f64, wv, fit)
        if str.eq(c.name, "netv") { ret val }
        var sm = 0.0f64
        q = 0usize
        if str.eq(c.name, "nets") {
            while q < nn_ * kk {
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
    let (sev, e2) = mem.alloc[f64](a, (nk - 1usize) * p)
    if e1 != ok || e2 != ok { ret nan }
    let dev = nn.multinom(a, z[4usize + n..4usize + n + n * p], z[4usize..4usize + n], n, p, nk, z[3usize], z[4usize + n + n * p..4usize + 2usize * n + n * p], coef, sev)
    if str.eq(c.name, "dev") { ret dev }
    if str.eq(c.name, "se") {
        var ss = 0.0f64
        var qi = 0usize
        while qi < sev.len {
            ss += sev[qi] * f64(qi + 1usize)
            qi += 1usize
        }
        ret ss
    }
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
