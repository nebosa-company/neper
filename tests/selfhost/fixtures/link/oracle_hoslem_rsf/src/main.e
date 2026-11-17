// e.algo.stat.hoslem_rsf against ResourceSelection (rsf, rspf, rsf.null, simulateUsedAvail, mep, the kdepairs panels). tests/oracle/hoslem_rsf.json
// comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R hoslem_rsf`; the layout is at the top of scripts/r_oracle/groups/hoslem_rsf.R.

use e.algo.rand.r as rng
use e.algo.stat.hoslem_rsf as rs
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn wsum(v: []const f64, weighted: bool) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        if weighted { s += v[i] * f64(i + 1usize) } else { s += v[i] }
        i += 1usize
    }
    ret s
}

fn answer_r(a: *mem.Arena, z: []const f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let kind = usize(z[0usize])
    let n = usize(z[1usize])
    let pc = usize(z[2usize])
    let mm = z[3usize]
    let nboot = usize(z[4usize])
    let seed = i64(z[5usize])
    let useinits = z[6usize] != 0.0f64
    let q = usize(z[7usize])
    let y = z[8usize..8usize + n]
    let x = z[8usize + n..8usize + n + n * pc]
    let inits = z[8usize + n + n * pc..8usize + n + n * pc + pc]
    let mrest = z[8usize + n + n * pc + pc..]
    var mvec = mrest
    if mrest.len == 1usize { mvec = mrest[0usize..1usize] }
    var link = 3usize
    if kind == 1usize { link = 0usize }
    if kind == 2usize { link = 1usize }
    if kind == 3usize { link = 2usize }
    var off = 0usize
    if kind == 0usize { off = 1usize }
    let pe = pc - off
    let (coef, e1) = mem.alloc[f64](a, pc)
    let (se, e2) = mem.alloc[f64](a, pc)
    let (ll, e3) = mem.alloc[f64](a, 1usize)
    let (boot, e4) = mem.alloc[f64](a, pc * (nboot + 1usize))
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    var iv = inits
    if !useinits { iv = inits[0usize..0usize] }
    let (conv, e) = rs.rsf_fit(a, &rg, x, y, n, pc, mvec, link, nboot, iv, 20000usize, coef, se, ll, boot)
    if e != ok { ret nan }
    if q == 0usize { ret ll[0usize] }
    if q == 1usize {
        if conv { ret 1.0f64 }
        ret 0.0f64
    }
    if q < 2usize + pe { ret coef[off + q - 2usize] }
    if q < 2usize + 2usize * pe { ret se[off + q - 2usize - pe] }
    if q < 2usize + 3usize * pe {
        let j = off + q - 2usize - 2usize * pe
        var s = 0.0f64
        var b = 0usize
        while b <= nboot {
            s += f64(b + 1usize) * boot[b * pc + j]
            b += 1usize
        }
        ret s
    }
    // fitted values: exp(X %*% c(0, coef)) for rsf, linkinv(X %*% coef) for rspf
    var s1 = 0.0f64
    var s2 = 0.0f64
    var i = 0usize
    while i < n {
        var eta = 0.0f64
        var j = off
        while j < pc {
            eta += x[j * n + i] * coef[j]
            j += 1usize
        }
        let f = rs.linkinv(link, eta)
        s1 += f
        s2 += f * f64(i + 1usize)
        i += 1usize
    }
    if q == 2usize + 3usize * pe { ret s1 }
    ret s2
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let nm0 = c.name[0usize]
    if nm0 == 114u8 { ret answer_r(a, z) }
    if nm0 == 122u8 {
        let n = usize(z[0usize])
        let y = z[2usize..2usize + n]
        var nu = 0usize
        var i = 0usize
        while i < n {
            if y[i] == 1.0f64 { nu += 1usize }
            i += 1usize
        }
        let (x, e1) = mem.alloc[f64](a, n)
        let (coef, e2) = mem.alloc[f64](a, 1usize)
        let (se, e3) = mem.alloc[f64](a, 1usize)
        let (ll, e4) = mem.alloc[f64](a, 1usize)
        let (boot, e5) = mem.alloc[f64](a, 1usize)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret nan }
        i = 0usize
        while i < n {
            x[i] = 1.0f64
            i += 1usize
        }
        var rg: rng.Rng = zero
        rng.seed(&rg, 1i64)
        var init: [1]f64 = zero
        init[0usize] = math.log[f64](f64(nu) / f64(n - nu))
        let (conv, e) = rs.rsf_fit(a, &rg, x, y, n, 1usize, z[1usize..2usize], 3usize, 0usize, init[0usize..1usize], 20000usize, coef, se, ll, boot)
        if e != ok { ret nan }
        ret ll[0usize]
    }
    if nm0 == 115u8 {
        let seed = i64(z[0usize])
        let sn = usize(z[1usize])
        let pc = usize(z[2usize])
        let nu = usize(z[3usize])
        let m = usize(z[4usize])
        let link = usize(z[5usize])
        let parms = z[6usize..6usize + pc + 1usize]
        let d1 = z[6usize + pc + 1usize..6usize + pc + 1usize + sn]
        var mode = 0usize
        if z.len > 6usize + pc + 1usize + sn * pc { mode = usize(z[6usize + pc + 1usize + sn * pc]) }
        let weighted = mode == 1usize
        let (x, e1) = mem.alloc[f64](a, sn * (pc + 1usize))
        let (id1, e2) = mem.alloc[usize](a, nu)
        let (id2, e3) = mem.alloc[usize](a, nu * m)
        if e1 != ok || e2 != ok || e3 != ok { ret nan }
        var i = 0usize
        while i < sn {
            x[i] = 1.0f64
            var j = 0usize
            while j < pc {
                x[(j + 1usize) * sn + i] = z[6usize + pc + 1usize + j * sn + i]
                j += 1usize
            }
            i += 1usize
        }
        var rg: rng.Rng = zero
        rng.seed(&rg, seed)
        if rs.simulate_used_avail(a, &rg, x, sn, pc + 1usize, parms, nu, m, link, id1, id2) != ok { ret nan }
        var s = 0.0f64
        i = 0usize
        while i < nu {
            var w = 1.0f64
            if weighted { w = f64(i + 1usize) }
            s += w * f64(id1[i])
            i += 1usize
        }
        if mode == 2usize { ret s }
        if mode == 3usize { s = 0.0f64 }
        i = 0usize
        while i < nu * m {
            var w = 1.0f64
            if weighted { w = f64(nu + i + 1usize) }
            s += w * f64(id2[i])
            i += 1usize
        }
        ret s
    }
    if nm0 == 109u8 {
        let ty = usize(z[0usize])
        let lk = i64(z[1usize])
        let n = usize(z[2usize])
        let nbin = usize(z[3usize])
        let mb = usize(z[4usize])
        let dg = usize(z[5usize])
        let lv = z[6usize]
        let q = usize(z[7usize])
        let (xv, e1) = mem.alloc[f64](a, n)
        let (yq, e2) = mem.alloc[f64](a, 3usize * n)
        if e1 != ok || e2 != ok { ret nan }
        let (nl, link, tyf, e) = rs.mep(a, z[8usize..8usize + n], z[8usize + n..8usize + 2usize * n], lv, lk, ty, nbin, mb, dg, xv, yq)
        if e != ok { ret nan }
        if q == 0usize { ret f64(nl) }
        if q == 1usize { ret f64(link) }
        if q == 2usize { ret wsum(xv[0usize..nl], false) }
        if q == 3usize { ret wsum(xv[0usize..nl], true) }
        let (col, e3) = mem.alloc[f64](a, nl)
        if e3 != ok { ret nan }
        var cc = 0usize
        if q >= 7usize { cc = q - 7usize } else { cc = q - 4usize }
        var i = 0usize
        while i < nl {
            col[i] = yq[3usize * i + cc]
            i += 1usize
        }
        ret wsum(col, q >= 7usize)
    }
    if nm0 == 107u8 {
        let n = usize(z[0usize])
        let m = usize(z[1usize])
        let q = usize(z[2usize])
        let x1 = z[3usize..3usize + m]
        let x2 = z[3usize + m..3usize + 2usize * m]
        let (zz, e1) = mem.alloc[f64](a, n * n)
        let (lx, e2) = mem.alloc[f64](a, m)
        let (ly, e3) = mem.alloc[f64](a, m)
        if e1 != ok || e2 != ok || e3 != ok { ret nan }
        let (cr, e) = rs.kdepair(a, x1, x2, n, zz, lx, ly)
        if e != ok { ret nan }
        if q == 0usize { ret cr }
        if q == 1usize { ret wsum(zz, false) }
        if q == 2usize { ret wsum(zz, true) }
        if q == 3usize { ret wsum(ly, false) }
        if q == 4usize { ret wsum(ly, true) }
        let i = q - 5usize
        ret zz[(i - 1usize) + n * (n - i)]
    }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/hoslem_rsf.json")
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
