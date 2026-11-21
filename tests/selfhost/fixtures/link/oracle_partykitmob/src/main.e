// e.algo.stat.partykitmob against partykit lmtree. tests/oracle/partykitmob.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R partykitmob`; the argument layout is at the top of scripts/r_oracle/groups/partykitmob.R.

use e.algo.stat.partykitmob as mb
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn fitted_at(o: *const mb.MOut, fam: usize, nd: usize, xr: []const f64, kx: usize, nr: usize, i: usize) -> f64 {
    var s = o.coef[(nd - 1usize) * o.k]
    var j = 0usize
    while j < kx {
        s += o.coef[(nd - 1usize) * o.k + j + 1usize] * xr[j * nr + i]
        j += 1usize
    }
    if fam == 0usize { ret s }
    ret mb.linkinv(fam, s)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let sel = usize(z[0usize])
    let n = usize(z[1usize])
    let kx = usize(z[2usize])
    let pz = usize(z[3usize])
    let fam = usize(z[4usize])
    let alpha = z[5usize]
    let bonf = z[6usize] > 0.5f64
    let minsize = usize(z[7usize])
    let maxdepth = usize(z[8usize])
    let trim = z[9usize]
    let prune = usize(z[10usize])
    let center = z[11usize] > 0.5f64
    let (nl, e1) = mem.alloc[usize](a, pz)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var j = 0usize
    while j < pz {
        nl[j] = usize(z[12usize + j])
        j += 1usize
    }
    var none: []const f64 = zero
    var nonu: []const usize = zero
    let b0 = 12usize + pz
    let xr = z[b0..b0 + n * kx]
    let zz = z[b0 + n * kx..b0 + n * kx + n * pz]
    let y = z[b0 + n * kx + n * pz..b0 + n * kx + n * pz + n]
    let (o, e2) = mb.lmtree(a, xr, kx, y, n, zz, pz, nl, fam, alpha, bonf, minsize, maxdepth, trim, center, prune, none, none, nonu, 0usize)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    if sel == 1usize { ret f64(o.count) }
    var s = 0.0f64
    var id = 1usize
    while id <= o.count {
        let k = id - 1usize
        let inner = o.vr[k] != 0i64
        if sel == 2usize { s += f64(id) * f64(o.vr[k]) }
        if sel == 3usize && inner {
            let v = usize(o.vr[k] - 1i64)
            if nl[v] == 0usize {
                s += f64(id) * o.brk[k]
            } else {
                var t = 0.0f64
                var l = 0usize
                while l < nl[v] {
                    let d = o.lmap[k * o.maxlev + l]
                    if d >= 0i64 { t += f64(l + 1usize) * f64(d + 1i64) }
                    l += 1usize
                }
                s += f64(id) * t
            }
        }
        if sel == 4usize { s += f64(id) * o.nobs[k] }
        if sel == 5usize && inner { s += f64(id) * o.pval[k] }
        if sel == 6usize {
            var q = 0usize
            while q < o.k {
                s += f64(id) * f64(q + 1usize) * o.coef[k * o.k + q]
                q += 1usize
            }
        }
        if sel == 7usize { s += f64(id) * o.objfun[k] }
        if sel == 10usize || sel == 11usize {
            var q = 0usize
            while q < pz {
                var v = o.stat[k * pz + q]
                if sel == 11usize { v = o.adjp[k * pz + q] }
                if v == v { s += f64(id) * v }
                q += 1usize
            }
        }
        id += 1usize
    }
    if sel >= 8usize && sel != 10usize && sel != 11usize {
        var xn: []f64 = zero
        var zn: []f64 = zero
        if sel >= 12usize {
            let (xa, e3) = mem.alloc[f64](a, n * kx + 1usize)
            let (za, e4) = mem.alloc[f64](a, n * pz + 1usize)
            if e3 != ok || e4 != ok { ret 0.0f64 / 0.0f64 }
            var q = 0usize
            while q < n * kx {
                xa[q] = xr[q] * 1.1f64 + 0.05f64
                q += 1usize
            }
            q = 0usize
            while q < n * pz {
                za[q] = zz[q] * 1.1f64 + 0.05f64
                q += 1usize
            }
            xn = xa
            zn = za
        }
        var i = 0usize
        while i < n {
            if sel >= 12usize {
                let nd = mb.predict_node(&o, nl, zn, n, i)
                if sel == 12usize { s += f64(i + 1usize) * f64(nd) }
                if sel == 13usize { s += fitted_at(&o, fam, nd, xn, kx, n, i) }
            } else {
                let nd = mb.predict_node(&o, nl, zz, n, i)
                if sel == 8usize { s += fitted_at(&o, fam, nd, xr, kx, n, i) }
                if sel == 9usize { s += f64(i + 1usize) * f64(nd) }
            }
            i += 1usize
        }
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/partykitmob.json")
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
