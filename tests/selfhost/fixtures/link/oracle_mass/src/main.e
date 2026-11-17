// e.algo.stat.mass against MASS: mad, huber, hubers, fitdistr (closed-form families), boxcox log-likelihood and
// bandwidth.nrd. tests/oracle/mass.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass`;
// the layout is at the top of scripts/r_oracle/groups/mass.R.

use e.algo.stat.mass as ms
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.starts_with(c.name, "ginv") {
        let m = usize(x[0usize])
        let nc = usize(x[1usize])
        let (g, ge) = ms.ginv(a, x[2usize..2usize + m * nc], m, nc)
        if ge != ok { ret 0.0f64 / 0.0f64 }
        if str.eq(c.name, "ginv_len") { ret f64(g.len) }
        var s = 0.0f64
        var i = 0usize
        while i < g.len {
            if str.eq(c.name, "ginv_sum") { s += g[i] } else { s += f64(i + 1usize) * g[i] }
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "kde2d") {
        let kn = usize(x[0usize])
        let n1 = usize(x[1usize])
        let n2 = usize(x[2usize])
        let (zz, ze) = mem.alloc[f64](a, n1 * n2)
        if ze != ok { ret 0.0f64 / 0.0f64 }
        if ms.kde2d(a, x[10usize..10usize + kn], x[10usize + kn..10usize + 2usize * kn], x[3usize], x[4usize], n1, n2, x[5usize..9usize], zz) != ok { ret 0.0f64 / 0.0f64 }
        ret zz[usize(x[9usize])]
    }
    if str.eq(c.name, "rlm") {
        let rn = usize(x[0usize])
        let rp = usize(x[1usize])
        let (rc, re1) = mem.alloc[f64](a, rp)
        let (ro, re2) = mem.alloc[f64](a, 3usize)
        if re1 != ok || re2 != ok { ret 0.0f64 / 0.0f64 }
        let psi = usize(x[2usize] / 100.0f64)
        var kk = 1.345f64
        if psi == 1usize { kk = 4.685f64 }
        if ms.rlm_psi(a, x[3usize + rn..3usize + rn + rn * rp], rn, rp, x[3usize..3usize + rn], psi, kk, rc, ro) != ok { ret 0.0f64 / 0.0f64 }
        let w = usize(x[2usize]) % 100usize
        if w < rp { ret rc[w] }
        ret ro[w - rp]
    }
    let n = usize(x[0usize])
    let y = x[1usize..1usize + n]
    if str.eq(c.name, "mad") { ret ms.mad(a, y) }
    if str.eq(c.name, "bw") { ret ms.bandwidth_nrd(a, y) }
    if str.eq(c.name, "huber_mu") || str.eq(c.name, "huber_s") {
        let (mu, s) = ms.huber(a, y, x[1usize + n], 1.0e-6f64)
        if str.eq(c.name, "huber_mu") { ret mu }
        ret s
    }
    if str.eq(c.name, "hubers_mu") || str.eq(c.name, "hubers_s") {
        let (mu, s) = ms.hubers(a, y, x[1usize + n], 1.0e-6f64)
        if str.eq(c.name, "hubers_mu") { ret mu }
        ret s
    }
    if str.eq(c.name, "fd") {
        let (e1, e2, s1, s2, ll, fe) = ms.fitdistr(a, y, u8(x[1usize + n]))
        if fe != ok { ret 0.0f64 / 0.0f64 }
        let q = u8(x[2usize + n])
        if q == 0u8 { ret e1 }
        if q == 1u8 { ret e2 }
        if q == 2u8 { ret s1 }
        if q == 3u8 { ret s2 }
        ret ll
    }
    let cv = x[1usize + n..1usize + 2usize * n]
    let (d, de) = mem.alloc[f64](a, 2usize * n)
    if de != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        d[i] = 1.0f64
        d[n + i] = cv[i]
        i += 1usize
    }
    let (ll, le) = ms.boxcox_loglik(a, y, d, 2usize, x[1usize + 2usize * n])
    if le != ok { ret 0.0f64 / 0.0f64 }
    ret ll
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass.json")
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
