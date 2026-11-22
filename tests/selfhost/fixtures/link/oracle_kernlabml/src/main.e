// e.algo.stat.kernlabml against kernlab rvm, kfa and ranking. tests/oracle/kernlabml.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R kernlabml`; the argument layouts are at the top of scripts/r_oracle/groups/kernlabml.R.

use e.algo.rand.r as rr
use e.algo.stat.kernlabml as ml
use e.algo.stat.kernlabmmd as km
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum(v: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        if v[i] == v[i] { s += v[i] * f64(i + 1usize) }
        i += 1usize
    }
    ret s
}

fn rvm_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let m = usize(z[0usize])
    let p = usize(z[1usize])
    let kind = usize(z[2usize])
    let nt = usize(z[9usize])
    let y = z[10usize..10usize + m]
    let x = z[10usize + m..10usize + m + m * p]
    let xt = z[10usize + m + m * p..10usize + m + m * p + nt * p]
    let (kk, e1) = mem.alloc[f64](a, m * m)
    let (w, e2) = mem.alloc[f64](a, m)
    let (nz, e3) = mem.alloc[f64](a, m)
    let (fit, e4) = mem.alloc[f64](a, m)
    let (kt, e5) = mem.alloc[f64](a, nt * m)
    let (pr, e6) = mem.alloc[f64](a, nt)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret nan }
    var res: [4]f64 = zero
    km.cross(true, kind, x, x, m, m, p, z[3usize], 0.0f64, 0.0f64, kk)
    if ml.rvm(a, kk, y, m, z[4usize], z[5usize], z[6usize] > 0.5f64, usize(z[7usize]), 2.220446049250313e-16f64, z[8usize], w, nz, fit, res[0usize..4usize]) != ok { ret nan }
    if str.eq(c.name, "rvm_w") { ret wsum(w, m) }
    if str.eq(c.name, "rvm_index") {
        var s = 0.0f64
        var cnt = 0.0f64
        var i = 0usize
        while i < m {
            if nz[i] > 0.5f64 {
                cnt += 1.0f64
                s += f64(i + 1usize) * cnt
            }
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "rvm_nrv") { ret res[0usize] }
    if str.eq(c.name, "rvm_var") { ret res[1usize] }
    if str.eq(c.name, "rvm_mlike") { ret res[2usize] }
    if str.eq(c.name, "rvm_mse") { ret res[3usize] }
    if str.eq(c.name, "rvm_fitted") { ret wsum(fit, m) }
    km.cross(false, kind, xt, x, nt, m, p, z[3usize], 0.0f64, 0.0f64, kt)
    var t = 0usize
    while t < nt {
        var s = 0.0f64
        var j = 0usize
        while j < m {
            if nz[j] > 0.5f64 { s += kt[t * m + j] * w[j] }
            j += 1usize
        }
        pr[t] = s
        t += 1usize
    }
    ret wsum(pr, nt)
}

fn kfa_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let m = usize(z[0usize])
    let p = usize(z[1usize])
    let kind = usize(z[2usize])
    let sub = usize(z[4usize])
    var fe = usize(z[5usize])
    if fe == 0usize { fe = sub }
    let nt = usize(z[8usize])
    let x = z[9usize..9usize + m * p]
    let xt = z[9usize + m * p..9usize + m * p + nt * p]
    var g: rr.Rng = zero
    rr.seed(&g, i64(z[7usize]))
    let (ri, e0) = rr.sample_int(a, &g, i64(m), i64(sub), false)
    let (xs, e1) = mem.alloc[f64](a, sub * p)
    let (ks, e2) = mem.alloc[f64](a, sub * m)
    let (af, e3) = mem.alloc[f64](a, fe * fe)
    let (sel, e4) = mem.alloc[usize](a, fe)
    let (xm, e5) = mem.alloc[f64](a, fe * p)
    let (kt, e6) = mem.alloc[f64](a, nt * fe)
    let (pr, e7) = mem.alloc[f64](a, nt * fe)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret nan }
    var r = 0usize
    while r < sub {
        var k = 0usize
        while k < p {
            xs[r * p + k] = x[(usize(ri[r]) - 1usize) * p + k]
            k += 1usize
        }
        r += 1usize
    }
    km.cross(false, kind, xs, x, sub, m, p, z[3usize], 0.0f64, 0.0f64, ks)
    if ml.kfa(a, ks, sub, m, fe, z[6usize] > 0.5f64, af, sel) != ok { ret nan }
    if str.eq(c.name, "kfa_alpha") { ret wsum(af, fe * fe) }
    if str.eq(c.name, "kfa_index") {
        var s = 0.0f64
        var i = 0usize
        while i < fe {
            s += f64(usize(ri[sel[i]])) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    r = 0usize
    while r < fe {
        var k = 0usize
        while k < p {
            xm[r * p + k] = x[(usize(ri[sel[r]]) - 1usize) * p + k]
            k += 1usize
        }
        r += 1usize
    }
    km.cross(false, kind, xt, xm, nt, fe, p, z[3usize], 0.0f64, 0.0f64, kt)
    ml.kfa_project(kt, af, nt, fe, pr)
    ret wsum(pr, nt * fe)
}

fn rank_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let m = usize(z[0usize])
    let p = usize(z[1usize])
    let x = z[7usize..7usize + m * p]
    let (kk, e1) = mem.alloc[f64](a, m * m)
    let (sc, e2) = mem.alloc[f64](a, m)
    let (rk, e3) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok { ret nan }
    km.cross(true, usize(z[2usize]), x, x, m, m, p, z[3usize], 0.0f64, 0.0f64, kk)
    if ml.ranking(a, kk, m, usize(z[4usize]), z[5usize], usize(z[6usize]), sc, rk) != ok { ret nan }
    if str.eq(c.name, "rank_score") { ret wsum(sc, m) }
    ret wsum(rk, m)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.starts_with(c.name, "rvm_") { ret rvm_case(a, c) }
    if str.starts_with(c.name, "kfa_") { ret kfa_case(a, c) }
    ret rank_case(a, c)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/kernlabml.json")
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
