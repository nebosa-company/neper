// e.algo.stat.ordinalpkg against ordinal clm. tests/oracle/ordinal.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ordinal`; the layout is at the top of scripts/r_oracle/groups/ordinal.R.

use e.algo.stat.ordinalpkg as od
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let nk = usize(z[2usize])
    let link = usize(z[3usize])
    let (par, e1) = mem.alloc[f64](a, nk - 1usize + p)
    let (wts, ew) = mem.alloc[f64](a, n)
    if e1 != ok || ew != ok { ret nan }
    var iw = 0usize
    while iw < n {
        wts[iw] = 1.0f64
        iw += 1usize
    }
    if c.name.len > 1usize && c.name[0usize] == 119u8 {
        // the weighted clm: the weights follow the design
        iw = 0usize
        while iw < n {
            wts[iw] = z[4usize + n + n * p + iw]
            iw += 1usize
        }
    }
    if c.name.len >= 4usize && c.name[0usize] == 110u8 && c.name[1usize] == 109u8 {
        let pn = usize(z[4usize])
        let (parn, en) = mem.alloc[f64](a, nk - 1usize + p + (nk - 1usize) * pn)
        if en != ok { ret nan }
        let yo = 5usize
        let xo = yo + n
        let wo = xo + n * p
        let llm = od.clm_nominal(a, z[xo..wo], z[wo..wo + n * pn], z[yo..yo + n], wts, n, p, pn, nk, link, 1.0f64, parn)
        if str.eq(c.name, "nmll") { ret llm }
        var sn = 0.0f64
        var im = 0usize
        if str.eq(c.name, "nmth") {
            while im < nk - 1usize {
                sn += parn[im] * f64(im + 1usize)
                im += 1usize
            }
            ret sn
        }
        if str.eq(c.name, "nmbeta") {
            while im < p {
                sn += parn[nk - 1usize + im] * f64(im + 1usize)
                im += 1usize
            }
            ret sn
        }
        var sq2 = 0.0f64
        im = 0usize
        while im < (nk - 1usize) * pn {
            let tv = parn[nk - 1usize + p + im]
            sq2 += tv * tv
            im += 1usize
        }
        ret sq2
    }
    if c.name.len >= 4usize && c.name[0usize] == 115u8 && c.name[1usize] == 99u8 {
        let ps = usize(z[4usize])
        let (parz, ez) = mem.alloc[f64](a, nk - 1usize + p + ps)
        if ez != ok { ret nan }
        let yo = 5usize
        let xo = yo + n
        let zo = xo + n * p
        let lls = od.clm_scale(a, z[xo..zo], z[zo..zo + n * ps], z[yo..yo + n], wts, n, p, ps, nk, link, parz)
        if str.eq(c.name, "scll") { ret lls }
        var ss = 0.0f64
        var is = 0usize
        if str.eq(c.name, "scth") {
            while is < nk - 1usize {
                ss += parz[is] * f64(is + 1usize)
                is += 1usize
            }
            ret ss
        }
        if str.eq(c.name, "scbeta") {
            while is < p {
                ss += parz[nk - 1usize + is] * f64(is + 1usize)
                is += 1usize
            }
            ret ss
        }
        while is < ps {
            ss += parz[nk - 1usize + p + is] * f64(is + 1usize)
            is += 1usize
        }
        ret ss
    }
    if c.name.len >= 3usize && c.name[0usize] == 115u8 && c.name[1usize] == 121u8 {
        let (tm, etm) = mem.alloc[f64](a, (nk - 1usize) * nk)
        if etm != ok { ret nan }
        let nas = od.thr_map(2usize, nk - 1usize, tm)
        let lls = od.clm_lin(a, z[4usize + n..4usize + n + n * p], z[4usize..4usize + n], wts, n, p, nk, link, tm, nas, par)
        if str.eq(c.name, "syll") { ret lls }
        var ss = 0.0f64
        var is = 0usize
        if str.eq(c.name, "syth") {
            while is < nk - 1usize {
                ss += par[is] * f64(is + 1usize)
                is += 1usize
            }
            ret ss
        }
        while is < p {
            ss += par[nk - 1usize + is] * f64(is + 1usize)
            is += 1usize
        }
        ret ss
    }
    if c.name.len >= 3usize && c.name[0usize] == 101u8 && c.name[1usize] == 113u8 {
        let lle = od.clm_equi(a, z[4usize + n..4usize + n + n * p], z[4usize..4usize + n], wts, n, p, nk, link, par)
        if str.eq(c.name, "eqll") { ret lle }
        if str.eq(c.name, "eqa") { ret par[0usize] }
        if str.eq(c.name, "eqb") { ret par[1usize] - par[0usize] }
        var se = 0.0f64
        var ie = 0usize
        while ie < p {
            se += par[nk - 1usize + ie] * f64(ie + 1usize)
            ie += 1usize
        }
        ret se
    }
    let ll = od.clm(a, z[4usize + n..4usize + n + n * p], z[4usize..4usize + n], wts, n, p, nk, link, par)
    if str.eq(c.name, "anst") || str.eq(c.name, "anp") {
        let ll1 = od.clm(a, z[4usize + n..4usize + n + n * p], z[4usize..4usize + n], wts, n, p, nk, link, par)
        // the reduced model drops the last covariate: its design is the first p - 1 columns of every row
        let (x0, ex0) = mem.alloc[f64](a, n * (p - 1usize))
        let (par0, ep0) = mem.alloc[f64](a, nk - 1usize + p - 1usize)
        if ex0 != ok || ep0 != ok { ret nan }
        var r0 = 0usize
        while r0 < n {
            var c0 = 0usize
            while c0 < p - 1usize {
                x0[r0 * (p - 1usize) + c0] = z[4usize + n + r0 * p + c0]
                c0 += 1usize
            }
            r0 += 1usize
        }
        let ll0 = od.clm(a, x0, z[4usize..4usize + n], wts, n, p - 1usize, nk, link, par0)
        var an: [2]f64 = zero
        od.clm_anova(ll0, ll1, 1.0f64, an[0usize..2usize])
        if str.eq(c.name, "anst") { ret an[0usize] }
        ret an[1usize]
    }
    if str.eq(c.name, "pr") {
        let mp = usize(z[4usize + n + n * p])
        let (po, ep) = mem.alloc[f64](a, mp * nk)
        if ep != ok { ret nan }
        od.clm_predict_prob(z[5usize + n + n * p..5usize + n + n * p + mp * p], mp, p, nk, link, par, po)
        var sp = 0.0f64
        var ir = 0usize
        while ir < mp {
            var jc = 0usize
            while jc < nk {
                sp += po[ir * nk + jc] * f64((ir + 1usize) * (jc + 1usize))
                jc += 1usize
            }
            ir += 1usize
        }
        ret sp
    }
    if str.eq(c.name, "ll") || str.eq(c.name, "wll") { ret ll }
    var s = 0.0f64
    var i = 0usize
    if str.eq(c.name, "theta") || str.eq(c.name, "wtheta") {
        while i < nk - 1usize {
            s += par[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    while i < p {
        s += par[nk - 1usize + i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ordinal.json")
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
