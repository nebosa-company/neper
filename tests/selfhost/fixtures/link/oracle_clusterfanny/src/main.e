// e.algo.stat.clusterfanny against cluster::fanny. tests/oracle/clusterfanny.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R clusterfanny`; the argument layout is at the top of
// scripts/r_oracle/groups/clusterfanny.R.

use e.algo.stat.clusterdiss as cd
use e.algo.stat.clusterfanny as cf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum_f(v: []const f64, cnt: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn wsum_u(v: []const usize, cnt: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        s += f64(v[i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let k = usize(x[2usize])
    let metric = usize(x[3usize])
    let stand = x[4usize] != 0.0f64
    let diss = x[5usize] != 0.0f64
    let membexp = x[6usize]
    let tol = x[7usize]
    let maxit = usize(x[8usize])
    let nini = usize(x[9usize])
    let base = 10usize + nini
    var dss: []f64 = zero
    if diss {
        let (v, e1) = mem.alloc[f64](a, n * (n - 1usize) / 2usize)
        if e1 != ok { os.exit(5) }
        var i = 0usize
        while i < n * (n - 1usize) / 2usize {
            v[i] = x[base + i]
            i += 1usize
        }
        dss = v
    } else {
        let (m, e2) = mem.alloc[f64](a, n * p)
        if e2 != ok { os.exit(6) }
        var i = 0usize
        while i < n * p {
            m[i] = x[base + i]
            if m[i] < 0.0f64 - 999000.0f64 { m[i] = 0.0f64 / 0.0f64 }
            i += 1usize
        }
        if stand {
            if cd.stand_meanabsdev(a, m, n, p) != ok { os.exit(7) }
        }
        let (v, e3) = mem.alloc[f64](a, n * (n - 1usize) / 2usize)
        if e3 != ok { os.exit(8) }
        if cf.fanny_dysta(m, n, p, metric, v) != 0usize { os.exit(9) }
        dss = v
    }
    let (r, e4) = cf.fanny_core(a, dss, n, k, x[10usize..base], membexp, tol, maxit, true)
    if e4 != ok { os.exit(10) }
    let nm = c.name
    if str.eq(nm, "memb") { ret wsum_f(r.p, n * k) }
    let (c1, c2) = cf.fanny_coef(r, n, k, membexp)
    if str.eq(nm, "coef1") { ret c1 }
    if str.eq(nm, "coef2") { ret c2 }
    if str.eq(nm, "obj") { ret r.cryt }
    if str.eq(nm, "kcrisp") { ret f64(r.ktrue) }
    if str.eq(nm, "clu") { ret wsum_u(r.clu, n) }
    if str.eq(nm, "iter") { ret f64(r.nit) }
    if str.eq(nm, "conv") {
        if r.nit > 0i64 { ret 1.0f64 }
        ret 0.0f64
    }
    if str.eq(nm, "avsil") { ret wsum_f(r.avsil, k) }
    if str.eq(nm, "ttsil") { ret r.ttsil }
    if str.eq(nm, "sil1") { ret wsum_f(r.silinf[0usize..n], n) }
    if str.eq(nm, "sil2") { ret wsum_f(r.silinf[n..2usize * n], n) }
    if str.eq(nm, "sil3") { ret wsum_f(r.silinf[2usize * n..3usize * n], n) }
    if str.eq(nm, "sil4") { ret wsum_f(r.silinf[3usize * n..4usize * n], n) }
    os.exit(11)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/clusterfanny.json")
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
