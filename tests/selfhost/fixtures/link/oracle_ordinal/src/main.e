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
