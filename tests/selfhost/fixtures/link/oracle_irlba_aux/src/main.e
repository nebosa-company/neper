// e.algo.stat.irlba_extra (svdr, partial_eigen, prcomp_irlba) against the irlba package. tests/oracle/irlba_aux.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R irlba_aux`; the layout is at the top of scripts/r_oracle/groups/irlba_aux.R.

use e.algo.rand.r as rr
use e.algo.stat.irlba as il
use e.algo.stat.irlba_extra as ex
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn wsum(v: []f64, cnt: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let mode = usize(z[0usize])
    var g: rr.Rng = zero
    if mode == 0usize {
        let m = usize(z[1usize])
        let n = usize(z[2usize])
        let k = usize(z[3usize])
        rr.seed(&g, i64(z[5usize]))
        var res: il.Fit = zero
        var cv: []const f64 = z[8usize..8usize]
        if z[7usize] != 0.0f64 { cv = z[8usize..8usize + n] }
        let e = ex.svdr(a, &g, z[8usize + n..8usize + n + m * n], m, n, k, usize(z[4usize]), 1.0e-5f64, 100usize, cv, &res)
        if e != ok { os.exit(5) }
        let kind = usize(z[6usize])
        if kind == 0usize { ret wsum(res.d, k) }
        if kind == 1usize { ret wsum(res.u, m * k) }
        if kind == 2usize { ret wsum(res.v, n * k) }
        ret f64(res.mprod)
    }
    if mode == 1usize {
        let n = usize(z[1usize])
        let nev = usize(z[2usize])
        rr.seed(&g, i64(z[3usize]))
        var res: il.Fit = zero
        let o = il.default_opts(nev)
        let e = ex.partial_eigen(a, &g, z[6usize..6usize + n * n], n, n, nev, z[5usize] != 0.0f64, o, &res)
        if e != ok { os.exit(6) }
        if usize(z[4usize]) == 0usize { ret wsum(res.d, nev) }
        ret wsum(res.u, n * nev)
    }
    if mode == 3usize {
        let m = usize(z[1usize])
        let p = usize(z[2usize])
        let k = usize(z[3usize])
        rr.seed(&g, i64(z[7usize]))
        var cen: []f64 = zero
        var sca: []f64 = zero
        let x = z[9usize..9usize + m * p]
        if z[5usize] != 0.0f64 {
            let (cm, e1) = il.zalloc(a, p)
            if e1 != ok { os.exit(4) }
            var j = 0usize
            while j < p {
                cm[j] = il.mean_ld(x[j * m..(j + 1usize) * m], m)
                j += 1usize
            }
            cen = cm
        }
        if z[6usize] != 0.0f64 {
            let (sm, e2) = il.zalloc(a, p)
            let (tmp, e3) = il.zalloc(a, m)
            if e2 != ok || e3 != ok { os.exit(4) }
            var j = 0usize
            while j < p {
                var i = 0usize
                while i < m {
                    var mu = 0.0f64
                    if z[5usize] != 0.0f64 { mu = cen[j] }
                    let dv = x[j * m + i] - mu
                    tmp[i] = dv * dv
                    i += 1usize
                }
                var den = f64(m - 1usize)
                if z[5usize] == 0.0f64 { den = f64(m - 1usize) }
                sm[j] = math.sqrt[f64](il.sum_ld(tmp, m) / den)
                j += 1usize
            }
            sca = sm
        }
        var out: ex.Ssvd = zero
        let e = ex.ssvd(a, &g, x, m, p, k, usize(z[4usize]), 500usize, 0.001f64, cen, sca, 0.0f64, il.default_opts(k), &out)
        if e != ok { os.exit(8) }
        let kind = usize(z[8usize])
        if kind == 0usize { ret wsum(out.d, k * k) }
        if kind == 1usize { ret wsum(out.u, m * k) }
        if kind == 2usize { ret wsum(out.v, p * k) }
        if kind == 3usize { ret f64(out.iter) }
        ret wsum(out.lambda, k)
    }
    let m = usize(z[1usize])
    let p = usize(z[2usize])
    let nv = usize(z[3usize])
    rr.seed(&g, i64(z[6usize]))
    var out: ex.Prcomp = zero
    let e = ex.prcomp_irlba(a, &g, z[8usize..8usize + m * p], m, p, nv, z[4usize] != 0.0f64, z[5usize] != 0.0f64, il.default_opts(nv), &out)
    if e != ok { os.exit(7) }
    let kind = usize(z[7usize])
    if kind == 0usize { ret wsum(out.sdev, nv) }
    if kind == 1usize { ret out.totalvar }
    if kind == 2usize { ret wsum(out.rot, p * nv) }
    ret wsum(out.scores, m * nv)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/irlba_aux.json")
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
