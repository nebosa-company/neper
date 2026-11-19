// e.algo.stat.armpolr against arm's bayespolr. tests/oracle/armpolr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R armpolr`; the layout of a case is at the top of scripts/r_oracle/groups/armpolr.R.

use e.algo.linalg.lapack_syevr as sy
use e.algo.stat.armpolr as ap
use e.algo.rand.r as rng
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum(v: []const f64) -> f64 {
    var s = 0.0f64
    var t = 0usize
    while t < v.len {
        s += f64(t + 1usize) * v[t]
        t += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    var x = c.args
    let simmed = str.eq(c.name, "simpolr") || str.eq(c.name, "simpolrz")
    if simmed { x = x[2usize..x.len] }
    let n = usize(x[0usize])
    let pc = usize(x[1usize])
    let jl = usize(x[2usize])
    let q = jl - 1usize
    let np = pc + q
    var at = 9usize
    let y = x[at..at + n]
    at += n
    let xm = x[at..at + n * pc]
    at += n * pc
    var w: []const f64 = x[0usize..0usize]
    if x[5usize] == 1.0f64 {
        w = x[at..at + n]
        at += n
    }
    let which = usize(x[at])
    let (beta, e1) = mem.alloc[f64](a, pc)
    let (zeta, e2) = mem.alloc[f64](a, q)
    let (info, e3) = mem.alloc[f64](a, 3usize)
    let (hess, e4) = mem.alloc[f64](a, np * np)
    let (fit, e5) = mem.alloc[f64](a, n * jl)
    let (vc, e6) = mem.alloc[f64](a, np * np)
    let (se, e7) = mem.alloc[f64](a, np)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { os.exit(10) }
    let nowt: []const f64 = x[0usize..0usize]
    if simmed {
        let ns = usize(c.args[1usize])
        let (dr, e8) = mem.alloc[f64](a, ns * np)
        if e8 != ok { os.exit(12) }
        var g: rng.Rng = zero
        rng.seed(&g, i64(c.args[0usize]))
        if ap.sim_polr(a, &g, xm, y, n, pc, jl, w, nowt, usize(x[3usize]), x[6usize], x[7usize], x[8usize], x[4usize] == 1.0f64, ns, dr) != ok { ret 0.0f64 / 0.0f64 }
        let row = dr[which * np..which * np + np]
        if str.eq(c.name, "simpolr") { ret wsum(row) }
        // simpolrz: the draw's coordinates along the eigenvectors of the covariance, in units of their standard deviation, whose absolute values do not depend on the sign
        // LAPACK gives an eigenvector. Their weighted sum is the same for every fit that has the same fitted parameters.
        if ap.bayespolr(a, xm, y, n, pc, jl, w, nowt, usize(x[3usize]), x[6usize], x[7usize], x[8usize], x[4usize] == 1.0f64, beta, zeta, info, hess, fit) == 0usize { ret 0.0f64 / 0.0f64 }
        if ap.polr_vcov(a, hess, pc, q, zeta, vc) != ok { os.exit(11) }
        let (vt, e9) = mem.alloc[f64](a, np * np)
        let (ev, e10) = mem.alloc[f64](a, np)
        let (evec, e11) = mem.alloc[f64](a, np * np)
        if e9 != ok || e10 != ok || e11 != ok { os.exit(13) }
        var t = 0usize
        while t < np * np {
            vt[(t % np) * np + t / np] = vc[t]
            t += 1usize
        }
        if sy.dsyevr_all(a, vt, np, ev, evec) != ok { os.exit(14) }
        var total = 0.0f64
        var k = 0usize
        while k < np {
            let kk = np - 1usize - k
            var proj = 0.0f64
            var r = 0usize
            while r < np {
                var mu = 0.0f64
                if r < pc { mu = beta[r] } else { mu = zeta[r - pc] }
                proj += evec[kk * np + r] * (row[r] - mu)
                r += 1usize
            }
            total += f64(k + 1usize) * math.abs[f64](proj / math.sqrt[f64](ev[kk]))
            k += 1usize
        }
        ret total
    }
    if ap.bayespolr(a, xm, y, n, pc, jl, w, nowt, usize(x[3usize]), x[6usize], x[7usize], x[8usize], x[4usize] == 1.0f64, beta, zeta, info, hess, fit) == 0usize { ret 0.0f64 / 0.0f64 }
    if which == 0usize { ret wsum(beta) }
    if which == 1usize { ret wsum(zeta) }
    if which == 2usize { ret info[0usize] }
    if which == 3usize { ret info[1usize] }
    if which == 4usize { ret info[2usize] }
    if which == 5usize { ret wsum(hess) }
    if which == 6usize { ret wsum(fit) }
    if ap.polr_vcov(a, hess, pc, q, zeta, vc) != ok { os.exit(11) }
    if which == 7usize { ret wsum(vc) }
    var i = 0usize
    while i < np {
        se[i] = math.sqrt[f64](vc[i * np + i])
        i += 1usize
    }
    ret wsum(se)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/armpolr.json")
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
