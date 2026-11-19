// e.algo.stat.fpc_km against stats::kmeans (Hartigan-Wong), fpc::kmeansruns and fpc::pamk. tests/oracle/fpc_km.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_km`; the layout of every case is at the top of scripts/r_oracle/groups/fpc_km.R.

use e.algo.rand.r as rg
use e.algo.stat.fpc_km as fk
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn wsum_u(v: []const usize, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += f64(i + 1usize) * f64(v[i])
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let fn_id = usize(z[0usize])
    let what = usize(z[1usize])
    let n = usize(z[2usize])
    let p = usize(z[3usize])
    let k1 = usize(z[4usize])
    let k2 = usize(z[5usize])
    let crit = usize(z[6usize])
    let itm = usize(z[7usize])
    let runs = usize(z[8usize])
    let sc = z[9usize] > 0.5f64
    let ns = usize(z[10usize])
    let seedv = i64(z[11usize])
    let flag = z[12usize] > 0.5f64
    var dlen = n * p
    if fn_id == 3usize && flag { dlen = n * n }
    let x = z[13usize..13usize + dlen]
    var g: rg.Rng = zero
    rg.seed(&g, seedv)
    let (cl, e1) = mem.alloc[usize](a, n + 1usize)
    let (cent, e2) = mem.alloc[f64](a, 16usize * p)
    let (wss, e3) = mem.alloc[f64](a, 16usize)
    let (size, e4) = mem.alloc[usize](a, 17usize)
    let (info, e5) = mem.alloc[f64](a, 8usize)
    let (cr, e6) = mem.alloc[f64](a, 17usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { os.exit(4) }
    if fn_id == 1usize {
        let (flt, e7) = fk.kmeans_hw(a, &g, x, n, p, k1, itm, ns, cl, cent, wss, size, info)
        if e7 != ok { os.exit(5) }
        if what == 0usize { ret wsum_u(cl[1usize..n + 1usize], n) }
        if what == 1usize { ret info[1usize] }
        if what == 2usize { ret info[0usize] }
        if what == 3usize { ret info[3usize] }
        if what == 7usize { ret f64(flt) }
        var t = 0.0f64
        var i = 0usize
        if what == 4usize {
            while i < k1 * p {
                t += f64(i + 1usize) * cent[i]
                i += 1usize
            }
        }
        if what == 5usize {
            while i < k1 {
                t += f64(i + 1usize) * wss[i]
                i += 1usize
            }
        }
        if what == 6usize {
            while i < k1 {
                t += f64(i + 1usize) * f64(size[i + 1usize])
                i += 1usize
            }
        }
        ret t
    }
    var kr: [16]usize = zero
    var nk = 0usize
    var k = k1
    while k <= k2 {
        kr[nk] = k
        nk += 1usize
        k += 1usize
    }
    if fn_id == 2usize {
        let (bk, e8) = fk.kmeansruns(a, &g, x, n, p, kr[0usize..nk], nk, crit == 1usize, itm, runs, sc, 0.001f64, ns, cl, cent, wss, size, info, cr)
        if e8 != ok { os.exit(6) }
        if what == 0usize { ret f64(bk) }
        var t = 0.0f64
        var i = 0usize
        if what == 1usize {
            i = 1usize
            while i <= k2 {
                t += f64(i) * cr[i]
                i += 1usize
            }
            ret t
        }
        if what == 2usize { ret wsum_u(cl[1usize..n + 1usize], n) }
        if what == 3usize { ret info[1usize] }
        if what == 5usize { ret info[3usize] }
        if what == 6usize { ret info[0usize] }
        while i < bk * p {
            t += f64(i + 1usize) * cent[i]
            i += 1usize
        }
        ret t
    }
    let (med, e9) = mem.alloc[usize](a, 17usize)
    let (pcl, e10) = mem.alloc[usize](a, n)
    if e9 != ok || e10 != ok { os.exit(4) }
    var ck = 0usize
    if crit == 1usize { ck = 1usize }
    if crit == 2usize { ck = 2usize }
    let (nc, e11) = fk.pamk(a, x, n, p, kr[0usize..nk], nk, ck, sc, 0.001f64, flag, runs, seedv, pcl, med, cr)
    if e11 != ok { os.exit(7) }
    if what == 0usize { ret f64(nc) }
    var t = 0.0f64
    var i = 1usize
    if what == 1usize {
        while i <= k2 {
            t += f64(i) * cr[i]
            i += 1usize
        }
        ret t
    }
    if what == 2usize { ret wsum_u(pcl, n) }
    ret wsum_u(med, nc)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_km.json")
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
            if failures <= 40usize {
                var c2 = *c
                c2.args = c.args[0usize..13usize]
                let _ = io.print(oracle.describe(a, &c2, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
