// e.algo.stat.looextra against loo; layouts at the top of scripts/r_oracle/groups/loo2.R (loo with r_eff, waic, loo_compare) and loo3.R (E_loo, model weights).

use e.algo.stat.looextra as lx
use e.algo.stat.loopkg as lp
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn pointwise_of(a: *mem.Arena, ll: []const f64, s: usize, nobs: usize, out: []f64, col: usize, k: usize) {
    let (rf, e1) = mem.alloc[f64](a, nobs)
    let (t, e2) = mem.alloc[f64](a, nobs * 5usize)
    if e1 != ok || e2 != ok { os.exit(4) }
    var i = 0usize
    while i < nobs {
        rf[i] = 1.0f64
        i += 1usize
    }
    if lx.loo_full(a, ll, s, nobs, rf, t) != ok { os.exit(5) }
    i = 0usize
    while i < nobs {
        out[i * k + col] = t[i * 5usize]
        i += 1usize
    }
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nm = c.name
    if str.starts_with(nm, "l_") || str.starts_with(nm, "w_") {
        let nc = usize(x[0usize])
        let n = usize(x[1usize])
        let nobs = usize(x[2usize])
        let s = nc * n
        let ll = x[3usize..3usize + s * nobs]
        if str.starts_with(nm, "w_") {
            let (t, e) = mem.alloc[f64](a, nobs * 2usize)
            if e != ok { os.exit(6) }
            lx.waic_pointwise(ll, s, nobs, t)
            if str.eq(nm, "w_elpd") {
                let (m, se) = lx.estimate(t, nobs, 2usize, 0usize)
                ret m
            }
            if str.eq(nm, "w_se") {
                let (m, se) = lx.estimate(t, nobs, 2usize, 0usize)
                ret se
            }
            if str.eq(nm, "w_p") {
                let (m, se) = lx.estimate(t, nobs, 2usize, 1usize)
                ret m
            }
            let (m, se) = lx.estimate(t, nobs, 2usize, 1usize)
            ret se
        }
        let (rf, e1) = mem.alloc[f64](a, nobs)
        let (t, e2) = mem.alloc[f64](a, nobs * 5usize)
        if e1 != ok || e2 != ok { os.exit(7) }
        var o = 0usize
        var rs = 0.0f64
        while o < nobs {
            let (ex, ee) = mem.alloc[f64](a, s)
            if ee != ok { os.exit(15) }
            var q = 0usize
            while q < s {
                ex[q] = math.exp[f64](ll[o * s + q])
                q += 1usize
            }
            rf[o] = lx.relative_eff(a, ex, nc, n)
            rs += rf[o]
            o += 1usize
        }
        if lx.loo_full(a, ll, s, nobs, rf, t) != ok { os.exit(8) }
        if str.eq(nm, "l_reff") { ret rs }
        if str.eq(nm, "l_elpd") {
            let (m, se) = lx.estimate(t, nobs, 5usize, 0usize)
            ret m
        }
        if str.eq(nm, "l_se") {
            let (m, se) = lx.estimate(t, nobs, 5usize, 0usize)
            ret se
        }
        if str.eq(nm, "l_p") {
            let (m, se) = lx.estimate(t, nobs, 5usize, 2usize)
            ret m
        }
        if str.eq(nm, "l_sep") {
            let (m, se) = lx.estimate(t, nobs, 5usize, 2usize)
            ret se
        }
        var tot = 0.0f64
        o = 0usize
        while o < nobs {
            let k = t[o * 5usize + 3usize]
            if str.eq(nm, "l_mcse") { tot += t[o * 5usize + 1usize] }
            if str.eq(nm, "l_neff") { tot += t[o * 5usize + 4usize] }
            if str.eq(nm, "l_k") && k - k == 0.0f64 { tot += k }
            o += 1usize
        }
        ret tot
    }
    if str.starts_with(nm, "cmp_") {
        let s = usize(x[0usize])
        let nobs = usize(x[1usize])
        let k = usize(x[2usize])
        let (pt, e1) = mem.alloc[f64](a, nobs * k)
        let (out, e2) = mem.alloc[f64](a, k * 2usize)
        if e1 != ok || e2 != ok { os.exit(9) }
        var j = 0usize
        while j < k {
            pointwise_of(a, x[3usize + j * s * nobs..3usize + (j + 1usize) * s * nobs], s, nobs, pt, j, k)
            j += 1usize
        }
        let _ = lx.compare(pt, nobs, k, out)
        let jj = usize(x[3usize + k * s * nobs])
        if str.eq(nm, "cmp_d") { ret out[jj * 2usize] }
        ret out[jj * 2usize + 1usize]
    }
    if str.starts_with(nm, "e_") || str.starts_with(nm, "ek_") {
        let s = usize(x[0usize])
        let xs = x[1usize..1usize + s]
        let ll = x[1usize + s..1usize + 2usize * s]
        let (lr, e) = mem.alloc[f64](a, s)
        if e != ok { os.exit(10) }
        var i = 0usize
        while i < s {
            lr[i] = 0.0f64 - ll[i]
            i += 1usize
        }
        var kind = 0usize
        if str.ends_with(nm, "var") { kind = 1usize }
        if str.ends_with(nm, "sd") { kind = 2usize }
        if str.ends_with(nm, "_q") { kind = 3usize }
        let (v, kh, ee) = lx.e_loo(a, xs, lr, x[1usize + 2usize * s], kind, x[2usize + 2usize * s])
        if ee != ok { os.exit(11) }
        if str.starts_with(nm, "ek_") { ret kh }
        ret v
    }
    // weights: (N, K, lpd row-major, j, seed, BB_n, alpha)
    let nobs = usize(x[0usize])
    let k = usize(x[1usize])
    let lpd = x[2usize..2usize + nobs * k]
    let j = usize(x[2usize + nobs * k])
    let (w, e) = mem.alloc[f64](a, k)
    if e != ok { os.exit(12) }
    if str.eq(nm, "pb") {
        lx.pseudobma_weights(lpd, nobs, k, w)
    } else if str.eq(nm, "bb") {
        if lx.pseudobma_bb(a, lpd, nobs, k, i64(x[3usize + nobs * k]), usize(x[4usize + nobs * k]), x[5usize + nobs * k], w) != ok { os.exit(13) }
    } else {
        if lx.stacking_weights(a, lpd, nobs, k, w) != ok { os.exit(14) }
    }
    ret w[j]
}

fn run(a: *mem.Arena, path: str) -> usize {
    let (golden, load_error) = oracle.load(a, path)
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
    ret failures
}

fn main(a: *mem.Arena, args: []str) -> err {
    let f1 = run(a, "tests/oracle/loo2.json")
    let f2 = run(a, "tests/oracle/loo3.json")
    if f1 + f2 > 0usize { os.exit(1) }
    ret ok
}
