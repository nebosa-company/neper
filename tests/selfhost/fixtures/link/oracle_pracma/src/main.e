// e.algo.stat.pracma against pracma. tests/oracle/pracma.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pracma`; the layout is at the top of scripts/r_oracle/groups/pracma.R.

use e.algo.stat.pracma as pm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "trapz") {
        let n = usize(x[0usize])
        ret pm.trapz(x[1usize..1usize + n], x[1usize + n..1usize + 2usize * n])
    }
    if str.eq(k, "cumtrapz") {
        let n = usize(x[0usize])
        let (o, e) = pm.cumtrapz(a, x[1usize..1usize + n], x[1usize + n..1usize + 2usize * n])
        if e != ok { os.exit(5) }
        var t = 0.0f64
        var i = 0usize
        while i < n {
            t += o[i] * f64(i + 1usize)
            i += 1usize
        }
        ret t
    }
    if str.eq(k, "polyfit") {
        let deg = usize(x[0usize])
        let idx = usize(x[1usize])
        let n = usize(x[2usize])
        let (p, e) = pm.polyfit(a, x[3usize..3usize + n], x[3usize + n..3usize + 2usize * n], deg)
        if e != ok { os.exit(5) }
        ret p[idx]
    }
    if str.eq(k, "polyval") { ret pm.polyval(x[1usize..x.len], x[0usize]) }
    if str.eq(k, "fp_count") || str.eq(k, "fp_sum") {
        let n = usize(x[7usize])
        let (rows, cnt, e) = pm.findpeaks(a, x[8usize..8usize + n], usize(x[0usize]), usize(x[1usize]), x[2usize], usize(x[3usize]), x[4usize], usize(x[5usize]), x[6usize] > 0.5f64)
        if e != ok { os.exit(5) }
        if str.eq(k, "fp_count") { ret f64(cnt) }
        var t = 0.0f64
        var i = 0usize
        while i < cnt * 4usize {
            t += rows[i] * f64(i + 1usize)
            i += 1usize
        }
        ret t
    }
    if str.eq(k, "rref") {
        let nr = usize(x[0usize])
        let nc = usize(x[1usize])
        let (m, e) = mem.alloc[f64](a, nr * nc)
        if e != ok { os.exit(5) }
        var i = 0usize
        while i < nr * nc {
            m[i] = x[2usize + i]
            i += 1usize
        }
        pm.rref(m, nr, nc)
        var t = 0.0f64
        i = 0usize
        while i < nr * nc {
            t += m[i] * f64(i + 1usize)
            i += 1usize
        }
        ret t
    }
    if str.eq(k, "primes") { ret f64(pm.primes_count(u64(x[0usize]))) }
    if str.eq(k, "fsum") || str.eq(k, "fcnt") {
        let (s, n) = pm.factors(u64(x[0usize]))
        if str.eq(k, "fsum") { ret f64(s) }
        ret f64(n)
    }
    if str.eq(k, "gcd") {
        let (g, cc, d) = pm.gcd_ext(i64(x[0usize]), i64(x[1usize]))
        let w = usize(x[2usize])
        if w == 0usize { ret f64(g) }
        if w == 1usize { ret f64(cc) }
        ret f64(d)
    }
    if str.eq(k, "roots") {
        let m = usize(x[0usize])
        let (rr, e1) = mem.alloc[f64](a, m)
        if e1 != ok { os.exit(5) }
        let (ri, e2) = mem.alloc[f64](a, m)
        if e2 != ok { os.exit(6) }
        pm.poly_roots(x[1usize..1usize + m], rr, ri)
        // the real parts, sorted ascending, weighted by position
        var q = 0usize
        while q + 1usize < m {
            var w = q + 1usize
            while w + 1usize < m {
                if rr[w] < rr[q] {
                    let t = rr[q]
                    rr[q] = rr[w]
                    rr[w] = t
                }
                w += 1usize
            }
            q += 1usize
        }
        var tt = 0.0f64
        q = 0usize
        while q + 1usize < m {
            tt += rr[q] * f64(q + 1usize)
            q += 1usize
        }
        ret tt
    }
    if str.eq(k, "conv") || str.eq(k, "deconvq") || str.eq(k, "deconvr") || str.eq(k, "polyint") {
        let na = usize(x[0usize])
        let nb = usize(x[1usize])
        let pa = x[2usize..2usize + na]
        let pb = x[2usize + na..2usize + na + nb]
        var tt = 0.0f64
        var q = 0usize
        if str.eq(k, "conv") {
            let (o, e1) = mem.alloc[f64](a, na + nb - 1usize)
            if e1 != ok { os.exit(5) }
            pm.conv(pa, pb, o)
            while q < o.len {
                tt += o[q] * f64(q + 1usize)
                q += 1usize
            }
            ret tt
        }
        if str.eq(k, "polyint") {
            let (o, e2) = mem.alloc[f64](a, na + 1usize)
            if e2 != ok { os.exit(6) }
            pm.polyint(pa, 1.5f64, o)
            while q < o.len {
                tt += o[q] * f64(q + 1usize)
                q += 1usize
            }
            ret tt
        }
        let (qq, e3) = mem.alloc[f64](a, na - nb + 1usize)
        if e3 != ok { os.exit(7) }
        let (rr, e4) = mem.alloc[f64](a, na)
        if e4 != ok { os.exit(8) }
        pm.deconv(pa, pb, qq, rr)
        if str.eq(k, "deconvq") {
            while q < qq.len {
                tt += qq[q] * f64(q + 1usize)
                q += 1usize
            }
        } else {
            q = na - nb + 1usize
            while q < rr.len {
                tt += rr[q] * f64(q - (na - nb) )
                q += 1usize
            }
        }
        ret tt
    }
    if str.eq(k, "nr_root") || str.eq(k, "nr_iter") || str.eq(k, "nr_prec") {
        let (rt, fr, ni, pr) = pm.newton_raphson(usize(x[0usize]), x[1usize], 500usize, 1.0e-8f64)
        if str.eq(k, "nr_root") { ret rt }
        if str.eq(k, "nr_iter") { ret f64(ni) }
        ret pr
    }
    if str.eq(k, "romb_v") || str.eq(k, "romb_it") {
        let (v, it, er) = pm.romberg(usize(x[0usize]), x[1usize], x[2usize], 12usize, 1.0e-12f64)
        if str.eq(k, "romb_v") { ret v }
        ret f64(it)
    }
    if str.eq(k, "legendre") {
        let (o, e) = mem.alloc[f64](a, usize(x[0usize]) + 1usize)
        if e != ok { os.exit(5) }
        if pm.legendre(a, usize(x[0usize]), x[1usize], o) != ok { os.exit(6) }
        var t = 0.0f64
        var i = 0usize
        while i < o.len {
            t += o[i] * f64(i + 1usize)
            i += 1usize
        }
        ret t
    }
    if str.eq(k, "chebval") || str.eq(k, "cheb") {
        let nn = usize(x[0usize])
        let (o, e) = mem.alloc[f64](a, nn + 1usize)
        if e != ok { os.exit(5) }
        if pm.cheb_poly(a, nn, o) != ok { os.exit(7) }
        if str.eq(k, "cheb") { ret o[usize(x[1usize])] }
        ret pm.polyval(o, x[1usize])
    }
    if str.eq(k, "laguerre") {
        let m = usize(x[0usize])
        ret pm.laguerre(a, x[2usize..2usize + m], x[1usize], 25usize)
    }
    if str.eq(k, "pchip") {
        let n = usize(x[0usize])
        ret pm.pchip(a, x[1usize..1usize + n], x[1usize + n..1usize + 2usize * n], x[1usize + 2usize * n])
    }
    if str.eq(k, "savgol") {
        let sn = usize(x[4usize])
        let (so, se) = mem.alloc[f64](a, sn)
        if se != ok { os.exit(7) }
        if pm.savgol(a, x[5usize..5usize + sn], usize(x[0usize]), usize(x[1usize]), usize(x[2usize]), so) != ok { os.exit(8) }
        ret so[usize(x[3usize])]
    }
    if str.eq(k, "kron") {
        let ra = usize(x[0usize])
        let ca = usize(x[1usize])
        let rb = usize(x[2usize])
        let cb = usize(x[3usize])
        let (ko, ke) = mem.alloc[f64](a, ra * rb * ca * cb)
        if ke != ok { os.exit(9) }
        pm.kron(x[6usize..6usize + ra * ca], ra, ca, x[6usize + ra * ca..6usize + ra * ca + rb * cb], rb, cb, ko)
        ret ko[usize(x[4usize]) * ca * cb + usize(x[5usize])]
    }
    if str.eq(k, "pinv") {
        let pm_r = usize(x[0usize])
        let pm_c = usize(x[1usize])
        let (po, pe) = mem.alloc[f64](a, pm_r * pm_c)
        if pe != ok { os.exit(10) }
        if !pm.pinv_full(a, x[4usize..4usize + pm_r * pm_c], pm_r, pm_c, po) { os.exit(11) }
        ret po[usize(x[2usize]) * pm_r + usize(x[3usize])]
    }
    if str.eq(k, "sval") || str.eq(k, "cond") {
        let sm = usize(x[0usize])
        let sn = usize(x[1usize])
        var kk = sn
        if sm < sn { kk = sm }
        let (sv, se) = mem.alloc[f64](a, kk)
        if se != ok { os.exit(12) }
        let (sw, sw2) = mem.alloc[f64](a, sm * sn + sn)
        if sw2 != ok { os.exit(13) }
        pm.singular_values(x[3usize..3usize + sm * sn], sm, sn, sv, sw)
        if str.eq(k, "cond") { ret sv[0usize] / sv[kk - 1usize] }
        ret sv[usize(x[2usize])]
    }
    if str.eq(k, "expm") {
        let nx = usize(x[0usize])
        let (eo, ee) = mem.alloc[f64](a, nx * nx)
        if ee != ok { os.exit(5) }
        if pm.expm(a, x[3usize..3usize + nx * nx], nx, 128usize, eo) != ok { os.exit(5) }
        ret eo[usize(x[1usize]) * nx + usize(x[2usize])]
    }
    if str.eq(k, "nullproj") || str.eq(k, "orthproj") {
        ret pm.svd_projector(a, x[4usize..4usize + usize(x[0usize]) * usize(x[1usize])], usize(x[0usize]), usize(x[1usize]), str.eq(k, "orthproj"), usize(x[2usize]), usize(x[3usize]))
    }
    if str.eq(k, "pr_cnt") || str.eq(k, "pr_mult") || str.eq(k, "pr_re") || str.eq(k, "pr_im2") {
        let m = usize(x[0usize])
        let (rr, er) = mem.alloc[f64](a, m + 1usize)
        let (ri, ei) = mem.alloc[f64](a, m + 1usize)
        let (rm, em) = mem.alloc[f64](a, m + 1usize)
        if er != ok || ei != ok || em != ok { os.exit(5) }
        let nr = pm.polyroots(a, x[1usize..1usize + m], rr, ri, rm)
        var sr = 0.0f64
        var i = 0usize
        while i < nr {
            if str.eq(k, "pr_cnt") { sr += 1.0f64 }
            if str.eq(k, "pr_mult") { sr += rm[i] }
            if str.eq(k, "pr_re") { sr += rm[i] * rr[i] }
            if str.eq(k, "pr_im2") { sr += rm[i] * ri[i] * ri[i] }
            i += 1usize
        }
        ret sr
    }
    if str.eq(k, "integral") { ret pm.integral(usize(x[0usize]), x[1usize], x[2usize]) }
    if str.eq(k, "quadgk") { ret pm.quadgk(usize(x[0usize]), x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "interp1") {
        let ni = usize(x[1usize])
        ret pm.interp1(a, x[2usize..2usize + ni], x[2usize + ni..2usize + 2usize * ni], x[2usize + 2usize * ni], usize(x[0usize]))
    }
    if str.eq(k, "quadl") { ret pm.quadl(usize(x[0usize]), x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "fzero") { ret pm.fzero(usize(x[0usize]), x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "nchoosek") { ret pm.nchoosek(x[0usize], x[1usize]) }
    var o: [3]f64 = zero
    pm.cross(x[0usize..3usize], x[3usize..6usize], o[0usize..3usize])
    ret o[usize(x[6usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pracma.json")
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
