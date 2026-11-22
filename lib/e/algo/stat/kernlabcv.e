// R kernlab ksvm(cross = k): the k-fold cross-validation error of ksvm.default, on R's stream. The folds are split(sample(1:m, m), 1:k) (fold j takes positions j, j + k, ... of
// the permutation), the training rows of fold i are the other folds in order, and each training set is refitted with the model's own kernel parameters (C-svc, nu-svc, C-bsvc,
// eps-svr, nu-svr). Classification answers the sum of the per-fold error rates over k; regression the summed squared errors of the folds, times the squared target scale, over m.
// Data are row-major, n by nf, already scaled by ksvm when it scales them.

use e.algo.rand.r as rr
use e.algo.stat.kernlabbpred as bp
use e.algo.stat.kernlabclass as cl
use e.algo.stat.kernlabsvm as ks
use e.mem

error Fail

// fold of every row (0-based fold index), the row order of the permutation in perm (0-based rows)
fn make_folds(a: *mem.Arena, g: *rr.Rng, n: usize, cross: usize, perm: []usize, fold: []usize) -> err {
    let (s, e) = rr.sample_int(a, g, i64(n), i64(n), false)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        perm[i] = usize(s[i]) - 1usize
        fold[perm[i]] = i % cross
        i += 1usize
    }
    ret ok
}

// the rows of the training set of fold f (the other folds in order, each in permutation order) and of the test set; answers their counts
fn split_rows(n: usize, cross: usize, perm: []const usize, f: usize, train: []usize, test: []usize) -> (usize, usize) {
    var nt = 0usize
    var ne = 0usize
    var k = 0usize
    while k < cross {
        var i = 0usize
        while i < n {
            if i % cross == k {
                if k == f {
                    test[ne] = perm[i]
                    ne += 1usize
                } else {
                    train[nt] = perm[i]
                    nt += 1usize
                }
            }
            i += 1usize
        }
        k += 1usize
    }
    ret (nt, ne)
}

fn gather(x: []const f64, nf: usize, rows: []const usize, cnt: usize, out: []f64) {
    var i = 0usize
    while i < cnt {
        var k = 0usize
        while k < nf {
            out[i * nf + k] = x[rows[i] * nf + k]
            k += 1usize
        }
        i += 1usize
    }
}

// classification: svm 0 C-svc, 1 nu-svc, 5 C-bsvc; cls the 0-based class of each row
fn cv_class(a: *mem.Arena, g: *rr.Rng, x: []const f64, n: usize, nf: usize, cls: []const usize, kc: usize, par: *const ks.Param, svm: usize, cross: usize, lam: *f64) -> (f64, err) {
    let (perm, e1) = mem.alloc[usize](a, n)
    let (fold, e2) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok { ret (0.0f64, Fail) }
    let e = make_folds(a, g, n, cross, perm, fold)
    if e != ok { ret (0.0f64, e) }
    var cerror = 0.0f64
    var f = 0usize
    while f < cross {
        let start = mem.mark(a)
        let (train, e3) = mem.alloc[usize](a, n)
        let (test, e4) = mem.alloc[usize](a, n)
        if e3 != ok || e4 != ok { ret (0.0f64, Fail) }
        let (nt, ne) = split_rows(n, cross, perm, f, train, test)
        let (xs, e5) = mem.alloc[f64](a, nt * nf)
        let (xt, e6) = mem.alloc[f64](a, ne * nf)
        let (cs, e7) = mem.alloc[usize](a, nt)
        let np = kc * (kc - 1usize) / 2usize
        let (coef, e8) = mem.alloc[f64](a, np * nt)
        let (bout, e9) = mem.alloc[f64](a, np)
        let (ob, e10) = mem.alloc[f64](a, np)
        let (resp, e11) = mem.alloc[usize](a, ne)
        if e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret (0.0f64, Fail) }
        gather(x, nf, train, nt, xs)
        gather(x, nf, test, ne, xt)
        var i = 0usize
        while i < nt {
            cs[i] = cls[train[i]]
            i += 1usize
        }
        var e12 = ok
        if svm == 5usize {
            // bsvc_pairs wants the rows grouped by class; the pair data order of ksvm is the order of the rows within each class, which the scan by class keeps
            e12 = bp.bsvc_pairs(a, xs, nt, nf, cs, kc, par, lam, coef, bout, ob)
        } else {
            let empty = coef[0usize..0usize]
            e12 = cl.fit_class(a, xs, nt, nf, cs, kc, par, empty, coef, bout, ob)
        }
        if e12 != ok { ret (0.0f64, e12) }
        let e13 = bp.predict_pairs(a, par, xs, nt, nf, coef, bout, kc, xt, ne, resp)
        if e13 != ok { ret (0.0f64, e13) }
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

// regression (svm 3 eps-svr, 4 nu-svr): y the (scaled) targets, yscale the target scale (1 when unscaled)
fn cv_reg(a: *mem.Arena, g: *rr.Rng, x: []const f64, n: usize, nf: usize, y: []const f64, par: *const ks.Param, cross: usize, yscale: f64) -> (f64, err) {
    let (perm, e1) = mem.alloc[usize](a, n)
    let (fold, e2) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok { ret (0.0f64, Fail) }
    let e = make_folds(a, g, n, cross, perm, fold)
    if e != ok { ret (0.0f64, e) }
    var cerror = 0.0f64
    var f = 0usize
    while f < cross {
        let start = mem.mark(a)
        let (train, e3) = mem.alloc[usize](a, n)
        let (test, e4) = mem.alloc[usize](a, n)
        if e3 != ok || e4 != ok { ret (0.0f64, Fail) }
        let (nt, ne) = split_rows(n, cross, perm, f, train, test)
        let (xs, e5) = mem.alloc[f64](a, nt * nf)
        let (xt, e6) = mem.alloc[f64](a, ne * nf)
        let (ys, e7) = mem.alloc[f64](a, nt)
        let (out, e8) = mem.alloc[f64](a, nt)
        let (pred, e9) = mem.alloc[f64](a, ne)
        if e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (0.0f64, Fail) }
        gather(x, nf, train, nt, xs)
        gather(x, nf, test, ne, xt)
        var i = 0usize
        while i < nt {
            ys[i] = y[train[i]]
            i += 1usize
        }
        let (rho, ob, e10) = ks.smo_optim(a, xs, nt, nf, ys, par, out)
        if e10 != ok { ret (0.0f64, e10) }
        let e11 = cl.decide(a, par, xs, nt, nf, out, rho, xt, ne, pred)
        if e11 != ok { ret (0.0f64, e11) }
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
