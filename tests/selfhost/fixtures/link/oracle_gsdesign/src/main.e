// e.algo.stat.gsdesign against gsDesign. tests/oracle/gsdesign.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gsdesign`; the layout of each fn's args is at the top of its section in scripts/r_oracle/groups/gsdesign.R.

use e.algo.stat.gsdesign as gs
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn same_design(p: []const f64, q: []const f64) -> bool {
    if p.len != q.len { ret false }
    var i = 1usize
    while i < p.len {
        if p[i] != q[i] { ret false }
        i += 1usize
    }
    ret true
}

fn design_spec(x: []const f64) -> gs.Spec {
    let k = usize(x[1usize])
    var n_i = x[19usize..19usize]
    if x[17usize] != 0.0f64 { n_i = x[19usize + k..19usize + 2usize * k] }
    ret gs.Spec { k: k, tt: usize(x[2usize]), alpha: x[3usize], beta: x[4usize], delta: x[5usize], n_fix: x[6usize], timing: x[19usize..19usize + k], n_i: n_i, maxn: x[16usize], upk: usize(x[7usize]), up1: x[8usize], up2: x[9usize], lok: usize(x[10usize]), lo1: x[11usize], lo2: x[12usize], tol: x[13usize], r: usize(x[14usize]), overrun: x[15usize], astar: x[18usize] }
}

fn design_value(dz: *const gs.Design, out: usize) -> f64 {
    let field = out / 100usize
    let at = out % 100usize
    let k = dz.k
    if field == 1usize { ret dz.upper[at] }
    if field == 2usize { ret dz.lower[at] }
    if field == 3usize { ret dz.n_i[at] }
    if field == 4usize { ret dz.uprob[at] }
    if field == 5usize { ret dz.uprob[k + at] }
    if field == 6usize { ret dz.lprob[at] }
    if field == 7usize { ret dz.lprob[k + at] }
    if field == 8usize { ret dz.en[0usize] }
    if field == 9usize { ret dz.en[1usize] }
    if field == 10usize { ret dz.delta }
    if field == 11usize { ret dz.n_fix }
    if field == 12usize { ret dz.uspend[at] }
    if field == 13usize { ret dz.lspend[at] }
    ret f64(k)
}

fn prob_value(p: *const gs.Prob, out: usize) -> f64 {
    let field = out / 100usize
    let at = out % 100usize
    if field == 1usize { ret p.plo[at] }
    if field == 2usize { ret p.phi[at] }
    ret p.en[at]
}

fn size_value(z: *const gs.SizeOut, out: usize, ratio: f64, nbin: bool) -> f64 {
    if out == 0usize { ret z.val }
    if out == 1usize { ret z.n / (ratio + 1.0f64) }
    if out == 2usize { ret ratio * z.n / (ratio + 1.0f64) }
    if out == 3usize { ret z.sigma0 }
    if out == 4usize { ret z.sigma1 }
    if out == 5usize { ret z.p10 }
    ret z.p20
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gsdesign.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    var have = false
    var prev = golden.cases[0usize].args
    var dz: gs.Design = zero
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let x = c.args
        let nm = c.name
        var got = 0.0f64
        if str.eq(nm, "spend") {
            got = gs.spend(usize(x[0usize]), x[1usize], x[2usize], x[3usize], x[4usize])
        } else if str.eq(nm, "design") {
            if !have || !same_design(prev, x) {
                let sp = design_spec(x)
                dz = gs.gs_design(a, &sp)
                prev = x
                have = true
            }
            got = design_value(&dz, usize(x[0usize]))
        } else if str.eq(nm, "gsprob") {
            let k = usize(x[1usize])
            let nth = usize(x[2usize])
            let o = 5usize
            let p = gs.gsprob(a, x[o..o + nth], x[o + nth..o + nth + k], x[o + nth + k..o + nth + 2usize * k], x[o + nth + 2usize * k..o + nth + 3usize * k], usize(x[3usize]), x[4usize])
            got = prob_value(&p, usize(x[0usize]))
        } else if str.eq(nm, "gscp") {
            let k = usize(x[1usize])
            let nth = usize(x[6usize])
            let o = 7usize
            let p = gs.gscp(a, x[o + nth..o + nth + k], x[o + nth + k..o + nth + 2usize * k], x[o + nth + 2usize * k..o + nth + 3usize * k], x[2usize] != 0.0f64, usize(x[4usize]), x[5usize], x[o..o + nth], usize(x[3usize]))
            got = prob_value(&p, usize(x[0usize]))
        } else if str.eq(nm, "nnormal") {
            var sd2 = x[3usize]
            if sd2 < 0.0f64 { sd2 = x[2usize] }
            let z = gs.nnormal(x[1usize], x[2usize], sd2, x[4usize], x[5usize], x[6usize], x[7usize], x[8usize], x[9usize])
            got = size_value(&z, usize(x[0usize]), x[6usize], false)
        } else if str.eq(nm, "nsurv") {
            let nr = usize(x[10usize])
            let ns = usize(x[11usize])
            let nl = ns + 1usize
            let o = 12usize
            let (outv, oe) = mem.alloc[f64](a, 11usize)
            gs.nsurv(a, x[1usize], x[2usize], x[3usize], x[4usize], x[5usize], x[6usize], x[7usize], x[8usize], usize(x[9usize]), x[o..o + nr], x[o + nr..o + 2usize * nr], x[o + 2usize * nr..o + 2usize * nr + ns], x[o + 2usize * nr + ns..o + 2usize * nr + ns + nl], x[o + 2usize * nr + ns + nl..o + 2usize * nr + ns + 2usize * nl], x[o + 2usize * nr + ns + 2usize * nl..o + 2usize * nr + ns + 3usize * nl], outv)
            got = outv[usize(x[0usize])]
        } else if str.eq(nm, "nbinom") {
            let z = gs.nbinomial(x[1usize], x[2usize], x[3usize], x[4usize], x[5usize], x[6usize], x[7usize], usize(x[8usize]), x[9usize])
            got = size_value(&z, usize(x[0usize]), x[6usize], true)
        }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(nm)
                let _ = io.print(" ")
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
