// R kernlab gausspr(cross = k): the cross-validation error of gausspr.default, on the folds of kernlabcv (split(sample(1:m, m), 1:k)). Classification refits the one-against-one
// Laplace approximation (kernlabgpc) on the other folds and answers the sum of the per-fold error rates over k; regression refits (K + var I)^-1 y (kernlabgp) and answers the summed
// squared errors of the folds, times the squared target scale, over m (gausspr only defines that scale when it scales its data, so regression cross-validation needs scaled = TRUE).

use e.algo.rand.r as rr
use e.algo.stat.kernlabcv as cv
use e.algo.stat.kernlabgp as gp
use e.algo.stat.kernlabgpc as gc
use e.algo.stat.kernlabmmd as km
use e.mem

error Fail

// classification: kind 0 rbfdot, 4 laplacedot with sigma par1; cls the 0-based class of each row
fn cv_class(a: *mem.Arena, g: *rr.Rng, x: []const f64, n: usize, nf: usize, cls: []const usize, kc: usize, kind: usize, par1: f64, tol: f64, cross: usize) -> (f64, err) {
    let (perm, e1) = mem.alloc[usize](a, n)
    let (fold, e2) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok { ret (0.0f64, Fail) }
    let e = cv.make_folds(a, g, n, cross, perm, fold)
    if e != ok { ret (0.0f64, e) }
    var cerror = 0.0f64
    var f = 0usize
    while f < cross {
        let start = mem.mark(a)
        let (train, e3) = mem.alloc[usize](a, n)
        let (test, e4) = mem.alloc[usize](a, n)
        if e3 != ok || e4 != ok { ret (0.0f64, Fail) }
        let (nt, ne) = cv.split_rows(n, cross, perm, f, train, test)
        let np = kc * (kc - 1usize) / 2usize
        let (xs, e5) = mem.alloc[f64](a, nt * nf)
        let (xt, e6) = mem.alloc[f64](a, ne * nf)
        let (cs, e7) = mem.alloc[usize](a, nt)
        let (alpha, e8) = mem.alloc[f64](a, np * nt)
        let (dec, e9) = mem.alloc[f64](a, np * ne)
        let (resp, e10) = mem.alloc[usize](a, ne)
        if e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret (0.0f64, Fail) }
        cv.gather(x, nf, train, nt, xs)
        cv.gather(x, nf, test, ne, xt)
        var i = 0usize
        while i < nt {
            cs[i] = cls[train[i]]
            i += 1usize
        }
        let e11 = gc.fit(a, xs, nt, nf, cs, kc, kind, par1, tol, alpha)
        if e11 != ok { ret (0.0f64, e11) }
        let e12 = gc.decisions(a, xs, nt, nf, kc, kind, par1, alpha, xt, ne, dec)
        if e12 != ok { ret (0.0f64, e12) }
        gc.respond(dec, kc, ne, resp)
        var hit = 0usize
        i = 0usize
        while i < ne {
            if resp[i] == cls[test[i]] + 1usize { hit += 1usize }
            i += 1usize
        }
        cerror = (1.0f64 - f64(hit) / f64(ne)) / f64(cross) + cerror
        mem.reset(a, start)
        f += 1usize
    }
    ret (cerror, ok)
}

// regression: y the (scaled) targets, yscale the target scale, vr the noise variance of gausspr(var = )
fn cv_reg(a: *mem.Arena, g: *rr.Rng, x: []const f64, n: usize, nf: usize, y: []const f64, kind: usize, par1: f64, vr: f64, cross: usize, yscale: f64) -> (f64, err) {
    let (perm, e1) = mem.alloc[usize](a, n)
    let (fold, e2) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok { ret (0.0f64, Fail) }
    let e = cv.make_folds(a, g, n, cross, perm, fold)
    if e != ok { ret (0.0f64, e) }
    var cerror = 0.0f64
    var f = 0usize
    while f < cross {
        let start = mem.mark(a)
        let (train, e3) = mem.alloc[usize](a, n)
        let (test, e4) = mem.alloc[usize](a, n)
        if e3 != ok || e4 != ok { ret (0.0f64, Fail) }
        let (nt, ne) = cv.split_rows(n, cross, perm, f, train, test)
        let (xs, e5) = mem.alloc[f64](a, nt * nf)
        let (xt, e6) = mem.alloc[f64](a, ne * nf)
        let (ys, e7) = mem.alloc[f64](a, nt)
        let (kk, e8) = mem.alloc[f64](a, nt * nt)
        let (inv, e9) = mem.alloc[f64](a, nt * nt)
        let (al, e10) = mem.alloc[f64](a, nt)
        let (kt, e11) = mem.alloc[f64](a, ne * nt)
        let (pred, e12) = mem.alloc[f64](a, ne)
        if e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret (0.0f64, Fail) }
        cv.gather(x, nf, train, nt, xs)
        cv.gather(x, nf, test, ne, xt)
        var i = 0usize
        while i < nt {
            ys[i] = y[train[i]]
            i += 1usize
        }
        km.cross(true, kind, xs, xs, nt, nt, nf, par1, 0.0f64, 0.0f64, kk)
        let e13 = gp.inverse(a, kk, nt, vr, inv)
        if e13 != ok { ret (0.0f64, e13) }
        gp.coefficients(inv, ys, nt, al)
        km.cross(false, kind, xt, xs, ne, nt, nf, par1, 0.0f64, 0.0f64, kt)
        gp.predict(kt, al, nt, ne, pred)
        var sse = 0.0f64
        i = 0usize
        while i < ne {
            let d = pred[i] - y[test[i]]
            sse += d * d
            i += 1usize
        }
        cerror = yscale * yscale * sse / f64(n) + cerror
        mem.reset(a, start)
        f += 1usize
    }
    ret (cerror, ok)
}
